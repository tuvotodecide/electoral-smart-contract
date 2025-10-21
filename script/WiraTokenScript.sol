// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {WiraToken} from "../src/WiraToken.sol";

contract OrackeScript is Script {
  function run() external {
    vm.startBroadcast();
    
    WiraToken token = new WiraToken(msg.sender, msg.sender, msg.sender);

    vm.stopBroadcast();
    console.log("Token deployed at:", address(token));
  }
}