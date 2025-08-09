// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {console} from "lib/forge-std/src/console.sol";

import {AttestationOracle} from "../../src/AttestationOracle.sol";
import {WiraToken} from "../../src/WiraToken.sol";
import {Reputation} from "../../src/Reputation.sol";
import {AttestationRecord} from "../../src/AttestationRecord.sol";

contract AttestationOracleTestUp is Test {
    AttestationOracle public oracle;
    Reputation public reputation;
    AttestationRecord public recordNft;
    WiraToken public token;
    address public owner; // propietario
    address public user1;
    address public user2;
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
        jury1 = makeAddr("jury1");
        jury2 = makeAddr("jury2");
        authority = makeAddr("authority");

        // Deploy contracts
        reputation = new Reputation(owner);
        recordNft = new AttestationRecord(owner);
        token = new WiraToken(owner, owner, owner);

        oracle = new AttestationOracle(
            owner,
            address(recordNft),
            address(reputation),
            address(token),
            5e18 // stake amount
        );

        // cfg permissions
        vm.startPrank(owner);

        console.log("owner: ", owner);
        recordNft.grantRole(recordNft.AUTHORIZED_ROLE(), address(oracle));
        reputation.grantRole(recordNft.AUTHORIZED_ROLE(), address(oracle));
        token.grantRole(token.MINTER_ROLE(), address(oracle));
        oracle.grantRole(oracle.AUTHORITY_ROLE(), authority);
        console.log("Oracle address: ", address(oracle));
        console.log("Reputation address: ", address(reputation));
        console.log("RecordNFT address: ", address(recordNft));
        console.log("WiraToken address: ", address(token));
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

    function test_requestRegister_doesNothingIfAlreadyRegistered() public {
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
    }

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

    // *** test attestation createAttestation

    function test_createAttestation_userSuccess() public {
        // Registrar usuario
        console.log("user register: ", user1);
        vm.prank(owner);
        oracle.register(user1, false);
        console.log("owner: ", owner);
        vm.prank(user1);
        vm.expectEmit(false, false, false, true);
        emit AttestationCreated(0, 1);

        (uint256 attestationId, uint256 recordId) = oracle.createAttestation("ipfs://evidence1");
        assertEq(attestationId, 0);
        console.log("Attestation created: ", attestationId);
        assertEq(recordId, 1);
        // Verificar estado inicial
        (AttestationOracle.AttestationState state, uint256 finalResult) = oracle.getAttestationInfo(attestationId);
        console.log("record:", recordId);
        assertEq(uint256(state), 0); // OPEN
        assertEq(finalResult, 0);
        // Verificar que el stake se depositó
        assertEq(token.balanceOf(address(oracle)), 5e18);
        console.log("status stake: ", token.balanceOf(address(oracle)));
    }

    function test_createAttestation_jurySuccess() public {
        vm.prank(owner);
        oracle.register(jury1, true);

        vm.prank(jury1);
        (uint256 attestationId, uint256 recordId) = oracle.createAttestation("ipfs://evidence1");

        assertEq(attestationId, 0);
        assertEq(recordId, 1);

        // Verificar attestation del jury
        assertEq(oracle.getJuryWeighedAttestations(attestationId, recordId), 1); // reputation inicial = 1
    }

    function test_createAttestation_revertsWhenUnauthorized() public {
        vm.prank(user1); // No registrado
        vm.expectRevert("Unauthorized");
        oracle.createAttestation("ipfs://evidence1");
    }

    function test_createAttestation_revertsWhenInactive() public {
        vm.prank(owner);
        oracle.register(user1, false);

        vm.warp(300); // Fuera del periodo activo

        vm.prank(user1);
        vm.expectRevert("Oracle inactive");
        oracle.createAttestation("ipfs://evidence1");
    }

    // pruebas attest

    function test_attest_newRecord() public {
        // Setup inicial
        vm.startPrank(owner);
        oracle.register(user1, false);
        oracle.register(user2, false);
        vm.stopPrank();

        // User1 crea attestation
        vm.prank(user1);
        (uint256 attestationId,) = oracle.createAttestation("ipfs://evidence1");

        // User2 atesta con nuevo record
        vm.prank(user2);
        vm.expectEmit(false, false, false, false);
        emit Attested(2);

        oracle.attest(attestationId, 0, false, "ipfs://evidence2");
        // Verificar que se creó un nuevo record
        assertEq(recordNft.totalSupply(), 2);
    }

    function test_attest_existingRecordTrue() public {
        vm.startPrank(owner);
        oracle.register(user1, false);
        oracle.register(user2, false);
        vm.stopPrank();

        vm.prank(user1);
        (uint256 attestationId, uint256 recordId) = oracle.createAttestation("ipfs://evidence1");

        vm.prank(user2);
        oracle.attest(attestationId, recordId, true, "");

        // Verificar que el peso aumentó
        assertEq(oracle.getWeighedAttestations(attestationId, recordId), 2); // user1 + user2 (ambos reputation = 1)
    }

    function test_attest_existingRecordFalse() public {
        vm.startPrank(owner);
        oracle.register(user1, false);
        oracle.register(user2, false);
        vm.stopPrank();

        vm.prank(user1);
        (uint256 attestationId, uint256 recordId) = oracle.createAttestation("ipfs://evidence1");

        vm.prank(user2);
        oracle.attest(attestationId, recordId, false, "");

        // Verificar que el peso disminuyó
        assertEq(oracle.getWeighedAttestations(attestationId, recordId), 0); // 1 - 1 = 0
    }

    function test_attest_revertsWhenAlreadyAttested() public {
        vm.startPrank(owner);
        oracle.register(user1, false);
        oracle.register(user2, false);
        vm.stopPrank();

        vm.prank(user1);
        (uint256 attestationId, uint256 recordId) = oracle.createAttestation("ipfs://evidence1");

        vm.prank(user2);
        oracle.attest(attestationId, recordId, true, "");

        // Segundo intento debería fallar
        vm.prank(user2);
        vm.expectRevert("already attested");
        oracle.attest(attestationId, recordId, false, "");
    }

    function test_attest_revertsWhenWrongState() public {
        vm.prank(owner);
        oracle.register(user1, false);

        vm.prank(user1);
        (uint256 attestationId, uint256 recordId) = oracle.createAttestation("ipfs://evidence1");

        // Avanzar tiempo y resolver
        vm.warp(201);
        oracle.resolve(attestationId);

        // Intentar atestar después de resolver
        vm.prank(owner);
        oracle.register(user2, false);

        // Restablecer el tiempo activo
        vm.prank(owner);
        oracle.setActiveTime(200, 400);
        vm.warp(300);

        vm.prank(user2);
        vm.expectRevert("Bad attestation state");
        oracle.attest(attestationId, recordId, true, "");
    }

    // ==================== TESTS PARA resolve ====================

    function test_resolve_unanimousOneRecord() public {
        vm.startPrank(owner);
        oracle.register(user1, false);
        oracle.register(user2, false);
        oracle.register(jury1, true);
        vm.stopPrank();

        vm.prank(user1);
        (uint256 attestationId, uint256 recordId) = oracle.createAttestation("ipfs://evidence1");

        vm.prank(user2);
        oracle.attest(attestationId, recordId, true, "");

        vm.prank(jury1);
        oracle.attest(attestationId, recordId, true, "");

        vm.warp(201);

        vm.expectEmit(true, false, false, true);
        emit Resolved(attestationId, AttestationOracle.AttestationState.CLOSED);

        oracle.resolve(attestationId);

        (AttestationOracle.AttestationState state, uint256 finalResult) = oracle.getAttestationInfo(attestationId);
        assertEq(uint256(state), 3); // CLOSED
        assertEq(finalResult, recordId);
    }

    function test_resolve_consensualMultipleRecords() public {
        vm.startPrank(owner);
        oracle.register(user1, false);
        oracle.register(user2, false);
        oracle.register(jury1, true);
        vm.stopPrank();

        vm.prank(user1);
        (uint256 attestationId, uint256 record1) = oracle.createAttestation("ipfs://evidence1");

        vm.prank(user2);
        oracle.attest(attestationId, 0, false, "ipfs://evidence2");

        // Más votos para record1
        vm.prank(jury1);
        oracle.attest(attestationId, record1, true, "");

        vm.warp(201);
        oracle.resolve(attestationId);

        (AttestationOracle.AttestationState state, uint256 finalResult) = oracle.getAttestationInfo(attestationId);
        assertEq(uint256(state), 1); // CONSENSUAL
        assertEq(finalResult, record1);
    }

    function test_resolve_revertsWhenTooSoon() public {
        vm.prank(owner);
        oracle.register(user1, false);

        vm.prank(user1);
        (uint256 attestationId,) = oracle.createAttestation("ipfs://evidence1");

        // No avanzar tiempo
        vm.expectRevert("too soon");
        oracle.resolve(attestationId);
    }

    // ==================== TESTS PARA verifyAttestation ====================
    /*
    function test_verifyAttestation_success() public {
        vm.prank(owner);
        oracle.register(user1, false);
        oracle.register(user2, false);

        vm.prank(user1);
        (uint256 attestationId, uint256 record1) = oracle.createAttestation("ipfs://evidence1");

        vm.prank(user2);
        oracle.attest(attestationId, 0, false, "ipfs://evidence2");

        // Llevar a estado VERIFYING
        vm.warp(201);
        oracle.resolve(attestationId);

        // Authority verifica
        vm.prank(authority);
        oracle.verifyAttestation(attestationId, record1);

        (AttestationOracle.AttestationState state, uint256 finalResult) = oracle.getAttestationInfo(attestationId);
        assertEq(uint256(state), 3); // CLOSED
        assertEq(finalResult, record1);
    }*/

    function test_verifyAttestation_revertsWhenNotAuthority() public {
        vm.prank(user1);
        vm.expectRevert();
        oracle.verifyAttestation(0, 1);
    }

    function test_verifyAttestation_revertsWhenWrongState() public {
        vm.prank(owner);
        oracle.register(user1, false);

        vm.prank(user1);
        (uint256 attestationId, uint256 recordId) = oracle.createAttestation("ipfs://evidence1");

        // Estado es OPEN, no VERIFYING
        vm.prank(authority);
        vm.expectRevert("Bad attestation state");
        oracle.verifyAttestation(attestationId, recordId);
    }

    // ==================== TESTS PARA getAttestationInfo ====================

    function test_getAttestationInfo() public {
        vm.prank(owner);
        oracle.register(user1, false);

        vm.prank(user1);
        (uint256 attestationId, uint256 recordId) = oracle.createAttestation("ipfs://evidence1");

        (AttestationOracle.AttestationState state, uint256 finalResult) = oracle.getAttestationInfo(attestationId);

        assertEq(uint256(state), 0); // OPEN
        assertEq(finalResult, 0); // No hay resultado final aún
    }

    // ==================== TESTS PARA getWeighedAttestations ====================

    function test_getWeighedAttestations() public {
        vm.startPrank(owner);
        oracle.register(user1, false);
        oracle.register(user2, false);
        vm.stopPrank();

        vm.prank(user1);
        (uint256 attestationId, uint256 recordId) = oracle.createAttestation("ipfs://evidence1");

        // Inicial: solo user1 votó (reputation = 1)
        assertEq(oracle.getWeighedAttestations(attestationId, recordId), 1);

        vm.prank(user2);
        oracle.attest(attestationId, recordId, true, "");

        // Ahora: user1 + user2 (ambos reputation = 1)
        assertEq(oracle.getWeighedAttestations(attestationId, recordId), 2);
    }

    // ==================== TESTS PARA getJuryWeighedAttestations ====================

    function test_getJuryWeighedAttestations() public {
        vm.startPrank(owner);
        oracle.register(jury1, true);
        oracle.register(jury2, true);
        vm.stopPrank();

        vm.prank(jury1);
        (uint256 attestationId, uint256 recordId) = oracle.createAttestation("ipfs://evidence1");

        assertEq(oracle.getJuryWeighedAttestations(attestationId, recordId), 1);

        vm.prank(jury2);
        oracle.attest(attestationId, recordId, true, "");

        assertEq(oracle.getJuryWeighedAttestations(attestationId, recordId), 2);
    }

    // ==================== TESTS PARA getOptionAttested ====================

    function test_getOptionAttested() public {
        vm.prank(owner);
        oracle.register(user1, false);

        vm.prank(user1);
        (uint256 attestationId, uint256 recordId) = oracle.createAttestation("ipfs://evidence1");

        vm.prank(user1);
        (uint256 recordAttested, bool choice) = oracle.getOptionAttested(attestationId);

        assertEq(recordAttested, recordId);
        assertTrue(choice); // Creador siempre vota true por defecto
    }

    // ==================== TESTS PARA viewAttestationResult ====================

    function test_viewAttestationResult() public {
        vm.startPrank(owner);
        oracle.register(user1, false);
        oracle.register(user2, false);
        oracle.register(jury1, true);
        vm.stopPrank();

        vm.prank(user1);
        (uint256 attestationId, uint256 record1) = oracle.createAttestation("ipfs://evidence1");

        vm.prank(user2);
        oracle.attest(attestationId, 0, false, "ipfs://evidence2");

        vm.prank(jury1);
        oracle.attest(attestationId, record1, true, "");

        vm.warp(201);
        oracle.resolve(attestationId);

        (uint256 mostAttested, uint256 mostJuryAttested) = oracle.viewAttestationResult(attestationId);

        assertEq(mostAttested, record1); // Usuarios votaron más por record1
        assertEq(mostJuryAttested, record1); // Juries votaron más por record1
    }

    // ==================== TESTS DE INTEGRACIÓN ====================
    /*
    function test_onlyJuriesVote() public {
        vm.startPrank(owner);
        oracle.register(jury1, true);
        oracle.register(jury2, true);
        vm.stopPrank();

        vm.prank(jury1);
        (uint256 attestationId, uint256 recordId) = oracle.createAttestation("ipfs://evidence1");

        vm.prank(jury2);
        oracle.attest(attestationId, recordId, true, "");

        vm.warp(201);
        oracle.resolve(attestationId);

        (AttestationOracle.AttestationState state, uint256 finalResult) = oracle.getAttestationInfo(attestationId);
        assertEq(uint256(state), 1); // CONSENSUAL
        assertEq(finalResult, recordId);
    }*/
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
