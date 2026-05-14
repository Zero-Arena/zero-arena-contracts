// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {AgentCertificate} from "./AgentCertificate.sol";
import {ZeroArenaINFT} from "./ZeroArenaINFT.sol";

// Append-only hash chain extending each iNFT's static runHash with one
// operator-signed epoch at a time (RFC-001).
contract LiveCertificate is Ownable2Step {
    uint8 internal constant STATUS_ACTIVE     = 0;
    uint8 internal constant STATUS_STOPPED    = 1;
    uint8 internal constant STATUS_LIQUIDATED = 2;

    struct LiveRun {
        bytes32 cumulativeHash;
        uint64  startedAt;
        uint64  lastUpdatedAt;
        uint64  epochCount;
        uint8   status;
        uint16  liveMaxDrawdownBps;
        uint16  liveWinRateBps;
        int128  liveTotalReturnBps;
        uint128 liveSharpeX1000;
    }

    error NotTokenOwner();
    error AlreadyStarted();
    error NotStarted();
    error NotActive();
    error EpochOutOfOrder(uint64 expected, uint64 got);
    error UnauthorizedUpdater();
    error EmptyHash();
    error GenesisMismatch(bytes32 expected, bytes32 got);

    event PaperRunStarted(
        uint256 indexed tokenId,
        address indexed owner,
        uint64  startedAt,
        bytes32 initialCumulativeHash
    );
    event EpochCommitted(
        uint256 indexed tokenId,
        uint64  indexed epochIndex,
        bytes32 cumulativeHash,
        bytes32 epochHash,
        int128  liveTotalReturnBps,
        uint128 liveSharpeX1000
    );
    event PaperRunStopped(uint256 indexed tokenId, uint8 status, uint64 stoppedAt);
    event UpdaterSet(address indexed updater, bool allowed);

    // Stored as the concrete type — start() reads the underlying cert via
    // inft.certificateContract().get() for the genesis cross-check.
    ZeroArenaINFT public immutable inft;

    mapping(uint256 => LiveRun) public runs;
    mapping(address => bool) public authorizedUpdaters;

    constructor(address admin, address inftAddress) Ownable(admin) {
        require(inftAddress != address(0), "zero addr");
        inft = ZeroArenaINFT(inftAddress);
    }

    function setUpdater(address updater, bool allowed) external onlyOwner {
        authorizedUpdaters[updater] = allowed;
        emit UpdaterSet(updater, allowed);
    }

    function start(uint256 tokenId, bytes32 initialCumulativeHash) external {
        if (inft.ownerOf(tokenId) != msg.sender) revert NotTokenOwner();
        if (runs[tokenId].startedAt != 0) revert AlreadyStarted();
        if (initialCumulativeHash == bytes32(0)) revert EmptyHash();

        uint256 certId = inft.certificateOf(tokenId);
        bytes32 certRunHash = inft.certificateContract().get(certId).runHash;
        if (initialCumulativeHash != certRunHash) {
            revert GenesisMismatch({expected: certRunHash, got: initialCumulativeHash});
        }

        runs[tokenId] = LiveRun({
            cumulativeHash:     initialCumulativeHash,
            startedAt:          uint64(block.timestamp),
            lastUpdatedAt:      uint64(block.timestamp),
            epochCount:         0,
            status:             STATUS_ACTIVE,
            liveMaxDrawdownBps: 0,
            liveWinRateBps:     0,
            liveTotalReturnBps: 0,
            liveSharpeX1000:    0
        });

        emit PaperRunStarted(tokenId, msg.sender, uint64(block.timestamp), initialCumulativeHash);
    }

    function stop(uint256 tokenId) external {
        if (inft.ownerOf(tokenId) != msg.sender) revert NotTokenOwner();
        LiveRun storage r = runs[tokenId];
        if (r.startedAt == 0) revert NotStarted();
        if (r.status != STATUS_ACTIVE) revert NotActive();
        r.status = STATUS_STOPPED;
        emit PaperRunStopped(tokenId, STATUS_STOPPED, uint64(block.timestamp));
    }

    function markLiquidated(uint256 tokenId) external {
        if (!authorizedUpdaters[msg.sender]) revert UnauthorizedUpdater();
        LiveRun storage r = runs[tokenId];
        if (r.startedAt == 0) revert NotStarted();
        if (r.status != STATUS_ACTIVE) revert NotActive();
        r.status = STATUS_LIQUIDATED;
        emit PaperRunStopped(tokenId, STATUS_LIQUIDATED, uint64(block.timestamp));
    }

    // cumulativeHash := keccak(cumulativeHash || epochHash). Verifiers replay
    // from the genesis runHash and arrive at the on-chain value.
    function update(
        uint256 tokenId,
        uint64  epochIndex,
        bytes32 epochHash,
        int128  liveTotalReturnBps,
        uint128 liveSharpeX1000,
        uint16  liveMaxDrawdownBps,
        uint16  liveWinRateBps
    ) external {
        if (!authorizedUpdaters[msg.sender]) revert UnauthorizedUpdater();
        if (epochHash == bytes32(0)) revert EmptyHash();

        LiveRun storage r = runs[tokenId];
        if (r.startedAt == 0) revert NotStarted();
        if (r.status != STATUS_ACTIVE) revert NotActive();
        if (epochIndex != r.epochCount) {
            revert EpochOutOfOrder({expected: r.epochCount, got: epochIndex});
        }

        bytes32 newCumulative = keccak256(abi.encodePacked(r.cumulativeHash, epochHash));
        r.cumulativeHash      = newCumulative;
        r.epochCount          = epochIndex + 1;
        r.lastUpdatedAt       = uint64(block.timestamp);
        r.liveTotalReturnBps  = liveTotalReturnBps;
        r.liveSharpeX1000     = liveSharpeX1000;
        r.liveMaxDrawdownBps  = liveMaxDrawdownBps;
        r.liveWinRateBps      = liveWinRateBps;

        emit EpochCommitted(tokenId, epochIndex, newCumulative, epochHash, liveTotalReturnBps, liveSharpeX1000);
    }

    function get(uint256 tokenId) external view returns (LiveRun memory r) {
        r = runs[tokenId];
        if (r.startedAt == 0) revert NotStarted();
    }

    function isActive(uint256 tokenId) external view returns (bool) {
        LiveRun storage r = runs[tokenId];
        return r.startedAt != 0 && r.status == STATUS_ACTIVE;
    }
}
