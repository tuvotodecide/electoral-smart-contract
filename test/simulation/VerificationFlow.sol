pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";

import {AttestationOracle} from "../../src/AttestationOracle.sol";
import {Reputation} from "../../src/Reputation.sol";
import {AttestationRecord} from "../../src/AttestationRecord.sol";
import {WiraToken} from "../../src/WiraToken.sol";

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

    //init stake wira token
    WiraToken token = new WiraToken(owner, owner, owner);

    //init oracle
    oracle = new AttestationOracle(
      owner,
      address(recordNft),
      address(reputation),
      address(token),
      5e18
    );

    //Authorize oracle access to record contract
    vm.startPrank(owner);
    recordNft.grantRole(recordNft.AUTHORIZED_ROLE(), address(oracle));
    reputation.grantRole(recordNft.AUTHORIZED_ROLE(), address(oracle));
    token.grantRole(token.MINTER_ROLE(), address(oracle));
    vm.stopPrank();
  }

  function test_createAttestation_emitRegisterEvent() public {
    (AttestationOracle oracle, AttestationRecord recordNft, address owner, address user) = initContracts();

    //set oracle active period
    vm.prank(owner);
    oracle.setActiveTime(0, 200);
    vm.warp(100);

    //request register as user (send empty uri)
    vm.prank(user);
    oracle.requestRegister("");

    //backend listen the event, verify and call the result
    vm.prank(owner);
    oracle.register(user, false);

    //then user can call createAttestation
    vm.startPrank(user);
    //user inits a votation updating their first image
    (uint256 attestationId, uint256 recordId) = oracle.createAttestation("new-record");

    //check attestation created and user has record nft
    (AttestationOracle.AttestationState resolved,) = oracle.getAttestationInfo(attestationId);
    assertEq(uint256(resolved), 0);
    assertEq(oracle.getWeighedAttestations(attestationId, recordId), 1);
    assertEq(recordNft.ownerOf(recordId), user);
    vm.stopPrank();
  }
}