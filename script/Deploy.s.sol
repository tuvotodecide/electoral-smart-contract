// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/AttestationOracle.sol";

contract DeployScript is Script {
    function run() external {
        vm.startBroadcast();

        address backend = vm.envAddress("BACKEND_SIGNER");
        //KycRegistry kyc = new KycRegistry(backend);

        //new HumanOracleWithID(address(kyc));

        vm.stopBroadcast();
    }
}
