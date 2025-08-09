// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {console} from "lib/forge-std/src/console.sol";
import {AttestationOracle} from "../../src/AttestationOracle.sol";

// Mocks mejorados para las interfaces
contract MockAttestationRecord {
    uint256 private _tokenIdCounter;
    mapping(address => bool) public hasRole_;
    bytes32 public constant AUTHORIZED_ROLE = keccak256("AUTHORIZED_ROLE");

    function safeMint(address, /*to*/ string memory /*uri*/ ) external returns (uint256) {
        return ++_tokenIdCounter;
    }

    function grantRole(bytes32, address account) external {
        hasRole_[account] = true;
    }

    function hasRole(bytes32, address account) external view returns (bool) {
        return hasRole_[account];
    }

    /*function AUTHORIZED_ROLE() external pure returns (bytes32) {
        return AUTHORIZED_ROLE;
    }*/

    function totalSupply() external view returns (uint256) {
        return _tokenIdCounter;
    }

    function balanceOf(address) external pure returns (uint256) {
        return 0;
    }
}

contract MockParticipation {
    uint256 private _tokenIdCounter;
    mapping(address => bool) public hasRole_;
    bytes32 public constant AUTHORIZED_ROLE = keccak256("AUTHORIZED_ROLE");

    function safeMint(address, /*to*/ string memory /*uri*/ ) external returns (uint256) {
        return ++_tokenIdCounter;
    }

    function grantRole(bytes32, address account) external {
        hasRole_[account] = true;
    }

    function hasRole(bytes32, address account) external view returns (bool) {
        return hasRole_[account];
    }

    /*function AUTHORIZED_ROLE() external pure returns (bytes32) {
        return AUTHORIZED_ROLE;
    }*/

    function balanceOf(address) external pure returns (uint256) {
        return 0;
    }
}

contract MockReputation {
    mapping(address => uint256) private _reputation;
    mapping(address => bool) private _initialized;
    mapping(address => bool) public hasRole_;
    bytes32 public constant AUTHORIZED_ROLE = keccak256("AUTHORIZED_ROLE");

    function initReputationOf(address user) external {
        _reputation[user] = 1; // Reputación inicial estándar
        _initialized[user] = true;
    }

    function getReputationOf(address user) external view returns (uint256) {
        return _initialized[user] ? _reputation[user] : 1;
    }

    function updateReputation(address user, bool up) external {
        if (!_initialized[user]) {
            _reputation[user] = 1;
            _initialized[user] = true;
        }
        
        if (up) {
            _reputation[user] += 1;
        } else {
            if (_reputation[user] > 1) {
                _reputation[user] -= 1;
            }
        }
    }

    function grantRole(bytes32, address account) external {
        hasRole_[account] = true;
    }

    function hasRole(bytes32, address account) external view returns (bool) {
        return hasRole_[account];
    }

    /*function AUTHORIZED_ROLE() external pure returns (bytes32) {
        return AUTHORIZED_ROLE;
    }*/
}

contract MockWiraToken {
    mapping(address => uint256) private _balances;
    mapping(address => bool) public hasRole_;
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
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

    function grantRole(bytes32, address account) external {
        hasRole_[account] = true;
    }

    function hasRole(bytes32, address account) external view returns (bool) {
        return hasRole_[account];
    }

    /*function MINTER_ROLE() external pure returns (bytes32) {
        return MINTER_ROLE;
    }*/
}

