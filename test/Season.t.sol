// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AgentCertificate} from "../src/AgentCertificate.sol";
import {LiveCertificate} from "../src/LiveCertificate.sol";
import {Season} from "../src/Season.sol";

/// @dev Minimal iNFT stub that satisfies the slice of {ZeroArenaINFT} the
///      {Season} contract calls: `ownerOf`, `certificateOf`, and
///      `certificateContract()`. We pair it with a real {AgentCertificate}
///      so the market-mismatch check exercises the real type the production
///      code reads.
contract MockINFT {
    AgentCertificate public certificateContract;
    mapping(uint256 => address) internal _owners;
    mapping(uint256 => uint256) public certificateOf;

    constructor(AgentCertificate certs) {
        certificateContract = certs;
    }

    function setToken(uint256 tokenId, address owner, uint256 certId) external {
        _owners[tokenId] = owner;
        certificateOf[tokenId] = certId;
    }

    function ownerOf(uint256 tokenId) external view returns (address) {
        address o = _owners[tokenId];
        require(o != address(0), "no owner");
        return o;
    }
}

contract SeasonTest is Test {
    AgentCertificate certs;
    LiveCertificate live;
    Season season;
    MockINFT inft;

    address admin    = makeAddr("admin");
    address operator = makeAddr("operator");
    address alice    = makeAddr("alice");
    address bob      = makeAddr("bob");
    address carol    = makeAddr("carol");

    uint8 constant T2   = 2;
    uint8 constant SPOT = 0;
    uint8 constant PERP = 1;

    bytes32 constant DATASET_BTC_15M_SPOT = keccak256("BTCUSDT-15m-spot");

    function setUp() public {
        certs = new AgentCertificate(admin);
        inft = new MockINFT(certs);
        live = new LiveCertificate(admin, address(inft));
        season = new Season(admin, address(live), address(inft));

        vm.prank(admin);
        live.setUpdater(operator, true);

        // Bind tokens 1-3 to spot certificates owned by alice/bob/carol.
        inft.setToken(1, alice, _mintCert(alice, SPOT));
        inft.setToken(2, bob,   _mintCert(bob,   SPOT));
        inft.setToken(3, carol, _mintCert(carol, SPOT));

        // Fund admin so it can create prize-pooled seasons.
        vm.deal(admin, 100 ether);
    }

    function _mintCert(address owner, uint8 market) internal returns (uint256 certId) {
        vm.prank(owner);
        certId = certs.submit(
            _certRunHashFor(owner, market),
            keccak256(abi.encode("s", owner)),
            keccak256(abi.encode("d", market)),
            bytes32(0),
            int128(500), uint128(1500), uint16(800), uint16(5500),
            T2, market
        );
    }

    function _certRunHashFor(address owner, uint8 market) internal pure returns (bytes32) {
        return keccak256(abi.encode("r", owner, market));
    }

    function _defaultSpec(uint64 startsAfter, uint64 durationSec, uint256 prize)
        internal
        view
        returns (Season.SeasonSpec memory)
    {
        return Season.SeasonSpec({
            datasetSpec:    DATASET_BTC_15M_SPOT,
            initialBalance: 10_000,
            feeBps:         10,
            slippageBps:    5,
            market:         0,
            maxLeverage:    1,
            startTime:      uint64(block.timestamp + startsAfter),
            endTime:        uint64(block.timestamp + startsAfter + durationSec),
            prizePool:      prize,
            creator:        address(0), // overwritten by contract
            settled:        false
        });
    }

    // ─── createSeason ──────────────────────────────────────────────────────

    function test_createSeason_emits_event_and_stores_spec() public {
        Season.SeasonSpec memory spec = _defaultSpec(1 hours, 7 days, 1 ether);
        vm.prank(admin);
        uint256 id = season.createSeason{value: 1 ether}(spec);
        assertEq(id, 1);

        (bytes32 datasetSpec, , , , , , , , uint256 pool, address creator, bool settled) =
            season.seasons(id);
        assertEq(datasetSpec, DATASET_BTC_15M_SPOT);
        assertEq(pool, 1 ether);
        assertEq(creator, admin);
        assertFalse(settled);
    }

    function test_createSeason_rejects_underfunded_pool() public {
        Season.SeasonSpec memory spec = _defaultSpec(1 hours, 7 days, 1 ether);
        vm.prank(admin);
        vm.expectRevert(Season.UnderfundedPrizePool.selector);
        season.createSeason{value: 0.5 ether}(spec);
    }

    function test_createSeason_rejects_start_in_past() public {
        Season.SeasonSpec memory spec = _defaultSpec(0, 7 days, 1 ether);
        spec.startTime = uint64(block.timestamp); // exactly now → "<=" check trips
        vm.prank(admin);
        vm.expectRevert(Season.InvalidWindow.selector);
        season.createSeason{value: 1 ether}(spec);
    }

    function test_createSeason_only_owner() public {
        Season.SeasonSpec memory spec = _defaultSpec(1 hours, 7 days, 0);
        vm.prank(bob);
        vm.expectRevert();
        season.createSeason(spec);
    }

    // ─── enroll ───────────────────────────────────────────────────────────

    function test_enroll_adds_to_participants() public {
        vm.prank(admin);
        uint256 id = season.createSeason{value: 1 ether}(_defaultSpec(1 hours, 7 days, 1 ether));

        vm.prank(alice);
        season.enroll(id, 1);
        assertTrue(season.enrolled(id, 1));
        assertEq(season.participantCount(id), 1);
    }

    function test_enroll_rejects_market_mismatch_spot_season_perp_token() public {
        // Issue a perp cert for alice and bind token 10 to it.
        uint256 perpCertId = _mintCert(alice, PERP);
        inft.setToken(10, alice, perpCertId);

        vm.prank(admin);
        uint256 id = season.createSeason{value: 1 ether}(_defaultSpec(1 hours, 7 days, 1 ether)); // market=SPOT

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Season.MarketMismatch.selector, SPOT, PERP));
        season.enroll(id, 10);
    }

    function test_enroll_rejects_market_mismatch_perp_season_spot_token() public {
        Season.SeasonSpec memory spec = _defaultSpec(1 hours, 7 days, 1 ether);
        spec.market = PERP;
        spec.maxLeverage = 5;
        vm.prank(admin);
        uint256 id = season.createSeason{value: 1 ether}(spec);

        // Token 1 has a SPOT cert from setUp.
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Season.MarketMismatch.selector, PERP, SPOT));
        season.enroll(id, 1);
    }

    function test_enroll_rejects_non_owner_of_token() public {
        vm.prank(admin);
        uint256 id = season.createSeason{value: 1 ether}(_defaultSpec(1 hours, 7 days, 1 ether));
        vm.prank(bob); // bob doesn't own token 1
        vm.expectRevert(Season.NotTokenOwner.selector);
        season.enroll(id, 1);
    }

    function test_enroll_rejects_after_start() public {
        vm.prank(admin);
        uint256 id = season.createSeason{value: 1 ether}(_defaultSpec(1 hours, 7 days, 1 ether));
        vm.warp(block.timestamp + 1 hours + 1);
        vm.prank(alice);
        vm.expectRevert(Season.EnrollmentClosed.selector);
        season.enroll(id, 1);
    }

    function test_enroll_rejects_duplicate() public {
        vm.prank(admin);
        uint256 id = season.createSeason{value: 1 ether}(_defaultSpec(1 hours, 7 days, 1 ether));
        vm.prank(alice);
        season.enroll(id, 1);
        vm.prank(alice);
        vm.expectRevert(Season.AlreadyEnrolled.selector);
        season.enroll(id, 1);
    }

    // ─── settle ───────────────────────────────────────────────────────────

    function _setupSeasonWithThreeEnrolled() internal returns (uint256) {
        vm.prank(admin);
        uint256 id = season.createSeason{value: 10 ether}(_defaultSpec(1 hours, 7 days, 10 ether));
        vm.prank(alice); season.enroll(id, 1);
        vm.prank(bob);   season.enroll(id, 2);
        vm.prank(carol); season.enroll(id, 3);

        // Move into the season window, start runs, record metrics.
        vm.warp(block.timestamp + 1 hours + 1);
        vm.prank(alice); live.start(1, _certRunHashFor(alice, SPOT));
        vm.prank(bob);   live.start(2, _certRunHashFor(bob,   SPOT));
        vm.prank(carol); live.start(3, _certRunHashFor(carol, SPOT));

        // Distinct returns so the leaderboard is unambiguous: alice > bob > carol.
        vm.prank(operator); live.update(1, 0, keccak256("a"), int128(2500), 0, 0, 0); // +25%
        vm.prank(operator); live.update(2, 0, keccak256("b"), int128(1200), 0, 0, 0); // +12%
        vm.prank(operator); live.update(3, 0, keccak256("c"), int128(300),  0, 0, 0); // +3%

        return id;
    }

    function test_settle_pays_top_three_in_50_30_20() public {
        uint256 id = _setupSeasonWithThreeEnrolled();

        uint256 aliceBefore = alice.balance;
        uint256 bobBefore = bob.balance;
        uint256 carolBefore = carol.balance;

        vm.warp(block.timestamp + 7 days + 1);

        uint256[] memory sorted = new uint256[](3);
        sorted[0] = 1; sorted[1] = 2; sorted[2] = 3;
        season.settle(id, sorted);

        assertEq(alice.balance - aliceBefore, 5 ether); // 50%
        assertEq(bob.balance   - bobBefore,   3 ether); // 30%
        assertEq(carol.balance - carolBefore, 2 ether); // 20%
    }

    function test_settle_rejects_unsorted_hint() public {
        uint256 id = _setupSeasonWithThreeEnrolled();
        vm.warp(block.timestamp + 7 days + 1);

        // bob (1200) before alice (2500) — out of order.
        uint256[] memory bad = new uint256[](2);
        bad[0] = 2; bad[1] = 1;
        vm.expectRevert(Season.HintNotSorted.selector);
        season.settle(id, bad);
    }

    function test_settle_rejects_non_enrolled_token() public {
        uint256 id = _setupSeasonWithThreeEnrolled();
        vm.warp(block.timestamp + 7 days + 1);

        // Token 99 is never enrolled; ownerOf doesn't have to resolve since
        // the enrollment check fires first.
        uint256[] memory bad = new uint256[](1);
        bad[0] = 99;
        vm.expectRevert(Season.NotEnrolled.selector);
        season.settle(id, bad);
    }

    function test_settle_rejects_before_end() public {
        uint256 id = _setupSeasonWithThreeEnrolled();
        // Inside season window.
        uint256[] memory sorted = new uint256[](3);
        sorted[0] = 1; sorted[1] = 2; sorted[2] = 3;
        vm.expectRevert(Season.SeasonNotOver.selector);
        season.settle(id, sorted);
    }

    function test_settle_rejects_double_settle() public {
        uint256 id = _setupSeasonWithThreeEnrolled();
        vm.warp(block.timestamp + 7 days + 1);
        uint256[] memory sorted = new uint256[](3);
        sorted[0] = 1; sorted[1] = 2; sorted[2] = 3;
        season.settle(id, sorted);
        vm.expectRevert(Season.AlreadySettled.selector);
        season.settle(id, sorted);
    }

    function test_settle_with_single_winner_pays_50_percent_only() public {
        vm.prank(admin);
        uint256 id = season.createSeason{value: 10 ether}(_defaultSpec(1 hours, 7 days, 10 ether));
        vm.prank(alice); season.enroll(id, 1);

        vm.warp(block.timestamp + 1 hours + 1);
        vm.prank(alice); live.start(1, _certRunHashFor(alice, SPOT));
        vm.prank(operator); live.update(1, 0, keccak256("a"), int128(2500), 0, 0, 0);

        vm.warp(block.timestamp + 7 days + 1);
        uint256[] memory sorted = new uint256[](1);
        sorted[0] = 1;
        uint256 aliceBefore = alice.balance;
        season.settle(id, sorted);

        assertEq(alice.balance - aliceBefore, 5 ether);
        // Remaining 5 ether stays in the contract (escrow). v0.4 may add a
        // refund-to-creator flow; v0.3 leaves it as protocol revenue.
    }

    function test_settle_empty_hint_pays_nothing() public {
        vm.prank(admin);
        uint256 id = season.createSeason{value: 10 ether}(_defaultSpec(1 hours, 7 days, 10 ether));
        vm.warp(block.timestamp + 7 days + 1 hours + 1);
        uint256[] memory empty = new uint256[](0);
        season.settle(id, empty);
        // No payouts; settled flag set.
        (, , , , , , , , , , bool settled) = season.seasons(id);
        assertTrue(settled);
    }
}
