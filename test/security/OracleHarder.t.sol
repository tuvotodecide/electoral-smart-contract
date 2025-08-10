// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {console} from "lib/forge-std/src/console.sol";

import {AttestationOracle} from "../../src/AttestationOracle.sol";
import {WiraToken} from "../../src/WiraToken.sol";
import {Reputation} from "../../src/Reputation.sol";
import {AttestationRecord} from "../../src/AttestationRecord.sol";
import {Participation} from "../../src/Participation.sol";

/**
 * @title VulnerabilityTests - Hacker Oracle
 * @dev Sanchez Brayan Ronaldo
 * @author Security Research Team
 */
contract OracleHarderTests is Test {
    AttestationOracle public oracle;
    WiraToken public token;
    Reputation public reputation;
    AttestationRecord public recordNft;
    Participation public participation;
    
    address public admin;
    address public oraclehack;
    address public victim;
    address[] public sybilAccounts;
    
    // Constantes de ataque
    uint256 constant SYBIL_COUNT = 100;
    uint256 constant STAKE_AMOUNT = 5e18;
    
    event AttackEvent(string attackType, bool success, uint256 damage);
    
    // Helper function to ensure oracle is active
    function ensureOracleActive() internal {
        vm.prank(admin);
        oracle.setActiveTime(block.timestamp, block.timestamp + 12 hours);
    }
    
    function setUp() public {
        admin = makeAddr("admin");
        oraclehack = makeAddr("oraclehack");
        victim = makeAddr("victim");
        
        // Deploy system
        vm.startPrank(admin);
        reputation = new Reputation(admin);
        recordNft = new AttestationRecord(admin);
        participation = new Participation(admin);
        token = new WiraToken(admin, admin, admin);
        
        oracle = new AttestationOracle(
            admin,
            address(recordNft),
            address(participation),
            address(reputation),
            address(token),
            STAKE_AMOUNT
        );
        
        // Grant permissions
        recordNft.grantRole(recordNft.AUTHORIZED_ROLE(), address(oracle));
        participation.grantRole(participation.AUTHORIZED_ROLE(), address(oracle));
        reputation.grantRole(reputation.AUTHORIZED_ROLE(), address(oracle));
        token.grantRole(token.MINTER_ROLE(), address(oracle));
        
        // Set active period (longer duration for tests)
        oracle.setActiveTime(block.timestamp, block.timestamp + 12 hours);
        vm.stopPrank();
        
        // Create sybil accounts
        for(uint i = 0; i < SYBIL_COUNT; i++) {
            sybilAccounts.push(makeAddr(string(abi.encodePacked("sybil", i))));
        }
    }
    
    
    
    /**
     * @dev Registro Masivo de Usuarios Falsos
     * Intenta registrar múltiples identidades falsas para manipular consenso
    **/

    function test_MassiveFakeRegistration() public {
        vm.startPrank(admin);
        
        // Registrar múltiples cuentas sybil
        for(uint i = 0; i < 10; i++) {
            oracle.register(sybilAccounts[i], false);
        }
        
        vm.stopPrank();
        
        // Verificar que todas tienen USER_ROLE
        uint256 successfulRegistrations = 0;
        for(uint i = 0; i < 10; i++) {
            if(oracle.hasRole(oracle.USER_ROLE(), sybilAccounts[i])) {
                successfulRegistrations++;
            }
        }
        
        emit AttackEvent("MassiveFakeRegistration", successfulRegistrations > 5, successfulRegistrations);
        
      
        assertTrue(successfulRegistrations > 5, "Sybil attack should succeed");
    }
    
    /**
     * @dev  Votacion Fuera de Período Activo
     * Intenta votar cuando el oráculo está inactivo
     */
    function test_VotingOutsideActivePeriod() public {
        vm.prank(admin);
        oracle.register(oraclehack, false);
        
        // Primero establecer período inactivo manualmente
        vm.prank(admin);
        oracle.setActiveTime(block.timestamp - 86400, block.timestamp - 1);
        
        // Intentar crear atestiguación fuera de período
        vm.prank(oraclehack);
        vm.expectRevert("Oracle inactive");
        oracle.createAttestation("attack_1", "evil_evidence", "evil_participation");
        
        emit AttackEvent("VotingOutsideActivePeriod", false, 0);
        
        // BIEN: El modifier onlyActive protege correctamente
        
        // Restaurar período activo para otros tests
        vm.prank(admin);
        // avance 86401
        oracle.setActiveTime(block.timestamp, block.timestamp + 12 hours);
    }
    
    /**
     * @dev Atestiguaciones Duplicadas
     * Intenta crear múltiples atestiguaciones con el mismo ID
     */
    function test_DuplicateAttestations() public {
        ensureOracleActive();
        
        vm.prank(admin);
        oracle.register(oraclehack, false);
        
        vm.startPrank(oraclehack);
        
        // Primera atestiguación exitosa
        oracle.createAttestation("duplicate_id", "evidence1", "participation1");
        
        // Segunda atestiguación con mismo ID debería fallar
        vm.expectRevert("Already created");
        oracle.createAttestation("duplicate_id", "evidence2", "participation2");
        
        vm.stopPrank();
        
        emit AttackEvent("DuplicateAttestations", false, 0);
        
        // BIEN: require protege contra duplicados
    }
    
    /**
     * @dev PRUEBA BLANDA 4: Manipulación de Reputación
     * Intenta incrementar reputación artificialmente
     */
    function test_ReputationManipulation() public {
        vm.prank(admin);
        oracle.register(oraclehack, false);
        
        // Intentar llamar directamente updateReputation (debería fallar)
        vm.prank(oraclehack);
        vm.expectRevert();
        reputation.updateReputation(oraclehack, true);
        
        emit AttackEvent("ReputationManipulation", false, 0);
        
        // BIEN: Solo el oráculo puede actualizar reputación
    }
    
    /**
     * @dev PRUEBA BLANDA 5: Bypass de Verificaciones de Rol
     * Intenta votar sin tener rol asignado
     */
    function test_RoleVerificationBypass() public {
        // Intentar crear atestiguación sin registro
        vm.prank(oraclehack);
        vm.expectRevert("Unauthorized");
        oracle.createAttestation("unauthorized", "evidence", "participation");
        
        emit AttackEvent("RoleVerificationBypass", false, 0);
        
        // BIEN: modifier onlyVerified protege correctamente
    }
    
    /**
     * @dev Gas Exhaustion en Loops
     * Intenta agotar gas en funciones con loops
     */
    function test_GasExhaustionLoops() public {
        ensureOracleActive();
        
        vm.startPrank(admin);
        
        // Registrar muchos usuarios
        for(uint i = 0; i < 20; i++) {
            oracle.register(sybilAccounts[i], false);
        }
        vm.stopPrank();
        
        // Crear atestiguación con muchos participantes
        vm.prank(sybilAccounts[0]);
        oracle.createAttestation("gas_attack", "evidence", "participation");
        
        // Muchos usuarios votan (esto podría agotar gas en resolve)
        for(uint i = 1; i < 15; i++) {
            vm.prank(sybilAccounts[i]);
            oracle.attest("gas_attack", 1, true, "", "participation");
        }
        
        // Intentar resolver (podría fallar por gas)
        vm.warp(block.timestamp + 86401);
        
        uint256 gasBefore = gasleft();
        oracle.resolve("gas_attack");
        uint256 gasUsed = gasBefore - gasleft();
        
        emit AttackEvent("GasExhaustionLoops", gasUsed > 1000000, gasUsed);
        
        // VULNERABILIDAD: Los loops pueden consumir mucho gas
        console.log("Gas usado en resolve:", gasUsed);
    }
    
    /**
     * @dev Frontrunning de Transacciones
     * Simula frontrunning de votos importantes
     */
    function test_TransactionFrontrunning() public {
        ensureOracleActive();
        vm.startPrank(admin);
        
        oracle.register(victim, false);
        oracle.register(oraclehack, false);
        vm.stopPrank();
        
        // Víctima crea atestiguación
        vm.prank(victim);
        uint256 recordId = oracle.createAttestation("frontrun_test", "honest_evidence", "participation");
        
        // Atacante ve la transacción en mempool y frontruns con voto contrario
        vm.prank(oraclehack);
        oracle.attest("frontrun_test", recordId, false, "", "evil_participation");
        
        emit AttackEvent("TransactionFrontrunning", true, 1);
        
        // VULNERABILIDAD: Las transacciones son visibles en mempool
        assertTrue(true, "Frontrunning is possible in public mempool");
    }
    
    
    
    /**
     * @dev Sybil Attack Coordinado
     * Test masivo con múltiples identidades para controlar consenso
     */
    function test_CoordinatedSybilAttack() public {
        ensureOracleActive();
        
        vm.startPrank(admin);
        
        // Registrar ejército de cuentas sybil
        for(uint i = 0; i < 75; i++) {
            oracle.register(sybilAccounts[i], false);
        }
        
        // Registrar víctima legítima
        oracle.register(victim, false);
        vm.stopPrank();
        
        // Víctima crea atestiguación honesta
        vm.prank(victim);
        oracle.createAttestation("election_2024", "real_fraud_evidence", "participation");
        
        // Atacante coordina respuesta masiva con evidencia falsa
        vm.prank(sybilAccounts[0]);
        uint256 fakeRecord = oracle.attest("election_2024", 0, false, "fake_evidence", "participation");
        console.log("Fake record ID:", fakeRecord);
        // Ejército sybil vota masivamente por evidencia falsa
        for(uint i = 1; i < 75; i++) {
            vm.prank(sybilAccounts[i]);
            oracle.attest("election_2024", fakeRecord, true, "", "participation");
        }
        
        // Resolver votación
        vm.warp(block.timestamp + 86401);
        oracle.resolve("election_2024");
        
        (AttestationOracle.AttestationState state, uint256 finalResult) = oracle.getAttestationInfo("election_2024");
        
        bool attackSucceeded = (finalResult == fakeRecord && uint256(state) == 1);
        console.log("Coordinated Sybil Attack status:", attackSucceeded);
        emit AttackEvent("CoordinatedSybilAttack", attackSucceeded, finalResult);
        
        // VULNERABILIDAD CRÍTICA: Sybil attack puede manipular resultados
        if(attackSucceeded) {
            console.log("CRITICAL: Sybil attack manipulated election result!");
        }
    }
    
    /**
     * @dev PRUEBA PESADA 9: Reentrancy Attack en Rewards
     * Ataque de reentrancia durante distribución de recompensas
     */
    function test_ReentrancyRewardAttack() public {
        ensureOracleActive();
        
        // Nota: Este test requiere un contrato malicioso para simular reentrancia
        // Por limitaciones del entorno, simulamos el concepto
        
        vm.startPrank(admin);
        oracle.register(oraclehack, false);
        vm.stopPrank();
        
        // Crear atestiguación y votar
        vm.prank(oraclehack);
        oracle.createAttestation("reentrancy_test", "evidence", "participation");
        
        // Simular resolución y distribución
        vm.warp(block.timestamp + 86401);
        
        uint256 balanceBefore = token.balanceOf(oraclehack);
        oracle.resolve("reentrancy_test");
        uint256 balanceAfter = token.balanceOf(oraclehack);
        
        uint256 reward = balanceAfter - balanceBefore;
        //console.log("Reentrancy reward:", reward);
        emit AttackEvent("ReentrancyRewardAttack", reward > 0, reward);
        
        // VULNERABILIDAD: safeTransfer podría ser vulnerable a reentrancia
        console.log("Reward received:", reward);
    }
    
    /**
     * @dev PRUEBA PESADA 10: Token Inflation Attack
     * Exploit de la función mint para crear tokens infinitos
     */
    function test_TokenInflationAttack() public {
        // El atacante necesitaría rol MINTER_ROLE para este ataque
        vm.prank(admin);
        token.grantRole(token.MINTER_ROLE(), oraclehack);
        
        uint256 initialSupply = token.totalSupply();
        
        // Atacante minta tokens masivamente
        vm.prank(oraclehack);
        token.mint(oraclehack, 1000000e18);
        
        uint256 finalSupply = token.totalSupply();
        uint256 inflationAmount = finalSupply - initialSupply;
        
        emit AttackEvent("TokenInflationAttack", inflationAmount > 0, inflationAmount);
        
        // VULNERABILIDAD CRÍTICA: No hay límites en mint()
        assertTrue(inflationAmount > 0, "Token inflation attack succeeded");
        console.log("Tokens inflated:", inflationAmount);
    }
    
    /**
     * @dev Admin Key Compromise Simulation
     * Simula compromiso de claves administrativas
     */
    function test_AdminKeyCompromise() public {
        // Simular que el atacante compromete las claves del admin
        address compromisedAdmin = oraclehack;
        
        vm.prank(admin);
        oracle.grantRole(oracle.DEFAULT_ADMIN_ROLE(), compromisedAdmin);
        
        // Atacante ahora tiene control total
        vm.startPrank(compromisedAdmin);
        
        // Puede registrar usuarios maliciosos
        oracle.register(makeAddr("Malicious1"), true); // Como JURY
        oracle.register(makeAddr("Malicious2"), false); // Como USER
        
        // Puede cambiar períodos activos
        oracle.setActiveTime(0, 999999999999);
        
        // Puede otorgar roles críticos
        oracle.grantRole(oracle.AUTHORITY_ROLE(), oraclehack);
        
        vm.stopPrank();
        
        bool hasControl = oracle.hasRole(oracle.DEFAULT_ADMIN_ROLE(), compromisedAdmin);
        
        emit AttackEvent("AdminKeyCompromise", hasControl, 1);
        
        // VULNERABILIDAD CRÍTICA: Centralización extrema
        assertTrue(hasControl, "Admin compromise gives total control");
        console.log("Admin key compromise: TOTAL SYSTEM CONTROL");
    }
    
    /**
     * @dev  Oracle Manipulation Attack
     * Manipula el oráculo para reportar datos falsos
     */
    function test_OracleManipulationAttack() public {
        ensureOracleActive();
        
        vm.startPrank(admin);
        oracle.register(oraclehack, false);
        oracle.grantRole(oracle.AUTHORITY_ROLE(), oraclehack);
        vm.stopPrank();
        
        // Víctima crea atestiguación legítima
        vm.prank(admin);
        oracle.register(victim, false);
        
        vm.prank(victim);
        oracle.createAttestation("real_fraud", "legitimate_evidence", "participation");
        
        // Forzar estado VERIFYING
        vm.warp(block.timestamp + 86401);
        oracle.resolve("real_fraud");
        
        // Atacante como AUTHORITY fuerza resultado falso
        vm.prank(oraclehack);
        oracle.verifyAttestation("real_fraud", 999); // Record inexistente
        
        (, uint256 finalResult) = oracle.getAttestationInfo("real_fraud");
        
        bool manipulationSucceeded = (finalResult == 999);
        
        emit AttackEvent("OracleManipulationAttack", manipulationSucceeded, finalResult);
        
        // VULNERABILIDAD: AUTHORITY puede forzar resultados arbitrarios
        if(manipulationSucceeded) {
            console.log("Oracle manipulation succeeded - false result set");
        }
    }
    
    /**
     * @dev Consensus Breaking Attack
     * Rompe el consenso para invalidar elecciones
     */
    function test_ConsensusBreakingAttack() public {
        ensureOracleActive();
        
        vm.startPrank(admin);
        
        // Registrar usuarios legítimos y atacantes
        oracle.register(victim, false);
        for(uint i = 0; i < 5; i++) {
            oracle.register(sybilAccounts[i], false);
        }
        
        // Registrar jurados maliciosos
        for(uint i = 5; i < 10; i++) {
            oracle.register(sybilAccounts[i], true);
        }
        vm.stopPrank();
        
        // Víctima crea atestiguación legítima
        vm.prank(victim);
        uint256 legitRecord = oracle.createAttestation("important_election", "real_evidence", "participation");
        
        // Usuarios legítimos apoyan evidencia real
        for(uint i = 0; i < 3; i++) {
            vm.prank(sybilAccounts[i]);
            oracle.attest("important_election", legitRecord, true, "", "participation");
        }
        
        // Atacantes crean evidencia falsa y la apoyan
        vm.prank(sybilAccounts[3]);
        uint256 fakeRecord = oracle.attest("important_election", 0, false, "false_evidence", "participation");
        
        vm.prank(sybilAccounts[4]);
        oracle.attest("important_election", fakeRecord, true, "", "participation");
        
        // Jurados maliciosos apoyan evidencia falsa
        for(uint i = 5; i < 8; i++) {
            vm.prank(sybilAccounts[i]);
            oracle.attest("important_election", fakeRecord, true, "", "participation");
        }
        
        // Resolver votación
        vm.warp(block.timestamp + 86401);
        oracle.resolve("important_election");
        
        (AttestationOracle.AttestationState state,) = oracle.getAttestationInfo("important_election");
        
        bool consensusBroken = (uint256(state) == 2); // VERIFYING
        
        emit AttackEvent("ConsensusBreakingAttack", consensusBroken, uint256(state));
        
        // VULNERABILIDAD: Conflicto usuario vs jurado rompe consenso
        if(consensusBroken) {
            console.log("Consensus broken - election invalidated");
        }
    }
    
    /**
     * @dev Economic Drain Attack
     * Drena todos los fondos del sistema
     */
    function test_EconomicDrainAttack() public {
        // Dar al atacante capacidad de mint
        vm.prank(admin);
        token.grantRole(token.MINTER_ROLE(), oraclehack);
        
        // Atacante minta tokens masivos al contrato del oráculo
        vm.prank(oraclehack);
        token.mint(address(oracle), 1000000e18);
        
        uint256 contractBalance = token.balanceOf(address(oracle));
        
        // Ahora necesita drenar estos fondos mediante resolución de atestiguaciones
        vm.startPrank(admin);
        oracle.register(oraclehack, false);
        vm.stopPrank();
        
        // Crear múltiples atestiguaciones para drenar fondos
        vm.prank(oraclehack);
        oracle.createAttestation("drain_attack", "evidence", "participation");
        
        vm.warp(block.timestamp + 86401);
        oracle.resolve("drain_attack");
        
        uint256 oraclehackBalance = token.balanceOf(oraclehack);
        
        emit AttackEvent("EconomicDrainAttack", oraclehackBalance > 0, oraclehackBalance);
        
        // VULNERABILIDAD: Combinación de mint + resolve puede drenar fondos
        console.log("Contract balance:", contractBalance);
        console.log("Attacker gained:", oraclehackBalance);
    }
    
    
    /**
     * @dev Full System Takeover
     * Compromiso completo del sistema
     */
    function test_FullSystemTakeover() public {
        // Simular múltiples vectores de ataque simultáneos
        
        // 1. Compromiso de admin
        vm.prank(admin);
        oracle.grantRole(oracle.DEFAULT_ADMIN_ROLE(), oraclehack);
        
        // 2. Control de tokens
        vm.prank(admin);
        token.grantRole(token.MINTER_ROLE(), oraclehack);
        
        // 3. Control de reputación
        vm.prank(admin);
        reputation.grantRole(reputation.AUTHORIZED_ROLE(), oraclehack);
        
        vm.startPrank(oraclehack);
        
        // 4. Registrar ejército de bots
        for(uint i = 0; i < 20; i++) {
            oracle.register(sybilAccounts[i], i % 2 == 0); // Mix de users y juries
        }
        
        // 5. Manipular período activo
        oracle.setActiveTime(0, 999999999999);
        
        // 6. Crear tokens infinitos
        token.mint(oraclehack, 1000000000e18);
        
        // 7. Manipular reputaciones
        for(uint i = 0; i < 10; i++) {
            reputation.updateReputation(sybilAccounts[i], true);
        }
        
        vm.stopPrank();
        
        bool fullControl = oracle.hasRole(oracle.DEFAULT_ADMIN_ROLE(), oraclehack) &&
                          token.hasRole(token.MINTER_ROLE(), oraclehack) &&
                          reputation.hasRole(reputation.AUTHORIZED_ROLE(), oraclehack);
        
        emit AttackEvent("FullSystemTakeover", fullControl, 999);
        
        assertTrue(fullControl, "Full system takeover achieved");
        console.log("CRITICAL: COMPLETE SYSTEM COMPROMISE");
    }
    
    /**
     * @dev ATAQUE CRÍTICO: Manipulación de Consenso con Control de Roles
     * Explota la vulnerabilidad de centralización para manipular resultados electorales
     */
    function test_ElectoralFraudSimulation() public {
        ensureOracleActive();
        
        // social engineering
        vm.startPrank(admin);
        // Registrar víctima legítima y observadores honestos
        oracle.register(makeAddr("honest_observer"), false);
        oracle.register(makeAddr("election_authority"), false);
        oracle.register(makeAddr("media_witness"), false);
        
        // filtro  de seguridad
        oracle.register(oraclehack, true); // Se registra como JURY (más poder)
        oracle.grantRole(oracle.AUTHORITY_ROLE(), oraclehack); // Admin le da confianza
        
        // Registrar ejército sybil como "auditores independientes"
        for(uint i = 0; i < 15; i++) {
            oracle.register(sybilAccounts[i], i < 8); // Mix estratégico de roles
        }
        vm.stopPrank();
        
        // crear evidencia contradictoria usando su posición privilegiada
        vm.prank(oraclehack);
        uint256 disinfoId = oracle.attest(
            "fraude reportado 2025",
            0, // Nueva evidencia
            false, // Contradice la evidencia real
            "Technical analysis shows no irregularities - false alarm",
            "certified_auditor_report"
        );
        

        // Coordinación masiva de desinformación
        // Los sybils actúan como "expertos independientes" apoyando la narrativa falsa
        for(uint i = 0; i < 12; i++) {
            vm.prank(sybilAccounts[i]);
            oracle.attest(
                "fraude reportado 2025", 
                disinfoId, 
                true, 
                string(abi.encodePacked("Independent verification #", i)), 
                string(abi.encodePacked("expert_", i))
            );
        }
        
      
        // Abuse of AUTHORITY role para forzar resultado
        // Si el consenso natural falla, el atacante usa su rol privilegiado
        vm.prank(oraclehack);
        oracle.verifyAttestation("fraude reportado 2025", disinfoId);

   
        (AttestationOracle.AttestationState finalState, uint256 finalResult) = oracle.getAttestationInfo("fraude reportado 2025");
        
        bool attackSucceeded = (finalResult == disinfoId || uint256(finalState) == 1);
        uint256 damageLevel = attackSucceeded ? 1000000 : 0; // $1M in damage to democracy
        
        emit AttackEvent("ElectoralFraudSimulation", attackSucceeded, damageLevel);
        
       
        if(attackSucceeded) {
            console.log("- Final result ID:", finalResult);
            console.log("- Disinformation ID:", disinfoId);
        } else {
            console.log("Election integrity maintained");
        }
        
        // VERIFICAR VULNERABILIDADES EXPLOTADAS
        assertTrue(
            oracle.hasRole(oracle.AUTHORITY_ROLE(), oraclehack), 
            "Critical: Attacker should have authority role"
        );
    }
    
    /**
     * @dev Reputation System Collapse
     * Colapsa completamente el sistema de reputación
     */
    function test_ReputationSystemCollapse() public {
        vm.prank(admin);
        reputation.grantRole(reputation.AUTHORIZED_ROLE(), oraclehack);
        
        // Crear cuentas para colapsar
        vm.startPrank(admin);
        for(uint i = 0; i < 20; i++) {
            oracle.register(sybilAccounts[i], false);
        }
        vm.stopPrank();
        
        vm.startPrank(oraclehack);
        
        // Inflación masiva de reputación
        for(uint i = 0; i < 20; i++) {
            for(uint j = 0; j < 100; j++) {
                reputation.updateReputation(sybilAccounts[i], true);
            }
        }
        
        vm.stopPrank();
        
        // Verificar colapso
        uint256 totalInflatedReputation = 0;
        for(uint i = 0; i < 20; i++) {
            vm.prank(address(oracle));
            totalInflatedReputation += reputation.getReputationOf(sybilAccounts[i]);
        }
        
        bool systemCollapsed = totalInflatedReputation > 2000;
        
        emit AttackEvent("ReputationSystemCollapse", systemCollapsed, totalInflatedReputation);
        
        if(systemCollapsed) {
            console.log("Reputation system collapsed - total reputation:", totalInflatedReputation);
        }
    }
    
    /**
     * @dev Smart Contract Destruction
     * Intenta destruir o inutilizar contratos
     */
    function test_SmartContractDestruction() public {
        ensureOracleActive();
        
        // Pausar token 
        vm.prank(admin);
        token.pause();
        
        // Intentar operaciones que deberían fallar
        vm.prank(admin);
        oracle.register(oraclehack, false);
        
        vm.prank(oraclehack);
        oracle.createAttestation("destruction_test", "evidence", "participation");
        
        vm.warp(block.timestamp + 86401);
        
        // Resolve debería fallar si los tokens están pausados
        try oracle.resolve("destruction_test") {
            emit AttackEvent("SmartContractDestruction", false, 0);
        } catch {
            emit AttackEvent("SmartContractDestruction", true, 1);
            console.log("Contract functionality destroyed via token pause");
        }
    }
    
    /**
     * @dev Data Integrity Compromise
     * Compromete la integridad de datos del sistema
     */
    function test_DataIntegrityCompromise() public {
        ensureOracleActive();
        
        vm.startPrank(admin);
        oracle.register(victim, false);
        oracle.register(oraclehack, false);
        oracle.grantRole(oracle.AUTHORITY_ROLE(), oraclehack);
        vm.stopPrank();
        
        // fake datos legítimos
        vm.prank(victim);
        oracle.createAttestation("data_integrity_test", "real_data", "legitimate_participation");
        
        vm.warp(block.timestamp + 86401);
        oracle.resolve("data_integrity_test");
        
        // Hackk corrompe resultado final
        vm.prank(oraclehack);
        oracle.verifyAttestation("data_integrity_test", 99999); // Datos corruptos
        
        (, uint256 corruptedResult) = oracle.getAttestationInfo("data_integrity_test");
        
        bool dataCorrupted = (corruptedResult == 99999);
        
        emit AttackEvent("DataIntegrityCompromise", dataCorrupted, corruptedResult);
        
        if(dataCorrupted) {
            console.log("Data integrity compromised - false data accepted");
        }
    }
    
    /**
     * @dev Complete Network Denial
     * Deniega completamente el servicio del oráculo
     */
    function test_CompleteNetworkDenial() public {
        ensureOracleActive();
        
        vm.startPrank(admin);
        
        // Registrar atacantes masivos
        for(uint i = 0; i < SYBIL_COUNT; i++) {
            oracle.register(sybilAccounts[i], i % 3 == 0); // Mix roles
        }
        vm.stopPrank();
        
        // Crear múltiples atestiguaciones conflictivas
        for(uint i = 0; i < 10; i++) {
            vm.prank(sybilAccounts[i]);
            oracle.createAttestation(
                string(abi.encodePacked("denial_", i)), 
                "spam_evidence", 
                "spam_participation"
            );
        }
        
        // Cada atestiguación recibe votos masivos conflictivos
        for(uint attestation = 0; attestation < 10; attestation++) {
            string memory attestationId = string(abi.encodePacked("denial_", attestation));
            
            for(uint voter = 10; voter < 50; voter++) {
                vm.prank(sybilAccounts[voter]);
                oracle.attest(
                    attestationId, 
                    attestation + 1, 
                    voter % 2 == 0, 
                    "", 
                    "spam_participation"
                );
            }
        }
        
        // Avanzar tiempo
        vm.warp(block.timestamp + 86401);
        
        // Intentar resolver todas (puede agotar gas)
        uint256 denialSuccessful = 0;
        for(uint i = 0; i < 10; i++) {
            try oracle.resolve(string(abi.encodePacked("denial_", i))) {
                // Resolve exitoso
            } catch {
                denialSuccessful++;
            }
        }
        
        emit AttackEvent("CompleteNetworkDenial", denialSuccessful > 0, denialSuccessful);
        
        if(denialSuccessful > 0) {
            console.log("Network denial successful - services unavailable");
        }
    }
}



