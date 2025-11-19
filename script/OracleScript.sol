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
    address stakeTokenHolder = vm.envAddress("RECIPIENT_ADDRESS");
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
    address oracleProxy = Upgrades.deployUUPSProxy(
      "AttestationOracle.sol",
      abi.encodeCall(AttestationOracle.initialize, (
        msg.sender,
        address(recordNft),
        address(reputation),
        stakeToken,
        stakeTokenHolder,
        5e18
      ))
    );
    AttestationOracle oracle = AttestationOracle(oracleProxy);

    //Authorize oracle access to record, reputation and stake token contracts
    recordNft.grantRole(recordNft.AUTHORIZED_ROLE(), address(oracle));
    reputation.grantRole(reputation.AUTHORIZED_ROLE(), address(oracle));
    oracle.grantRole(oracle.DEFAULT_ADMIN_ROLE(), resolver);

    vm.stopBroadcast();

    //Approve oracle to transfer stake tokens on behalf of holder
    uint256 holderPk = vm.envUint("RECIPIENT_PK");
    vm.startBroadcast(holderPk);
    stakeContract.approve(address(oracle), 1000000e18);
    vm.stopBroadcast();

    console.log("Oracle deployed at:", address(oracle));
  }
}