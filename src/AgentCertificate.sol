// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

// Append-only registry of backtest certificates. Admin is reserved for v0.3+ —
// no admin functions are exposed in v0.2; submissions remain immutable.
contract AgentCertificate is Ownable2Step {
    uint8 internal constant TIER_T1 = 1;
    uint8 internal constant TIER_T2 = 2;
    uint8 internal constant TIER_T3 = 3;

    uint8 internal constant MARKET_SPOT = 0;
    uint8 internal constant MARKET_PERP = 1;

    struct Certificate {
        bytes32 runHash;
        bytes32 storageRootHash;
        bytes32 datasetHash;
        bytes32 attestationHash; // 0x0 for T1/T2, TEE quote root for T3
        int128  totalReturnBps;
        uint128 sharpeX1000;
        address owner;
        uint48  createdAt;
        uint16  maxDrawdownBps;
        uint16  winRateBps;
        uint8   trustTier;       // 1=T1, 2=T2, 3=T3
        uint8   market;          // 0=spot, 1=perp
    }

    error EmptyHash();
    error UnknownCertificate();
    error InvalidTier();
    error InvalidMarket();
    error AttestationRequired();
    error AttestationForbidden();

    event CertificateSubmitted(
        uint256 indexed certId,
        address indexed owner,
        bytes32 indexed runHash,
        bytes32 storageRootHash,
        uint8   trustTier,
        uint8   market
    );

    uint256 public nextCertId = 1;
    mapping(uint256 => Certificate) private _certs;

    constructor(address admin) Ownable(admin) {}

    function submit(
        bytes32 runHash,
        bytes32 storageRootHash,
        bytes32 datasetHash,
        bytes32 attestationHash,
        int128  totalReturnBps,
        uint128 sharpeX1000,
        uint16  maxDrawdownBps,
        uint16  winRateBps,
        uint8   trustTier,
        uint8   market
    ) external returns (uint256 certId) {
        if (runHash == bytes32(0) || storageRootHash == bytes32(0) || datasetHash == bytes32(0)) {
            revert EmptyHash();
        }
        if (trustTier < TIER_T1 || trustTier > TIER_T3) revert InvalidTier();
        if (market != MARKET_SPOT && market != MARKET_PERP) revert InvalidMarket();

        // T1/T2 must NOT carry an attestation; T3 MUST carry one.
        if (trustTier == TIER_T3 && attestationHash == bytes32(0)) revert AttestationRequired();
        if (trustTier != TIER_T3 && attestationHash != bytes32(0)) revert AttestationForbidden();

        unchecked { certId = nextCertId++; }

        _certs[certId] = Certificate({
            runHash:          runHash,
            storageRootHash:  storageRootHash,
            datasetHash:      datasetHash,
            attestationHash:  attestationHash,
            totalReturnBps:   totalReturnBps,
            sharpeX1000:      sharpeX1000,
            owner:            msg.sender,
            createdAt:        uint48(block.timestamp),
            maxDrawdownBps:   maxDrawdownBps,
            winRateBps:       winRateBps,
            trustTier:        trustTier,
            market:           market
        });

        emit CertificateSubmitted(certId, msg.sender, runHash, storageRootHash, trustTier, market);
    }

    function get(uint256 certId) external view returns (Certificate memory cert) {
        cert = _certs[certId];
        if (cert.owner == address(0)) revert UnknownCertificate();
    }

    function exists(uint256 certId) external view returns (bool) {
        return _certs[certId].owner != address(0);
    }
}
