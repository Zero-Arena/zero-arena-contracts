// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {ReencryptionOracle} from "../src/oracle/ReencryptionOracle.sol";
import {ZeroArenaINFT} from "../src/ZeroArenaINFT.sol";

/// @notice Redeploys ReencryptionOracle + ZeroArenaINFT (M3: per-token
///         transferNonce bound into the proof digest) on top of the EXISTING
///         AgentCertificate — certificates carry no INFT coupling, so they
///         survive the redeploy. Run before DeployPaperEngine.s.sol, which
///         needs the fresh ZA_ADDR_INFT. Output overwrites
///         `deployments/<chainId>.json`, preserving the AgentCertificate entry.
///
/// Required env:
///   DEPLOYER_PRIVATE_KEY     admin wallet (owns Ownable2Step on both contracts)
///   DEPLOYER_ADDRESS         same address as above
///   ORACLE_SIGNER_ADDRESS    off-chain re-encryption proof signer (unchanged)
///   ZA_ADDR_CERT             already-deployed AgentCertificate address
///
/// Invocation (mainnet 16661):
///   forge script script/DeployINFTStack.s.sol:DeployINFTStack \
///     --rpc-url https://evmrpc.0g.ai --private-key $DEPLOYER_PRIVATE_KEY \
///     --broadcast
contract DeployINFTStack is Script {
    function run() external {
        address admin = vm.envAddress("DEPLOYER_ADDRESS");
        address oracleSigner = vm.envAddress("ORACLE_SIGNER_ADDRESS");
        address certAddr = vm.envAddress("ZA_ADDR_CERT");

        vm.startBroadcast();

        ReencryptionOracle oracle = new ReencryptionOracle(admin, oracleSigner);
        ZeroArenaINFT inft = new ZeroArenaINFT(admin, address(oracle), certAddr);

        vm.stopBroadcast();

        console2.log("chainId:             ", block.chainid);
        console2.log("AgentCertificate:    ", certAddr);
        console2.log("ReencryptionOracle:  ", address(oracle));
        console2.log("ZeroArenaINFT:       ", address(inft));

        string memory json = string.concat(
            '{\n  "chainId": ', vm.toString(block.chainid), ',\n',
            '  "addresses": {\n',
            '    "AgentCertificate": "',    vm.toString(certAddr),        '",\n',
            '    "ReencryptionOracle": "',  vm.toString(address(oracle)), '",\n',
            '    "ZeroArenaINFT": "',       vm.toString(address(inft)),   '"\n',
            '  },\n',
            '  "deployBlock": ', vm.toString(block.number), '\n}\n'
        );
        string memory outPath = string.concat(
            "deployments/", vm.toString(block.chainid), ".json"
        );
        vm.writeFile(outPath, json);
        console2.log("wrote:");
        console2.log(outPath);
    }
}
