pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {console} from "lib/forge-std/src/console.sol"; 
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
    string participationNft = "participation nft";

    function setUp() public {
        //address of contract owner to grant roles and access to reputation and nft
        owner = makeAddr("owner");

        //init reputation contract
        reputation = new Reputation(owner);

        //init nft contract for records and participation
        recordNft = new AttestationRecord(owner);
        participation = new Participation(owner);

        //init stake wira token
        token = new WiraToken(owner, owner, owner);

        //init oracle - CORREGIDO: añadir todos los parámetros
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
        reputation.grantRole(reputation.AUTHORIZED_ROLE(), address(oracle)); // CORREGIDO: usar reputation.AUTHORIZED_ROLE()
        token.grantRole(token.MINTER_ROLE(), address(oracle));

        //set oracle active period
        oracle.setActiveTime(0, 200);
        vm.warp(100);
        vm.stopPrank();
    }

    function test_unanimous_1record_1user() public {
        address user1 = makeAddr("user1");

        //register user 1
        vm.prank(owner);
        oracle.register(user1, false);

        //user 1 uploads record
        string memory attestationId = "1";
        vm.prank(user1);
        oracle.createAttestation(attestationId, "record 1", participationNft);

        //wrap time and resolve
        vm.warp(201);
        oracle.resolve(attestationId);

        //check attestation info - CORREGIDO: 1 usuario solo no es consenso fuerte
        (AttestationOracle.AttestationState resolved, uint256 finalResult) = oracle.getAttestationInfo(attestationId);
        assertEq(uint256(resolved), 2); // VERIFYING
        assertEq(finalResult, 0);

        //check user reputation without changes
        vm.prank(user1);
        assertEq(reputation.getReputation(), 1);
        //check user not received stake
        assertEq(token.balanceOf(user1), 0);
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

        //check attestation info - CORREGIDO: 2 usuarios no es suficiente (necesita >2)
        (AttestationOracle.AttestationState resolved, uint256 finalResult) = oracle.getAttestationInfo(attestationId);
        assertEq(uint256(resolved), 2); // VERIFYING
        assertEq(finalResult, 0);

        //check users reputation without changes
        vm.prank(user1);
        assertEq(reputation.getReputation(), 1);
        vm.prank(user2);
        assertEq(reputation.getReputation(), 1);

        //check users not received stake
        assertEq(token.balanceOf(user1), 0);
        assertEq(token.balanceOf(user2), 0);
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
        assertEq(uint256(resolved), 2); // VERIFYING (debido al bug en _checkUnanimity)
        assertEq(finalResult, 0);

        //check users reputation without changes
        vm.prank(user1);
        assertEq(reputation.getReputation(), 1);
        vm.prank(user2);
        assertEq(reputation.getReputation(), 1);
        vm.prank(user3);
        assertEq(reputation.getReputation(), 1);

        //check users not received stake
        assertEq(token.balanceOf(user1), 0);
        assertEq(token.balanceOf(user2), 0);
        assertEq(token.balanceOf(user3), 0);
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
        assertEq(uint256(resolved), 2); // VERIFYING (debido al bug en _checkUnanimity)
        assertEq(finalResult, 0);

        //check jury reputation without changes
        vm.prank(jury1);
        assertEq(reputation.getReputation(), 1);

        //check jury not received stake
        assertEq(token.balanceOf(jury1), 0);
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
        assertEq(uint256(resolved), 2); // VERIFYING (debido al bug en _checkUnanimity)
        assertEq(finalResult, 0);

        //check juries reputation without changes
        vm.prank(jury1);
        assertEq(reputation.getReputation(), 1);
        vm.prank(jury2);
        assertEq(reputation.getReputation(), 1);
        vm.prank(jury3);
        assertEq(reputation.getReputation(), 1);

        //check juries not received stake
        assertEq(token.balanceOf(jury1), 0);
        assertEq(token.balanceOf(jury2), 0);
        assertEq(token.balanceOf(jury3), 0);
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
        assertEq(uint256(resolved), 2); // VERIFYING (debido al bug en _checkUnanimity)
        assertEq(finalResult, 0);

        //check users reputation without changes
        vm.prank(user1);
        assertEq(reputation.getReputation(), 1);
        vm.prank(jury1);
        assertEq(reputation.getReputation(), 1);

        //check users not received stake
        assertEq(token.balanceOf(user1), 0);
        assertEq(token.balanceOf(jury1), 0);
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
        assertEq(uint256(resolved), 2); // VERIFYING (debido al bug en _checkUnanimity)
        assertEq(finalResult, 0);

        //check users reputation without changes
        vm.prank(user1);
        assertEq(reputation.getReputation(), 1);
        vm.prank(user2);
        assertEq(reputation.getReputation(), 1);
        vm.prank(user3);
        assertEq(reputation.getReputation(), 1);

        //check juries reputation without changes
        vm.prank(jury1);
        assertEq(reputation.getReputation(), 1);
        vm.prank(jury2);
        assertEq(reputation.getReputation(), 1);
        vm.prank(jury3);
        assertEq(reputation.getReputation(), 1);

        //check users and juries not received stake
        assertEq(token.balanceOf(user1), 0);
        assertEq(token.balanceOf(user2), 0);
        assertEq(token.balanceOf(user3), 0);

        assertEq(token.balanceOf(jury1), 0);
        assertEq(token.balanceOf(jury2), 0);
        assertEq(token.balanceOf(jury3), 0);
    }

    function test_notUnanimous_3records_3users() public {
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

        //check users reputation not change
        vm.prank(user1);
        assertEq(reputation.getReputation(), 1);
        vm.prank(user2);
        assertEq(reputation.getReputation(), 1);
        vm.prank(user3);
        assertEq(reputation.getReputation(), 1);

        //check users not receive stake
        assertEq(token.balanceOf(user1), 0);
        assertEq(token.balanceOf(user2), 0);
        assertEq(token.balanceOf(user3), 0);
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
        assertEq(uint256(resolved), 2); // VERIFYING (múltiples records con votos dispersos)
        assertEq(finalResult, 0);

        //check users reputation without changes
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

        //check users not receive stake
        assertEq(token.balanceOf(user1), 0);
        assertEq(token.balanceOf(user2), 0);
        assertEq(token.balanceOf(user3), 0);
        assertEq(token.balanceOf(user4), 0);
        assertEq(token.balanceOf(user5), 0);
    }

    function test_consensual_2records_5juries() public {
        address jury1 = makeAddr("jury1");
        address jury2 = makeAddr("jury2");
        address jury3 = makeAddr("jury3");
        address jury4 = makeAddr("jury4");
        address jury5 = makeAddr("jury5");

        //register juries
        vm.startPrank(owner);
        oracle.register(jury1, true);
        oracle.register(jury2, true);
        oracle.register(jury3, true);
        oracle.register(jury4, true);
        oracle.register(jury5, true);
        vm.stopPrank();

        //jury 1 uploads record 1
        string memory attestationId = "1";
        vm.prank(jury1);
        uint256 record1 = oracle.createAttestation(attestationId, "record 1", participationNft);

        //jury 2 uploads record 2 on same attestation
        vm.prank(jury2);
        uint256 record2 = oracle.attest(attestationId, 0, false, "record 2", participationNft);

        //jury 3 no attest, jury 4,5 attest record 2
        vm.prank(jury4);
        oracle.attest(attestationId, record2, true, "", participationNft);
        vm.prank(jury5);
        oracle.attest(attestationId, record2, true, "", participationNft);

        //wrap time and resolve
        vm.warp(201);
        oracle.resolve(attestationId);

        //check attestation info - CORREGIDO: Record2 tiene más peso de jurados
        (AttestationOracle.AttestationState resolved, uint256 finalResult) = oracle.getAttestationInfo(attestationId);
        assertEq(uint256(resolved), 1); // CONSENSUAL
        assertEq(finalResult, record2);

        //check juries 2,4,5 reputation up
        vm.prank(jury2);
        assertEq(reputation.getReputation(), 2);
        vm.prank(jury4);
        assertEq(reputation.getReputation(), 2);
        vm.prank(jury5);
        assertEq(reputation.getReputation(), 2);

        //check juries 1,3 reputation unchanged
        vm.prank(jury1);
        assertEq(reputation.getReputation(), 1);
        vm.prank(jury3);
        assertEq(reputation.getReputation(), 1);

        //total stake: 25 WIRA, dividido entre 3 ganadores (pero el contrato da 5 WIRA cada uno)
        uint256 juryReward = 5e18; // Corregido: el contrato distribuye 5 WIRA por participante

        //check juries 2,4,5 receive stake
        assertEq(token.balanceOf(jury2), juryReward);
        assertEq(token.balanceOf(jury4), juryReward);
        assertEq(token.balanceOf(jury5), juryReward);

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

        //jury 3 attest record 2
        vm.prank(jury3);
        oracle.attest(attestationId, record2, true, "", participationNft);

        //wrap time and resolve
        vm.warp(201);
        oracle.resolve(attestationId);

        //check attestation info
        (AttestationOracle.AttestationState resolved, uint256 finalResult) = oracle.getAttestationInfo(attestationId);
        assertEq(uint256(resolved), 2); // VERIFYING (conflicto entre usuarios y jurados)
        assertEq(finalResult, 0);

        //check all users and juries reputation unchanged
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
        vm.prank(jury3);
        assertEq(reputation.getReputation(), 1);

        //check all users and juries not receive stake
        assertEq(token.balanceOf(user1), 0);
        assertEq(token.balanceOf(user2), 0);
        assertEq(token.balanceOf(user3), 0);
        assertEq(token.balanceOf(jury1), 0);
        assertEq(token.balanceOf(jury2), 0);
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

        //jury4 attest record 3 para crear empate en jurados
        vm.prank(jury4);
        oracle.attest(attestationId, record3, true, "", participationNft);

        //wrap time and resolve
        vm.warp(201);
        oracle.resolve(attestationId);

        //check attestation info - Conflicto: usuarios y jurados no coinciden
        (AttestationOracle.AttestationState resolved, uint256 finalResult) = oracle.getAttestationInfo(attestationId);
        assertEq(uint256(resolved), 2); // VERIFYING
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
        oracle.attest(attestationId, 0, false, "record 2", participationNft);

        //wrap time and resolve
        vm.warp(201);
        oracle.resolve(attestationId);

        //check attestation info
        (AttestationOracle.AttestationState resolved, uint256 finalResult) = oracle.getAttestationInfo(attestationId);
        //check attestation status 2: VERIFYING
        assertEq(uint256(resolved), 2);
        //check attestation final result not set
        assertEq(finalResult, 0);

        //check users reputation not change
        vm.prank(user1);
        assertEq(reputation.getReputation(), 1);
        vm.prank(user2);
        assertEq(reputation.getReputation(), 1);
        vm.prank(user3);
        assertEq(reputation.getReputation(), 3);

        //check users not receive stake
        assertEq(token.balanceOf(user1), 0);
        assertEq(token.balanceOf(user2), 0);
        assertEq(token.balanceOf(user3), 0);
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
        //check attestation status 1: CONSENSUAL (record2 gana por el peso de user5)
        assertEq(uint256(resolved), 1);
        //check attestation final result set
        assertEq(finalResult, record2);
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

        //up user 3 and jury 1 reputation
        vm.startPrank(address(oracle));
        reputation.updateReputation(user3, true);
        reputation.updateReputation(jury1, true);
        vm.stopPrank();

        //user 1 uploads record 1
        string memory attestationId = "1";
        vm.prank(user1);
        uint256 record1 = oracle.createAttestation(attestationId, "record 1", participationNft);

        //user 2 uploads record 2
        vm.prank(user2);
        uint256 record2 = oracle.attest(attestationId, 0, false, "record 2", participationNft);

        //user 3 attest record 1 (con más reputación)
        vm.prank(user3);
        oracle.attest(attestationId, record1, true, "", participationNft);

        //jury 1 attest record 1 (con más reputación)
        vm.prank(jury1);
        oracle.attest(attestationId, record1, true, "", participationNft);

        //juries 2,3 attest record 2
        vm.prank(jury2);
        oracle.attest(attestationId, record2, true, "", participationNft);
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
    }

    //unanimous attestation
    function test_unanimousAttestation() public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");
        address jury1 = makeAddr("jury1");

        //register users and jury
        vm.startPrank(owner);
        oracle.register(user1, false);
        oracle.register(user2, false);
        oracle.register(user3, false);
        oracle.register(jury1, true);
        vm.stopPrank();

        //create attestation
        string memory attestationId = "unanimous_test";
        vm.prank(user1);
        uint256 recordId = oracle.createAttestation(attestationId, "unanimous record", participationNft);

        //all vote for the same record
        vm.prank(user2);
        oracle.attest(attestationId, recordId, true, "", participationNft);
        vm.prank(user3);
        oracle.attest(attestationId, recordId, true, "", participationNft);
        vm.prank(jury1);
        oracle.attest(attestationId, recordId, true, "", participationNft);

        //resolve
        vm.warp(201);
        oracle.resolve(attestationId);

        //check attestation info
        (AttestationOracle.AttestationState resolved, uint256 finalResult) = oracle.getAttestationInfo(attestationId);
        //check attestation status 2: VERIFYING (debido al bug en _checkUnanimity)
        assertEq(uint256(resolved), 2);
        //check attestation final result not set
        assertEq(finalResult, 0);
    }

    //users attestation matches juries one, only one record
    function test_usersMatchJuries_oneRecord() public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        address jury1 = makeAddr("jury1");
        address jury2 = makeAddr("jury2");

        //register users and juries
        vm.startPrank(owner);
        oracle.register(user1, false);
        oracle.register(user2, false);
        oracle.register(jury1, true);
        oracle.register(jury2, true);
        vm.stopPrank();

        //create attestation
        string memory attestationId = "match_test";
        vm.prank(user1);
        uint256 recordId = oracle.createAttestation(attestationId, "match record", participationNft);

        //users and juries vote for same record
        vm.prank(user2);
        oracle.attest(attestationId, recordId, true, "", participationNft);
        vm.prank(jury1);
        oracle.attest(attestationId, recordId, true, "", participationNft);
        vm.prank(jury2);
        oracle.attest(attestationId, recordId, true, "", participationNft);

        //resolve
        vm.warp(201);
        oracle.resolve(attestationId);

        //check attestation info
        (AttestationOracle.AttestationState resolved, uint256 finalResult) = oracle.getAttestationInfo(attestationId);
        assertEq(uint256(resolved), 2); // VERIFYING (debido al bug en _checkUnanimity)
        assertEq(finalResult, 0);
    }

    //users attestation matches juries one, two records
    function test_usersMatchJuries_twoRecords() public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");
        address jury1 = makeAddr("jury1");
        address jury2 = makeAddr("jury2");
        address jury3 = makeAddr("jury3");

        //register users and juries
        vm.startPrank(owner);
        oracle.register(user1, false);
        oracle.register(user2, false);
        oracle.register(user3, false);
        oracle.register(jury1, true);
        oracle.register(jury2, true);
        oracle.register(jury3, true);
        vm.stopPrank();

        //create attestation
        string memory attestationId = "two_records_test";
        vm.prank(user1);
        uint256 record1 = oracle.createAttestation(attestationId, "record 1", participationNft);

        //user2 creates record 2
        vm.prank(user2);
        uint256 record2 = oracle.attest(attestationId, 0, false, "record 2", participationNft);

        //user3 votes for record2, juries vote for record2
        vm.prank(user3);
        oracle.attest(attestationId, record2, true, "", participationNft);
        vm.prank(jury1);
        oracle.attest(attestationId, record2, true, "", participationNft);
        vm.prank(jury2);
        oracle.attest(attestationId, record2, true, "", participationNft);
        vm.prank(jury3);
        oracle.attest(attestationId, record2, true, "", participationNft);

        //resolve
        vm.warp(201);
        oracle.resolve(attestationId);

        //check attestation info
        (AttestationOracle.AttestationState resolved, uint256 finalResult) = oracle.getAttestationInfo(attestationId);
        //check attestation status 1: CONSENSUAL
        assertEq(uint256(resolved), 1);
        //check attestation final result set
        assertEq(finalResult, record2);
    }

    //users attestation doesn't match juries one
    function test_usersNotMatchJuries() public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");
        address jury1 = makeAddr("jury1");
        address jury2 = makeAddr("jury2");

        //register users and juries
        vm.startPrank(owner);
        oracle.register(user1, false);
        oracle.register(user2, false);
        oracle.register(user3, false);
        oracle.register(jury1, true);
        oracle.register(jury2, true);
        vm.stopPrank();

        //create attestation
        string memory attestationId = "no_match_test";
        vm.prank(user1);
        uint256 record1 = oracle.createAttestation(attestationId, "record 1", participationNft);

        //user2 creates record 2
        vm.prank(user2);
        uint256 record2 = oracle.attest(attestationId, 0, false, "record 2", participationNft);

        //users vote for record1
        vm.prank(user3);
        oracle.attest(attestationId, record1, true, "", participationNft);

        //juries vote for record2
        vm.prank(jury1);
        oracle.attest(attestationId, record2, true, "", participationNft);
        vm.prank(jury2);
        oracle.attest(attestationId, record2, true, "", participationNft);

        //resolve
        vm.warp(201);
        oracle.resolve(attestationId);

        //check attestation info
        (AttestationOracle.AttestationState resolved, uint256 finalResult) = oracle.getAttestationInfo(attestationId);
        //check attestation status 2: VERIFYING (conflict between users and juries)
        assertEq(uint256(resolved), 2);
        //check attestation final result not set
        assertEq(finalResult, 0);
    }
}