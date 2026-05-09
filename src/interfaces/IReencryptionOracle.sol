// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IReencryptionOracle
/// @notice Verifier for sealed-key proofs produced by the off-chain oracle service.
///         The proof is an ECDSA signature over the canonical message hash defined
///         in `messageHash()`. v0.1 trusts a single signer; production should swap
///         this stub for TEE attestation.
interface IReencryptionOracle {
    /// @notice Verify a transfer proof for token `tokenId`.
    /// @param inft         address of the calling iNFT contract (binds proof to scope)
    /// @param tokenId      token being transferred
    /// @param from         current owner
    /// @param to           recipient
    /// @param sealedKeyHash keccak256 of the sealed data key handed to `to`
    /// @param newMetadataHash hash of the metadata after re-encryption
    /// @param deadline     expiry timestamp of this proof
    /// @param signature    ECDSA(secp256k1) signature by the trusted signer
    function verifyTransfer(
        address inft,
        uint256 tokenId,
        address from,
        address to,
        bytes32 sealedKeyHash,
        bytes32 newMetadataHash,
        uint256 deadline,
        bytes calldata signature
    ) external view returns (bool);
}
