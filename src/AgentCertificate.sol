// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title AgentCertificate
/// @notice Append-only registry of verifiable backtest results. Each certificate
///         binds an agent's run log (stored encrypted on 0G Storage) to its
///         deterministic `runHash` and headline metrics. The iNFT contract
///         consults this registry at mint time to enforce performance gates.
/// @dev Storage is packed into 5 slots per certificate (160 gas saved vs. naive layout):
///        slot 0 — runHash
///        slot 1 — storageRootHash
///        slot 2 — datasetHash
///        slot 3 — totalReturnBps (int128) | sharpeX1000 (uint128)
///        slot 4 — owner (160) | createdAt (64) | maxDrawdownBps (16) | winRateBps (16)
contract AgentCertificate {
    struct Certificate {
        bytes32 runHash;
        bytes32 storageRootHash;
        bytes32 datasetHash;
        int128  totalReturnBps;
        uint128 sharpeX1000;
        address owner;
        uint64  createdAt;
        uint16  maxDrawdownBps;
        uint16  winRateBps;
    }

    error EmptyHash();
    error UnknownCertificate();

    event CertificateSubmitted(
        uint256 indexed certId,
        address indexed owner,
        bytes32 indexed runHash,
        bytes32 storageRootHash
    );

    uint256 public nextCertId = 1;
    mapping(uint256 => Certificate) private _certs;

    function submit(
        bytes32 runHash,
        bytes32 storageRootHash,
        bytes32 datasetHash,
        int128  totalReturnBps,
        uint128 sharpeX1000,
        uint16  maxDrawdownBps,
        uint16  winRateBps
    ) external returns (uint256 certId) {
        if (runHash == bytes32(0) || storageRootHash == bytes32(0) || datasetHash == bytes32(0)) {
            revert EmptyHash();
        }

        unchecked {
            certId = nextCertId++;
        }

        _certs[certId] = Certificate({
            runHash:          runHash,
            storageRootHash:  storageRootHash,
            datasetHash:      datasetHash,
            totalReturnBps:   totalReturnBps,
            sharpeX1000:      sharpeX1000,
            owner:            msg.sender,
            createdAt:        uint64(block.timestamp),
            maxDrawdownBps:   maxDrawdownBps,
            winRateBps:       winRateBps
        });

        emit CertificateSubmitted(certId, msg.sender, runHash, storageRootHash);
    }

    function get(uint256 certId) external view returns (Certificate memory cert) {
        cert = _certs[certId];
        if (cert.owner == address(0)) revert UnknownCertificate();
    }

    function exists(uint256 certId) external view returns (bool) {
        return _certs[certId].owner != address(0);
    }
}
