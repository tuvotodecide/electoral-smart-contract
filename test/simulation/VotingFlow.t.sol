pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import {KycRegistry} from "../../src/KycRegistry.sol";
import {HumanOracleWithID} from "../../src/HumanOracleWithID.sol";
import {Reputation} from "../../src/Reputation.sol";
import {VotingRecord} from "../../src/VotingRecord.sol";

contract VotingFlowTest is Test {

    function initContracts() public returns(
        uint256 backPk,
        address user,
        address user2,
        address user3,
        address jury,
        string memory userDni,
        string memory juryDni,
        Reputation reputation,
        KycRegistry userKeys,
        KycRegistry juryKeys,
        VotingRecord recordNft,
        HumanOracleWithID oracle
    ) {
        //address of contract owner off-chain verification
        address owner = address(0x123);
        address backendSigner;
        (backendSigner, backPk) = makeAddrAndKey("backendSigner");

        //addresses of user and jury with their dni
        user = address(0x789);
        user2 = address(0x1011);
        user3 = address(0x1213);
        jury = address(0x1415);
        userDni = '123456';
        juryDni = '789010';

        //init reputation contract
        reputation = new Reputation(owner);

        //init user and jury nft for on-chain verification
        userKeys = new KycRegistry(backendSigner, address(reputation));
        juryKeys = new KycRegistry(backendSigner, address(reputation));

        //init nft contract for records
        recordNft = new VotingRecord(owner);

        //init oracle
        oracle = new HumanOracleWithID(
            address(userKeys),
            address(juryKeys),
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
        vm.stopPrank();
    }
    
    //three users vote
    function test_successVote() public {
        (
            uint256 backPk,
            address user,
            address user2,
            address user3,
            ,
            string memory userDni,
            ,
            Reputation reputation,
            KycRegistry userKeys,
            KycRegistry juryKeys,
            VotingRecord recordNft,
            HumanOracleWithID oracle
        ) = initContracts();

        //Claim a user kyc
        claimKyc(user, backPk, userDni, userKeys, reputation);
        claimKyc(user2, backPk, userDni, userKeys, reputation);
        claimKyc(user3, backPk, userDni, userKeys, reputation);

        vm.startPrank(user);
        //user inits a votation updating their first image
        vm.warp(123);
        (uint256 questionId, uint256 recordId) = oracle.createQuestion("new record");

        //check question created and user has record nft
        (uint256 createdAt, HumanOracleWithID.QuestionState resolved, uint256 finalResult) = oracle.viewQuestionInfo(questionId);
        assertEq(createdAt, 123);
        assertEq(uint256(resolved), 0);
        assertEq(oracle.viewQuestionWeighedVotes(questionId, recordId), 1);
        assertEq(recordNft.ownerOf(recordId), user);
        vm.stopPrank();

        //user 2 votes yes
        vm.prank(user2);
        oracle.vote(questionId, recordId, "");

        //check vote added +1
        assertEq(oracle.viewQuestionWeighedVotes(questionId, recordId), 2);

        //user 3 votes no and upload another record
        vm.startPrank(user3);
        oracle.vote(questionId, 0, "another record");

        //get user 3 vote
        uint256 record2Id = oracle.getOptionVoted(questionId);
        vm.stopPrank();

        //check votes for first and second record
        assertEq(oracle.viewQuestionWeighedVotes(questionId, recordId), 2);
        assertEq(oracle.viewQuestionWeighedVotes(questionId, record2Id), 1);

        //warp 4 days and resolve votation
        vm.warp(4 days);
        oracle.resolve(questionId);

        //check question status
        (createdAt, resolved, finalResult) = oracle.viewQuestionInfo(questionId);
        assertEq(uint256(resolved), 2);
        assertEq(finalResult, recordId);

        //check users reputation
        vm.prank(user);
        assertEq(reputation.getReputation(), 2);
        vm.prank(user2);
        assertEq(reputation.getReputation(), 2);
        vm.prank(user3);
        assertEq(reputation.getReputation(), 0);
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