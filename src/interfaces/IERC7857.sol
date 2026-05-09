// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/// @title IERC7857 — Intelligent NFT (iNFT) standard
/// @notice Per 0G ERC-7857 spec: ownership transfer carries encrypted metadata
///         re-encrypted by an oracle. Vanilla ERC-721 transfers are forbidden
///         on tokens that hold encrypted metadata.
interface IERC7857 is IERC721 {
    event MetadataUpdated(uint256 indexed tokenId, bytes32 newMetadataHash);
    event UsageAuthorized(uint256 indexed tokenId, address indexed executor);
    event OracleUpdated(address indexed oldOracle, address indexed newOracle);

    /// @notice Transfer a token together with re-encrypted metadata.
    /// @param sealedKey symmetric data key sealed against `to`'s pubkey
    /// @param proof oracle attestation that `sealedKey` is the re-encryption
    ///        of the existing data key for `to`
    function transfer(
        address from,
        address to,
        uint256 tokenId,
        bytes calldata sealedKey,
        bytes calldata proof
    ) external;

    /// @notice Mint a copy of an existing token's metadata to `to`.
    function clone(
        address to,
        uint256 tokenId,
        bytes calldata sealedKey,
        bytes calldata proof
    ) external returns (uint256 newTokenId);

    /// @notice Grant `executor` permission to use the token without transferring it.
    function authorizeUsage(uint256 tokenId, address executor, bytes calldata permissions)
        external;
}
