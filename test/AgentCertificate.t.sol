// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AgentCertificate} from "../src/AgentCertificate.sol";

contract AgentCertificateTest is Test {
    AgentCertificate cert;

    address alice = makeAddr("alice");

    function setUp() public {
        cert = new AgentCertificate();
    }

    function test_submit_assigns_sequential_ids_and_stores_metrics() public {
        vm.prank(alice);
        uint256 id = cert.submit(
            keccak256("run"),
            keccak256("storage"),
            keccak256("dataset"),
            int128(500),       // +5%
            uint128(1500),     // Sharpe 1.5
            uint16(800),       // 8% drawdown
            uint16(5500)       // 55% win rate
        );

        assertEq(id, 1);

        AgentCertificate.Certificate memory c = cert.get(id);
        assertEq(c.runHash, keccak256("run"));
        assertEq(c.owner, alice);
        assertEq(c.totalReturnBps, int128(500));
        assertEq(c.sharpeX1000, uint128(1500));
        assertEq(c.maxDrawdownBps, uint16(800));
        assertEq(c.winRateBps, uint16(5500));
        assertGt(c.createdAt, 0);
    }

    function test_submit_rejects_zero_hashes() public {
        vm.expectRevert(AgentCertificate.EmptyHash.selector);
        cert.submit(bytes32(0), keccak256("s"), keccak256("d"), 0, 1000, 0, 0);
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
        uint16  wr
    ) public {
        vm.assume(runHash != 0 && storageHash != 0 && datasetHash != 0);

        uint256 id = cert.submit(runHash, storageHash, datasetHash, ret, sharpe, dd, wr);
        AgentCertificate.Certificate memory c = cert.get(id);

        assertEq(c.runHash, runHash);
        assertEq(c.totalReturnBps, ret);
        assertEq(c.sharpeX1000, sharpe);
        assertEq(c.maxDrawdownBps, dd);
        assertEq(c.winRateBps, wr);
    }
}
