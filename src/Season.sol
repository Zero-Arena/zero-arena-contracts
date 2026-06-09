// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AgentCertificate} from "./AgentCertificate.sol";
import {LiveCertificate} from "./LiveCertificate.sol";
import {ZeroArenaINFT} from "./ZeroArenaINFT.sol";

// Paper-trading season. Fixed (dataset, balance, fees, market) per season; pays
// top-3 by liveTotalReturnBps via a caller-provided sorted hint verified in O(N).
contract Season is Ownable2Step, ReentrancyGuard {
    uint16 internal constant FIRST_PRIZE_BPS  = 5000; // 50%
    uint16 internal constant SECOND_PRIZE_BPS = 3000; // 30%
    uint16 internal constant THIRD_PRIZE_BPS  = 2000; // 20%

    struct SeasonSpec {
        bytes32 datasetSpec;     // keccak("BTCUSDT-15m-spot") etc.
        uint64  initialBalance;
        uint16  feeBps;
        uint16  slippageBps;
        uint8   market;          // 0=spot, 1=perp
        uint8   maxLeverage;     // 1..10
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
    error IncompleteHint(uint256 expected, uint256 got);
    error DuplicateInHint(uint256 tokenId);
    error PayoutFailed();
    error RefundFailed();
    error NothingToWithdraw();
    error MarketMismatch(uint8 expected, uint8 got);

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

    LiveCertificate public immutable live;
    ZeroArenaINFT public immutable inft;

    uint256 public nextSeasonId = 1;
    mapping(uint256 => SeasonSpec) public seasons;
    mapping(uint256 => mapping(uint256 => bool)) public enrolled;
    mapping(uint256 => uint256[]) public participants;

    // In-season baseline (L1): each token's liveTotalReturnBps captured at enroll
    // time. settle() ranks on (current - baseline) so an agent's lifetime return
    // earned before it joined doesn't dominate the season standing.
    mapping(uint256 => mapping(uint256 => int128)) public baselineReturnBps;

    // Pull-payment ledger: any prize/refund that can't be pushed (recipient
    // rejected the transfer) is credited here and claimable via withdraw(), so
    // a hostile recipient can never strand the pool or block settlement.
    mapping(address => uint256) public pendingWithdrawals;

    // Scratch set used only inside settle() to reject duplicate tokenIds in the
    // ranking hint; always cleared before settle() returns (no cross-call state).
    mapping(uint256 => bool) private _seenInSettle;

    constructor(address admin, address liveAddress, address inftAddress) Ownable(admin) {
        require(liveAddress != address(0) && inftAddress != address(0), "zero addr");
        live = LiveCertificate(liveAddress);
        inft = ZeroArenaINFT(inftAddress);
    }

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

        unchecked { id = nextSeasonId++; }

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

        // Refund any overpayment so surplus never gets stranded in the contract.
        uint256 surplus = msg.value - spec.prizePool;
        if (surplus > 0) {
            (bool ok, ) = msg.sender.call{value: surplus}("");
            if (!ok) revert RefundFailed();
        }
    }

    function enroll(uint256 seasonId, uint256 tokenId) external {
        SeasonSpec memory s = seasons[seasonId];
        if (s.startTime == 0) revert UnknownSeason();
        if (block.timestamp >= s.startTime) revert EnrollmentClosed();
        if (inft.ownerOf(tokenId) != msg.sender) revert NotTokenOwner();
        if (enrolled[seasonId][tokenId]) revert AlreadyEnrolled();

        uint256 certId = inft.certificateOf(tokenId);
        AgentCertificate.Certificate memory cert = inft.certificateContract().get(certId);
        if (cert.market != s.market) revert MarketMismatch(s.market, cert.market);

        enrolled[seasonId][tokenId] = true;
        participants[seasonId].push(tokenId);

        // Snapshot the live return now so settle() measures the in-season delta.
        (, , , , , , , int128 baseRet, ) = live.runs(tokenId);
        baselineReturnBps[seasonId][tokenId] = baseRet;

        emit Enrolled(seasonId, tokenId, msg.sender);
    }

    // Permissionless after endTime. `sortedTokens` MUST be the COMPLETE ranking
    // of every enrolled token — not a caller-chosen subset. We verify it covers
    // all participants exactly once (no omissions, no duplicates) and is
    // monotonically decreasing in liveTotalReturnBps, which makes the top-3
    // unambiguous and independent of who calls settle. Without the completeness
    // + uniqueness checks, anyone could pass a hint listing only their own
    // (worst-ranked or repeated) tokens and drain the whole pool.
    function settle(uint256 seasonId, uint256[] calldata sortedTokens)
        external
        nonReentrant
    {
        SeasonSpec storage s = seasons[seasonId];
        if (s.startTime == 0) revert UnknownSeason();
        if (block.timestamp <= s.endTime) revert SeasonNotOver();
        if (s.settled) revert AlreadySettled();

        uint256 n = participants[seasonId].length;
        if (sortedTokens.length != n) revert IncompleteHint(n, sortedTokens.length);

        int256 prev = type(int256).max;
        for (uint256 i = 0; i < n; i++) {
            uint256 tokenId = sortedTokens[i];
            if (!enrolled[seasonId][tokenId]) revert NotEnrolled();
            if (_seenInSettle[tokenId]) revert DuplicateInHint(tokenId);
            _seenInSettle[tokenId] = true;
            (, , , , , , , int128 ret, ) = live.runs(tokenId);
            // Rank on the IN-SEASON delta (current - enroll baseline), not the
            // agent's lifetime return (L1).
            int256 delta = int256(ret) - int256(baselineReturnBps[seasonId][tokenId]);
            if (delta > prev) revert HintNotSorted();
            prev = delta;
        }
        // Clear the scratch set so it carries no state into the next settle().
        for (uint256 i = 0; i < n; i++) {
            _seenInSettle[sortedTokens[i]] = false;
        }

        s.settled = true;

        uint256 pool = s.prizePool;
        uint256 totalPaid = 0;
        if (n >= 1) {
            uint256 amt = (pool * FIRST_PRIZE_BPS) / 10_000;
            _pay(seasonId, sortedTokens[0], amt);
            totalPaid += amt;
        }
        if (n >= 2) {
            uint256 amt = (pool * SECOND_PRIZE_BPS) / 10_000;
            _pay(seasonId, sortedTokens[1], amt);
            totalPaid += amt;
        }
        if (n >= 3) {
            uint256 amt = (pool * THIRD_PRIZE_BPS) / 10_000;
            _pay(seasonId, sortedTokens[2], amt);
            totalPaid += amt;
        }

        // Refund the unpaid remainder (fewer than 3 winners) to the creator
        // instead of stranding it. Falls back to the pull ledger on push failure.
        uint256 remainder = pool - totalPaid;
        if (remainder > 0) {
            (bool ok, ) = s.creator.call{value: remainder}("");
            if (!ok) pendingWithdrawals[s.creator] += remainder;
        }

        emit Settled(seasonId, sortedTokens, totalPaid);
    }

    function participantCount(uint256 seasonId) external view returns (uint256) {
        return participants[seasonId].length;
    }

    function getParticipants(uint256 seasonId) external view returns (uint256[] memory) {
        return participants[seasonId];
    }

    function _pay(uint256 seasonId, uint256 tokenId, uint256 amount) private {
        address winner = inft.ownerOf(tokenId);
        (bool ok, ) = winner.call{value: amount}("");
        // Never let a hostile/contract recipient revert settlement — credit the
        // amount for later withdraw() instead of reverting the whole payout.
        if (!ok) pendingWithdrawals[winner] += amount;
        emit PrizeAwarded(seasonId, tokenId, winner, amount);
    }

    /// Claim a prize or refund that couldn't be pushed during settle().
    function withdraw() external nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        if (amount == 0) revert NothingToWithdraw();
        pendingWithdrawals[msg.sender] = 0;
        (bool ok, ) = msg.sender.call{value: amount}("");
        if (!ok) revert PayoutFailed();
    }
}
