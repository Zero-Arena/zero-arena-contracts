// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {LiveCertificate} from "../src/LiveCertificate.sol";
import {Season} from "../src/Season.sol";
import {AgentCertificate} from "../src/AgentCertificate.sol";

/// @notice Enroll an iNFT into a season AND start its paper run. The iNFT
///         owner runs this; the script does both calls in one broadcast.
///
/// Required env:
///   ZA_ADDR_CERT          AgentCertificate (to fetch the genesis runHash)
///   ZA_ADDR_LIVE_CERT     LiveCertificate
///   ZA_ADDR_SEASON        Season (for enrollment, optional)
///   PAPER_TOKEN_ID        iNFT token id this run binds to
///   PAPER_CERT_ID         the iNFT's AgentCertificate id (so the script can
///                         fetch the genesis runHash and assert continuity)
///   PAPER_SEASON_ID       (optional) season to enroll into; omit to start
///                         the run without competing
///
/// Invocation:
///   forge script script/StartPaperRun.s.sol:StartPaperRun \
///     --rpc-url $GALILEO_RPC_URL --private-key $OWNER_PRIVATE_KEY \
///     --broadcast --legacy --with-gas-price 3000000000
contract StartPaperRun is Script {
    function run() external {
        address certAddr  = vm.envAddress("ZA_ADDR_CERT");
        address liveAddr  = vm.envAddress("ZA_ADDR_LIVE_CERT");
        uint256 tokenId   = vm.envUint("PAPER_TOKEN_ID");
        uint256 certId    = vm.envUint("PAPER_CERT_ID");
        uint256 seasonId  = vm.envOr("PAPER_SEASON_ID", uint256(0));

        AgentCertificate cert = AgentCertificate(certAddr);
        LiveCertificate live  = LiveCertificate(liveAddr);

        AgentCertificate.Certificate memory c = cert.get(certId);
        bytes32 genesisHash = c.runHash;
        require(genesisHash != bytes32(0), "empty runHash");

        vm.startBroadcast();

        if (seasonId > 0) {
            address seasonAddr = vm.envAddress("ZA_ADDR_SEASON");
            Season(seasonAddr).enroll(seasonId, tokenId);
            console2.log("enrolled tokenId in season:", seasonId);
        }

        live.start(tokenId, genesisHash);

        vm.stopBroadcast();

        console2.log("paper run started for tokenId:", tokenId);
        console2.log("genesis runHash:");
        console2.logBytes32(genesisHash);
    }
}
