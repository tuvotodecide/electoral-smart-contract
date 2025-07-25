// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";


import {AttestationOracle} from "../../src/AttestationOracle.sol";

// Mocks para las interfaces
contract MockAttestationRecord {
    uint256 private _tokenIdCounter;
    
    function safeMint(address /*to*/, string memory /*uri*/) external returns (uint256) {
        return ++_tokenIdCounter;
    }
}

contract MockReputation {
    mapping(address => uint256) private _reputation;
    mapping(address => bool) private _initialized;
    
    function initReputationOf(address user) external {
        _reputation[user] = 100; // Reputación inicial
        _initialized[user] = true;
    }
    
    function getReputationOf(address user) external view returns (uint256) {
        return _reputation[user];
    }
    
    function updateReputation(address user, bool up) external {
        if (up) {
            _reputation[user] += 10;
        } else {
            if (_reputation[user] >= 10) {
                _reputation[user] -= 10;
            }
        }
    }
}

contract MockWiraToken {
    mapping(address => uint256) private _balances;
    uint256 private _totalSupply;
    
    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
        _totalSupply += amount;
    }
    
    function transfer(address to, uint256 amount) external returns (bool) {
        require(_balances[msg.sender] >= amount, "Insufficient balance");
        _balances[msg.sender] -= amount;
        _balances[to] += amount;
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(_balances[from] >= amount, "Insufficient balance");
        _balances[from] -= amount;
        _balances[to] += amount;
        return true;
    }
    
    function safeTransfer(address to, uint256 amount) external {
        require(_balances[address(this)] >= amount, "Insufficient balance");
        _balances[address(this)] -= amount;
        _balances[to] += amount;
    }
    
    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }
    
    function allowance(address /*owner*/, address /*spender*/) external pure returns (uint256) {
        return type(uint256).max;
    }
    
    function approve(address /*spender*/, uint256 /*amount*/) external pure returns (bool) {
        return true;
    }
}

