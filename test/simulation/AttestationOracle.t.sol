// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {console} from "lib/forge-std/src/console.sol";

import {AttestationOracle} from "../../src/AttestationOracle.sol";
import {WiraToken} from "../../src/WiraToken.sol";
import {Reputation} from "../../src/Reputation.sol";
import {AttestationRecord} from "../../src/AttestationRecord.sol";
import {Participation} from "../../src/Participation.sol";

contract AttestationOracleTestUp is Test {
    AttestationOracle public oracle;
    Reputation public reputation;
    AttestationRecord public recordNft;
    Participation public participation;
    WiraToken public token;
    address public owner; // propietario
    address public user1;
    address public user2;
    address public user3;
    address public jury1;
    address public jury2;
    address public authority;

    // Events para testing
    event RegisterRequested(address user, string uri);
    event AttestationCreated(uint256 id, uint256 recordId);
    event Attested(uint256 recordId);
    event Resolved(uint256 id, AttestationOracle.AttestationState closeState);
    event InitVerification(uint256 id);

    function setUp() public {
        // Configurar addresses
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        jury1 = makeAddr("jury1");
        jury2 = makeAddr("jury2");
        authority = makeAddr("authority");

        // Deploy contracts
        reputation = new Reputation(owner);
        recordNft = new AttestationRecord(owner);
        participation = new Participation(owner); // Desplegar Participation
        token = new WiraToken(owner, owner, owner);



        oracle = new AttestationOracle(
            owner,
            address(recordNft),
            address(participation),
            address(reputation),
            address(token),
            5e18 // stake amount
        );

        // cfg permissions
        vm.startPrank(owner);

        console.log("owner: ", owner);
        recordNft.grantRole(recordNft.AUTHORIZED_ROLE(), address(oracle));
        participation.grantRole(participation.AUTHORIZED_ROLE(), address(oracle));
        reputation.grantRole(recordNft.AUTHORIZED_ROLE(), address(oracle));
        token.grantRole(token.MINTER_ROLE(), address(oracle));
        oracle.grantRole(oracle.AUTHORITY_ROLE(), authority);
        console.log("Oracle address: ", address(oracle));
        console.log("Reputation address: ", address(reputation));
        console.log("RecordNFT address: ", address(recordNft));
        console.log("-> WiraToken address: ", address(token));
        // Configurar periodo activo
        oracle.setActiveTime(0, 200);
        vm.warp(100);
        vm.stopPrank();
    }

    // *** requestRegister

    function test_requestRegister_success() public {
        vm.prank(user1);
        vm.expectEmit(true, false, false, true);
        emit RegisterRequested(user1, "ipfs://user1-kyc");
        //console.log("Requesting registration for user1");
        oracle.requestRegister("ipfs://user1-kyc");
    }

    function test_requestRegister_revertsWhenInactive() public {
        vm.warp(300); // Fuera del periodo activo
        vm.prank(user1);
        vm.expectRevert("Oracle inactive");
        oracle.requestRegister("ipfs://user1-kyc");
    }

    /*function test_requestRegister_doesNothingIfAlreadyRegistered() public {
        // Registrar usuario primero
        vm.prank(owner);
        oracle.register(user1, false);

        // No debería emitir evento si ya está registrado
        vm.prank(user1);
        vm.recordLogs();
        oracle.requestRegister("ipfs://user1-kyc");
        //vm.stopPrank();
        // Verificar que no se emitió evento
        //vm.Log[] memory logs = vm.getRecordedLogs();
        //assertEq(logs.length, 0);
    }*/

    // *** prueba para register

    function test_register_userSuccess() public {
        vm.prank(owner);
        oracle.register(user1, false);

        // Verificar que tiene rol USER
        assertTrue(oracle.hasRole(oracle.USER_ROLE(), user1));
        assertFalse(oracle.hasRole(oracle.JURY_ROLE(), user1));
        console.log("owner: ", owner);
        console.log("register user: ", user1);
        console.log("status:", oracle.hasRole(oracle.USER_ROLE(), user1));
    }

    function test_register_jurySuccess() public {
        vm.prank(owner);
        oracle.register(jury1, true);
        // stataus register
        console.log("User jury register;");
        // Verificar que tiene rol JURY
        assertTrue(oracle.hasRole(oracle.JURY_ROLE(), jury1));
        assertFalse(oracle.hasRole(oracle.USER_ROLE(), jury1));
        console.log("user: ", oracle.hasRole(oracle.JURY_ROLE(), jury1));
        console.log("status:", oracle.hasRole(oracle.USER_ROLE(), jury1));
    }

    function test_register_revertsWhenNotAdmin() public {
        vm.prank(user1);
        vm.expectRevert();
        oracle.register(user2, false);
    }



function test_RequestRegister_EmitsEvent() public {
        vm.prank(user1);
        vm.expectEmit(true, false, false, true);
        emit RegisterRequested(user1, "QmHash123"); // Hash IPFS realista
        oracle.requestRegister("QmHash123");
    }

    function test_RequestRegister_FailsWhenOracleInactive() public {
        // Hacer que el oráculo esté inactivo
        vm.warp(block.timestamp + 86401); // Más de 24 horas
        
        vm.prank(user1);
        vm.expectRevert("Oracle inactive");
        oracle.requestRegister("QmHash123");
    }

    function test_Register_CreatesUserRole() public {
        vm.prank(owner);
        oracle.register(user1, false);

        assertTrue(oracle.hasRole(oracle.USER_ROLE(), user1));
        assertFalse(oracle.hasRole(oracle.JURY_ROLE(), user1));
    }

    function test_Register_CreatesJuryRole() public {
        vm.prank(owner);
        oracle.register(jury1, true);

        assertTrue(oracle.hasRole(oracle.JURY_ROLE(), jury1));
        assertFalse(oracle.hasRole(oracle.USER_ROLE(), jury1));
    }

    function test_Register_OnlyAdminCanRegister() public {
        vm.prank(user1);
        vm.expectRevert();
        oracle.register(user2, false);
    }

    // ==================== TESTS PARA CREAR ATESTIGUACIONES ====================

    function test_CreateAttestation_UserSuccess() public {
        // Registrar usuario
        vm.prank(owner);
        oracle.register(user1, false);

        vm.prank(user1);
        vm.expectEmit(false, false, false, true);
        emit AttestationCreated(0, 1);

        uint256 recordId = oracle.createAttestation(
            "election_fraud_case_001", 
            "QmRecordHash123", 
            "QmParticipationHash456"
        );

        assertEq(recordId, 1);
        
        // Verificar estado inicial
        (AttestationOracle.AttestationState state, uint256 finalResult) = 
            oracle.getAttestationInfo("election_fraud_case_001");
        assertEq(uint256(state), 0); // OPEN
        assertEq(finalResult, 0);
        
        // Verificar que se depositó el stake
        assertEq(token.balanceOf(address(oracle)), 1000 * 10**18);
    }

    function test_CreateAttestation_JurySuccess() public {
        vm.prank(owner);
        oracle.register(jury1, true);

        vm.prank(jury1);
        uint256 recordId = oracle.createAttestation(
            "voting_irregularity_001", 
            "QmEvidenceHash789", 
            "QmJuryParticipation123"
        );

        assertEq(recordId, 1);
        
        // Verificar peso inicial del jurado
        assertEq(oracle.getJuryWeighedAttestations("voting_irregularity_001", recordId), 1);
    }

    function test_CreateAttestation_FailsWhenUnauthorized() public {
        vm.prank(user1); // Usuario no registrado
        vm.expectRevert("Unauthorized");
        oracle.createAttestation("case_001", "QmHash1", "QmHash2");
    }

    function test_CreateAttestation_FailsWhenAlreadyExists() public {
        vm.prank(owner);
        oracle.register(user1, false);

        vm.prank(user1);
        oracle.createAttestation("duplicate_case", "QmHash1", "QmHash2");

        // Intentar crear la misma atestiguación
        vm.prank(user1);
        vm.expectRevert("Already created");
        oracle.createAttestation("duplicate_case", "QmHash3", "QmHash4");
    }

    // ==================== TESTS PARA ATESTIGUAR ====================

    function test_Attest_VoteOnExistingRecord() public {
        // Setup: crear usuarios y atestiguación
        vm.startPrank(owner);
        oracle.register(user1, false);
        oracle.register(user2, false);
        vm.stopPrank();

        // User1 crea la atestiguación
        vm.prank(user1);
        uint256 recordId = oracle.createAttestation(
            "vote_buying_case", 
            "QmEvidenceVoteBuying", 
            "QmParticipation1"
        );

        // User2 vota a favor del mismo record
        vm.prank(user2);
        uint256 result = oracle.attest(
            "vote_buying_case", 
            recordId, 
            true, 
            "", 
            "QmParticipation2"
        );

        assertEq(result, recordId);
        
        // Verificar que el peso aumentó (ambos usuarios tienen reputación inicial = 1)
        assertEq(oracle.getWeighedAttestations("vote_buying_case", recordId), 2);
    }

    function test_Attest_VoteAgainstRecord() public {
        vm.startPrank(owner);
        oracle.register(user1, false);
        oracle.register(user2, false);
        vm.stopPrank();

        vm.prank(user1);
        uint256 recordId = oracle.createAttestation(
            "disputed_ballots", 
            "QmDisputedEvidence", 
            "QmParticipation1"
        );

        // User2 vota en contra
        vm.prank(user2);
        oracle.attest("disputed_ballots", recordId, false, "", "QmParticipation2");

        // El peso debería ser 0 (1 a favor - 1 en contra)
        assertEq(oracle.getWeighedAttestations("disputed_ballots", recordId), 0);
    }

    function test_Attest_CreateNewEvidence() public {
        vm.startPrank(owner);
        oracle.register(user1, false);
        oracle.register(user2, false);
        vm.stopPrank();

        // User1 crea atestiguación inicial
        vm.prank(user1);
        oracle.createAttestation("ballot_stuffing", "QmEvidence1", "QmParticipation1");

        // User2 aporta nueva evidencia
        vm.prank(user2);
        vm.expectEmit(false, false, false, false);
        emit Attested(2);

        uint256 newRecordId = oracle.attest(
            "ballot_stuffing", 
            0, // 0 indica que se creará nuevo record
            false, 
            "QmNewEvidence2", 
            "QmParticipation2"
        );

        assertEq(newRecordId, 2);
        assertEq(recordNft.totalSupply(), 2); // Ahora hay 2 registros NFT
    }

    function test_Attest_FailsWhenAlreadyAttested() public {
        vm.startPrank(owner);
        oracle.register(user1, false);
        oracle.register(user2, false);
        vm.stopPrank();

        vm.prank(user1);
        uint256 recordId = oracle.createAttestation("double_voting", "QmEvidence", "QmParticipation1");

        vm.prank(user2);
        oracle.attest("double_voting", recordId, true, "", "QmParticipation2");

        // Segundo intento debería fallar
        vm.prank(user2);
        vm.expectRevert("already attested");
        oracle.attest("double_voting", recordId, false, "", "QmParticipation3");
    }

    // ==================== TESTS PARA RESOLVER ATESTIGUACIONES ====================

    function test_Resolve_UnanimousConsensus() public {
        vm.startPrank(owner);
        oracle.register(user1, false);
        oracle.register(user2, false);
        oracle.register(user3, false);
        oracle.register(jury1, true);
        vm.stopPrank();

        // Crear atestiguación
        vm.prank(user1);
        uint256 recordId = oracle.createAttestation("clear_fraud", "QmClearEvidence", "QmParticipation1");

        // Todos votan a favor
        vm.prank(user2);
        oracle.attest("clear_fraud", recordId, true, "", "QmParticipation2");
        
        vm.prank(user3);
        oracle.attest("clear_fraud", recordId, true, "", "QmParticipation3");
        
        vm.prank(jury1);
        oracle.attest("clear_fraud", recordId, true, "", "QmParticipation4");

        // Avanzar tiempo para permitir resolución
        vm.warp(block.timestamp + 86401);

        vm.expectEmit(true, false, false, true);
        console.log("clear fraud");
        emit Resolved(1, AttestationOracle.AttestationState.CLOSED);

        oracle.resolve("clear_fraud");

        (AttestationOracle.AttestationState state, uint256 finalResult) = 
            oracle.getAttestationInfo("clear_fraud");
        assertEq(uint256(state), 3); // CLOSED
        assertEq(finalResult, recordId);
    }

    function test_Resolve_ConflictingEvidence() public {
        vm.startPrank(owner);
        oracle.register(user1, false);
        oracle.register(user2, false);
        oracle.register(jury1, true);
        oracle.register(jury2, true);
        vm.stopPrank();

        // User1 presenta evidencia de fraude
        vm.prank(user1);
        uint256 fraudRecord = oracle.createAttestation("contested_fraud", "QmFraudEvidence", "QmParticipation1");

        // User2 presenta contra-evidencia
        vm.prank(user2);
        uint256 counterRecord = oracle.attest("contested_fraud", 0, false, "QmCounterEvidence", "QmParticipation2");

        // Jurados votan en direcciones opuestas
        vm.prank(jury1);
        oracle.attest("contested_fraud", fraudRecord, true, "", "QmParticipation3");
        
        vm.prank(jury2);
        oracle.attest("contested_fraud", counterRecord, true, "", "QmParticipation4");

        vm.warp(block.timestamp + 86401);

        vm.expectEmit(true, false, false, true);
        emit InitVerification(1);

        oracle.resolve("contested_fraud");

        (AttestationOracle.AttestationState state,) = oracle.getAttestationInfo("contested_fraud");
        assertEq(uint256(state), 2); // VERIFYING - requiere intervención de autoridad
    }

    function test_Resolve_FailsWhenTooEarly() public {
        vm.prank(owner);
        oracle.register(user1, false);

        vm.prank(user1);
        oracle.createAttestation("premature_case", "QmEvidence", "QmParticipation");

        // Intentar resolver antes de tiempo
        vm.expectRevert("too soon");
        oracle.resolve("premature_case");
    }

    // ==================== TESTS PARA VERIFICACIÓN POR AUTORIDAD ====================

    function test_VerifyAttestation_AuthorityIntervention() public {
        vm.startPrank(owner);
        oracle.register(user1, false);
        oracle.register(user2, false);
        vm.stopPrank();

        // Crear caso conflictivo
        vm.prank(user1);
        uint256 record1 = oracle.createAttestation("complex_case", "QmEvidence1", "QmParticipation1");
        
        vm.prank(user2);
        oracle.attest("complex_case", 0, false, "QmEvidence2", "QmParticipation2");

        // Resolver -> ir a VERIFYING
        vm.warp(block.timestamp + 86401);
        oracle.resolve("complex_case");

        // Authority decide
        vm.prank(authority);
        oracle.verifyAttestation("complex_case", record1);

        (AttestationOracle.AttestationState state, uint256 finalResult) = 
            oracle.getAttestationInfo("complex_case");
        assertEq(uint256(state), 3); // CLOSED
        assertEq(finalResult, record1);
    }

    function test_VerifyAttestation_OnlyAuthorityCanVerify() public {
        vm.prank(user1);
        vm.expectRevert();
        oracle.verifyAttestation("any_case", 1);
    }

    // ==================== TESTS PARA FUNCIONES DE CONSULTA ====================

    function test_GetWeighedAttestations_ReflectsReputationWeights() public {
        vm.startPrank(owner);
        oracle.register(user1, false);
        oracle.register(user2, false);
        vm.stopPrank();

        vm.prank(user1);
        uint256 recordId = oracle.createAttestation("reputation_test", "QmEvidence", "QmParticipation1");

        // Verificar peso inicial
        assertEq(oracle.getWeighedAttestations("reputation_test", recordId), 1);

        vm.prank(user2);
        oracle.attest("reputation_test", recordId, true, "", "QmParticipation2");

        // Verificar peso combinado
        assertEq(oracle.getWeighedAttestations("reputation_test", recordId), 2);
    }

    function test_GetOptionAttested_ReturnsUserChoice() public {
        vm.prank(owner);
        oracle.register(user1, false);

        vm.prank(user1);
        uint256 recordId = oracle.createAttestation("user_choice_test", "QmEvidence", "QmParticipation");

        vm.prank(user1);
        (uint256 recordAttested, bool choice) = oracle.getOptionAttested("user_choice_test");

        assertEq(recordAttested, recordId);
        assertTrue(choice); // El creador siempre vota 'true' por defecto
    }

    function test_ViewAttestationResult_ShowsMostAttested() public {
        vm.startPrank(owner);
        oracle.register(user1, false);
        oracle.register(user2, false);
        oracle.register(jury1, true);
        vm.stopPrank();

        vm.prank(user1);
        uint256 record1 = oracle.createAttestation("popular_case", "QmEvidence1", "QmParticipation1");

        vm.prank(user2);
        oracle.attest("popular_case", record1, true, "", "QmParticipation2");

        vm.prank(jury1);
        oracle.attest("popular_case", record1, true, "", "QmParticipation3");

        vm.warp(block.timestamp + 86401);
        oracle.resolve("popular_case");

        (uint256 mostAttested, uint256 mostJuryAttested) = oracle.viewAttestationResult("popular_case");
        
        assertEq(mostAttested, record1);
        assertEq(mostJuryAttested, record1);
    }

    // ==================== TESTS DE INTEGRACIÓN ====================

    function test_FullWorkflow_ElectionFraudCase() public {
        // Simular un caso completo de fraude electoral
        vm.startPrank(owner);
        oracle.register(user1, false); // Denunciante
        oracle.register(user2, false); // Testigo
        oracle.register(user3, false); // Observador
        oracle.register(jury1, true);  // Jurado especialista
        oracle.register(jury2, true);  // Jurado ciudadano
        vm.stopPrank();

        // 1. Denuncia inicial
        vm.prank(user1);
        uint256 fraudRecord = oracle.createAttestation(
            "election_fraud_district_5", 
            "QmBallotBoxStuffingEvidence", 
            "QmDenuncianteParticipation"
        );

        // 2. Testigo confirma
        vm.prank(user2);
        oracle.attest("election_fraud_district_5", fraudRecord, true, "", "QmTestigoParticipation");

        // 3. Observador aporta evidencia adicional
        vm.prank(user3);
        oracle.attest("election_fraud_district_5", fraudRecord, true, "", "QmObservadorParticipation");

        // 4. Jurados evalúan
        vm.prank(jury1);
        oracle.attest("election_fraud_district_5", fraudRecord, true, "", "QmJury1Participation");

        vm.prank(jury2);
        oracle.attest("election_fraud_district_5", fraudRecord, true, "", "QmJury2Participation");

        // 5. Resolución automática por consenso
        vm.warp(block.timestamp + 86401);
        oracle.resolve("election_fraud_district_5");

        // 6. Verificar resultado
        (AttestationOracle.AttestationState finalState, uint256 finalResult) = 
            oracle.getAttestationInfo("election_fraud_district_5");
        
        assertEq(uint256(finalState), 3); // CLOSED por consenso
        assertEq(finalResult, fraudRecord);
        
        // 7. Verificar peso final
        assertEq(oracle.getWeighedAttestations("election_fraud_district_5", fraudRecord), 4); // 3 usuarios + jury1 debe ser considerado
    }

}

// requestregister
// register
// _depositStake
// createAttestation
// attest
// resolv
// _checkUmanaty
// _setReputation
// verifyAttestation
// getAttestationInfo
// getWeighedAttestations
// getJuryWeighedAttestations
// getOptionAttested
// viewAttestationResult
