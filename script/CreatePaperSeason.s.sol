// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {Season} from "../src/Season.sol";

/// @notice Create a new paper-trading season. Admin-only.
///
/// Required env:
///   ZA_ADDR_SEASON        deployed Season address
///   SEASON_PRIZE_WEI      prize pool, in wei of the chain's native token (0G on Galileo)
///   SEASON_START_OFFSET   seconds-from-now until enrollment closes (e.g. 3600 for 1 hour)
///   SEASON_DURATION       seconds the season runs (e.g. 2592000 for 30 days)
///   SEASON_DATASET_SPEC   keccak of the dataset key, e.g. keccak("BTCUSDT-15m-spot")
///                         If omitted, defaults to BTCUSDT-15m-spot.
///   SEASON_MARKET         0=spot, 1=perp (default 0)
///
/// Invocation:
///   forge script script/CreatePaperSeason.s.sol:CreatePaperSeason \
///     --rpc-url $GALILEO_RPC_URL --private-key $DEPLOYER_PRIVATE_KEY \
///     --broadcast --legacy --with-gas-price 3000000000
contract CreatePaperSeason is Script {
    function run() external {
        address seasonAddr = vm.envAddress("ZA_ADDR_SEASON");
        uint256 prizePool = vm.envUint("SEASON_PRIZE_WEI");
        uint64  startOffset = uint64(vm.envOr("SEASON_START_OFFSET", uint256(3600)));
        uint64  duration    = uint64(vm.envOr("SEASON_DURATION",     uint256(30 days)));
        uint8   market      = uint8(vm.envOr("SEASON_MARKET",        uint256(0)));

        bytes32 datasetSpec = vm.envOr(
            "SEASON_DATASET_SPEC",
            keccak256("BTCUSDT-15m-spot")
        );

        Season season = Season(seasonAddr);

        Season.SeasonSpec memory spec = Season.SeasonSpec({
            datasetSpec:    datasetSpec,
            initialBalance: 10_000,
            feeBps:         10,
            slippageBps:    5,
            market:         market,
            maxLeverage:    market == 1 ? 5 : 1,
            startTime:      uint64(block.timestamp) + startOffset,
            endTime:        uint64(block.timestamp) + startOffset + duration,
            prizePool:      prizePool,
            creator:        address(0),   // contract overwrites with msg.sender
            settled:        false
        });

        vm.startBroadcast();
        uint256 id = season.createSeason{value: prizePool}(spec);
        vm.stopBroadcast();

        console2.log("Season id:        ", id);
        console2.log("startTime (unix): ", spec.startTime);
        console2.log("endTime   (unix): ", spec.endTime);
        console2.log("prizePool (wei):  ", prizePool);
        console2.log("market:           ", market == 0 ? "spot" : "perp");
    }
}
