pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import {KycRegistry} from "../../src/KycRegistry.sol";
import {AttestationOracle} from "../../src/AttestationOracle.sol";
import {Reputation} from "../../src/Reputation.sol";
import {AttestationRecord} from "../../src/AttestationRecord.sol";

contract AttestationFlowTest is Test {

    function initContracts() public returns(
        address user,
        address user2,
        address user3,
        address jury,
        address authorized,
        Reputation reputation,
        AttestationRecord recordNft,
        AttestationOracle oracle
    ) {
        //address of contract owner off-chain verification
        address owner = address(0x123);
        (address backendSigner, uint256 backPk) = makeAddrAndKey("backendSigner");

        //addresses of user and jury with their dni
        user = address(0x789);
        user2 = address(0x1011);
        user3 = address(0x1213);
        jury = address(0x1415);
        authorized = address(0x1617);

        //init reputation contract
        reputation = new Reputation(owner);

        //init user and jury nft for on-chain verification
        KycRegistry userKeys = new KycRegistry(backendSigner, address(reputation));
        KycRegistry juryKeys = new KycRegistry(backendSigner, address(reputation));
        KycRegistry authorizedKeys = new KycRegistry(backendSigner, address(reputation));

        //init nft contract for records
        recordNft = new AttestationRecord(owner);

        //init oracle
        oracle = new AttestationOracle(
            address(userKeys),
            address(juryKeys),
            address(authorizedKeys),
            address(recordNft),
            address(reputation)
        );

        vm.startPrank(owner);
        //Authorize oracle access to record and reputation contracts
        recordNft.setAuthorized(address(oracle), true);
        reputation.setAuthorized(address(oracle), true);

        //Authorize ntf access to reputation, for initialize user reputation on claim kyc
        reputation.setAuthorized(address(userKeys), true);
        reputation.setAuthorized(address(juryKeys), true);
        reputation.setAuthorized(address(authorizedKeys), true);
        vm.stopPrank();

        //Claim a user kyc
        claimKyc(user, backPk, '123456', userKeys, reputation);
        claimKyc(user2, backPk, '123456', userKeys, reputation);
        claimKyc(user3, backPk, '123456', userKeys, reputation);
        claimKyc(jury, backPk, '789010', juryKeys, reputation);
        claimKyc(authorized, backPk, '111213', authorizedKeys, reputation);
    }
    
    //unanimous attestation
    function test_unanimousAttestation() public {
        (
            address user,
            address user2,
            address user3,
            ,
            ,
            Reputation reputation,
            AttestationRecord recordNft,
            AttestationOracle oracle
        ) = initContracts();

        vm.startPrank(user);
        //user inits a votation updating their first image
        vm.warp(123);
        (uint256 attestationId, uint256 recordId) = oracle.createAttestation("new record");

        //check attestation created and user has record nft
        (uint256 createdAt, AttestationOracle.AttestationState resolved, uint256 finalResult) = oracle.getAttestationInfo(attestationId);
        assertEq(createdAt, 123);
        assertEq(uint256(resolved), 0);
        assertEq(oracle.getWeighedAttestations(attestationId, recordId), 1);
        assertEq(recordNft.ownerOf(recordId), user);
        vm.stopPrank();

        //user 2 attest yes
        vm.prank(user2);
        oracle.attest(attestationId, recordId, true, "");

        //check attest added +1
        assertEq(oracle.getWeighedAttestations(attestationId, recordId), 2);

        //user 3 attest yes
        vm.prank(user3);
        oracle.attest(attestationId, recordId, true, "");

        //check attest added +1
        assertEq(oracle.getWeighedAttestations(attestationId, recordId), 3);

        //warp 3 hours and resolve votation
        vm.warp(4 hours);
        oracle.resolve(attestationId);

        //check attestation status
        (createdAt, resolved, finalResult) = oracle.getAttestationInfo(attestationId);
        assertEq(uint256(resolved), 3);
        assertEq(finalResult, recordId);

        //check users reputation
        vm.prank(user);
        assertEq(reputation.getReputation(), 2);
        vm.prank(user2);
        assertEq(reputation.getReputation(), 2);
        vm.prank(user3);
        assertEq(reputation.getReputation(), 2);
    }

    //users attestation matches juries one, only one record
    function test_usersMatchJuries_oneRecord() public {
        (
            address user,
            address user2,
            address user3,
            address jury,
            ,
            Reputation reputation,
            AttestationRecord recordNft,
            AttestationOracle oracle
        ) = initContracts();

        vm.startPrank(user);
        //user inits a votation updating their first image
        vm.warp(123);
        (uint256 attestationId, uint256 recordId) = oracle.createAttestation("new record");

        //check attestation created and user has record nft
        (uint256 createdAt, AttestationOracle.AttestationState resolved, uint256 finalResult) = oracle.getAttestationInfo(attestationId);
        assertEq(createdAt, 123);
        assertEq(uint256(resolved), 0);
        assertEq(oracle.getWeighedAttestations(attestationId, recordId), 1);
        assertEq(recordNft.ownerOf(recordId), user);
        vm.stopPrank();

        //user 2 attest yes
        vm.prank(user2);
        oracle.attest(attestationId, recordId, true, "");

        //check attest added +1
        assertEq(oracle.getWeighedAttestations(attestationId, recordId), 2);

        //user 3 attest no
        vm.prank(user3);
        oracle.attest(attestationId, recordId, false, "");

        //check attest added -1
        assertEq(oracle.getWeighedAttestations(attestationId, recordId), 1);

        //jury attest yes
        vm.prank(jury);
        oracle.attest(attestationId, recordId, true, "");

        //check juries attest added +1
        assertEq(oracle.getJuryWeighedAttestations(attestationId, recordId), 1);

        //warp 3 hours and resolve votation
        vm.warp(4 hours);
        oracle.resolve(attestationId);

        //check attestation status
        (createdAt, resolved, finalResult) = oracle.getAttestationInfo(attestationId);
        assertEq(uint256(resolved), 2);
        assertEq(finalResult, recordId);

        //check users reputation
        vm.prank(user);
        assertEq(reputation.getReputation(), 2);
        vm.prank(user2);
        assertEq(reputation.getReputation(), 2);
        vm.prank(user3);
        assertEq(reputation.getReputation(), 0);
        vm.prank(jury);
        assertEq(reputation.getReputation(), 2);
    }

    //users attestation matches juries one, two records
    function test_usersMatchJuries_twoRecords() public {
        (
            address user,
            address user2,
            address user3,
            address jury,
            ,
            Reputation reputation,
            AttestationRecord recordNft,
            AttestationOracle oracle
        ) = initContracts();

        vm.startPrank(user);
        //user inits a votation updating their first image
        vm.warp(123);
        (uint256 attestationId, uint256 recordId) = oracle.createAttestation("new record");

        //check attestation created and user has record nft
        (uint256 createdAt, AttestationOracle.AttestationState resolved, uint256 finalResult) = oracle.getAttestationInfo(attestationId);
        assertEq(createdAt, 123);
        assertEq(uint256(resolved), 0);
        assertEq(oracle.getWeighedAttestations(attestationId, recordId), 1);
        assertEq(recordNft.ownerOf(recordId), user);
        vm.stopPrank();

        //user 2 attest yes
        vm.prank(user2);
        oracle.attest(attestationId, recordId, true, "");

        //check attest added +1
        assertEq(oracle.getWeighedAttestations(attestationId, recordId), 2);

        //user 3 attest yes to new record
        vm.startPrank(user3);
        oracle.attest(attestationId, recordId, true, "record 2");

        //get user 3 vote
        (uint256 record2Id,) = oracle.getOptionAttested(attestationId);
        vm.stopPrank();

        //check attestations
        assertEq(oracle.getWeighedAttestations(attestationId, recordId), 2);
        assertEq(oracle.getWeighedAttestations(attestationId, record2Id), 1);

        //jury attest yes to first record
        vm.prank(jury);
        oracle.attest(attestationId, recordId, true, "");

        //check juries attest added +1
        assertEq(oracle.getJuryWeighedAttestations(attestationId, recordId), 1);

        //warp 3 hours and resolve votation
        vm.warp(4 hours);
        oracle.resolve(attestationId);

        //check attestation status
        (createdAt, resolved, finalResult) = oracle.getAttestationInfo(attestationId);
        assertEq(uint256(resolved), 2);
        assertEq(finalResult, recordId);

        //check users reputation
        vm.prank(user);
        assertEq(reputation.getReputation(), 2);
        vm.prank(user2);
        assertEq(reputation.getReputation(), 2);
        vm.prank(user3);
        assertEq(reputation.getReputation(), 0);
        vm.prank(jury);
        assertEq(reputation.getReputation(), 2);
    }

    //users attestation doesn't match juries one
    function test_usersNotMatchJuries() public {
        (
            address user,
            address user2,
            address user3,
            address jury,
            address authorized,
            Reputation reputation,
            AttestationRecord recordNft,
            AttestationOracle oracle
        ) = initContracts();

        vm.startPrank(user);
        //user inits a votation updating their first image
        vm.warp(123);
        (uint256 attestationId, uint256 recordId) = oracle.createAttestation("new record");

        //check attestation created and user has record nft
        (uint256 createdAt, AttestationOracle.AttestationState resolved, uint256 finalResult) = oracle.getAttestationInfo(attestationId);
        assertEq(createdAt, 123);
        assertEq(uint256(resolved), 0);
        assertEq(oracle.getWeighedAttestations(attestationId, recordId), 1);
        assertEq(recordNft.ownerOf(recordId), user);
        vm.stopPrank();

        //user 2 attest yes
        vm.prank(user2);
        oracle.attest(attestationId, recordId, true, "");

        //check attest added +1
        assertEq(oracle.getWeighedAttestations(attestationId, recordId), 2);

        //user 3 attest yes to new record
        vm.startPrank(user3);
        oracle.attest(attestationId, recordId, true, "record 2");

        //get user 3 vote
        (uint256 record2Id,) = oracle.getOptionAttested(attestationId);
        vm.stopPrank();

        //check attestations
        assertEq(oracle.getWeighedAttestations(attestationId, recordId), 2);
        assertEq(oracle.getWeighedAttestations(attestationId, record2Id), 1);

        //jury attest yes to sencond record
        vm.prank(jury);
        oracle.attest(attestationId, record2Id, true, "");

        //check juries attest added +1
        assertEq(oracle.getJuryWeighedAttestations(attestationId, record2Id), 1);

        //warp 3 hours and resolve votation
        vm.warp(4 hours);
        oracle.resolve(attestationId);

        //check attestation is in verification state
        (createdAt, resolved, finalResult) = oracle.getAttestationInfo(attestationId);
        assertEq(uint256(resolved), 1);
        assertEq(finalResult, 0);

        //check users reputation without changes
        vm.prank(user);
        assertEq(reputation.getReputation(), 1);
        vm.prank(user2);
        assertEq(reputation.getReputation(), 1);
        vm.prank(user3);
        assertEq(reputation.getReputation(), 1);
        vm.prank(jury);
        assertEq(reputation.getReputation(), 1);

        //authorized address makes final decision, selection second record
        vm.prank(authorized);
        oracle.verifyAttestation(attestationId, record2Id);

        //check attestation state
        (createdAt, resolved, finalResult) = oracle.getAttestationInfo(attestationId);
        assertEq(uint256(resolved), 3);
        assertEq(finalResult, record2Id);

        //check reputation changes
        vm.prank(user);
        assertEq(reputation.getReputation(), 0);
        vm.prank(user2);
        assertEq(reputation.getReputation(), 0);
        vm.prank(user3);
        assertEq(reputation.getReputation(), 2);
        vm.prank(jury);
        assertEq(reputation.getReputation(), 2);
    }

    function signHash(bytes32 userHash, uint256 privateKey) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, userHash);
        return abi.encodePacked(r, s, v);
    }

    function claimKyc(address user, uint256 backPk, string memory userDni, KycRegistry kyc, Reputation reputation) internal {
        bytes32 idHash = keccak256(abi.encodePacked(userDni));
        bytes32 userHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n84", user, idHash)
        );
        bytes memory userSign = signHash(userHash, backPk);
        vm.startPrank(user);
        kyc.claim(idHash, userSign);

        //check user has kyc and has reputation
        assertEq(kyc.balanceOf(user), 1);
        assertEq(reputation.getReputation(), 1);
        vm.stopPrank();
    }
}