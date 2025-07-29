// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {AttestationOracle} from "../src/AttestationOracle.sol";
import {Reputation} from "../src/Reputation.sol";
import {AttestationRecord} from "../src/AttestationRecord.sol";
import {Participation} from "../src/Participation.sol";
import {WiraToken} from "../src/WiraToken.sol";

contract OracleScript is Script {
  function run() external {
    address stakeToken = vm.envAddress("STAKE_TOKEN");
    WiraToken stakeContract = WiraToken(stakeToken);

    vm.startBroadcast();
    //init reputation contract
    Reputation reputation = new Reputation(msg.sender);

    //init nft contract for records
    AttestationRecord recordNft = new AttestationRecord(msg.sender);
    Participation participation = new Participation(msg.sender);

    //init oracle with wira token as stake and 5 WIRA as stake amount
    AttestationOracle oracle = new AttestationOracle(
        msg.sender,
        address(recordNft),
        address(participation),
        address(reputation),
        stakeToken,
        5e18
    );

    //Authorize oracle access to record, reputation and stake token contracts
    recordNft.grantRole(recordNft.AUTHORIZED_ROLE(), address(oracle));
    participation.grantRole(participation.AUTHORIZED_ROLE(), address(oracle));
    reputation.grantRole(reputation.AUTHORIZED_ROLE(), address(oracle));
    stakeContract.grantRole(stakeContract.MINTER_ROLE(), address(oracle));

    vm.stopBroadcast();
    console.log("Oracle deployed at:", address(oracle));
  }
}