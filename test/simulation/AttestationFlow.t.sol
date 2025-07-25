pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import {AttestationOracle} from "../../src/AttestationOracle.sol";
import {Reputation} from "../../src/Reputation.sol";
import {AttestationRecord} from "../../src/AttestationRecord.sol";
import {WiraToken} from "../../src/WiraToken.sol";

contract AttestationFlowTest is Test {
    function initContracts()
        public
        returns (
            address user,
            address user2,
            address user3,
            address jury,
            address authorized,
            Reputation reputation,
            AttestationRecord recordNft,
            AttestationOracle oracle,
            WiraToken token
        )
    {
        //address of contract owner to grant roles and access to reputation and nft
        address owner = address(0x123);

        //addresses of user and jury with their dni
        user = address(0x789);
        user2 = address(0x1011);
        user3 = address(0x1213);
        jury = address(0x1415);
        authorized = address(0x1617);

        //init reputation contract
        reputation = new Reputation(owner);

        //init nft contract for records
        recordNft = new AttestationRecord(owner);

        //init stake wira token
        token = new WiraToken(owner, owner, owner);

        //init oracle
        oracle = new AttestationOracle(owner, address(recordNft), address(reputation), address(token), 5e18);

        vm.startPrank(owner);
        //Authorize oracle access to record and reputation contracts
        recordNft.grantRole(recordNft.AUTHORIZED_ROLE(), address(oracle));
        reputation.grantRole(recordNft.AUTHORIZED_ROLE(), address(oracle));
        token.grantRole(token.MINTER_ROLE(), address(oracle));

        //set oracle active period
        oracle.setActiveTime(0, 200);
        vm.warp(100);

        //register users and jury on oracle
        oracle.register(user, false);
        oracle.register(user2, false);
        oracle.register(user3, false);
        oracle.register(jury, true);

        //Grant authority role manually
        oracle.grantRole(oracle.AUTHORITY_ROLE(), authorized);
        vm.stopPrank();
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
            AttestationOracle oracle,
            WiraToken token
        ) = initContracts();

        vm.startPrank(user);
        //user inits a votation updating their first image
        (uint256 attestationId, uint256 recordId) = oracle.createAttestation("new record");

        //check attestation created and user has record nft
        (AttestationOracle.AttestationState resolved, uint256 finalResult) = oracle.getAttestationInfo(attestationId);
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
        vm.warp(3 hours);
        oracle.resolve(attestationId);

        //check attestation status
        (resolved, finalResult) = oracle.getAttestationInfo(attestationId);
        assertEq(uint256(resolved), 3);
        assertEq(finalResult, recordId);

        //three users voted, 15e18 total staking, all voted yes, 5e18 for every user
        //check users reputation and stake
        vm.prank(user);
        assertEq(reputation.getReputation(), 2);
        assertEq(token.balanceOf(user), 5e18);
        vm.prank(user2);
        assertEq(reputation.getReputation(), 2);
        assertEq(token.balanceOf(user2), 5e18);
        vm.prank(user3);
        assertEq(reputation.getReputation(), 2);
        assertEq(token.balanceOf(user3), 5e18);
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
            AttestationOracle oracle,
            WiraToken token
        ) = initContracts();

        vm.startPrank(user);
        //user inits a votation updating their first image
        (uint256 attestationId, uint256 recordId) = oracle.createAttestation("new record");

        //check attestation created and user has record nft
        (AttestationOracle.AttestationState resolved, uint256 finalResult) = oracle.getAttestationInfo(attestationId);
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
        vm.warp(3 hours);
        oracle.resolve(attestationId);

        //check attestation status
        (resolved, finalResult) = oracle.getAttestationInfo(attestationId);
        assertEq(uint256(resolved), 1);
        assertEq(finalResult, recordId);

        //four users voted, 20e18 total staking, three was right, 6.666...e18 for every user
        uint256 userReward = uint256(20e18) / uint256(3);
        //check users reputation
        vm.prank(user);
        assertEq(reputation.getReputation(), 2);
        assertEq(token.balanceOf(user), userReward);
        vm.prank(user2);
        assertEq(reputation.getReputation(), 2);
        assertEq(token.balanceOf(user2), userReward);
        vm.prank(user3);
        assertEq(reputation.getReputation(), 0);
        assertEq(token.balanceOf(user3), 0);
        vm.prank(jury);
        assertEq(reputation.getReputation(), 2);
        assertEq(token.balanceOf(jury), userReward);
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
            AttestationOracle oracle,
            WiraToken token
        ) = initContracts();

        vm.startPrank(user);
        //user inits a votation updating their first image
        (uint256 attestationId, uint256 recordId) = oracle.createAttestation("new record");

        //check attestation created and user has record nft
        (AttestationOracle.AttestationState resolved, uint256 finalResult) = oracle.getAttestationInfo(attestationId);
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
        vm.warp(3 hours);
        oracle.resolve(attestationId);

        //check attestation status
        (resolved, finalResult) = oracle.getAttestationInfo(attestationId);
        assertEq(uint256(resolved), 1);
        assertEq(finalResult, recordId);

        //four users voted, 20e18 total staking, three was right, 6.666...e18 for every user
        uint256 userReward = uint256(20e18) / uint256(3);
        //check users reputation
        vm.prank(user);
        assertEq(reputation.getReputation(), 2);
        assertEq(token.balanceOf(user), userReward);
        vm.prank(user2);
        assertEq(reputation.getReputation(), 2);
        assertEq(token.balanceOf(user2), userReward);
        vm.prank(user3);
        assertEq(reputation.getReputation(), 0);
        assertEq(token.balanceOf(user3), 0);
        vm.prank(jury);
        assertEq(reputation.getReputation(), 2);
        assertEq(token.balanceOf(jury), userReward);
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
            AttestationOracle oracle,
            WiraToken token
        ) = initContracts();

        vm.startPrank(user);
        //user inits a votation updating their first image
        (uint256 attestationId, uint256 recordId) = oracle.createAttestation("new record");

        //check attestation created and user has record nft
        (AttestationOracle.AttestationState resolved, uint256 finalResult) = oracle.getAttestationInfo(attestationId);
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
        vm.warp(3 hours);
        oracle.resolve(attestationId);

        //check attestation is in verification state
        (resolved, finalResult) = oracle.getAttestationInfo(attestationId);
        assertEq(uint256(resolved), 2);
        assertEq(finalResult, 0);

        //check users reputation without changes
        vm.prank(user);
        assertEq(reputation.getReputation(), 1);
        assertEq(token.balanceOf(user), 0);
        vm.prank(user2);
        assertEq(reputation.getReputation(), 1);
        assertEq(token.balanceOf(user2), 0);
        vm.prank(user3);
        assertEq(reputation.getReputation(), 1);
        assertEq(token.balanceOf(user3), 0);
        vm.prank(jury);
        assertEq(reputation.getReputation(), 1);
        assertEq(token.balanceOf(jury), 0);

        //authorized address makes final decision, selection second record
        vm.prank(authorized);
        oracle.verifyAttestation(attestationId, record2Id);

        //check attestation state
        (resolved, finalResult) = oracle.getAttestationInfo(attestationId);
        assertEq(uint256(resolved), 3);
        assertEq(finalResult, record2Id);

        //four users voted, 20e18 total staking, two was right, 10e18 for every user
        //check reputation changes
        vm.prank(user);
        assertEq(reputation.getReputation(), 0);
        assertEq(token.balanceOf(user), 0);
        vm.prank(user2);
        assertEq(reputation.getReputation(), 0);
        assertEq(token.balanceOf(user2), 0);
        vm.prank(user3);
        assertEq(reputation.getReputation(), 2);
        assertEq(token.balanceOf(user3), 10e18);
        vm.prank(jury);
        assertEq(reputation.getReputation(), 2);
        assertEq(token.balanceOf(jury), 10e18);
    }
}
