// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {Options} from "openzeppelin-foundry-upgrades/Options.sol";

contract UpgradeReputationScript is Script {
  function run() external {
    address proxyAddress = vm.envAddress("REPUTATION_PROXY_ADDRESS");

    vm.startBroadcast();
    Upgrades.upgradeProxy(
      proxyAddress,
      "out/ReputationV2.sol/ReputationV2.json",
      ""
    );

    vm.stopBroadcast();
  }
}