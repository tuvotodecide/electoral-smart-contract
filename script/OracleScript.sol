// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {AttestationOracle} from "../src/AttestationOracle.sol";
import {Reputation} from "../src/Reputation.sol";
import {AttestationRecord} from "../src/AttestationRecord.sol";
import {WiraToken} from "../src/WiraToken.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract OracleScript is Script {
  function run() external {
    address stakeToken = vm.envAddress("STAKE_TOKEN");
    address resolver = vm.envAddress("RESOLVER");
    WiraToken stakeContract = WiraToken(stakeToken);

    vm.startBroadcast();
    //init reputation contract
    address proxy = Upgrades.deployUUPSProxy(
      "Reputation.sol",
      abi.encodeCall(Reputation.initialize, (msg.sender))
    );
    Reputation reputation = Reputation(proxy);

    //init nft contract for records
    AttestationRecord recordNft = new AttestationRecord(msg.sender);

    //init oracle with wira token as stake and 5 WIRA as stake amount
    AttestationOracle oracle = new AttestationOracle(
        msg.sender,
        address(recordNft),
        address(reputation),
        stakeToken,
        5e18
    );

    //Authorize oracle access to record, reputation and stake token contracts
    recordNft.grantRole(recordNft.AUTHORIZED_ROLE(), address(oracle));
    reputation.grantRole(reputation.AUTHORIZED_ROLE(), address(oracle));
    stakeContract.grantRole(stakeContract.MINTER_ROLE(), address(oracle));
    oracle.grantRole(oracle.DEFAULT_ADMIN_ROLE(), resolver);

    vm.stopBroadcast();
    console.log("Oracle deployed at:", address(oracle));
  }
}