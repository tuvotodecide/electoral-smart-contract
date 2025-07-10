pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";

import {AttestationOracle} from "../../src/AttestationOracle.sol";
import {Reputation} from "../../src/Reputation.sol";
import {AttestationRecord} from "../../src/AttestationRecord.sol";

contract VerificationFlowTest is Test {
  function initContracts() public returns(
    AttestationOracle oracle,
    AttestationRecord recordNft,
    address owner,
    address user
  ) {
    //address of contract owner to grant roles and access to reputation and nft
    owner = address(0x123);

    user = address(0x456);

    //init nft contract for records
    recordNft = new AttestationRecord(owner);

    //init reputation contract
    Reputation reputation = new Reputation(owner);

    //init oracle
    oracle = new AttestationOracle(
      owner,
      address(recordNft),
      address(reputation)
    );

    //Authorize oracle access to record contract
    vm.startPrank(owner);
    recordNft.grantRole(recordNft.AUTHORIZED_ROLE(), address(oracle));
    reputation.grantRole(recordNft.AUTHORIZED_ROLE(), address(oracle));
    vm.stopPrank();

    //init user reputation
    vm.prank(user);
    reputation.initReputation();
  }

  function test_createAttestation_emitRegisterEvent() public {
    (AttestationOracle oracle, AttestationRecord recordNft, address owner, address user) = initContracts();

    //request register as user (send empty uri)
    vm.prank(user);
    oracle.requestRegister("");

    //backend listen the event, verify and call the result
    vm.prank(owner);
    oracle.register(user, false);

    //then user can call createAttestation
    vm.startPrank(user);
    //user inits a votation updating their first image
    vm.warp(123);
    (uint256 attestationId, uint256 recordId) = oracle.createAttestation("new-record");

    //check attestation created and user has record nft
    (uint256 createdAt, AttestationOracle.AttestationState resolved,) = oracle.getAttestationInfo(attestationId);
    assertEq(createdAt, 123);
    assertEq(uint256(resolved), 0);
    assertEq(oracle.getWeighedAttestations(attestationId, recordId), 1);
    assertEq(recordNft.ownerOf(recordId), user);
    vm.stopPrank();
  }
}