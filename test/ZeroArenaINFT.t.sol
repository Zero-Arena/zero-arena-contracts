// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AgentCertificate} from "../src/AgentCertificate.sol";
import {ReencryptionOracle} from "../src/oracle/ReencryptionOracle.sol";
import {ZeroArenaINFT} from "../src/ZeroArenaINFT.sol";
import {IERC7857} from "../src/interfaces/IERC7857.sol";

contract ZeroArenaINFTTest is Test {
    AgentCertificate certs;
    ReencryptionOracle oracle;
    ZeroArenaINFT inft;

    address admin = makeAddr("admin");
    address alice = makeAddr("alice");
    address bob   = makeAddr("bob");

    uint256 signerKey = 0xA11CE;
    address signerAddr;

    bytes32 constant META = keccak256("metadata-v1");
    bytes32 constant ROOT = keccak256("storage-root");

    function setUp() public {
        signerAddr = vm.addr(signerKey);
        certs = new AgentCertificate(admin);
        oracle = new ReencryptionOracle(admin, signerAddr);
        inft = new ZeroArenaINFT(admin, address(oracle), address(certs));
    }

    uint8 constant T2 = 2;
    uint8 constant SPOT = 0;

    function _submitPassingCert(address owner) internal returns (uint256) {
        vm.prank(owner);
        return certs.submit(
            keccak256("r"), keccak256("s"), keccak256("d"),
            bytes32(0),
            int128(500), uint128(1500), uint16(800), uint16(5500),
            T2, SPOT
        );
    }

    function _signProof(
        uint256 tokenId,
        address from,
        address to,
        bytes memory sealedKey,
        bytes32 newMetadata,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes memory proof) {
        bytes32 inner = keccak256(
            abi.encode(
                block.chainid, address(inft), tokenId, from, to,
                keccak256(sealedKey), newMetadata, nonce, deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", inner));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digest);
        proof = abi.encode(newMetadata, deadline, abi.encodePacked(r, s, v));
    }

    function test_mint_succeeds_with_passing_cert() public {
        uint256 certId = _submitPassingCert(alice);

        vm.prank(alice);
        uint256 tokenId = inft.mint(certId, META, ROOT);

        assertEq(tokenId, 1);
        assertEq(inft.ownerOf(tokenId), alice);
        assertEq(inft.metadataHashes(tokenId), META);
        assertEq(inft.storageRoots(tokenId), ROOT);
        assertEq(inft.certificateOf(tokenId), certId);
    }

    function test_mint_rejects_below_threshold() public {
        vm.prank(alice);
        uint256 certId = certs.submit(
            keccak256("r"), keccak256("s"), keccak256("d"),
            bytes32(0),
            int128(500), uint128(500), uint16(800), uint16(5500), // Sharpe 0.5 < 1.0
            T2, SPOT
        );

        vm.prank(alice);
        vm.expectRevert(ZeroArenaINFT.ThresholdNotMet.selector);
        inft.mint(certId, META, ROOT);
    }

    function test_mint_rejects_non_cert_owner() public {
        uint256 certId = _submitPassingCert(alice);

        vm.prank(bob);
        vm.expectRevert(ZeroArenaINFT.CertificateNotOwned.selector);
        inft.mint(certId, META, ROOT);
    }

    function test_vanilla_transferFrom_reverts() public {
        uint256 certId = _submitPassingCert(alice);
        vm.prank(alice);
        uint256 tokenId = inft.mint(certId, META, ROOT);

        vm.prank(alice);
        vm.expectRevert(ZeroArenaINFT.VanillaTransferDisabled.selector);
        inft.transferFrom(alice, bob, tokenId);
    }

    function test_oracle_transfer_succeeds_and_updates_metadata() public {
        uint256 certId = _submitPassingCert(alice);
        vm.prank(alice);
        uint256 tokenId = inft.mint(certId, META, ROOT);

        bytes memory sealedKey = bytes("sealed-for-bob");
        bytes32 newMeta = keccak256("metadata-v2");
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory proof = _signProof(tokenId, alice, bob, sealedKey, newMeta, 0, deadline);

        vm.prank(alice);
        inft.transfer(alice, bob, tokenId, sealedKey, proof);

        assertEq(inft.ownerOf(tokenId), bob);
        assertEq(inft.metadataHashes(tokenId), newMeta);
        assertEq(inft.transferNonce(tokenId), 1); // nonce consumed (M3)
    }

    // M3 — a captured proof cannot be replayed once its nonce is consumed.
    function test_transfer_proof_replay_reverts() public {
        uint256 certId = _submitPassingCert(alice);
        vm.prank(alice);
        uint256 tokenId = inft.mint(certId, META, ROOT);

        bytes memory sealedKey = bytes("sealed-for-bob");
        bytes32 newMeta = keccak256("metadata-v2");
        uint256 deadline = block.timestamp + 1 hours;

        // alice -> bob, signed at nonce 0.
        bytes memory proof0 = _signProof(tokenId, alice, bob, sealedKey, newMeta, 0, deadline);
        vm.prank(alice);
        inft.transfer(alice, bob, tokenId, sealedKey, proof0);
        assertEq(inft.ownerOf(tokenId), bob);

        // bob -> alice, fresh proof at the now-current nonce 1.
        bytes memory proof1 = _signProof(tokenId, bob, alice, sealedKey, newMeta, 1, deadline);
        vm.prank(bob);
        inft.transfer(bob, alice, tokenId, sealedKey, proof1);
        assertEq(inft.ownerOf(tokenId), alice);

        // Replay the FIRST proof (nonce 0) while still inside its deadline — the
        // contract is now at nonce 2, so the recovered signer won't match.
        vm.prank(alice);
        vm.expectRevert(ZeroArenaINFT.InvalidProof.selector);
        inft.transfer(alice, bob, tokenId, sealedKey, proof0);
    }

    function test_transfer_with_bad_signature_reverts() public {
        uint256 certId = _submitPassingCert(alice);
        vm.prank(alice);
        uint256 tokenId = inft.mint(certId, META, ROOT);

        // Sign with a non-trusted key.
        uint256 badKey = 0xBADBAD;
        bytes memory sealedKey = bytes("x");
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 inner = keccak256(
            abi.encode(
                block.chainid, address(inft), tokenId, alice, bob,
                keccak256(sealedKey), META, uint256(0), deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", inner));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(badKey, digest);
        bytes memory proof = abi.encode(META, deadline, abi.encodePacked(r, s, v));

        vm.prank(alice);
        vm.expectRevert(ZeroArenaINFT.InvalidProof.selector);
        inft.transfer(alice, bob, tokenId, sealedKey, proof);
    }

    function test_supportsInterface_includes_erc7857() public view {
        assertTrue(inft.supportsInterface(type(IERC7857).interfaceId));
    }

    function test_authorizeUsage_records_permissions() public {
        uint256 certId = _submitPassingCert(alice);
        vm.prank(alice);
        uint256 tokenId = inft.mint(certId, META, ROOT);

        bytes memory perms = bytes("read-only");
        vm.prank(alice);
        inft.authorizeUsage(tokenId, bob, perms);

        assertEq(inft.authorizations(tokenId, bob), perms);
    }
}
