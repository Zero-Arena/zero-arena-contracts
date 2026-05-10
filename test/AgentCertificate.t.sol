// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AgentCertificate} from "../src/AgentCertificate.sol";

contract AgentCertificateTest is Test {
    AgentCertificate cert;

    address alice = makeAddr("alice");

    uint8 constant T1 = 1;
    uint8 constant T2 = 2;
    uint8 constant T3 = 3;

    uint8 constant SPOT = 0;
    uint8 constant PERP = 1;

    function setUp() public {
        cert = new AgentCertificate();
    }

    function test_submit_assigns_sequential_ids_and_stores_metrics() public {
        vm.prank(alice);
        uint256 id = cert.submit(
            keccak256("run"),
            keccak256("storage"),
            keccak256("dataset"),
            bytes32(0),         // T2 — no attestation in v0.1
            int128(500),        // +5%
            uint128(1500),      // Sharpe 1.5
            uint16(800),        // 8% drawdown
            uint16(5500),       // 55% win rate
            T2,
            SPOT
        );

        assertEq(id, 1);

        AgentCertificate.Certificate memory c = cert.get(id);
        assertEq(c.runHash, keccak256("run"));
        assertEq(c.attestationHash, bytes32(0));
        assertEq(c.owner, alice);
        assertEq(c.totalReturnBps, int128(500));
        assertEq(c.sharpeX1000, uint128(1500));
        assertEq(c.maxDrawdownBps, uint16(800));
        assertEq(c.winRateBps, uint16(5500));
        assertEq(c.trustTier, T2);
        assertEq(c.market, SPOT);
        assertGt(c.createdAt, 0);
    }

    function test_submit_T3_requires_attestation() public {
        vm.expectRevert(AgentCertificate.AttestationRequired.selector);
        cert.submit(
            keccak256("r"), keccak256("s"), keccak256("d"),
            bytes32(0), 0, 1000, 0, 0, T3, SPOT
        );
    }

    function test_submit_T2_forbids_attestation() public {
        vm.expectRevert(AgentCertificate.AttestationForbidden.selector);
        cert.submit(
            keccak256("r"), keccak256("s"), keccak256("d"),
            keccak256("attestation"),
            0, 1000, 0, 0, T2, SPOT
        );
    }

    function test_submit_rejects_invalid_tier() public {
        vm.expectRevert(AgentCertificate.InvalidTier.selector);
        cert.submit(
            keccak256("r"), keccak256("s"), keccak256("d"),
            bytes32(0), 0, 1000, 0, 0, 0, SPOT  // tier 0 invalid
        );

        vm.expectRevert(AgentCertificate.InvalidTier.selector);
        cert.submit(
            keccak256("r"), keccak256("s"), keccak256("d"),
            bytes32(0), 0, 1000, 0, 0, 4, SPOT  // tier 4 invalid
        );
    }

    function test_submit_rejects_invalid_market() public {
        vm.expectRevert(AgentCertificate.InvalidMarket.selector);
        cert.submit(
            keccak256("r"), keccak256("s"), keccak256("d"),
            bytes32(0), 0, 1000, 0, 0, T2, 2  // market 2 invalid
        );
    }

    function test_submit_rejects_zero_hashes() public {
        vm.expectRevert(AgentCertificate.EmptyHash.selector);
        cert.submit(
            bytes32(0), keccak256("s"), keccak256("d"),
            bytes32(0), 0, 1000, 0, 0, T2, SPOT
        );
    }

    function test_submit_perp_market_round_trips() public {
        uint256 id = cert.submit(
            keccak256("r"), keccak256("s"), keccak256("d"),
            bytes32(0), int128(1200), uint128(2000), uint16(1500), uint16(6000),
            T2, PERP
        );
        assertEq(cert.get(id).market, PERP);
    }

    function test_get_unknown_reverts() public {
        vm.expectRevert(AgentCertificate.UnknownCertificate.selector);
        cert.get(42);
    }

    function testFuzz_submit_preserves_metrics(
        bytes32 runHash,
        bytes32 storageHash,
        bytes32 datasetHash,
        int128  ret,
        uint128 sharpe,
        uint16  dd,
        uint16  wr,
        bool    perp
    ) public {
        vm.assume(runHash != 0 && storageHash != 0 && datasetHash != 0);

        uint8 m = perp ? PERP : SPOT;
        uint256 id = cert.submit(
            runHash, storageHash, datasetHash, bytes32(0),
            ret, sharpe, dd, wr, T2, m
        );
        AgentCertificate.Certificate memory c = cert.get(id);

        assertEq(c.runHash, runHash);
        assertEq(c.totalReturnBps, ret);
        assertEq(c.sharpeX1000, sharpe);
        assertEq(c.maxDrawdownBps, dd);
        assertEq(c.winRateBps, wr);
        assertEq(c.trustTier, T2);
        assertEq(c.market, m);
    }
}
