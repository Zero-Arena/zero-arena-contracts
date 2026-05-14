// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

// ERC-7857 iNFT standard (0G). Transfers carry an oracle-attested
// re-encryption of the sealed metadata key; vanilla 721 transfers are
// forbidden for tokens holding encrypted metadata.
interface IERC7857 is IERC721 {
    event MetadataUpdated(uint256 indexed tokenId, bytes32 newMetadataHash);
    event UsageAuthorized(uint256 indexed tokenId, address indexed executor);
    event OracleUpdated(address indexed oldOracle, address indexed newOracle);

    function transfer(
        address from,
        address to,
        uint256 tokenId,
        bytes calldata sealedKey,
        bytes calldata proof
    ) external;

    function clone(
        address to,
        uint256 tokenId,
        bytes calldata sealedKey,
        bytes calldata proof
    ) external returns (uint256 newTokenId);

    function authorizeUsage(uint256 tokenId, address executor, bytes calldata permissions) external;
}
