pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {AttestationOracle} from "../../src/AttestationOracle.sol";
import {Reputation} from "../../src/Reputation.sol";
import {AttestationRecord} from "../../src/AttestationRecord.sol";
import {WiraToken} from "../../src/WiraToken.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {MaliciousToken} from "../mocks/MaliciousToken.sol";

contract VerificationFlowTest is Test {
    AttestationOracle oracle;
    AttestationRecord recordNft;
    Reputation reputation;
    address owner;

    function setUp() public {
        //address of contract owner to grant roles and access to reputation and nft
        owner = makeAddr("owner");

        //init nft contract for records and participation
        recordNft = new AttestationRecord(owner);

        //init reputation contract
        address implementation = address(new Reputation());
        address proxy = UnsafeUpgrades.deployUUPSProxy(
            implementation,
            abi.encodeCall(Reputation.initialize, (owner))
        );
        reputation = Reputation(proxy);

        //init stake wira token
        address tokenHolder = makeAddr("tokenHolder");
        WiraToken token = new WiraToken(tokenHolder, owner, owner, owner);

        //init oracle
        address oracleImpl = address(new AttestationOracle());
        address oracleProxy = UnsafeUpgrades.deployUUPSProxy(
            oracleImpl,
            abi.encodeCall(AttestationOracle.initialize, (
                owner,
                address(recordNft),
                address(reputation),
                address(token),
                tokenHolder,
                5e18
            ))
        );
        oracle = AttestationOracle(oracleProxy);

        vm.startPrank(owner);
        //set default oracle active period
        oracle.setActiveTime(0, 200);
        vm.warp(100);

        //Authorize oracle access to record contract
        recordNft.grantRole(recordNft.AUTHORIZED_ROLE(), address(oracle));
        reputation.grantRole(recordNft.AUTHORIZED_ROLE(), address(oracle));
        vm.stopPrank();

        //Approve oracle to transfer stake tokens on behalf of holder
        vm.prank(tokenHolder);
        token.approve(address(oracle), 1000000e18);
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
        oracle.createAttestation("1", "new-record");

        //user creates second attestation
        vm.prank(user);
        oracle.createAttestation("2", "new-record-2");
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
        uint256 recordId = oracle.createAttestation(attestationId, "new-record");

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
        oracle.createAttestation("1", "record 1");
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
        uint256 recordId = oracle.createAttestation(id, "record 1");

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
        string memory id = "1";
        vm.prank(user1);
        oracle.createAttestation(id, "record 1");

        //default active period is 0-200, current time is 100, test resolve
        vm.expectRevert(bytes("too soon"));
        oracle.resolve(id);
    }

    function test_resolve_reentrancyAttack() public {
        // Deploy malicious token
        string memory id = "reentry-test";
        address tokenHolder = makeAddr("tokenHolder");
        MaliciousToken maliciousToken = new MaliciousToken(tokenHolder);

        // Reinitialize oracle with malicious token
        vm.startPrank(owner);
        address oracleImpl = address(new AttestationOracle());
        address oracleProxy = UnsafeUpgrades.deployUUPSProxy(
            oracleImpl,
            abi.encodeCall(AttestationOracle.initialize, (
                owner,
                address(recordNft),
                address(reputation),
                address(maliciousToken),
                tokenHolder,
                5e18
            ))
        );
        AttestationOracle oracleMod = AttestationOracle(oracleProxy);
        oracleMod.setActiveTime(0, 200);
        recordNft.grantRole(recordNft.AUTHORIZED_ROLE(), address(oracleMod));
        reputation.grantRole(recordNft.AUTHORIZED_ROLE(), address(oracleMod));
        vm.stopPrank();

        //Set reentrancy data in malicious token
        maliciousToken.setReentrancyData(address(oracleMod), id);

        //Approve oracle to transfer stake tokens on behalf of holder
        vm.prank(tokenHolder);
        maliciousToken.approve(address(oracleMod), 1000000e18);

        // Register users and jury
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        address jury1 = makeAddr("jury1");

        vm.startPrank(owner);
        oracleMod.register(user1, false);
        oracleMod.register(user2, false);
        oracleMod.register(jury1, true);
        vm.stopPrank();

        // Create attestation
        vm.prank(user1);
        uint256 recordId = oracleMod.createAttestation(id, "record");

        // Attest to accumulate stakes
        vm.prank(user2);
        oracleMod.attest(id, recordId, true, "");

        vm.prank(jury1);
        oracleMod.attest(id, recordId, true, "");

        // Warp past attestEnd
        vm.warp(201);

        // Attempt resolve - should revert due to reentrancy
        vm.expectRevert("ReentrancyGuardReentrantCall()");
        oracleMod.resolve(id);
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
        oracle.createAttestation("1", "record 1");
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
        uint256 recordId = oracle.createAttestation(id, "record 1");
        
        //check user 2 attest
        vm.expectRevert("Unauthorized");
        vm.prank(user2);
        oracle.attest(id, recordId, true, "");
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
        uint256 recordId = oracle.createAttestation(attestationId, "new-record");
        uint256 recordId2 = oracle.createAttestation(attestationId2, "new-record-2");
        vm.stopPrank();

        //user 2 attest
        vm.prank(user2);
        oracle.attest(attestationId, recordId, true, "");

        //user 2 attest
        vm.prank(user2);
        oracle.attest(attestationId2, recordId2, true, "");
    }

    function test_failOn_noExistingAttestationId() public {
        //set oracle active period
        vm.prank(owner);
        oracle.setActiveTime(0, 200);
        vm.warp(100);

        address user1 = makeAddr("user1");
        address authority = makeAddr("authority");

        //register user
        vm.startPrank(owner);
        oracle.register(user1, false);
        oracle.grantRole(oracle.AUTHORITY_ROLE(), authority);
        vm.stopPrank();

        //try to attest non existing attestation id
        vm.expectRevert("Non existing attestation");
        vm.prank(user1);
        oracle.attest("non-existing-id", 1, true, "");

        //try to resolve non existing attestation id
        vm.warp(201);
        vm.expectRevert("Non existing attestation");
        oracle.resolve("non-existing-id");

        //try to verify non existing attestation id
        //this returns "Bad attestation state" because not existing attestation doesn't have state VERIFYING
        vm.expectRevert("Bad attestation state");
        vm.prank(authority);
        oracle.verifyAttestation("non-existing-id", 1);
    }

    function test_attest_failOn_noExistingRecord() public {
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

        //user 1 creates attestation, creating a recordId
        string memory attestationId = "1";
        
        vm.startPrank(user1);
        uint256 recordId = oracle.createAttestation(attestationId, "new-record");
        vm.stopPrank();

        //user 2 attest not existing record id
        uint256 nonExistingRecordId = recordId + 1;
        vm.prank(user2);
        uint256 attestedRecord = oracle.attest(attestationId, nonExistingRecordId, true, "");

        //When attestation record does not exist, attest returns 0 instead of attested record id
        assertEq(attestedRecord, 0);
    }
}