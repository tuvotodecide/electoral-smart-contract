pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {console} from "lib/forge-std/src/console.sol";

import {AttestationOracle} from "../../src/AttestationOracle.sol";
import {Reputation} from "../../src/Reputation.sol";
import {AttestationRecord} from "../../src/AttestationRecord.sol";
import {Participation} from "../../src/Participation.sol";
import {WiraToken} from "../../src/WiraToken.sol";

contract VerificationFlowTest is Test {
    AttestationOracle oracle;
    AttestationRecord recordNft;
    Participation participation;
    Reputation reputation;
    address owner;
    string participationNft = "participation nft";

    function setUp() public {
        //address of contract owner to grant roles and access to reputation and nft
        owner = makeAddr("owner");

        //init nft contract for records and participation
        recordNft = new AttestationRecord(owner);
        participation = new Participation(owner);

        //init reputation contract
        reputation = new Reputation(owner);

        //init stake wira token
        WiraToken token = new WiraToken(owner, owner, owner);

        //init oracle
        oracle = new AttestationOracle(
            owner,
            address(recordNft),
            address(participation),
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
        participation.grantRole(participation.AUTHORIZED_ROLE(), address(oracle));
        reputation.grantRole(recordNft.AUTHORIZED_ROLE(), address(oracle));
        token.grantRole(token.MINTER_ROLE(), address(oracle));
        vm.stopPrank();
    }

    function test_createAttestation_givesOnlyOneParticipation() public {
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

        //user creates first attestation
        vm.prank(user);
        oracle.createAttestation("1", "new-record", participationNft);

        //check user have participation nft
        assertEq(participation.balanceOf(user), 1);

        //user creates second attestation
        vm.prank(user);
        oracle.createAttestation("2", "new-record-2", participationNft);

        //check user have still only one participation nft
        assertEq(participation.balanceOf(user), 1);
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
        string memory attestationId = "1";
        vm.startPrank(user);
        //user inits a votation updating their first image
        uint256 recordId = oracle.createAttestation(attestationId, "new-record", participationNft);

        //check attestation created and user has record and participation nft
        (AttestationOracle.AttestationState resolved,) = oracle.getAttestationInfo(attestationId);
        assertEq(uint256(resolved), 0);
        assertEq(oracle.getWeighedAttestations(attestationId, recordId), 1);
        assertEq(recordNft.ownerOf(recordId), user);
        assertEq(participation.balanceOf(user), 1);
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
        oracle.createAttestation("1", "record 1", participationNft);
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
        string memory id = "1";
        vm.prank(user1);
        uint256 recordId = oracle.createAttestation(id, "record 1", participationNft);

        //default active period is 0-200, ser current time to 201
        vm.warp(201);
        //test attest
        vm.expectRevert(bytes("Oracle inactive"));
        vm.prank(user2);
        oracle.attest(id, recordId, true, "", participationNft);
    }

    function test_resolve_failOn_activeOracle() public {
        address user1 = makeAddr("user1");

        //register user
        vm.prank(owner);
        oracle.register(user1, false);

        //user 1 uploads a record
        string memory id = "1";
        vm.prank(user1);
        oracle.createAttestation(id, "record 1", participationNft);

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
        oracle.createAttestation("1", "record 1", participationNft);
    }

    function test_attest_failOn_notRegisteredUser() public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");

        //register user
        vm.prank(owner);
        oracle.register(user1, false);

        //user 1 create attestation
        string memory id = "1";
        vm.prank(user1);
        uint256 recordId = oracle.createAttestation(id, "record 1", participationNft);
        
        //check user 2 attest
        vm.expectRevert("Unauthorized");
        vm.prank(user2);
        oracle.attest(id, recordId, true, "", participationNft);
    }

    function test_attest_givesOnlyOneParticipation() public {
        //set oracle active period
        vm.prank(owner);
        oracle.setActiveTime(0, 200);
        vm.warp(100);

        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");

        //register users
        vm.startPrank(owner);
        oracle.register(user1, false);
        oracle.register(user2, false);
        vm.stopPrank();

        //user 1 creates two attestations
        string memory attestationId = "1";
        string memory attestationId2 = "2";
        
        vm.startPrank(user1);
        uint256 recordId = oracle.createAttestation(attestationId, "new-record", participationNft);
        uint256 recordId2 = oracle.createAttestation(attestationId2, "new-record-2", participationNft);
        vm.stopPrank();

        //check user 1 have only one participation nft
        assertEq(participation.balanceOf(user1), 1);

        //user 2 attest
        vm.prank(user2);
        oracle.attest(attestationId, recordId, true, "", participationNft);

        //check user 2 have participation nft
        assertEq(participation.balanceOf(user2), 1);

        //user 2 attest
        vm.prank(user2);
        oracle.attest(attestationId2, recordId2, true, "", participationNft);

        //check user 2 have still one participation nft
        assertEq(participation.balanceOf(user2), 1);
    }
}
