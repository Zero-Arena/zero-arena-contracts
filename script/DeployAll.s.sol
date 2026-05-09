// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {AgentCertificate} from "../src/AgentCertificate.sol";
import {ReencryptionOracle} from "../src/oracle/ReencryptionOracle.sol";
import {ZeroArenaINFT} from "../src/ZeroArenaINFT.sol";

/// @notice Deploys the three Zero Arena contracts and writes addresses to
///         deployments/galileo-testnet.json. Intended invocation:
///
///   forge script script/DeployAll.s.sol:DeployAll \
///     --rpc-url $GALILEO_RPC_URL --private-key $DEPLOYER_PRIVATE_KEY \
///     --broadcast --verify
contract DeployAll is Script {
    function run() external {
        address admin = vm.envAddress("DEPLOYER_ADDRESS");
        address oracleSigner = vm.envAddress("ORACLE_SIGNER_ADDRESS");

        vm.startBroadcast();

        AgentCertificate cert = new AgentCertificate();
        ReencryptionOracle oracle = new ReencryptionOracle(admin, oracleSigner);
        ZeroArenaINFT inft = new ZeroArenaINFT(admin, address(oracle), address(cert));

        vm.stopBroadcast();

        console2.log("AgentCertificate:    ", address(cert));
        console2.log("ReencryptionOracle:  ", address(oracle));
        console2.log("ZeroArenaINFT:       ", address(inft));

        string memory json = string.concat(
            '{\n  "chainId": ', vm.toString(block.chainid), ',\n',
            '  "addresses": {\n',
            '    "AgentCertificate": "',    vm.toString(address(cert)),   '",\n',
            '    "ReencryptionOracle": "',  vm.toString(address(oracle)), '",\n',
            '    "ZeroArenaINFT": "',       vm.toString(address(inft)),   '"\n',
            '  },\n',
            '  "deployBlock": ', vm.toString(block.number), '\n}\n'
        );
        vm.writeFile("deployments/galileo-testnet.json", json);
    }
}
