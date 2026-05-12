// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {LiveCertificate} from "../src/LiveCertificate.sol";
import {Season} from "../src/Season.sol";

/// @notice Deploys the v0.3 paper-trading contracts on top of the existing
///         AgentCertificate + ZeroArenaINFT pair. Run after DeployAll.s.sol.
///
/// Required env:
///   GALILEO_RPC_URL          target RPC
///   DEPLOYER_PRIVATE_KEY     admin wallet (Wallet A; owns Ownable2Step)
///   DEPLOYER_ADDRESS         same address as above
///   OPERATOR_ADDRESS         backend daemon wallet, authorized as updater
///   ZA_ADDR_INFT             already-deployed ZeroArenaINFT address
///                            (from deployments/galileo-testnet.json)
///
/// Invocation:
///   forge script script/DeployPaperEngine.s.sol:DeployPaperEngine \
///     --rpc-url $GALILEO_RPC_URL --private-key $DEPLOYER_PRIVATE_KEY \
///     --broadcast --legacy --with-gas-price 3000000000
contract DeployPaperEngine is Script {
    function run() external {
        address admin = vm.envAddress("DEPLOYER_ADDRESS");
        address operator = vm.envAddress("OPERATOR_ADDRESS");
        address inftAddr = vm.envAddress("ZA_ADDR_INFT");

        vm.startBroadcast();

        // 1. Deploy LiveCertificate bound to the existing iNFT.
        LiveCertificate live = new LiveCertificate(admin, inftAddr);

        // 2. Authorize the operator daemon to push epoch updates.
        live.setUpdater(operator, true);

        // 3. Deploy Season pointing at LiveCertificate + iNFT.
        Season season = new Season(admin, address(live), inftAddr);

        vm.stopBroadcast();

        console2.log("LiveCertificate:     ", address(live));
        console2.log("Season:              ", address(season));
        console2.log("operator (updater):  ", operator);

        // Append to the existing deployment file (or create a new section).
        // We write a separate paper-engine file to avoid stepping on
        // galileo-testnet.json — operator can merge both as needed.
        string memory json = string.concat(
            '{\n  "chainId": ', vm.toString(block.chainid), ',\n',
            '  "paperEngine": {\n',
            '    "LiveCertificate": "', vm.toString(address(live)),   '",\n',
            '    "Season": "',          vm.toString(address(season)), '",\n',
            '    "operator": "',        vm.toString(operator),        '",\n',
            '    "deployBlock": ',      vm.toString(block.number),    '\n',
            '  }\n}\n'
        );
        vm.writeFile("deployments/galileo-paper-engine.json", json);
    }
}
