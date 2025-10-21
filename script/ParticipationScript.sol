// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {Participation} from "../src/Participation.sol";

contract ParticipationScript is Script {
  function run() external {
    vm.startBroadcast();

    Participation participation = new Participation(msg.sender);

    vm.stopBroadcast();
    console.log("NFT deployed at:", address(participation));
  }
}