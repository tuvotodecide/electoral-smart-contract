pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {AttestationOracle} from "../../src/AttestationOracle.sol";
import {Reputation} from "../../src/Reputation.sol";
import {AttestationRecord} from "../../src/AttestationRecord.sol";
import {WiraToken} from "../../src/WiraToken.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {AttestationOracleV2} from "../mocks/AttestationOracleV2.sol";

contract VerificationFlowUpgradeTest is Test {
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
        WiraToken token = new WiraToken(owner, owner, owner);

        //init oracle
        address oracleImpl = address(new AttestationOracle());
        address oracleProxy = UnsafeUpgrades.deployUUPSProxy(
            oracleImpl,
            abi.encodeCall(AttestationOracle.initialize, (
                owner,
                address(recordNft),
                address(reputation),
                address(token),
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
        token.grantRole(token.MINTER_ROLE(), address(oracle));
        vm.stopPrank();
    }

    function upgradeOracle() internal {
        vm.startPrank(owner);
        address newImplementation = address(new AttestationOracleV2());
        UnsafeUpgrades.upgradeProxy(address(oracle), newImplementation, "");
        vm.stopPrank();
    }

    function test_createAttestation_multiple_upgrade() public {
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

        upgradeOracle();
        //set new active time
        vm.prank(owner);
        oracle.setActiveTime(0, 200);

        //user creates third attestation after upgrade
        vm.prank(user);
        oracle.createAttestation("3", "new-record-3");

        //check attestation created and user has record nft
        (AttestationOracle.AttestationState resolved1,) = oracle.getAttestationInfo("1");
        (AttestationOracle.AttestationState resolved2,) = oracle.getAttestationInfo("2");
        (AttestationOracle.AttestationState resolved3,) = oracle.getAttestationInfo("3");
        assertEq(uint256(resolved1), 0);
        assertEq(uint256(resolved2), 0);
        assertEq(uint256(resolved3), 0);
        assertEq(oracle.getWeighedAttestations("1", 1), 1);
        assertEq(oracle.getWeighedAttestations("2", 2), 1);
        assertEq(oracle.getWeighedAttestations("3", 3), 1);
        assertEq(recordNft.ownerOf(1), user);
        assertEq(recordNft.ownerOf(2), user);
        assertEq(recordNft.ownerOf(3), user);
    }

    function test_createAttestation_withRegisterUser_upgrade() public {
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

        upgradeOracle();
        //set new active time
        vm.prank(owner);
        oracle.setActiveTime(0, 200);

        //check attestation created before upgrade is still accessible
        (AttestationOracle.AttestationState resolved2,) = oracle.getAttestationInfo(attestationId);
        assertEq(uint256(resolved2), 0);
        assertEq(oracle.getWeighedAttestations(attestationId, recordId), 1);
        assertEq(recordNft.ownerOf(recordId), user);
    }

    function test_inactiveOracle_upgrade() public {
        //default active period is 0-200, set current time to 201
        vm.warp(201);
        vm.expectRevert(bytes("Oracle inactive"));
        oracle.requestRegister("");

        upgradeOracle();

        //oracle active time is now 0-0, still inactive
        vm.warp(1);
        vm.expectRevert(bytes("Oracle inactive"));
        oracle.requestRegister("");
    }

    function test_activeOracle_upgrade() public {
        address user = makeAddr("user");
        address user2 = makeAddr("user2");

        //default active period is 0-200
        vm.warp(100);

        vm.prank(user);
        oracle.requestRegister("");

        upgradeOracle();

        //oracle active time is now 0-0, inactive
        vm.startPrank(user2);
        vm.expectRevert(bytes("Oracle inactive"));
        oracle.requestRegister("");
        vm.stopPrank();

        //set new active time: 100 - 150
        vm.prank(owner);
        oracle.setActiveTime(100, 50);

        //current time is 120, oracle active
        vm.warp(120);
        vm.prank(user2);
        oracle.requestRegister("");
    }

    function test_createAttestation_failOn_inactiveOracle_upgrade() public {
        address user = makeAddr("user");

        //register as user
        vm.prank(owner);
        oracle.register(user, false);

        //default active period is 0-200, ser current time to 201
        vm.warp(201);
        vm.expectRevert(bytes("Oracle inactive"));
        vm.prank(user);
        oracle.createAttestation("1", "record 1");

        upgradeOracle();

        //oracle active time is now 0-0, still inactive
        vm.warp(1);
        vm.expectRevert(bytes("Oracle inactive"));
        vm.prank(user);
        oracle.createAttestation("1", "record 1");
    }

    function test_createAttestation_alreadyAttested_upgrade() public {
        address user = makeAddr("user");

        //register as user
        vm.prank(owner);
        oracle.register(user, false);

        vm.warp(100);

        //user creates first attestation
        vm.prank(user);
        oracle.createAttestation("1", "record 1");

        upgradeOracle();
        //set new active time
        vm.prank(owner);
        oracle.setActiveTime(0, 200);

        //user tries to create attestation with same id, new error message should be triggered
        vm.prank(user);
        vm.expectRevert("Record already created");
        oracle.createAttestation("1", "record 1");
    }

    function test_createAttestation_setStartDate() public {
        address user = makeAddr("user");

        //register as user
        vm.prank(owner);
        oracle.register(user, false);

        vm.warp(100);

        //user creates first attestation
        vm.prank(user);
        oracle.createAttestation("1", "record 1");

        upgradeOracle();
        //set new active time
        vm.prank(owner);
        oracle.setActiveTime(0, 200);

        //user creates second attestation
        vm.prank(user);
        oracle.createAttestation("2", "record 2");

        AttestationOracleV2 upgradedOracle = AttestationOracleV2(address(oracle));

        //check first attestation has attestation start time as 0
        ( ,, uint256 startTime1,) = upgradedOracle.getAttestationInfo("1");
        assertEq(startTime1, 0);

        //check second attestation has attestation start time as current time (100)
        ( ,, uint256 startTime2,) = upgradedOracle.getAttestationInfo("2");
        assertEq(startTime2, 100);
    }

    function test_attest_failOn_inactiveOracle_upgrade() public {
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

        upgradeOracle();

        //oracle active time is now 0-0, still inactive
        vm.warp(1);
        vm.expectRevert(bytes("Oracle inactive"));
        vm.prank(user2);
        oracle.attest(id, recordId, true, "");
    }

    function test_resolve_failOn_activeOracle_upgrade() public {
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

        upgradeOracle();

        //oracle active time is now 0-0, need to set new active time
        vm.prank(owner);
        oracle.setActiveTime(100, 50);
        vm.warp(120);

        //check resolve still fails as too soon
        vm.expectRevert(bytes("too soon"));
        oracle.resolve(id);
    }

    function test_register_initsReputation_upgrade() public {
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

        upgradeOracle();

        //check user reputation after upgrade
        vm.prank(user1);
        assertEq(reputation.getReputation(), 1);

        //check jury reputation
        vm.prank(jury1);
        assertEq(reputation.getReputation(), 1);
    }

    function test_createAttestation_failOn_notRegisteredUser_upgrade() public {
        address user1 = makeAddr("user1");

        vm.expectRevert(bytes("Unauthorized"));
        vm.prank(user1);
        oracle.createAttestation("1", "record 1");

        upgradeOracle();
        vm.prank(owner);
        oracle.setActiveTime(0, 200);

        vm.expectRevert(bytes("Unauthorized"));
        vm.prank(user1);
        oracle.createAttestation("1", "record 1");
    }

    function test_attest_failOn_notRegisteredUser_upgrade() public {
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

        upgradeOracle();
        vm.prank(owner);
        oracle.setActiveTime(0, 200);

        //check user 2 tries to attest again
        vm.expectRevert("Unauthorized");
        vm.prank(user2);
        oracle.attest(id, recordId, true, "");
    }

    function test_attest_multiple_upgrade() public {
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

        upgradeOracle();
        //set new active time
        vm.prank(owner);
        oracle.setActiveTime(0, 200);

        //following attestations by user2 should work after upgrade
        //user 2 attest
        vm.prank(user2);
        oracle.attest(attestationId, recordId, true, "");

        //user 2 attest
        vm.prank(user2);
        oracle.attest(attestationId2, recordId2, true, "");
    }

    function test_create_thousandAttestations() public {
        address user = makeAddr("user");
        upgradeOracle();
        //set new active time
        vm.prank(owner);
        oracle.setActiveTime(0, 200);

        //register as user
        vm.prank(owner);
        oracle.register(user, false);

        //user creates 1000 attestations
        vm.startPrank(user);
        for (uint256 i = 0; i < 1000; i++) {
            string memory attestationId = vm.toString(i);
            oracle.createAttestation(attestationId, "record");
        }
        vm.stopPrank();

        AttestationOracleV2 upgradedOracle = AttestationOracleV2(address(oracle));
        vm.warp(250);

        //check attestations created and user has record nft
        for (uint256 i = 0; i < 1000; i++) {
            string memory attestationId = vm.toString(i);
            uint256 recordId = i + 1; //record ids start from 1
            upgradedOracle.resolve(attestationId);

            (AttestationOracleV2.AttestationState resolved, uint256 finalResult, uint256 startTime, uint256 endTime) = upgradedOracle.getAttestationInfo(attestationId);
            //check attestation status 4: PENDING
            assertEq(uint256(resolved), 4);
            //check attestation final result set
            assertEq(finalResult, recordId);
            assertEq(startTime, 100);
            assertEq(endTime, 250);
            assertEq(upgradedOracle.getWeighedAttestations(attestationId, i + 1), 1);
            assertEq(recordNft.ownerOf(recordId), user);
        }
    }

    function test_1attestation_100records_50users_50juries() public {
        address user = makeAddr("user");

        //register as user
        vm.prank(owner);
        oracle.register(user, false);

        string memory attestationId = "1";

        //user creates 1 attestation
        vm.prank(user);
        oracle.createAttestation(attestationId, "record");

        //register 49 users and 50 juries, everyone attest different records
        for (uint256 i = 0; i < 99; i++) {
            address userI = address(uint160(uint256(keccak256(abi.encodePacked(i)))));
            vm.prank(owner);
            oracle.register(userI, i < 49);

            vm.prank(userI);
            oracle.attest(attestationId, 0, false, vm.toString(i));
        }

        vm.warp(250);

        //check attestation created and user has record nft
        vm.prank(owner);
        oracle.resolve(attestationId);

        //check attestation info
        (AttestationOracle.AttestationState resolved, uint256 finalResult) = oracle.getAttestationInfo(attestationId);
        //check attestation status 2: VERIFYING
        assertEq(uint256(resolved), 2);
        //check attestation final result
        assertEq(finalResult, 0);
    }

    function test_1attestation_100records_101users() public {
        address user = makeAddr("user");

        //register as user
        vm.prank(owner);
        oracle.register(user, false);

        string memory attestationId = "1";

        //user creates 1 attestation
        vm.prank(user);
        oracle.createAttestation(attestationId, "record");

        //register 99 users and attest different records
        for (uint256 i = 0; i < 99; i++) {
            address userI = address(uint160(uint256(keccak256(abi.encodePacked(i)))));
            vm.prank(owner);
            oracle.register(userI, false);

            vm.prank(userI);
            oracle.attest(attestationId, 0, false, vm.toString(i));
        }

        //only last user attest an existing record
        address lastUser = makeAddr("lastUser");
        vm.prank(owner);
        oracle.register(lastUser, false);
        vm.prank(lastUser);
        oracle.attest(attestationId, 37, true, "");

        vm.warp(250);

        //check attestation created and user has record nft
        vm.prank(owner);
        oracle.resolve(attestationId);

        //check attestation info
        (AttestationOracle.AttestationState resolved, uint256 finalResult) = oracle.getAttestationInfo(attestationId);
        //check attestation status 4: PENDING
        assertEq(uint256(resolved), 4);
        //check attestation final result
        assertEq(finalResult, 37);
    }
}