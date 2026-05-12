// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {LiveCertificate} from "../src/LiveCertificate.sol";

/// Minimal ERC-721 stub so LiveCertificate's `ownerOf` lookups resolve in
/// tests without spinning up the real ZeroArenaINFT (which carries its own
/// oracle + certificate dependencies — orthogonal to what we're testing).
contract MockINFT {
    mapping(uint256 => address) public owners;

    function setOwner(uint256 tokenId, address owner) external {
        owners[tokenId] = owner;
    }

    function ownerOf(uint256 tokenId) external view returns (address) {
        address o = owners[tokenId];
        require(o != address(0), "no owner");
        return o;
    }
}

contract LiveCertificateTest is Test {
    LiveCertificate live;
    MockINFT inft;

    address admin    = makeAddr("admin");
    address operator = makeAddr("operator");
    address alice    = makeAddr("alice");
    address bob      = makeAddr("bob");

    uint256 constant TOKEN_A = 1;

    bytes32 constant GENESIS_HASH = keccak256("static-cert-runhash");

    function setUp() public {
        inft = new MockINFT();
        live = new LiveCertificate(admin, address(inft));

        vm.prank(admin);
        live.setUpdater(operator, true);

        inft.setOwner(TOKEN_A, alice);
    }

    // ─── start ────────────────────────────────────────────────────────────

    function test_start_records_initial_state() public {
        vm.prank(alice);
        live.start(TOKEN_A, GENESIS_HASH);

        LiveCertificate.LiveRun memory r = live.get(TOKEN_A);
        assertEq(r.cumulativeHash, GENESIS_HASH);
        assertEq(r.epochCount, 0);
        assertEq(r.status, 0);
        assertEq(uint256(r.startedAt), block.timestamp);
        assertEq(uint256(r.lastUpdatedAt), block.timestamp);
        assertTrue(live.isActive(TOKEN_A));
    }

    function test_start_rejects_non_owner() public {
        vm.prank(bob);
        vm.expectRevert(LiveCertificate.NotTokenOwner.selector);
        live.start(TOKEN_A, GENESIS_HASH);
    }

    function test_start_rejects_zero_genesis_hash() public {
        vm.prank(alice);
        vm.expectRevert(LiveCertificate.EmptyHash.selector);
        live.start(TOKEN_A, bytes32(0));
    }

    function test_start_rejects_double_start() public {
        vm.prank(alice);
        live.start(TOKEN_A, GENESIS_HASH);

        vm.prank(alice);
        vm.expectRevert(LiveCertificate.AlreadyStarted.selector);
        live.start(TOKEN_A, GENESIS_HASH);
    }

    // ─── update ───────────────────────────────────────────────────────────

    function test_update_extends_hash_chain() public {
        vm.prank(alice);
        live.start(TOKEN_A, GENESIS_HASH);

        bytes32 epoch0 = keccak256("epoch-0");
        bytes32 expectedCum = keccak256(abi.encodePacked(GENESIS_HASH, epoch0));

        vm.prank(operator);
        live.update(TOKEN_A, 0, epoch0, int128(120), uint128(1500), uint16(400), uint16(5500));

        LiveCertificate.LiveRun memory r = live.get(TOKEN_A);
        assertEq(r.cumulativeHash, expectedCum);
        assertEq(r.epochCount, 1);
        assertEq(r.liveTotalReturnBps, int128(120));
        assertEq(r.liveSharpeX1000, uint128(1500));
        assertEq(r.liveMaxDrawdownBps, uint16(400));
        assertEq(r.liveWinRateBps, uint16(5500));
    }

    function test_update_chain_replay_matches_off_chain() public {
        // Off-chain verifier replay: take genesis, fold N epochs, assert it
        // equals the on-chain cumulativeHash.
        vm.prank(alice);
        live.start(TOKEN_A, GENESIS_HASH);

        bytes32 expectedCum = GENESIS_HASH;
        for (uint64 i = 0; i < 5; i++) {
            bytes32 epochHash = keccak256(abi.encodePacked("epoch", i));
            expectedCum = keccak256(abi.encodePacked(expectedCum, epochHash));
            vm.prank(operator);
            live.update(TOKEN_A, i, epochHash, 0, 0, 0, 0);
        }
        assertEq(live.get(TOKEN_A).cumulativeHash, expectedCum);
        assertEq(live.get(TOKEN_A).epochCount, 5);
    }

    function test_update_rejects_unauthorized_caller() public {
        vm.prank(alice);
        live.start(TOKEN_A, GENESIS_HASH);

        vm.prank(alice); // alice is the owner, not an updater
        vm.expectRevert(LiveCertificate.UnauthorizedUpdater.selector);
        live.update(TOKEN_A, 0, keccak256("epoch-0"), 0, 0, 0, 0);
    }

    function test_update_rejects_out_of_order_epoch() public {
        vm.prank(alice);
        live.start(TOKEN_A, GENESIS_HASH);

        vm.prank(operator);
        live.update(TOKEN_A, 0, keccak256("e0"), 0, 0, 0, 0);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(LiveCertificate.EpochOutOfOrder.selector, 1, 5));
        live.update(TOKEN_A, 5, keccak256("e5"), 0, 0, 0, 0);
    }

    function test_update_rejects_zero_epoch_hash() public {
        vm.prank(alice);
        live.start(TOKEN_A, GENESIS_HASH);

        vm.prank(operator);
        vm.expectRevert(LiveCertificate.EmptyHash.selector);
        live.update(TOKEN_A, 0, bytes32(0), 0, 0, 0, 0);
    }

    function test_update_rejects_when_not_started() public {
        vm.prank(operator);
        vm.expectRevert(LiveCertificate.NotStarted.selector);
        live.update(TOKEN_A, 0, keccak256("e0"), 0, 0, 0, 0);
    }

    // ─── stop / liquidate ─────────────────────────────────────────────────

    function test_stop_flips_status_and_blocks_updates() public {
        vm.prank(alice);
        live.start(TOKEN_A, GENESIS_HASH);

        vm.prank(alice);
        live.stop(TOKEN_A);

        assertEq(live.get(TOKEN_A).status, 1);
        assertFalse(live.isActive(TOKEN_A));

        vm.prank(operator);
        vm.expectRevert(LiveCertificate.NotActive.selector);
        live.update(TOKEN_A, 0, keccak256("e0"), 0, 0, 0, 0);
    }

    function test_stop_rejects_non_owner() public {
        vm.prank(alice);
        live.start(TOKEN_A, GENESIS_HASH);

        vm.prank(bob);
        vm.expectRevert(LiveCertificate.NotTokenOwner.selector);
        live.stop(TOKEN_A);
    }

    function test_markLiquidated_operator_only() public {
        vm.prank(alice);
        live.start(TOKEN_A, GENESIS_HASH);

        vm.prank(alice);
        vm.expectRevert(LiveCertificate.UnauthorizedUpdater.selector);
        live.markLiquidated(TOKEN_A);

        vm.prank(operator);
        live.markLiquidated(TOKEN_A);
        assertEq(live.get(TOKEN_A).status, 2);
    }

    // ─── admin ────────────────────────────────────────────────────────────

    function test_setUpdater_only_owner() public {
        address mallory = makeAddr("mallory");
        vm.prank(mallory);
        vm.expectRevert();
        live.setUpdater(mallory, true);
    }

    function test_setUpdater_can_revoke() public {
        vm.prank(admin);
        live.setUpdater(operator, false);

        vm.prank(alice);
        live.start(TOKEN_A, GENESIS_HASH);

        vm.prank(operator);
        vm.expectRevert(LiveCertificate.UnauthorizedUpdater.selector);
        live.update(TOKEN_A, 0, keccak256("e0"), 0, 0, 0, 0);
    }

    // ─── fuzz ─────────────────────────────────────────────────────────────

    function testFuzz_update_chain_extends_correctly(bytes32 epochHash, int128 ret) public {
        vm.assume(epochHash != bytes32(0));
        vm.prank(alice);
        live.start(TOKEN_A, GENESIS_HASH);

        bytes32 expected = keccak256(abi.encodePacked(GENESIS_HASH, epochHash));
        vm.prank(operator);
        live.update(TOKEN_A, 0, epochHash, ret, 0, 0, 0);

        assertEq(live.get(TOKEN_A).cumulativeHash, expected);
        assertEq(live.get(TOKEN_A).liveTotalReturnBps, ret);
    }
}
