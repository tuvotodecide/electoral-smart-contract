pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";

import {AttestationOracle} from "../../src/AttestationOracle.sol";
import {Reputation} from "../../src/Reputation.sol";
import {AttestationRecord} from "../../src/AttestationRecord.sol";
import {WiraToken} from "../../src/WiraToken.sol";

contract VerificationFlowTest is Test {
    AttestationOracle oracle;
    AttestationRecord recordNft;
    Reputation reputation;
    address owner;

    function setUp() public {
        //address of contract owner to grant roles and access to reputation and nft
        owner = makeAddr("owner");

        //init nft contract for records
        recordNft = new AttestationRecord(owner);

        //init reputation contract
        reputation = new Reputation(owner);

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

        vm.startPrank(owner);
        //set default oracle active period
        oracle.setActiveTime(0, 200);
        vm.warp(100);

        //Authorize oracle access to record contract
        recordNft.grantRole(recordNft.AUTHORIZED_ROLE(), address(oracle));
        reputation.grantRole(recordNft.AUTHORIZED_ROLE(), address(oracle));
        token.grantRole(token.MINTER_ROLE(), address(oracle));
        vm.stopPrank();
    }

    function test_createAttestation_withRegisterUser() public {
        address user = makeAddr("user");

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

    function test_requestRegister_failOn_inactiveOracle() public {
        //default active period is 0-200, set current time to 201
        vm.warp(201);
        vm.expectRevert(bytes("Oracle inactive"));
        oracle.requestRegister("");
    }

    function test_createAttestation_failOn_inactiveOracle() public {
        address user = makeAddr("user");

        //register as user
        vm.prank(owner);
        oracle.register(user, false);

        //default active period is 0-200, ser current time to 201
        vm.warp(201);
        vm.expectRevert(bytes("Oracle inactive"));
        vm.prank(user);
        oracle.createAttestation("record 1");
    }

    function test_attest_failOn_inactiveOracle() public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");

        //register users
        vm.startPrank(owner);
        oracle.register(user1, false);
        oracle.register(user2, false);
        vm.stopPrank();

        //user 1 uploads a record
        vm.prank(user1);
        (uint256 id, uint256 recordId) = oracle.createAttestation("record 1");

        //default active period is 0-200, ser current time to 201
        vm.warp(201);
        //test attest
        vm.expectRevert(bytes("Oracle inactive"));
        vm.prank(user2);
        oracle.attest(id, recordId, true, "");
    }

    function test_resolve_failOn_activeOracle() public {
        address user1 = makeAddr("user1");

        //register user
        vm.prank(owner);
        oracle.register(user1, false);

        //user 1 uploads a record
        vm.prank(user1);
        (uint256 id, ) = oracle.createAttestation("record 1");

        //default active period is 0-200, current time is 100, test resolve
        vm.expectRevert(bytes("too soon"));
        oracle.resolve(id);
    }

    function test_register_initsReputation() public {
        address user1 = makeAddr("user1");
        address jury1 = makeAddr("jury1");

        //register user
        vm.prank(owner);
        oracle.register(user1, false);

        //check user reputation
        vm.prank(user1);
        assertEq(reputation.getReputation(), 1);

        //register jury
        vm.prank(owner);
        oracle.register(jury1, true);

        //check jury reputation
        vm.prank(jury1);
        assertEq(reputation.getReputation(), 1);
    }

    function test_createAttestation_failOn_notRegisteredUser() public {
        address user1 = makeAddr("user1");

        vm.expectRevert(bytes("Unauthorized"));
        vm.prank(user1);
        oracle.createAttestation("record 1");
    }

    function test_attest_failOn_notRegisteredUser() public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");

        //register user
        vm.prank(owner);
        oracle.register(user1, false);

        //user 1 create attestation
        vm.prank(user1);
        (uint256 id, uint256 recordId) = oracle.createAttestation("record 1");
        
        //check user 2 attest
        vm.expectRevert("Unauthorized");
        vm.prank(user2);
        oracle.attest(id, recordId, true, "");
    }
}