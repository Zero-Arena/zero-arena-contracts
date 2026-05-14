// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {IReencryptionOracle} from "../interfaces/IReencryptionOracle.sol";

// v0.1 trusted-signer stub. The off-chain service performs the actual
// re-encryption (currently in a simulated TEE) and signs the proof here.
// v0.2 replaces this with a contract that consumes a real TEE attestation.
contract ReencryptionOracle is Ownable2Step, IReencryptionOracle {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    error InvalidSigner();
    error ProofExpired();

    event SignerUpdated(address indexed oldSigner, address indexed newSigner);

    address public signer;

    constructor(address admin, address initialSigner) Ownable(admin) {
        if (initialSigner == address(0)) revert InvalidSigner();
        signer = initialSigner;
        emit SignerUpdated(address(0), initialSigner);
    }

    function setSigner(address newSigner) external onlyOwner {
        if (newSigner == address(0)) revert InvalidSigner();
        address old = signer;
        signer = newSigner;
        emit SignerUpdated(old, newSigner);
    }

    function verifyTransfer(
        address inft,
        uint256 tokenId,
        address from,
        address to,
        bytes32 sealedKeyHash,
        bytes32 newMetadataHash,
        uint256 deadline,
        bytes calldata signature
    ) external view returns (bool) {
        if (block.timestamp > deadline) revert ProofExpired();

        bytes32 digest = keccak256(abi.encode(
            block.chainid, inft, tokenId, from, to,
            sealedKeyHash, newMetadataHash, deadline
        )).toEthSignedMessageHash();

        return digest.recover(signature) == signer;
    }
}