contract AttestationOracleTestMin is Test {
    AttestationOracle public oracle;
    MockAttestationRecord public mockRecord;
    MockParticipation public mockParticipation;
    MockReputation public mockReputation;
    MockWiraToken public mockToken;

    address public admin;
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    address public jury1 = address(0x4);
    address public authority = address(0x5);

    uint256 public constant STAKE_AMOUNT = 100 ether;

    // Events para testing
    event RegisterRequested(address user, string uri);
    event AttestationCreated(string id, uint256 recordId);
    event Attested(uint256 recordId);
    event Resolved(string id, AttestationOracle.AttestationState closeState);

    function setUp() public {
        admin = address(this);

        // Crear mocks
        mockRecord = new MockAttestationRecord();
        mockParticipation = new MockParticipation();
        mockReputation = new MockReputation();
        mockToken = new MockWiraToken();

        // Desplegar oracle con 6 parámetros
        oracle = new AttestationOracle(
            admin,
            address(mockRecord),
            address(mockParticipation), // Parámetro que faltaba
            address(mockReputation),
            address(mockToken),
            STAKE_AMOUNT
        );

        // Configurar permisos
        mockRecord.grantRole(mockRecord.AUTHORIZED_ROLE(), address(oracle));
        mockParticipation.grantRole(mockParticipation.AUTHORIZED_ROLE(), address(oracle));
        mockReputation.grantRole(mockReputation.AUTHORIZED_ROLE(), address(oracle));
        mockToken.grantRole(mockToken.MINTER_ROLE(), address(oracle));

        // Configurar tiempos activos
        oracle.setActiveTime(block.timestamp, block.timestamp + 3600);

        // Registrar usuarios
        oracle.register(user1, false);
        oracle.register(user2, false);
        oracle.register(jury1, true);
        oracle.grantRole(oracle.AUTHORITY_ROLE(), authority);
    }

    function test_Constructor() public view {
        assertEq(oracle.stake(), STAKE_AMOUNT);
        assertTrue(oracle.hasRole(oracle.DEFAULT_ADMIN_ROLE(), admin));
        console.log("Stake configurado:", oracle.stake());
    }

    function test_RequestRegister() public {
        address newUser = address(0x6);

        vm.expectEmit(true, false, false, true);
        emit RegisterRequested(newUser, "QmTestHash123");

        vm.prank(newUser);
        oracle.requestRegister("QmTestHash123");
        console.log("Solicitud de registro para:", newUser);
    }

    function test_Register() public {
        address newUser = address(0x7);

        oracle.register(newUser, false);

        assertTrue(oracle.hasRole(oracle.USER_ROLE(), newUser));
        assertFalse(oracle.hasRole(oracle.JURY_ROLE(), newUser));
        console.log("Usuario registrado:", newUser);
    }

    function test_CreateAttestation() public {
        vm.expectEmit(false, false, false, true);
        emit AttestationCreated("fraud_case_001", 1);

        vm.prank(user1);
        uint256 recordId = oracle.createAttestation(
            "fraud_case_001", 
            "QmEvidenceHash", 
            "QmParticipationHash"
        );

        assertEq(recordId, 1);
        console.log("Atestiguacion creada con record ID:", recordId);

        // Verificar estado
        (AttestationOracle.AttestationState state, uint256 finalResult) = 
            oracle.getAttestationInfo("fraud_case_001");
        assertEq(uint256(state), 0); // OPEN
        assertEq(finalResult, 0);
    }

    function test_Attest() public {
        // Crear atestiguación
        vm.prank(user1);
        uint256 recordId = oracle.createAttestation(
            "vote_buying_case", 
            "QmEvidence1", 
            "QmParticipation1"
        );

        // User2 vota a favor
        vm.expectEmit(false, false, false, false);
        emit Attested(recordId);

        vm.prank(user2);
        uint256 result = oracle.attest(
            "vote_buying_case", 
            recordId, 
            true, 
            "", 
            "QmParticipation2"
        );

        assertEq(result, recordId);

        // Verificar voto
        vm.prank(user2);
        (uint256 votedRecord, bool choice) = oracle.getOptionAttested("vote_buying_case");
        assertEq(votedRecord, recordId);
        assertTrue(choice);
        console.log("Usr2 voto por record:", votedRecord, "con eleccion:", choice);
    }

    function test_Resolve() public {
        // Crear atestiguación con consenso
        vm.prank(user1);
        uint256 recordId = oracle.createAttestation(
            "consensus_case", 
            "QmStrongEvidence", 
            "QmParticipation1"
        );

        // Múltiples votos a favor
        vm.prank(user2);
        oracle.attest("consensus_case", recordId, true, "", "QmParticipation2");

        vm.prank(jury1);
        oracle.attest("consensus_case", recordId, true, "", "QmParticipation3");

        // Avanzar tiempo y resolver
        vm.warp(block.timestamp + 3601);

        vm.expectEmit(true, false, false, true);
        emit Resolved("consensus_case", AttestationOracle.AttestationState.CLOSED);

        oracle.resolve("consensus_case");

        // Verificar resolución
        (AttestationOracle.AttestationState state, uint256 finalResult) = 
            oracle.getAttestationInfo("consensus_case");
        assertEq(uint256(state), 3); // CLOSED
        assertEq(finalResult, recordId);
        console.log("Caso resuelto con estado:", uint256(state));
    }

    function test_VerifyAttestation() public {
        // Crear caso conflictivo
        vm.prank(user1);
        uint256 record1 = oracle.createAttestation(
            "disputed_case", 
            "QmEvidence1", 
            "QmParticipation1"
        );

        // Crear evidencia conflictiva
        vm.prank(user2);
        oracle.attest("disputed_case", 0, false, "QmCounterEvidence", "QmParticipation2");

        // Resolver -> debería ir a VERIFYING
        vm.warp(block.timestamp + 3601);
        oracle.resolve("disputed_case");

        // Verificar que está en estado VERIFYING
        (AttestationOracle.AttestationState state,) = oracle.getAttestationInfo("disputed_case");
        assertEq(uint256(state), 2); // VERIFYING

        // Authority verifica
        vm.prank(authority);
        oracle.verifyAttestation("disputed_case", record1);

        // Verificar resolución final
        (state,) = oracle.getAttestationInfo("disputed_case");
        assertEq(uint256(state), 3); // CLOSED
        console.log("Caso verificado por autoridad");
    }

    function test_SetActiveTime() public {
        uint256 newStart = block.timestamp + 7200; // +2 horas
        uint256 newEnd = block.timestamp + 14400;   // +4 horas

        oracle.setActiveTime(newStart, newEnd);

        assertEq(oracle.attestStart(), newStart);
        assertEq(oracle.attestEnd(), newEnd);

        // Verificar que falla cuando está inactivo
        vm.expectRevert("Oracle inactive");
        vm.prank(user1);
        oracle.createAttestation("inactive_test", "QmTest", "QmTest");

        console.log("Tiempos activos actualizados");
    }

    function test_GetWeighedAttestations() public {
        vm.prank(user1);
        uint256 recordId = oracle.createAttestation(
            "weight_test", 
            "QmEvidence", 
            "QmParticipation1"
        );

        // Verificar peso inicial
        assertEq(oracle.getWeighedAttestations("weight_test", recordId), 1);

        vm.prank(user2);
        oracle.attest("weight_test", recordId, true, "", "QmParticipation2");

        // Verificar peso combinado
        assertEq(oracle.getWeighedAttestations("weight_test", recordId), 2);
        console.log("Peso total de atestiguaciones:", oracle.getWeighedAttestations("weight_test", recordId));
    }

    function test_ViewAttestationResult() public {
        vm.prank(user1);
        uint256 record1 = oracle.createAttestation(
            "result_test", 
            "QmEvidence1", 
            "QmParticipation1"
        );

        vm.prank(user2);
        oracle.attest("result_test", record1, true, "", "QmParticipation2");

        vm.prank(jury1);
        oracle.attest("result_test", record1, true, "", "QmParticipation3");

        // Resolver para calcular resultados
        vm.warp(block.timestamp + 3601);
        oracle.resolve("result_test");

        (uint256 mostAttested, uint256 mostJuryAttested) = 
            oracle.viewAttestationResult("result_test");
        
        assertEq(mostAttested, record1);
        assertEq(mostJuryAttested, record1);
        console.log("Record mas atestiguado:", mostAttested);
    }
}