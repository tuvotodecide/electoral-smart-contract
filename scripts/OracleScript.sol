// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {AttestationOracle} from "../src/AttestationOracle.sol";
import {Reputation} from "../src/Reputation.sol";
import {AttestationRecord} from "../src/AttestationRecord.sol";

contract OrackeScript is Script {
  function run() external {
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    vm.startBroadcast(deployerPrivateKey);
    //init reputation contract
    Reputation reputation = new Reputation(msg.sender);

    //init nft contract for records
    AttestationRecord recordNft = new AttestationRecord(msg.sender);

    //init oracle
    AttestationOracle oracle = new AttestationOracle(
        msg.sender,
        address(recordNft),
        address(reputation)
    );

    //Authorize oracle access to record and reputation contracts
    recordNft.grantRole(recordNft.AUTHORIZED_ROLE(), address(oracle));
    reputation.grantRole(recordNft.AUTHORIZED_ROLE(), address(oracle));

    vm.stopBroadcast();
    console.log("Oracle deployed at:", address(oracle));
  }
}