// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {LiveCertificate} from "./LiveCertificate.sol";

/// @title Season
/// @notice Competition wrapper for paper-trading runs. Each season pins a
///         fixed (datasetSpec, initialBalance, fees, market) tuple and
///         settles by paying out the top-3 enrolled tokens ranked by
///         `liveTotalReturnBps` at season end.
/// @dev    Sorting the leaderboard fully on-chain is O(N²) and breaks at
///         >100 enrollments. Instead `settle` accepts a caller-provided
///         sorted hint and verifies monotonicity in O(N) — see RFC-001 §7.2.
contract Season is Ownable2Step, ReentrancyGuard {
    uint16 internal constant FIRST_PRIZE_BPS  = 5000; // 50%
    uint16 internal constant SECOND_PRIZE_BPS = 3000; // 30%
    uint16 internal constant THIRD_PRIZE_BPS  = 2000; // 20%

    struct SeasonSpec {
        bytes32 datasetSpec;     // keccak("BTCUSDT-15m-spot") — operator-agreed identifier
        uint64  initialBalance;  // standardized starting USDT equivalent
        uint16  feeBps;
        uint16  slippageBps;
        uint8   market;          // 0=spot, 1=perp
        uint8   maxLeverage;     // 1..10 (10 = perp cap)
        uint64  startTime;
        uint64  endTime;
        uint256 prizePool;
        address creator;
        bool    settled;
    }

    error InvalidWindow();
    error UnderfundedPrizePool();
    error EnrollmentClosed();
    error NotTokenOwner();
    error AlreadyEnrolled();
    error NotEnrolled();
    error SeasonNotOver();
    error AlreadySettled();
    error UnknownSeason();
    error HintNotSorted();
    error HintTooLong();
    error PayoutFailed();

    event SeasonCreated(
        uint256 indexed id,
        bytes32 indexed datasetSpec,
        uint64  startTime,
        uint64  endTime,
        uint256 prizePool
    );
    event Enrolled(uint256 indexed seasonId, uint256 indexed tokenId, address indexed owner);
    event Settled(uint256 indexed seasonId, uint256[] sortedWinners, uint256 paidOut);
    event PrizeAwarded(uint256 indexed seasonId, uint256 indexed tokenId, address indexed winner, uint256 amount);

    /// @notice The LiveCertificate this Season reads rankings from.
    LiveCertificate public immutable live;

    /// @notice The iNFT contract used to look up token owners for payouts.
    IERC721 public immutable inft;

    uint256 public nextSeasonId = 1;
    mapping(uint256 => SeasonSpec) public seasons;

    /// @notice seasonId => tokenId => enrolled?
    mapping(uint256 => mapping(uint256 => bool)) public enrolled;

    /// @notice Enumerable list of tokens per season (for off-chain indexers).
    mapping(uint256 => uint256[]) public participants;

    constructor(address admin, address liveAddress, address inftAddress) Ownable(admin) {
        require(liveAddress != address(0) && inftAddress != address(0), "zero addr");
        live = LiveCertificate(liveAddress);
        inft = IERC721(inftAddress);
    }

    // ─── season lifecycle ──────────────────────────────────────────────────

    /// @notice Create a new season. Admin-only in v0.3; v1.0 may open it up to
    ///         anyone who funds a prize pool.
    function createSeason(SeasonSpec calldata spec)
        external
        payable
        onlyOwner
        returns (uint256 id)
    {
        if (spec.startTime <= block.timestamp || spec.endTime <= spec.startTime) {
            revert InvalidWindow();
        }
        if (msg.value < spec.prizePool) revert UnderfundedPrizePool();

        unchecked {
            id = nextSeasonId++;
        }

        seasons[id] = SeasonSpec({
            datasetSpec:    spec.datasetSpec,
            initialBalance: spec.initialBalance,
            feeBps:         spec.feeBps,
            slippageBps:    spec.slippageBps,
            market:         spec.market,
            maxLeverage:    spec.maxLeverage,
            startTime:      spec.startTime,
            endTime:        spec.endTime,
            prizePool:      spec.prizePool,
            creator:        msg.sender,
            settled:        false
        });

        emit SeasonCreated(id, spec.datasetSpec, spec.startTime, spec.endTime, spec.prizePool);
    }

    /// @notice Enroll an owned iNFT into a season. Must be called before
    ///         the season's `startTime`.
    function enroll(uint256 seasonId, uint256 tokenId) external {
        SeasonSpec memory s = seasons[seasonId];
        if (s.startTime == 0) revert UnknownSeason();
        if (block.timestamp >= s.startTime) revert EnrollmentClosed();
        if (inft.ownerOf(tokenId) != msg.sender) revert NotTokenOwner();
        if (enrolled[seasonId][tokenId]) revert AlreadyEnrolled();

        enrolled[seasonId][tokenId] = true;
        participants[seasonId].push(tokenId);

        emit Enrolled(seasonId, tokenId, msg.sender);
    }

    /// @notice Settle the season. Permissionless — anyone can trigger after
    ///         endTime. `sortedTokens` is an O(N log N) caller-provided hint
    ///         of the top participants by `liveTotalReturnBps`, verified here
    ///         in O(N).
    /// @dev    Only the first 3 entries are paid out; passing more is allowed
    ///         (helps off-chain indexers display a full ranking) but the
    ///         contract caps hint length at participants[id].length to bound
    ///         gas.
    function settle(uint256 seasonId, uint256[] calldata sortedTokens)
        external
        nonReentrant
    {
        SeasonSpec storage s = seasons[seasonId];
        if (s.startTime == 0) revert UnknownSeason();
        if (block.timestamp <= s.endTime) revert SeasonNotOver();
        if (s.settled) revert AlreadySettled();
        if (sortedTokens.length > participants[seasonId].length) revert HintTooLong();

        // Verify monotonicity. Empty hint is allowed (no winners → pool unspent).
        int256 prev = type(int256).max;
        for (uint256 i = 0; i < sortedTokens.length; i++) {
            uint256 tokenId = sortedTokens[i];
            if (!enrolled[seasonId][tokenId]) revert NotEnrolled();
            (, , , , , , , int128 ret, ) = live.runs(tokenId);
            if (int256(ret) > prev) revert HintNotSorted();
            prev = int256(ret);
        }

        s.settled = true;

        // Pay top-3 (50/30/20). Tokens beyond #3 are kept in the hint only for
        // off-chain visibility — no payout.
        uint256 totalPaid = 0;
        uint256 pool = s.prizePool;
        if (sortedTokens.length >= 1) {
            uint256 amt = (pool * FIRST_PRIZE_BPS) / 10_000;
            _pay(seasonId, sortedTokens[0], amt);
            totalPaid += amt;
        }
        if (sortedTokens.length >= 2) {
            uint256 amt = (pool * SECOND_PRIZE_BPS) / 10_000;
            _pay(seasonId, sortedTokens[1], amt);
            totalPaid += amt;
        }
        if (sortedTokens.length >= 3) {
            uint256 amt = (pool * THIRD_PRIZE_BPS) / 10_000;
            _pay(seasonId, sortedTokens[2], amt);
            totalPaid += amt;
        }

        emit Settled(seasonId, sortedTokens, totalPaid);
    }

    // ─── views ─────────────────────────────────────────────────────────────

    function participantCount(uint256 seasonId) external view returns (uint256) {
        return participants[seasonId].length;
    }

    function getParticipants(uint256 seasonId) external view returns (uint256[] memory) {
        return participants[seasonId];
    }

    // ─── internal ──────────────────────────────────────────────────────────

    function _pay(uint256 seasonId, uint256 tokenId, uint256 amount) private {
        address winner = inft.ownerOf(tokenId);
        (bool ok, ) = winner.call{value: amount}("");
        if (!ok) revert PayoutFailed();
        emit PrizeAwarded(seasonId, tokenId, winner, amount);
    }
}
