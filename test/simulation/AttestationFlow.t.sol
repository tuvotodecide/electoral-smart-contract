pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import {AttestationOracle} from "../../src/AttestationOracle.sol";
import {Reputation} from "../../src/Reputation.sol";
import {AttestationRecord} from "../../src/AttestationRecord.sol";
import {Participation} from "../../src/Participation.sol";
import {WiraToken} from "../../src/WiraToken.sol";

contract AttestationFlowTest is Test {
    Reputation reputation;
    AttestationRecord recordNft;
    Participation participation;
    AttestationOracle oracle;
    WiraToken token;
    address owner;
    address resolver;
    string participationNft = "participation nft";

    function setUp() public {
        //address of contract owner to grant roles and access to reputation and nft
        owner = makeAddr("owner");
        resolver = makeAddr("resolver");

        //init reputation contract
        reputation = new Reputation(owner);

        //init nft contract for records and participation
        recordNft = new AttestationRecord(owner);
        participation = new Participation(owner);

        //init stake wira token
        token = new WiraToken(owner, owner, owner);

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
        //Authorize oracle access to record and reputation contracts
        recordNft.grantRole(recordNft.AUTHORIZED_ROLE(), address(oracle));
        participation.grantRole(participation.AUTHORIZED_ROLE(), address(oracle));
        reputation.grantRole(recordNft.AUTHORIZED_ROLE(), address(oracle));
        token.grantRole(token.MINTER_ROLE(), address(oracle));
        oracle.grantRole(oracle.DEFAULT_ADMIN_ROLE(), resolver);

        //set oracle active period
        oracle.setActiveTime(0, 200);
        vm.warp(100);
        vm.stopPrank();
    }

    function test_unanimous_1record_1user() public {
        address user1 = makeAddr("user1");

        //register user 1
        vm.prank(resolver);
        oracle.register(user1, false);

        //user 1 uploads record
        string memory attestationId = "1";
        vm.prank(user1);
        (uint256 recordId) = oracle.createAttestation(attestationId, "record 1", participationNft);

        //wrap time and resolve
        vm.warp(201);
        oracle.resolve(attestationId);

        //check attestation info
        (AttestationOracle.AttestationState resolved, uint256 finalResult) = oracle.getAttestationInfo(attestationId);
        //check attestation status 4: PENDING
        assertEq(uint256(resolved), 4);
        //check attestation final result set
        assertEq(finalResult, recordId);

        //check user reputation
        vm.prank(user1);
        assertEq(reputation.getReputation(), 2);
        //check user received stake
        assertEq(token.balanceOf(user1), 5e18);
    }

    function test_unanimous_1record_2users() public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");

        //register users
        vm.startPrank(owner);
        oracle.register(user1, false);
        oracle.register(user2, false);
        vm.stopPrank();

        //user 1 uploads record
        string memory attestationId = "1";
        vm.prank(user1);
        uint256 recordId = oracle.createAttestation(attestationId, "record 1", participationNft);

        //user 2 attest record 1
        vm.prank(user2);
        oracle.attest(attestationId, recordId, true, "", participationNft);

        //wrap time and resolve
        vm.warp(201);
        oracle.resolve(attestationId);

        //check attestation info
        (AttestationOracle.AttestationState resolved, uint256 finalResult) = oracle.getAttestationInfo(attestationId);
        //check attestation status 4: PENDING
        assertEq(uint256(resolved), 4);
        //check attestation final result
        assertEq(finalResult, recordId);

        //check users reputation
        vm.prank(user1);
        assertEq(reputation.getReputation(), 2);
        vm.prank(user2);
        assertEq(reputation.getReputation(), 2);

        //check users received stake
        assertEq(token.balanceOf(user1), 5e18);
        assertEq(token.balanceOf(user2), 5e18);
    }

    function test_unanimous_1record_3users() public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");

        //register users
        vm.startPrank(owner);
        oracle.register(user1, false);
        oracle.register(user2, false);
        oracle.register(user3, false);
        vm.stopPrank();

        //user 1 uploads record
        string memory attestationId = "1";
        vm.prank(user1);
        uint256 recordId = oracle.createAttestation(attestationId, "record 1", participationNft);

        //user 2 attest record 1
        vm.prank(user2);
        oracle.attest(attestationId, recordId, true, "", participationNft);

        //user 3 attest record 1
        vm.prank(user3);
        oracle.attest(attestationId, recordId, true, "", participationNft);

        //wrap time and resolve
        vm.warp(201);
        oracle.resolve(attestationId);

        //check attestation info
        (AttestationOracle.AttestationState resolved, uint256 finalResult) = oracle.getAttestationInfo(attestationId);
        //check attestation status 3: CLOSED
        assertEq(uint256(resolved), 3);
        //check attestation final result set
        assertEq(finalResult, recordId);

        //check users reputation up
        vm.prank(user1);
        assertEq(reputation.getReputation(), 2);
        vm.prank(user2);
        assertEq(reputation.getReputation(), 2);
        vm.prank(user3);
        assertEq(reputation.getReputation(), 2);

        //total stake 15 WIRA, three users was right, 5 WIRA for every user
        assertEq(token.balanceOf(user1), 5e18);
        assertEq(token.balanceOf(user2), 5e18);
        assertEq(token.balanceOf(user3), 5e18);
    }

    function test_unanimous_1record_1jury() public {
        address jury1 = makeAddr("jury1");

        //register jury 1
        vm.prank(owner);
        oracle.register(jury1, true);

        //jury 1 uploads record
        string memory attestationId = "1";
        vm.prank(jury1);
        uint256 recordId = oracle.createAttestation(attestationId, "record 1", participationNft);

        //wrap time and resolve
        vm.warp(201);
        oracle.resolve(attestationId);

        //check attestation info
        (AttestationOracle.AttestationState resolved, uint256 finalResult) = oracle.getAttestationInfo(attestationId);
        //check attestation status 3: CLOSED
        assertEq(uint256(resolved), 3);
        //check attestation final result set
        assertEq(finalResult, recordId);

        //check jury reputation up
        vm.prank(jury1);
        assertEq(reputation.getReputation(), 2);

        //total stake: 5 WIRA, all for unique jury
        assertEq(token.balanceOf(jury1), 5e18);
    }

    function test_unanimous_1record_3juries() public {
        address jury1 = makeAddr("jury1");
        address jury2 = makeAddr("jury2");
        address jury3 = makeAddr("jury3");

        //register juries
        vm.startPrank(owner);
        oracle.register(jury1, true);
        oracle.register(jury2, true);
        oracle.register(jury3, true);
        vm.stopPrank();

        //jury 1 uploads record
        string memory attestationId = "1";
        vm.prank(jury1);
        uint256 recordId = oracle.createAttestation(attestationId, "record 1", participationNft);

        //jury 2 attest record 1
        vm.prank(jury2);
        oracle.attest(attestationId, recordId, true, "", participationNft);

        //jury 3 attest record 1
        vm.prank(jury3);
        oracle.attest(attestationId, recordId, true, "", participationNft);

        //wrap time and resolve
        vm.warp(201);
        oracle.resolve(attestationId);

        //check attestation info
        (AttestationOracle.AttestationState resolved, uint256 finalResult) = oracle.getAttestationInfo(attestationId);
        //check attestation status 3: CLOSED
        assertEq(uint256(resolved), 3);
        //check attestation final result set
        assertEq(finalResult, recordId);

        //check juries reputation up
        vm.prank(jury1);
        assertEq(reputation.getReputation(), 2);
        vm.prank(jury2);
        assertEq(reputation.getReputation(), 2);
        vm.prank(jury3);
        assertEq(reputation.getReputation(), 2);

        //total stake: 15 WIRA, three juries was right, 5 WIRA for every jury
        assertEq(token.balanceOf(jury1), 5e18);
        assertEq(token.balanceOf(jury2), 5e18);
        assertEq(token.balanceOf(jury3), 5e18);
    }

    function test_unanimous_1record_1user_1jury() public {
        address user1 = makeAddr("user1");
        address jury1 = makeAddr("jury1");

        //register users
        vm.startPrank(owner);
        oracle.register(user1, false);
        oracle.register(jury1, true);
        vm.stopPrank();

        //user 1 uploads record
        string memory attestationId = "1";
        vm.prank(user1);
        uint256 recordId = oracle.createAttestation(attestationId, "record 1", participationNft);

        //jury 1 attest record 1
        vm.prank(jury1);
        oracle.attest(attestationId, recordId, true, "", participationNft);

        //wrap time and resolve
        vm.warp(201);
        oracle.resolve(attestationId);

        //check attestation info
        (AttestationOracle.AttestationState resolved, uint256 finalResult) = oracle.getAttestationInfo(attestationId);
        //check attestation status 3: CLOSED
        assertEq(uint256(resolved), 3);
        //check attestation final result set
        assertEq(finalResult, recordId);

        //check users reputation up
        vm.prank(user1);
        assertEq(reputation.getReputation(), 2);
        vm.prank(jury1);
        assertEq(reputation.getReputation(), 2);

        //total stake: 15 WIRA, two users was right, 5 WIRA for every user
        assertEq(token.balanceOf(user1), 5e18);
        assertEq(token.balanceOf(jury1), 5e18);
    }

    function test_unanimous_1record_3users_3juries() public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");

        address jury1 = makeAddr("jury1");
        address jury2 = makeAddr("jury2");
        address jury3 = makeAddr("jury3");

        //register users
        vm.startPrank(owner);
        oracle.register(user1, false);
        oracle.register(user2, false);
        oracle.register(user3, false);
        oracle.register(jury1, true);
        oracle.register(jury2, true);
        oracle.register(jury3, true);
        vm.stopPrank();

        //user 1 uploads record
        vm.prank(user1);
        string memory attestationId = "1";
        uint256 recordId = oracle.createAttestation(attestationId, "record 1", participationNft);

        //users attest record 1
        vm.prank(user2);
        oracle.attest(attestationId, recordId, true, "", participationNft);
        vm.prank(user3);
        oracle.attest(attestationId, recordId, true, "", participationNft);

        //juries attest record 1
        vm.prank(jury1);
        oracle.attest(attestationId, recordId, true, "", participationNft);
        vm.prank(jury2);
        oracle.attest(attestationId, recordId, true, "", participationNft);
        vm.prank(jury3);
        oracle.attest(attestationId, recordId, true, "", participationNft);

        //wrap time and resolve
        vm.warp(201);
        oracle.resolve(attestationId);

        //check attestation info
        (AttestationOracle.AttestationState resolved, uint256 finalResult) = oracle.getAttestationInfo(attestationId);
        //check attestation status 3: CLOSED
        assertEq(uint256(resolved), 3);
        //check attestation final result set
        assertEq(finalResult, recordId);

        //check users reputation up
        vm.prank(user1);
        assertEq(reputation.getReputation(), 2);
        vm.prank(user2);
        assertEq(reputation.getReputation(), 2);
        vm.prank(user3);
        assertEq(reputation.getReputation(), 2);

        //check juries reputation up
        vm.prank(jury1);
        assertEq(reputation.getReputation(), 2);
        vm.prank(jury2);
        assertEq(reputation.getReputation(), 2);
        vm.prank(jury3);
        assertEq(reputation.getReputation(), 2);

        //total stake: 30 WIRA, all users was right, 5 WIRA for every user
        assertEq(token.balanceOf(user1), 5e18);
        assertEq(token.balanceOf(user2), 5e18);
        assertEq(token.balanceOf(user3), 5e18);

        assertEq(token.balanceOf(jury1), 5e18);
        assertEq(token.balanceOf(jury2), 5e18);
        assertEq(token.balanceOf(jury3), 5e18);
    }

    function test_tie_3records_3users() public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");

        //register users
        vm.startPrank(owner);
        oracle.register(user1, false);
        oracle.register(user2, false);
        oracle.register(user3, false);
        vm.stopPrank();

        //user 1 uploads record 1
        string memory attestationId = "1";
        vm.prank(user1);
        oracle.createAttestation(attestationId, "record 1", participationNft);

        //user 2 uploads record 2 on same attestation
        vm.prank(user2);
        oracle.attest(attestationId, 0, false, "record 2", participationNft);

        //user 3 uploads record 3 on same attestation
        vm.prank(user3);
        oracle.attest(attestationId, 0, false, "record 3", participationNft);

        //wrap time and resolve
        vm.warp(201);
        oracle.resolve(attestationId);

        //check attestation info
        (AttestationOracle.AttestationState resolved, uint256 finalResult) = oracle.getAttestationInfo(attestationId);
        //check attestation status 2: VERIFYING
        assertEq(uint256(resolved), 2);
        //check attestation final result not set
        assertEq(finalResult, 0);

        //check users reputation without changes
        vm.prank(user1);
        assertEq(reputation.getReputation(), 1);
        vm.prank(user2);
        assertEq(reputation.getReputation(), 1);
        vm.prank(user3);
        assertEq(reputation.getReputation(), 1);

        //check users stake without changes
        assertEq(token.balanceOf(user1), 0);
        assertEq(token.balanceOf(user2), 0);
        assertEq(token.balanceOf(user3), 0);
    }

    function test_consensualWithTie_3records_3users_1jury() public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");
        address jury1 = makeAddr("jury1");

        //register users
        vm.startPrank(owner);
        oracle.register(user1, false);
        oracle.register(user2, false);
        oracle.register(user3, false);
        oracle.register(jury1, true);
        vm.stopPrank();

        //user 1 uploads record 1
        string memory attestationId = "1";
        vm.prank(user1);
        oracle.createAttestation(attestationId, "record 1", participationNft);

        //user 2 uploads record 2 on same attestation
        vm.prank(user2);
        uint256 record2 = oracle.attest(attestationId, 0, false, "record 2", participationNft);

        //user 3 uploads record 3 on same attestation
        vm.prank(user3);
        oracle.attest(attestationId, 0, false, "record 3", participationNft);

        //jury1 attest record 2
        vm.prank(jury1);
        oracle.attest(attestationId, record2, true, "", participationNft);

        //wrap time and resolve
        vm.warp(201);
        oracle.resolve(attestationId);

        //check attestation info
        (AttestationOracle.AttestationState resolved, uint256 finalResult) = oracle.getAttestationInfo(attestationId);
        //check attestation status 1: CONSENSUAL
        assertEq(uint256(resolved), 1);
        //check attestation final result
        assertEq(finalResult, record2);

        //check users reputation
        vm.prank(user1);
        assertEq(reputation.getReputation(), 0);
        vm.prank(user2);
        assertEq(reputation.getReputation(), 2);
        vm.prank(user3);
        assertEq(reputation.getReputation(), 0);
        vm.prank(jury1);
        assertEq(reputation.getReputation(), 2);

        //check users stake
        assertEq(token.balanceOf(user1), 0);
        assertEq(token.balanceOf(user2), 10e18);
        assertEq(token.balanceOf(user3), 0);
        assertEq(token.balanceOf(jury1), 10e18);
    }

    function test_conflictTie_4records_3users_1jury() public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");
        address jury1 = makeAddr("jury1");

        //register users
        vm.startPrank(owner);
        oracle.register(user1, false);
        oracle.register(user2, false);
        oracle.register(user3, false);
        oracle.register(jury1, true);
        vm.stopPrank();

        //user 1 uploads record 1
        string memory attestationId = "1";
        vm.prank(user1);
        oracle.createAttestation(attestationId, "record 1", participationNft);

        //user 2 uploads record 2 on same attestation
        vm.prank(user2);
        oracle.attest(attestationId, 0, false, "record 2", participationNft);

        //user 3 uploads record 3 on same attestation
        vm.prank(user3);
        oracle.attest(attestationId, 0, false, "record 3", participationNft);

        //jury1 uploads record 4 on same attestation
        vm.prank(jury1);
        oracle.attest(attestationId, 0, false, "record 4", participationNft);

        //wrap time and resolve
        vm.warp(201);
        oracle.resolve(attestationId);

        //check attestation info
        (AttestationOracle.AttestationState resolved, uint256 finalResult) = oracle.getAttestationInfo(attestationId);
        //check attestation status 2: VERIFYING
        assertEq(uint256(resolved), 2);
        //check attestation final result
        assertEq(finalResult, 0);

        //check users reputation
        vm.prank(user1);
        assertEq(reputation.getReputation(), 1);
        vm.prank(user2);
        assertEq(reputation.getReputation(), 1);
        vm.prank(user3);
        assertEq(reputation.getReputation(), 1);
        vm.prank(jury1);
        assertEq(reputation.getReputation(), 1);

        //check users stake
        assertEq(token.balanceOf(user1), 0);
        assertEq(token.balanceOf(user2), 0);
        assertEq(token.balanceOf(user3), 0);
        assertEq(token.balanceOf(jury1), 0);
    }

    function test_conflictTie_5records_3users_2juries() public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");
        address jury1 = makeAddr("jury1");
        address jury2 = makeAddr("jury2");

        //register users
        vm.startPrank(owner);
        oracle.register(user1, false);
        oracle.register(user2, false);
        oracle.register(user3, false);
        oracle.register(jury1, true);
        oracle.register(jury2, true);
        vm.stopPrank();

        //user 1 uploads record 1
        string memory attestationId = "1";
        vm.prank(user1);
        oracle.createAttestation(attestationId, "record 1", participationNft);

        //user 2 uploads record 2 on same attestation
        vm.prank(user2);
        oracle.attest(attestationId, 0, false, "record 2", participationNft);

        //user 3 uploads record 3 on same attestation
        vm.prank(user3);
        oracle.attest(attestationId, 0, false, "record 3", participationNft);

        //jury 1 uploads record 4 on same attestation
        vm.prank(jury1);
        oracle.attest(attestationId, 0, false, "record 4", participationNft);

        //jury 2 uploads record 5 on same attestation
        vm.prank(jury2);
        oracle.attest(attestationId, 0, false, "record 5", participationNft);

        //wrap time and resolve
        vm.warp(201);
        oracle.resolve(attestationId);

        //check attestation info
        (AttestationOracle.AttestationState resolved, uint256 finalResult) = oracle.getAttestationInfo(attestationId);
        //check attestation status 2: VERIFYING
        assertEq(uint256(resolved), 2);
        //check attestation final result
        assertEq(finalResult, 0);

        //check users reputation
        vm.prank(user1);
        assertEq(reputation.getReputation(), 1);
        vm.prank(user2);
        assertEq(reputation.getReputation(), 1);
        vm.prank(user3);
        assertEq(reputation.getReputation(), 1);
        vm.prank(jury1);
        assertEq(reputation.getReputation(), 1);
        vm.prank(jury2);
        assertEq(reputation.getReputation(), 1);

        //check users stake
        assertEq(token.balanceOf(user1), 0);
        assertEq(token.balanceOf(user2), 0);
        assertEq(token.balanceOf(user3), 0);
        assertEq(token.balanceOf(jury1), 0);
        assertEq(token.balanceOf(jury2), 0);
    }

    function test_conflictJuryTie_3records_3users_2juries() public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");
        address jury1 = makeAddr("jury1");
        address jury2 = makeAddr("jury2");

        //register users
        vm.startPrank(owner);
        oracle.register(user1, false);
        oracle.register(user2, false);
        oracle.register(user3, false);
        oracle.register(jury1, true);
        oracle.register(jury2, true);
        vm.stopPrank();

        //user 1 uploads record 1
        string memory attestationId = "1";
        vm.prank(user1);
        uint256 record1 = oracle.createAttestation(attestationId, "record 1", participationNft);

        //user 2 attest record 1
        vm.prank(user2);
        oracle.attest(attestationId, record1, true, "", participationNft);

        //user 3 attest record 1
        vm.prank(user3);
        oracle.attest(attestationId, record1, true, "", participationNft);

        //jury 1 uploads record 2 on same attestation
        vm.prank(jury1);
        oracle.attest(attestationId, 0, false, "record 2", participationNft);

        //jury 2 uploads record 3 on same attestation
        vm.prank(jury2);
        oracle.attest(attestationId, 0, false, "record 3", participationNft);

        //wrap time and resolve
        vm.warp(201);
        oracle.resolve(attestationId);

        //check attestation info
        (AttestationOracle.AttestationState resolved, uint256 finalResult) = oracle.getAttestationInfo(attestationId);
        //check attestation status 2: VERIFYING
        assertEq(uint256(resolved), 2);
        //check attestation final result
        assertEq(finalResult, 0);

        //check users reputation
        vm.prank(user1);
        assertEq(reputation.getReputation(), 1);
        vm.prank(user2);
        assertEq(reputation.getReputation(), 1);
        vm.prank(user3);
        assertEq(reputation.getReputation(), 1);
        vm.prank(jury1);
        assertEq(reputation.getReputation(), 1);
        vm.prank(jury2);
        assertEq(reputation.getReputation(), 1);

        //check users stake
        assertEq(token.balanceOf(user1), 0);
        assertEq(token.balanceOf(user2), 0);
        assertEq(token.balanceOf(user3), 0);
        assertEq(token.balanceOf(jury1), 0);
        assertEq(token.balanceOf(jury2), 0);
    }

    function test_consensual_3records_5users() public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");
        address user4 = makeAddr("user4");
        address user5 = makeAddr("user5");

        //register users
        vm.startPrank(owner);
        oracle.register(user1, false);
        oracle.register(user2, false);
        oracle.register(user3, false);
        oracle.register(user4, false);
        oracle.register(user5, false);
        vm.stopPrank();

        //user 1 uploads record 1
        string memory attestationId = "1";
        vm.prank(user1);
        oracle.createAttestation(attestationId, "record 1", participationNft);

        //user 2 uploads record 2 on same attestation
        vm.prank(user2);
        uint256 record2 = oracle.attest(attestationId, 0, false, "record 2", participationNft);

        //user 3 uploads record 3 on same attestation
        vm.prank(user3);
        oracle.attest(attestationId, 0, false, "record 3", participationNft);

        //users 4,5 attest record 2
        vm.prank(user4);
        oracle.attest(attestationId, record2, true, "", participationNft);
        vm.prank(user5);
        oracle.attest(attestationId, record2, true, "", participationNft);

        //wrap time and resolve
        vm.warp(201);
        oracle.resolve(attestationId);

        //check attestation info
        (AttestationOracle.AttestationState resolved, uint256 finalResult) = oracle.getAttestationInfo(attestationId);
        //check attestation status 1: CONSENSUAL
        assertEq(uint256(resolved), 1);
        //check attestation final result set
        assertEq(finalResult, record2);

        //check users 2,4,5 reputation up
        vm.prank(user2);
        assertEq(reputation.getReputation(), 2);
        vm.prank(user4);
        assertEq(reputation.getReputation(), 2);
        vm.prank(user5);
        assertEq(reputation.getReputation(), 2);

        //check users 1,3 reputation down
        vm.prank(user1);
        assertEq(reputation.getReputation(), 0);
        vm.prank(user3);
        assertEq(reputation.getReputation(), 0);

        //total stake: 25 WIRA, three users was rigth, 8.333... WIRA for every user
        uint256 userReward = uint(25e18) / uint(3);

        //check users 2,4,5 receive stake
        assertEq(token.balanceOf(user2), userReward);
        assertEq(token.balanceOf(user4), userReward);
        assertEq(token.balanceOf(user5), userReward);


        //check users 1,3 not receive stake
        assertEq(token.balanceOf(user1), 0);
        assertEq(token.balanceOf(user3), 0);
    }

    function test_consensual_2records_5juries() public {
        address jury1 = makeAddr("jury1");
        address jury2 = makeAddr("jury2");
        address jury3 = makeAddr("jury3");
        address jury4 = makeAddr("jury4");
        address jury5 = makeAddr("jury5");

        //register users
        vm.startPrank(owner);
        oracle.register(jury1, false);
        oracle.register(jury2, false);
        oracle.register(jury3, false);
        oracle.register(jury4, false);
        oracle.register(jury5, false);
        vm.stopPrank();

        //jury 1 uploads record 1
        string memory attestationId = "1";
        vm.prank(jury1);
        uint256 record1 = oracle.createAttestation(attestationId, "record 1", participationNft);

        //jury 2 uploads record 2 on same attestation
        vm.prank(jury2);
        uint256 record2 = oracle.attest(attestationId, 0, false, "record 2", participationNft);

        //jury 3 attest record 1
        vm.prank(jury3);
        oracle.attest(attestationId, record1, true, "", participationNft);

        //juries 4,5 attest record 2
        vm.prank(jury4);
        oracle.attest(attestationId, record2, true, "", participationNft);
        vm.prank(jury5);
        oracle.attest(attestationId, record2, true, "", participationNft);

        //wrap time and resolve
        vm.warp(201);
        oracle.resolve(attestationId);

        //check attestation info
        (AttestationOracle.AttestationState resolved, uint256 finalResult) = oracle.getAttestationInfo(attestationId);
        //check attestation status 1: CONSENSUAL
        assertEq(uint256(resolved), 1);
        //check attestation final result set
        assertEq(finalResult, record2);

        //check juries 2,4,5 reputation up
        vm.prank(jury2);
        assertEq(reputation.getReputation(), 2);
        vm.prank(jury4);
        assertEq(reputation.getReputation(), 2);
        vm.prank(jury5);
        assertEq(reputation.getReputation(), 2);

        //check juries 1,3 reputation down
        vm.prank(jury1);
        assertEq(reputation.getReputation(), 0);
        vm.prank(jury3);
        assertEq(reputation.getReputation(), 0);

        //total stake: 25 WIRA, three juries was rigth, 8.333... WIRA for every jury
        uint256 userReward = uint(25e18) / uint(3);

        //check juries 2,4,5 receive stake
        assertEq(token.balanceOf(jury2), userReward);
        assertEq(token.balanceOf(jury4), userReward);
        assertEq(token.balanceOf(jury5), userReward);

        //check juries 1,3 not receive stake
        assertEq(token.balanceOf(jury1), 0);
        assertEq(token.balanceOf(jury3), 0);
    }

    function test_consensual_2records_3users_3juries() public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");

        address jury1 = makeAddr("jury1");
        address jury2 = makeAddr("jury2");
        address jury3 = makeAddr("jury3");

        //register users
        vm.startPrank(owner);
        oracle.register(user1, false);
        oracle.register(user2, false);
        oracle.register(user3, false);
        oracle.register(jury1, true);
        oracle.register(jury2, true);
        oracle.register(jury3, true);
        vm.stopPrank();

        //user 1 uploads record 1
        string memory attestationId = "1";
        vm.prank(user1);
        uint256 record1 = oracle.createAttestation(attestationId, "record 1", participationNft);

        //user 2 uploads record 2
        vm.prank(user2);
        uint256 record2 = oracle.attest(attestationId, 0, false, "record 2", participationNft);

        //user 3 attest record 1
        vm.prank(user3);
        oracle.attest(attestationId, record1, true, "", participationNft);

        //juries 1,2 attest record 1
        vm.prank(jury1);
        oracle.attest(attestationId, record1, true, "", participationNft);
        vm.prank(jury2);
        oracle.attest(attestationId, record1, true, "", participationNft);

        //juriy 3 attest record 2
        vm.prank(jury3);
        oracle.attest(attestationId, record2, true, "", participationNft);

        //wrap time and resolve
        vm.warp(201);
        oracle.resolve(attestationId);

        //check attestation info
        (AttestationOracle.AttestationState resolved, uint256 finalResult) = oracle.getAttestationInfo(attestationId);
        //check attestation status 1: CONSENSUAL
        assertEq(uint256(resolved), 1);
        //check attestation final result set
        assertEq(finalResult, record1);

        //check users 1,3 reputation up
        vm.prank(user1);
        assertEq(reputation.getReputation(), 2);
        vm.prank(user3);
        assertEq(reputation.getReputation(), 2);

        //check juries 1,2 reputation up
        vm.prank(jury1);
        assertEq(reputation.getReputation(), 2);
        vm.prank(jury2);
        assertEq(reputation.getReputation(), 2);

        //check user 2 and jury 3 reputation down
        vm.prank(user2);
        assertEq(reputation.getReputation(), 0);
        vm.prank(jury3);
        assertEq(reputation.getReputation(), 0);

        //total stake: 30 WIRA, four users was right, 7.5 WIRA for every user
        uint256 userReward = uint(30e18) / uint(4);

        //check users 1,3 and juries 1,2 receive stake
        assertEq(token.balanceOf(user1), userReward);
        assertEq(token.balanceOf(user3), userReward);
        assertEq(token.balanceOf(jury1), userReward);
        assertEq(token.balanceOf(jury2), userReward);

        //check user 2 and jury 3 not receive stake
        assertEq(token.balanceOf(user2), 0);
        assertEq(token.balanceOf(jury3), 0);
    }

    function test_conflict_3records_5users_4juries() public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");
        address user4 = makeAddr("user4");
        address user5 = makeAddr("user5");

        address jury1 = makeAddr("jury1");
        address jury2 = makeAddr("jury2");
        address jury3 = makeAddr("jury3");
        address jury4 = makeAddr("jury4");

        //register users
        vm.startPrank(owner);
        oracle.register(user1, false);
        oracle.register(user2, false);
        oracle.register(user3, false);
        oracle.register(user4, false);
        oracle.register(user5, false);
        oracle.register(jury1, true);
        oracle.register(jury2, true);
        oracle.register(jury3, true);
        oracle.register(jury4, true);
        vm.stopPrank();

        //jury 1 uploads record 1
        string memory attestationId = "1";
        vm.prank(jury1);
        uint256 record1 = oracle.createAttestation(attestationId, "record 1", participationNft);

        //user 1 uploads record 2
        vm.prank(user1);
        oracle.attest(attestationId, 0, false, "record 2", participationNft);

        //user 2 uploads record 3
        vm.prank(user2);
        uint256 record3 = oracle.attest(attestationId, 0, false, "record 3", participationNft);

        //user 3 attest record 1
        vm.prank(user3);
        oracle.attest(attestationId, record1, true, "", participationNft);

        //juries 2,3 attest record 1
        vm.prank(jury2);
        oracle.attest(attestationId, record1, true, "", participationNft);
        vm.prank(jury3);
        oracle.attest(attestationId, record1, true, "", participationNft);

        //users 4,5 attest record 3
        vm.prank(user4);
        oracle.attest(attestationId, record3, true, "", participationNft);
        vm.prank(user5);
        oracle.attest(attestationId, record3, true, "", participationNft);

        //wrap time and resolve
        vm.warp(201);
        oracle.resolve(attestationId);

        //check attestation info
        (AttestationOracle.AttestationState resolved, uint256 finalResult) = oracle.getAttestationInfo(attestationId);
        //check attestation status 2: VERIFYING
        assertEq(uint256(resolved), 2);
        //check attestation final result not set
        assertEq(finalResult, 0);

        //check users and juries reputation not change
        vm.prank(user1);
        assertEq(reputation.getReputation(), 1);
        vm.prank(user2);
        assertEq(reputation.getReputation(), 1);
        vm.prank(user3);
        assertEq(reputation.getReputation(), 1);
        vm.prank(user4);
        assertEq(reputation.getReputation(), 1);
        vm.prank(user5);
        assertEq(reputation.getReputation(), 1);

        vm.prank(jury1);
        assertEq(reputation.getReputation(), 1);
        vm.prank(jury2);
        assertEq(reputation.getReputation(), 1);
        vm.prank(jury3);
        assertEq(reputation.getReputation(), 1);
        vm.prank(jury4);
        assertEq(reputation.getReputation(), 1);

        //check users and juries not receive stake
        assertEq(token.balanceOf(user1), 0);
        assertEq(token.balanceOf(user2), 0);
        assertEq(token.balanceOf(user3), 0);
        assertEq(token.balanceOf(user4), 0);
        assertEq(token.balanceOf(user5), 0);

        assertEq(token.balanceOf(jury1), 0);
        assertEq(token.balanceOf(jury2), 0);
        assertEq(token.balanceOf(jury3), 0);
        assertEq(token.balanceOf(jury4), 0);
    }

    function test_reputationWeigth_notConsensual_2records_3users() public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");

        //register users
        vm.startPrank(owner);
        oracle.register(user1, false);
        oracle.register(user2, false);
        oracle.register(user3, false);
        vm.stopPrank();

        //up user 3 reputation to 3
        vm.startPrank(address(oracle));
        reputation.updateReputation(user3, true);
        reputation.updateReputation(user3, true);
        vm.stopPrank();

        //user 1 uploads record 1
        string memory attestationId = "1";
        vm.prank(user1);
        uint256 record1 = oracle.createAttestation(attestationId, "record 1", participationNft);

        //user 2 attest record 1
        vm.prank(user2);
        oracle.attest(attestationId, record1, true, "", participationNft);

        //user 3 uploads record 2
        vm.prank(user3);
        uint256 record2 = oracle.attest(attestationId, 0, false, "record 2", participationNft);

        //wrap time and resolve
        vm.warp(201);
        oracle.resolve(attestationId);

        //check attestation info
        (AttestationOracle.AttestationState resolved, uint256 finalResult) = oracle.getAttestationInfo(attestationId);
        //check attestation status 4: PENDING
        assertEq(uint256(resolved), 4);
        //check attestation final result set
        assertEq(finalResult, record2);

        //check users reputation
        vm.prank(user1);
        assertEq(reputation.getReputation(), 0);
        vm.prank(user2);
        assertEq(reputation.getReputation(), 0);
        vm.prank(user3);
        assertEq(reputation.getReputation(), 4);

        //check users stake
        assertEq(token.balanceOf(user1), 0);
        assertEq(token.balanceOf(user2), 0);
        assertEq(token.balanceOf(user3), 15e18);
    }

    function test_reputationWeigth_consensual_2records_5users() public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");
        address user4 = makeAddr("user4");
        address user5 = makeAddr("user5");

        //register users
        vm.startPrank(owner);
        oracle.register(user1, false);
        oracle.register(user2, false);
        oracle.register(user3, false);
        oracle.register(user4, false);
        oracle.register(user5, false);
        vm.stopPrank();

        //up user 5 reputation to 3
        vm.startPrank(address(oracle));
        reputation.updateReputation(user5, true);
        reputation.updateReputation(user5, true);
        vm.stopPrank();

        //user 1 uploads record 1
        string memory attestationId = "1";
        vm.prank(user1);
        uint256 record1 = oracle.createAttestation(attestationId, "record 1", participationNft);

        //user 2 attest record 1
        vm.prank(user2);
        oracle.attest(attestationId, record1, true, "", participationNft);

        //user 3 uploads record 2
        vm.prank(user3);
        uint256 record2 = oracle.attest(attestationId, 0, false, "record 2", participationNft);

        //users 4,5 attest record 2
        vm.prank(user4);
        oracle.attest(attestationId, record2, true, "", participationNft);
        vm.prank(user5);
        oracle.attest(attestationId, record2, true, "", participationNft);

        //wrap time and resolve
        vm.warp(201);
        oracle.resolve(attestationId);

        //check attestation info
        (AttestationOracle.AttestationState resolved, uint256 finalResult) = oracle.getAttestationInfo(attestationId);
        //check attestation status 1: CONSENSUAL
        assertEq(uint256(resolved), 1);
        //check attestation final result set
        assertEq(finalResult, record2);

        //check users 3,4,5 reputation up
        vm.prank(user3);
        assertEq(reputation.getReputation(), 2);
        vm.prank(user4);
        assertEq(reputation.getReputation(), 2);
        vm.prank(user5);
        assertEq(reputation.getReputation(), 4);

        //check users 1,2 reputation down
        vm.prank(user1);
        assertEq(reputation.getReputation(), 0);
        vm.prank(user2);
        assertEq(reputation.getReputation(), 0);

        //total stake: 25 WIRA, three users was righ, 8.33... WIRA for every user
        uint256 userReward = uint(25e18) / uint(3);

        //check users 3,4,5 receive stake
        assertEq(token.balanceOf(user3), userReward);
        assertEq(token.balanceOf(user4), userReward);
        assertEq(token.balanceOf(user5), userReward);

        //check users 1,2 not receive stake
        assertEq(token.balanceOf(user1), 0);
        assertEq(token.balanceOf(user2), 0);
    }

    function test_reputationWeigth_consensual_2records_3users_3juries() public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");

        address jury1 = makeAddr("jury1");
        address jury2 = makeAddr("jury2");
        address jury3 = makeAddr("jury3");

        //register users
        vm.startPrank(owner);
        oracle.register(user1, false);
        oracle.register(user2, false);
        oracle.register(user3, false);

        oracle.register(jury1, true);
        oracle.register(jury2, true);
        oracle.register(jury3, true);
        vm.stopPrank();

        //up user 3 and jury 3 reputation to 3
        vm.startPrank(address(oracle));
        reputation.updateReputation(user3, true);
        reputation.updateReputation(user3, true);
        reputation.updateReputation(jury3, true);
        reputation.updateReputation(jury3, true);
        vm.stopPrank();

        //user 1 uploads record 1
        string memory attestationId = "1";
        vm.prank(user1);
        uint256 record1 = oracle.createAttestation(attestationId, "record 1", participationNft);

        //user 2 attest record 1
        vm.prank(user2);
        oracle.attest(attestationId, record1, true, "", participationNft);

        //juries 1,2 attest record 1
        vm.prank(jury1);
        oracle.attest(attestationId, record1, true, "", participationNft);
        vm.prank(jury2);
        oracle.attest(attestationId, record1, true, "", participationNft);

        //user 3 uploads record 2
        vm.prank(user3);
        uint256 record2 = oracle.attest(attestationId, 0, false, "record 2", participationNft);

        //jury 3 attest record 2
        vm.prank(jury3);
        oracle.attest(attestationId, record2, true, "", participationNft);

        //wrap time and resolve
        vm.warp(201);
        oracle.resolve(attestationId);

        //check attestation info
        (AttestationOracle.AttestationState resolved, uint256 finalResult) = oracle.getAttestationInfo(attestationId);
        //check attestation status 1: CONSENSUAL
        assertEq(uint256(resolved), 1);
        //check attestation final result set
        assertEq(finalResult, record2);

        //check users 3 and jury 3 reputation up
        vm.prank(user3);
        assertEq(reputation.getReputation(), 4);
        vm.prank(user3);
        assertEq(reputation.getReputation(), 4);

        //check users 1,2 and juries 1,2 reputation down
        vm.prank(user1);
        assertEq(reputation.getReputation(), 0);
        vm.prank(user2);
        assertEq(reputation.getReputation(), 0);
        vm.prank(jury1);
        assertEq(reputation.getReputation(), 0);
        vm.prank(jury2);
        assertEq(reputation.getReputation(), 0);

        //total stake: 30 WIRA, two users was righ, 15 WIRA for every user
        uint256 userReward = 15e18;

        //check user 3 and jury 3 receive stake
        assertEq(token.balanceOf(user3), userReward);
        assertEq(token.balanceOf(jury3), userReward);

        //check users 1,2 and juries 1,2 not receive stake
        assertEq(token.balanceOf(user1), 0);
        assertEq(token.balanceOf(user2), 0);
        assertEq(token.balanceOf(jury1), 0);
        assertEq(token.balanceOf(jury2), 0);
    }

    //unanimous attestation
    function test_unanimousAttestation() public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");

        //register users
        vm.startPrank(owner);
        oracle.register(user1, false);
        oracle.register(user2, false);
        oracle.register(user3, false);
        vm.stopPrank();

        string memory attestationId = "1";
        vm.startPrank(user1);
        //user inits a votation updating their first image
        uint256 recordId = oracle.createAttestation(attestationId, "new record", participationNft);

        //check attestation created and user has record nft
        (AttestationOracle.AttestationState resolved, uint256 finalResult) = oracle.getAttestationInfo(attestationId);
        assertEq(uint256(resolved), 0);
        assertEq(oracle.getWeighedAttestations(attestationId, recordId), 1);
        assertEq(recordNft.ownerOf(recordId), user1);
        vm.stopPrank();

        //user 2 attest yes
        vm.prank(user2);
        oracle.attest(attestationId, recordId, true, "", participationNft);

        //check attest added +1
        assertEq(oracle.getWeighedAttestations(attestationId, recordId), 2);

        //user 3 attest yes
        vm.prank(user3);
        oracle.attest(attestationId, recordId, true, "", participationNft);

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
        vm.prank(user1);
        assertEq(reputation.getReputation(), 2);
        assertEq(token.balanceOf(user1), 5e18);
        vm.prank(user2);
        assertEq(reputation.getReputation(), 2);
        assertEq(token.balanceOf(user2), 5e18);
        vm.prank(user3);
        assertEq(reputation.getReputation(), 2);
        assertEq(token.balanceOf(user3), 5e18);
    }

    //users attestation matches juries one, only one record
    function test_usersMatchJuries_oneRecord() public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");
        address jury1 = makeAddr("jury1");

        //register users
        vm.startPrank(owner);
        oracle.register(user1, false);
        oracle.register(user2, false);
        oracle.register(user3, false);
        oracle.register(jury1, true);
        vm.stopPrank();

        string memory attestationId = "1";
        vm.startPrank(user1);
        //user inits a votation updating their first image
        uint256 recordId = oracle.createAttestation(attestationId, "new record", participationNft);

        //check attestation created and user has record nft
        (AttestationOracle.AttestationState resolved, uint256 finalResult) = oracle.getAttestationInfo(attestationId);
        assertEq(uint256(resolved), 0);
        assertEq(oracle.getWeighedAttestations(attestationId, recordId), 1);
        assertEq(recordNft.ownerOf(recordId), user1);
        vm.stopPrank();

        //user 2 attest yes
        vm.prank(user2);
        oracle.attest(attestationId, recordId, true, "", participationNft);

        //check attest added +1
        assertEq(oracle.getWeighedAttestations(attestationId, recordId), 2);

        //user 3 attest no
        vm.prank(user3);
        oracle.attest(attestationId, recordId, false, "", participationNft);

        //check attest added -1
        assertEq(oracle.getWeighedAttestations(attestationId, recordId), 1);

        //jury attest yes
        vm.prank(jury1);
        oracle.attest(attestationId, recordId, true, "", participationNft);

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
        uint256 userReward = uint(20e18) / uint(3);
        //check users reputation
        vm.prank(user1);
        assertEq(reputation.getReputation(), 2);
        assertEq(token.balanceOf(user1), userReward);
        vm.prank(user2);
        assertEq(reputation.getReputation(), 2);
        assertEq(token.balanceOf(user2), userReward);
        vm.prank(user3);
        assertEq(reputation.getReputation(), 0);
        assertEq(token.balanceOf(user3), 0);
        vm.prank(jury1);
        assertEq(reputation.getReputation(), 2);
        assertEq(token.balanceOf(jury1), userReward);
    }

    //users attestation matches juries one, two records
    function test_usersMatchJuries_twoRecords() public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");
        address jury1 = makeAddr("jury1");

        //register users
        vm.startPrank(owner);
        oracle.register(user1, false);
        oracle.register(user2, false);
        oracle.register(user3, false);
        oracle.register(jury1, true);
        vm.stopPrank();

        string memory attestationId = "1";
        vm.startPrank(user1);
        //user inits a votation updating their first image
        uint256 recordId = oracle.createAttestation(attestationId, "new record", participationNft);

        //check attestation created and user has record nft
        (AttestationOracle.AttestationState resolved, uint256 finalResult) = oracle.getAttestationInfo(attestationId);
        assertEq(uint256(resolved), 0);
        assertEq(oracle.getWeighedAttestations(attestationId, recordId), 1);
        assertEq(recordNft.ownerOf(recordId), user1);
        vm.stopPrank();

        //user 2 attest yes
        vm.prank(user2);
        oracle.attest(attestationId, recordId, true, "", participationNft);

        //check attest added +1
        assertEq(oracle.getWeighedAttestations(attestationId, recordId), 2);

        //user 3 attest yes to new record
        vm.startPrank(user3);
        oracle.attest(attestationId, recordId, true, "record 2", participationNft);

        //get user 3 vote
        (uint256 record2Id,) = oracle.getOptionAttested(attestationId);
        vm.stopPrank();

        //check attestations
        assertEq(oracle.getWeighedAttestations(attestationId, recordId), 2);
        assertEq(oracle.getWeighedAttestations(attestationId, record2Id), 1);

        //jury attest yes to first record
        vm.prank(jury1);
        oracle.attest(attestationId, recordId, true, "", participationNft);

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
        uint256 userReward = uint(20e18) / uint(3);
        //check users reputation
        vm.prank(user1);
        assertEq(reputation.getReputation(), 2);
        assertEq(token.balanceOf(user1), userReward);
        vm.prank(user2);
        assertEq(reputation.getReputation(), 2);
        assertEq(token.balanceOf(user2), userReward);
        vm.prank(user3);
        assertEq(reputation.getReputation(), 0);
        assertEq(token.balanceOf(user3), 0);
        vm.prank(jury1);
        assertEq(reputation.getReputation(), 2);
        assertEq(token.balanceOf(jury1), userReward);
    }

    //users attestation doesn't match juries one
    function test_usersNotMatchJuries() public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");
        address jury1 = makeAddr("jury1");
        address authority = makeAddr("authority");

        //register users
        vm.startPrank(owner);
        oracle.register(user1, false);
        oracle.register(user2, false);
        oracle.register(user3, false);
        oracle.register(jury1, true);
        oracle.grantRole(oracle.AUTHORITY_ROLE(), authority);
        vm.stopPrank();

        string memory attestationId = "1";
        vm.startPrank(user1);
        //user inits a votation updating their first image
        uint256 recordId = oracle.createAttestation(attestationId, "new record", participationNft);

        //check attestation created and user has record nft
        (AttestationOracle.AttestationState resolved, uint256 finalResult) = oracle.getAttestationInfo(attestationId);
        assertEq(uint256(resolved), 0);
        assertEq(oracle.getWeighedAttestations(attestationId, recordId), 1);
        assertEq(recordNft.ownerOf(recordId), user1);
        vm.stopPrank();

        //user 2 attest yes
        vm.prank(user2);
        oracle.attest(attestationId, recordId, true, "", participationNft);

        //check attest added +1
        assertEq(oracle.getWeighedAttestations(attestationId, recordId), 2);

        //user 3 attest yes to new record
        vm.startPrank(user3);
        oracle.attest(attestationId, recordId, true, "record 2", participationNft);

        //get user 3 vote
        (uint256 record2Id,) = oracle.getOptionAttested(attestationId);
        vm.stopPrank();

        //check attestations
        assertEq(oracle.getWeighedAttestations(attestationId, recordId), 2);
        assertEq(oracle.getWeighedAttestations(attestationId, record2Id), 1);

        //jury attest yes to sencond record
        vm.prank(jury1);
        oracle.attest(attestationId, record2Id, true, "", participationNft);

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
        vm.prank(user1);
        assertEq(reputation.getReputation(), 1);
        assertEq(token.balanceOf(user1), 0);
        vm.prank(user2);
        assertEq(reputation.getReputation(), 1);
        assertEq(token.balanceOf(user2), 0);
        vm.prank(user3);
        assertEq(reputation.getReputation(), 1);
        assertEq(token.balanceOf(user3), 0);
        vm.prank(jury1);
        assertEq(reputation.getReputation(), 1);
        assertEq(token.balanceOf(jury1), 0);

        //authority address makes final decision, selection second record
        vm.prank(authority);
        oracle.verifyAttestation(attestationId, record2Id);

        //check attestation state
        (resolved, finalResult) = oracle.getAttestationInfo(attestationId);
        assertEq(uint256(resolved), 3);
        assertEq(finalResult, record2Id);

        //four users voted, 20e18 total staking, two was right, 10e18 for every user
        //check reputation changes
        vm.prank(user1);
        assertEq(reputation.getReputation(), 0);
        assertEq(token.balanceOf(user1), 0);
        vm.prank(user2);
        assertEq(reputation.getReputation(), 0);
        assertEq(token.balanceOf(user2), 0);
        vm.prank(user3);
        assertEq(reputation.getReputation(), 2);
        assertEq(token.balanceOf(user3), 10e18);
        vm.prank(jury1);
        assertEq(reputation.getReputation(), 2);
        assertEq(token.balanceOf(jury1), 10e18);
    }
}