// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract UpgradeOracleScript is Script {
  function run() external {
    address proxyAddress = vm.envAddress("ORACLE_PROXY_ADDRESS");

    vm.startBroadcast();
    Upgrades.upgradeProxy(
      proxyAddress,
      "out/AttestationOracleV2.sol/AttestationOracleV2.json",
      ""
    );

    vm.stopBroadcast();
  }
}