contract AttestationOracleTestMin is Test {
    AttestationOracle public oracle;
    MockAttestationRecord public mockRecord;
    MockReputation public mockReputation;
    MockWiraToken public mockToken;
    // cambiar roles

    address public admin; // Se asigna en setUp()
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    address public jury1 = address(0x4);
    address public authority = address(0x5);
    
    uint256 public constant STAKE_AMOUNT = 100 ether;
    
    function setUp() public {
        // Configurar las direcciones
        admin = address(this); // El contrato de test es el admin
        
        // Configurar los mocks
        mockRecord = new MockAttestationRecord();
        mockReputation = new MockReputation();
        mockToken = new MockWiraToken();
        
        // Desplegar el contrato principal
        oracle = new AttestationOracle(
            admin,
            address(mockRecord),
            address(mockReputation),
            address(mockToken),
            STAKE_AMOUNT
        );
        
        // Configurar tiempos activos (ahora + 1 hora hasta ahora + 3 horas)
        oracle.setActiveTime(block.timestamp + 1 hours, block.timestamp + 3 hours);
        
        // Registrar usuarios
        oracle.register(user1, false); // Usuario normal
        oracle.register(user2, false); // Usuario normal
        oracle.register(jury1, true); // Jurado
        
        // Otorgar rol de autoridad
        oracle.grantRole(oracle.AUTHORITY_ROLE(), authority);
        
        // Avanzar el tiempo para que el oráculo esté activo
        vm.warp(block.timestamp + 1 hours + 1);
    }
    
    // TEST 1: Verificar que el constructor inicializa correctamente
    function test_Constructor() public view {
        assertEq(oracle.stake(), STAKE_AMOUNT);
        assertEq(oracle.totalAttestations(), 0);
        assertTrue(oracle.hasRole(oracle.DEFAULT_ADMIN_ROLE(), admin));
        console.log("stake: " , oracle.stake());
        console.log("totalAttestations: ", oracle.totalAttestations());
    }
    
    //Verificar que requestRegister funciona correctamente
    function test_RequestRegister() public {
        address newUser = address(0x6);
        
        vm.expectEmit(true, false, false, true);
        emit AttestationOracle.RegisterRequested(newUser, "test-uri");
        
        vm.prank(newUser);
        oracle.requestRegister("test-uri");
        console.log("Request register: ", newUser);
        
    }
    
    //Verificar que register funciona correctamente
    function test_Register() public {
        address newUser = address(0x7);
        
        vm.prank(admin);
        oracle.register(newUser, false);
        
        assertTrue(oracle.hasRole(oracle.USER_ROLE(), newUser));
        assertFalse(oracle.hasRole(oracle.JURY_ROLE(), newUser));
    }
    
    //  why Verifyng  createAttestation started correct
    function test_CreateAttestation() public {
        string memory uri = "ipfs://test-hash";
        console.log("Creating attestation with URI:", uri);
        vm.expectEmit(true, true, false, true);
        emit AttestationOracle.AttestationCreated(0, 1);
        vm.prank(user1);
        (uint256 attestationId, uint256 recordId) = oracle.createAttestation(uri);
        
        assertEq(attestationId, 0);
        assertEq(recordId, 1);
        assertEq(oracle.totalAttestations(), 1);
        console.log("Attestation created ID:", attestationId);
        console.log("Attestation Record ID:", recordId);
        
        // Verificar el estado de la attestación
        (AttestationOracle.AttestationState state, uint256 finalResult) = oracle.getAttestationInfo(0);
        assertEq(uint256(state), uint256(AttestationOracle.AttestationState.OPEN));
        assertEq(finalResult, 0);
        //console.log("Attestation State:", state);
        console.log("Attestation result:", finalResult);
    }
    
    // Verificar que attest funciona correctamente
    function test_Attest() public {
        // Primero crear una attestación
        vm.prank(user1);
        (uint256 attestationId,) = oracle.createAttestation("ipfs://test-hash");
        
        // Usuario 2 vota en la misma attestación
        vm.expectEmit();
        emit AttestationOracle.Attested();
        console.log("Attestation ID:", attestationId);
        vm.prank(user2);
        oracle.attest(attestationId, 1, true, "");
        
        // Verificar que el usuario votó
        vm.prank(user2);
        (uint256 record, bool choice) = oracle.getOptionAttested(attestationId);
        assertEq(record, 1);
        assertTrue(choice);
        console.log("Attestation User1:",user1 ," vote Record:", record);
        console.log("Attestation User2:",user2 , "Vote:", choice);
    }
    
    // TEST 6: Verificar que resolve funciona correctamente
    function test_Resolve() public {
        // Crear attestación y obtener votos
        vm.prank(user1);
        (uint256 attestationId,) = oracle.createAttestation("ipfs://test-hash");
        
        vm.prank(user2);
        oracle.attest(attestationId, 1, true, "");
        
        vm.prank(jury1);
        oracle.attest(attestationId, 1, true, "");
        
        // Avanzar tiempo pasado el final de attestación
        vm.warp(block.timestamp + 3 hours);
        
        // No especificamos el evento exacto, solo verificamos que se resuelve
        oracle.resolve(attestationId);
        
        // Verificar que se resolvió correctamente
        (AttestationOracle.AttestationState state, uint256 finalResult) = oracle.getAttestationInfo(attestationId);
        assertTrue(uint256(state) > uint256(AttestationOracle.AttestationState.OPEN));
        assertEq(finalResult, 1);
    }
    
// verifyAttestation funciona correctamente
    function test_VerifyAttestation() public {
        // Crear una situación donde se necesita verificación
        vm.prank(user1);
        (uint256 attestationId,) = oracle.createAttestation("ipfs://test-hash");
        
        vm.prank(user2);

        oracle.attest(attestationId, 1, false, ""); // Voto en contra
        console.log(oracle.attestStart(), oracle.attestEnd());
        vm.warp(block.timestamp + 3 hours);
        oracle.resolve(attestationId);
        (AttestationOracle.AttestationState state,) = oracle.getAttestationInfo(attestationId);
        assertEq(uint256(state), uint256(AttestationOracle.AttestationState.VERIFYING));
        vm.prank(authority);
        oracle.verifyAttestation(attestationId, 1);
        console.log(authority);
        (state,) = oracle.getAttestationInfo(attestationId);
        assertEq(uint256(state), uint256(AttestationOracle.AttestationState.CLOSED));
    }
    
    //Verificar que setActiveTime funciona correctamente
    function test_SetActiveTime() public {
        uint256 newStart = block.timestamp + 5 hours;
        uint256 newEnd = block.timestamp + 10 hours;
        
        vm.prank(admin);
        oracle.setActiveTime(newStart, newEnd);
        
        assertEq(oracle.attestStart(), newStart);
        assertEq(oracle.attestEnd(), newEnd);
        
        // Verificar que las funciones que requieren estar activo fallan fuera del tiempo
        vm.warp(block.timestamp + 1); // Antes del nuevo start
        console.log("Current time:", block.timestamp);
        vm.expectRevert("Oracle inactive");
        vm.prank(user1);
        oracle.createAttestation("test");
    }
}




