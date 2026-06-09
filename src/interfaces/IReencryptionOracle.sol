// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Verifier for sealed-key proofs from the off-chain oracle. v0.1 trusts a
// single ECDSA signer; v1.0 replaces this with TEE attestation (0G Compute).
interface IReencryptionOracle {
    function verifyTransfer(
        address inft,
        uint256 tokenId,
        address from,
        address to,
        bytes32 sealedKeyHash,
        bytes32 newMetadataHash,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature
    ) external view returns (bool);
}
