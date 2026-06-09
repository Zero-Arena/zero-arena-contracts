// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IERC7857} from "./interfaces/IERC7857.sol";
import {IReencryptionOracle} from "./interfaces/IReencryptionOracle.sol";
import {AgentCertificate} from "./AgentCertificate.sol";

// ERC-7857 iNFT. Mint gated by AgentCertificate thresholds. Vanilla ERC-721
// transfers are disabled; ownership moves only via `transfer` / `clone`, which
// require an oracle proof that the sealed key has been re-encrypted for `to`.
contract ZeroArenaINFT is ERC721, Ownable2Step, IERC7857 {
    error VanillaTransferDisabled();
    error CertificateNotOwned();
    error ThresholdNotMet();
    error InvalidProof();
    error WrongOwner();
    error TokenDoesNotExist();
    error InvalidRecipient();
    error EmptyMetadata();

    event AgentMinted(
        uint256 indexed tokenId,
        address indexed owner,
        uint256 indexed certificateId,
        bytes32 metadataHash,
        bytes32 storageRoot
    );
    event SealedKeyDelivered(uint256 indexed tokenId, address indexed to, bytes sealedKey);
    event ThresholdsUpdated(int128 minTotalReturnBps, uint128 minSharpeX1000);

    AgentCertificate public immutable certificateContract;
    IReencryptionOracle public oracle;

    int128  public minTotalReturnBps;
    uint128 public minSharpeX1000 = 1000; // Sharpe >= 1.0

    mapping(uint256 => bytes32) public metadataHashes;
    mapping(uint256 => bytes32) public storageRoots;
    mapping(uint256 => uint256) public certificateOf;
    mapping(uint256 => mapping(address => bytes)) public authorizations;
    // Per-token transfer nonce (M3): bound into the oracle proof + incremented on
    // each transfer so a captured proof can't be replayed within its deadline.
    mapping(uint256 => uint256) public transferNonce;

    uint256 public nextTokenId = 1;

    constructor(address admin, address oracleAddress, address certificate)
        ERC721("Zero Arena Agent", "ZAA")
        Ownable(admin)
    {
        require(oracleAddress != address(0) && certificate != address(0), "zero addr");
        oracle = IReencryptionOracle(oracleAddress);
        certificateContract = AgentCertificate(certificate);
        emit OracleUpdated(address(0), oracleAddress);
    }

    function setOracle(address newOracle) external onlyOwner {
        require(newOracle != address(0), "zero addr");
        address old = address(oracle);
        oracle = IReencryptionOracle(newOracle);
        emit OracleUpdated(old, newOracle);
    }

    function setThresholds(int128 minReturn, uint128 minSharpe) external onlyOwner {
        minTotalReturnBps = minReturn;
        minSharpeX1000 = minSharpe;
        emit ThresholdsUpdated(minReturn, minSharpe);
    }

    function mint(uint256 certificateId, bytes32 metadataHash, bytes32 storageRoot)
        external
        returns (uint256 tokenId)
    {
        if (metadataHash == bytes32(0) || storageRoot == bytes32(0)) revert EmptyMetadata();

        AgentCertificate.Certificate memory cert = certificateContract.get(certificateId);
        if (cert.owner != msg.sender) revert CertificateNotOwned();
        if (cert.totalReturnBps < minTotalReturnBps || cert.sharpeX1000 < minSharpeX1000) {
            revert ThresholdNotMet();
        }

        unchecked { tokenId = nextTokenId++; }

        metadataHashes[tokenId] = metadataHash;
        storageRoots[tokenId] = storageRoot;
        certificateOf[tokenId] = certificateId;

        _mint(msg.sender, tokenId);
        emit AgentMinted(tokenId, msg.sender, certificateId, metadataHash, storageRoot);
        emit MetadataUpdated(tokenId, metadataHash);
    }

    // proof = abi.encode(bytes32 newMetadataHash, uint256 deadline, bytes signature)
    function transfer(
        address from,
        address to,
        uint256 tokenId,
        bytes calldata sealedKey,
        bytes calldata proof
    ) external override {
        if (to == address(0)) revert InvalidRecipient();
        address current = _requireOwned(tokenId);
        if (current != from) revert WrongOwner();
        if (msg.sender != from && !isApprovedForAll(from, msg.sender) && getApproved(tokenId) != msg.sender) {
            revert WrongOwner();
        }

        (bytes32 newMetadataHash, uint256 deadline, bytes memory signature) =
            abi.decode(proof, (bytes32, uint256, bytes));

        uint256 nonce = transferNonce[tokenId];
        if (!oracle.verifyTransfer(
            address(this), tokenId, from, to,
            keccak256(sealedKey), newMetadataHash, nonce, deadline, signature
        )) revert InvalidProof();
        // Consume the nonce so this exact proof can't be replayed (M3).
        unchecked { transferNonce[tokenId] = nonce + 1; }

        if (newMetadataHash != metadataHashes[tokenId]) {
            metadataHashes[tokenId] = newMetadataHash;
            emit MetadataUpdated(tokenId, newMetadataHash);
        }

        _update(to, tokenId, address(0));
        emit SealedKeyDelivered(tokenId, to, sealedKey);
    }

    function clone(address to, uint256 tokenId, bytes calldata sealedKey, bytes calldata proof)
        external
        override
        returns (uint256 newTokenId)
    {
        if (to == address(0)) revert InvalidRecipient();
        address owner_ = _requireOwned(tokenId);
        if (msg.sender != owner_) revert WrongOwner();

        (bytes32 newMetadataHash, uint256 deadline, bytes memory signature) =
            abi.decode(proof, (bytes32, uint256, bytes));

        unchecked { newTokenId = nextTokenId++; }

        // Fresh newTokenId → its nonce starts at 0; uniqueness of newTokenId
        // already makes a clone proof single-use. Pass it to keep the digest
        // shape uniform with transfer() (M3).
        if (!oracle.verifyTransfer(
            address(this), newTokenId, owner_, to,
            keccak256(sealedKey), newMetadataHash, transferNonce[newTokenId], deadline, signature
        )) revert InvalidProof();

        metadataHashes[newTokenId] = newMetadataHash;
        storageRoots[newTokenId] = storageRoots[tokenId];
        certificateOf[newTokenId] = certificateOf[tokenId];

        _mint(to, newTokenId);
        emit MetadataUpdated(newTokenId, newMetadataHash);
        emit SealedKeyDelivered(newTokenId, to, sealedKey);
    }

    function authorizeUsage(uint256 tokenId, address executor, bytes calldata permissions)
        external
        override
    {
        if (_ownerOf(tokenId) == address(0)) revert TokenDoesNotExist();
        if (msg.sender != _ownerOf(tokenId)) revert WrongOwner();
        authorizations[tokenId][executor] = permissions;
        emit UsageAuthorized(tokenId, executor);
    }

    // Vanilla 721 transfers would leak the encrypted blob to a recipient
    // without a key — force everything through the oracle flow above.
    function transferFrom(address, address, uint256) public pure override(ERC721, IERC721) {
        revert VanillaTransferDisabled();
    }

    function safeTransferFrom(address, address, uint256, bytes memory)
        public
        pure
        override(ERC721, IERC721)
    {
        revert VanillaTransferDisabled();
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, IERC165) returns (bool) {
        return interfaceId == type(IERC7857).interfaceId || super.supportsInterface(interfaceId);
    }
}
