## Foundry - Testing of SmartContracts

using step to step, basic line commands for interaction foundry 

## Usage

### Build - test - format - Gas - snapshots - anvil - deploy 

```shell
$ forge build

$ forge test

$ forge fmt

$ forge snapshot

$ anvil

$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>

$ cast <subcommand>

$ forge --help
$ anvil --help
$ cast --help
```


Testing Aplicado: 

implementacion: 

**-> AttestationOracleMin.t.sol**

```
[⠊] Compiling...
No files changed, compilation skipped

Ran 8 tests for test/simulation/AttestationOracleMin.t.sol:AttestationOracleTestMin
[PASS] test_Attest() (gas: 481813)
Logs:
  Attestation ID: 0
  Attestation User1: 0x0000000000000000000000000000000000000002  vote Record: 1
  Attestation User2: 0x0000000000000000000000000000000000000003 Vote: true

Traces:
  [481813] AttestationOracleTestMin::test_Attest()
    ├─ [0] VM::prank(SHA-256: [0x0000000000000000000000000000000000000002])
    │   └─ ← [Return]
    ├─ [350191] AttestationOracle::createAttestation("ipfs://test-hash")
    │   ├─ [23838] MockAttestationRecord::safeMint(SHA-256: [0x0000000000000000000000000000000000000002], "ipfs://test-hash")
    │   │   └─ ← [Return] 1
    │   ├─ [3130] MockReputation::getReputationOf(SHA-256: [0x0000000000000000000000000000000000000002]) [staticcall]
    │   │   └─ ← [Return] 100
    │   ├─ [46369] MockWiraToken::mint(AttestationOracle: [0x5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A9], 100000000000000000000 [1e20])
    │   │   └─ ← [Return]
    │   ├─ emit AttestationCreated(id: 0, recordId: 1)
    │   └─ ← [Return] 0, 1
    ├─ [0] VM::expectEmit()
    │   └─ ← [Return]
    ├─ emit Attested()
    ├─ [0] console::log("Attestation ID:", 0) [staticcall]
    │   └─ ← [Stop]
    ├─ [0] VM::prank(RIPEMD-160: [0x0000000000000000000000000000000000000003])
    │   └─ ← [Return]
    ├─ [93773] AttestationOracle::attest(0, 1, true, "")
    │   ├─ [3130] MockReputation::getReputationOf(RIPEMD-160: [0x0000000000000000000000000000000000000003]) [staticcall]
    │   │   └─ ← [Return] 100
    │   ├─ [2569] MockWiraToken::mint(AttestationOracle: [0x5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A9], 100000000000000000000 [1e20])
    │   │   └─ ← [Return]
    │   ├─ emit Attested()
    │   └─ ← [Return]
    ├─ [0] VM::prank(RIPEMD-160: [0x0000000000000000000000000000000000000003])
    │   └─ ← [Return]
    ├─ [2563] AttestationOracle::getOptionAttested(0) [staticcall]
    │   └─ ← [Return] 1, true
    ├─ [0] VM::assertEq(1, 1) [staticcall]
    │   └─ ← [Return]
    ├─ [0] VM::assertTrue(true) [staticcall]
    │   └─ ← [Return]
    ├─ [0] console::log("Attestation User1:", SHA-256: [0x0000000000000000000000000000000000000002], " vote Record:", 1) [staticcall]
    │   └─ ← [Stop]
    ├─ [0] console::log("Attestation User2:", RIPEMD-160: [0x0000000000000000000000000000000000000003], "Vote:", true) [staticcall]
    │   └─ ← [Stop]
    └─ ← [Return]

[PASS] test_Constructor() (gas: 39895)
Logs:
  stake:  100000000000000000000
  totalAttestations:  0

Traces:
  [39895] AttestationOracleTestMin::test_Constructor()
    ├─ [2862] AttestationOracle::stake() [staticcall]
    │   └─ ← [Return] 100000000000000000000 [1e20]
    ├─ [0] VM::assertEq(100000000000000000000 [1e20], 100000000000000000000 [1e20]) [staticcall]
    │   └─ ← [Return]
    ├─ [2994] AttestationOracle::totalAttestations() [staticcall]
    │   └─ ← [Return] 0
    ├─ [0] VM::assertEq(0, 0) [staticcall]
    │   └─ ← [Return]
    ├─ [1010] AttestationOracle::DEFAULT_ADMIN_ROLE() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000000
    ├─ [3868] AttestationOracle::hasRole(0x0000000000000000000000000000000000000000000000000000000000000000, AttestationOracleTestMin: [0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496]) [staticcall]
    │   └─ ← [Return] true
    ├─ [0] VM::assertTrue(true) [staticcall]
    │   └─ ← [Return]
    ├─ [862] AttestationOracle::stake() [staticcall]
    │   └─ ← [Return] 100000000000000000000 [1e20]
    ├─ [0] console::log("stake: ", 100000000000000000000 [1e20]) [staticcall]
    │   └─ ← [Stop]
    ├─ [994] AttestationOracle::totalAttestations() [staticcall]
    │   └─ ← [Return] 0
    ├─ [0] console::log("totalAttestations: ", 0) [staticcall]
    │   └─ ← [Stop]
    └─ ← [Return]

[PASS] test_CreateAttestation() (gas: 394022)
Logs:
  Creating attestation with URI: ipfs://test-hash
  Attestation created ID: 0
  Attestation Record ID: 1
  Attestation result: 0

Traces:
  [394022] AttestationOracleTestMin::test_CreateAttestation()
    ├─ [0] console::log("Creating attestation with URI:", "ipfs://test-hash") [staticcall]
    │   └─ ← [Stop]
    ├─ [0] VM::expectEmit(true, true, false, true)
    │   └─ ← [Return]
    ├─ emit AttestationCreated(id: 0, recordId: 1)
    ├─ [0] VM::prank(SHA-256: [0x0000000000000000000000000000000000000002])
    │   └─ ← [Return]
    ├─ [350191] AttestationOracle::createAttestation("ipfs://test-hash")
    │   ├─ [23838] MockAttestationRecord::safeMint(SHA-256: [0x0000000000000000000000000000000000000002], "ipfs://test-hash")
    │   │   └─ ← [Return] 1
    │   ├─ [3130] MockReputation::getReputationOf(SHA-256: [0x0000000000000000000000000000000000000002]) [staticcall]
    │   │   └─ ← [Return] 100
    │   ├─ [46369] MockWiraToken::mint(AttestationOracle: [0x5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A9], 100000000000000000000 [1e20])
    │   │   └─ ← [Return]
    │   ├─ emit AttestationCreated(id: 0, recordId: 1)
    │   └─ ← [Return] 0, 1
    ├─ [0] VM::assertEq(0, 0) [staticcall]
    │   └─ ← [Return]
    ├─ [0] VM::assertEq(1, 1) [staticcall]
    │   └─ ← [Return]
    ├─ [994] AttestationOracle::totalAttestations() [staticcall]
    │   └─ ← [Return] 1
    ├─ [0] VM::assertEq(1, 1) [staticcall]
    │   └─ ← [Return]
    ├─ [0] console::log("Attestation created ID:", 0) [staticcall]
    │   └─ ← [Stop]
    ├─ [0] console::log("Attestation Record ID:", 1) [staticcall]
    │   └─ ← [Stop]
    ├─ [5855] AttestationOracle::getAttestationInfo(0) [staticcall]
    │   └─ ← [Return] 0, 0
    ├─ [0] VM::assertEq(0, 0) [staticcall]
    │   └─ ← [Return]
    ├─ [0] VM::assertEq(0, 0) [staticcall]
    │   └─ ← [Return]
    ├─ [0] console::log("Attestation result:", 0) [staticcall]
    │   └─ ← [Stop]
    └─ ← [Return]

[PASS] test_Register() (gas: 107685)
Traces:
  [107685] AttestationOracleTestMin::test_Register()
    ├─ [0] VM::prank(AttestationOracleTestMin: [0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496])
    │   └─ ← [Return]
    ├─ [79812] AttestationOracle::register(ECMul: [0x0000000000000000000000000000000000000007], false)
    │   ├─ emit RoleGranted(role: 0x2db9fd3d099848027c2383d0a083396f6c41510d7acfd92adc99b6cffcf31e96, account: ECMul: [0x0000000000000000000000000000000000000007], sender: AttestationOracleTestMin: [0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496])
    │   ├─ [45869] MockReputation::initReputationOf(ECMul: [0x0000000000000000000000000000000000000007])
    │   │   └─ ← [Return]
    │   └─ ← [Return]
    ├─ [455] AttestationOracle::USER_ROLE() [staticcall]
    │   └─ ← [Return] 0x2db9fd3d099848027c2383d0a083396f6c41510d7acfd92adc99b6cffcf31e96
    ├─ [1868] AttestationOracle::hasRole(0x2db9fd3d099848027c2383d0a083396f6c41510d7acfd92adc99b6cffcf31e96, ECMul: [0x0000000000000000000000000000000000000007]) [staticcall]
    │   └─ ← [Return] true
    ├─ [0] VM::assertTrue(true) [staticcall]
    │   └─ ← [Return]
    ├─ [1045] AttestationOracle::JURY_ROLE() [staticcall]
    │   └─ ← [Return] 0x9f70476b4563c57c3056cc4e8dffc8025828c99ea7a458e33c1502f84b53cc94
    ├─ [3868] AttestationOracle::hasRole(0x9f70476b4563c57c3056cc4e8dffc8025828c99ea7a458e33c1502f84b53cc94, ECMul: [0x0000000000000000000000000000000000000007]) [staticcall]
    │   └─ ← [Return] false
    ├─ [0] VM::assertFalse(false) [staticcall]
    │   └─ ← [Return]
    └─ ← [Return]

[PASS] test_RequestRegister() (gas: 32052)
Logs:
  Request register:  0x0000000000000000000000000000000000000006

Traces:
  [32052] AttestationOracleTestMin::test_RequestRegister()
    ├─ [0] VM::expectEmit(true, false, false, true)
    │   └─ ← [Return]
    ├─ emit RegisterRequested(user: ECAdd: [0x0000000000000000000000000000000000000006], uri: "test-uri")
    ├─ [0] VM::prank(ECAdd: [0x0000000000000000000000000000000000000006])
    │   └─ ← [Return]
    ├─ [14197] AttestationOracle::requestRegister("test-uri")
    │   ├─ emit RegisterRequested(user: ECAdd: [0x0000000000000000000000000000000000000006], uri: "test-uri")
    │   └─ ← [Return]
    ├─ [0] console::log("Request register: ", ECAdd: [0x0000000000000000000000000000000000000006]) [staticcall]
    │   └─ ← [Stop]
    └─ ← [Return]

[PASS] test_Resolve() (gas: 772068)
Traces:
  [791968] AttestationOracleTestMin::test_Resolve()
    ├─ [0] VM::prank(SHA-256: [0x0000000000000000000000000000000000000002])
    │   └─ ← [Return]
    ├─ [350191] AttestationOracle::createAttestation("ipfs://test-hash")
    │   ├─ [23838] MockAttestationRecord::safeMint(SHA-256: [0x0000000000000000000000000000000000000002], "ipfs://test-hash")
    │   │   └─ ← [Return] 1
    │   ├─ [3130] MockReputation::getReputationOf(SHA-256: [0x0000000000000000000000000000000000000002]) [staticcall]
    │   │   └─ ← [Return] 100
    │   ├─ [46369] MockWiraToken::mint(AttestationOracle: [0x5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A9], 100000000000000000000 [1e20])
    │   │   └─ ← [Return]
    │   ├─ emit AttestationCreated(id: 0, recordId: 1)
    │   └─ ← [Return] 0, 1
    ├─ [0] VM::prank(RIPEMD-160: [0x0000000000000000000000000000000000000003])
    │   └─ ← [Return]
    ├─ [93773] AttestationOracle::attest(0, 1, true, "")
    │   ├─ [3130] MockReputation::getReputationOf(RIPEMD-160: [0x0000000000000000000000000000000000000003]) [staticcall]
    │   │   └─ ← [Return] 100
    │   ├─ [2569] MockWiraToken::mint(AttestationOracle: [0x5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A9], 100000000000000000000 [1e20])
    │   │   └─ ← [Return]
    │   ├─ emit Attested()
    │   └─ ← [Return]
    ├─ [0] VM::prank(Identity: [0x0000000000000000000000000000000000000004])
    │   └─ ← [Return]
    ├─ [158285] AttestationOracle::attest(0, 1, true, "")
    │   ├─ [3130] MockReputation::getReputationOf(Identity: [0x0000000000000000000000000000000000000004]) [staticcall]
    │   │   └─ ← [Return] 100
    │   ├─ [2569] MockWiraToken::mint(AttestationOracle: [0x5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A9], 100000000000000000000 [1e20])
    │   │   └─ ← [Return]
    │   ├─ emit Attested()
    │   └─ ← [Return]
    ├─ [0] VM::warp(14402 [1.44e4])
    │   └─ ← [Return]
    ├─ [157901] AttestationOracle::resolve(0)
    │   ├─ [4690] MockReputation::updateReputation(SHA-256: [0x0000000000000000000000000000000000000002], true)
    │   │   └─ ← [Return]
    │   ├─ [25606] MockWiraToken::transfer(SHA-256: [0x0000000000000000000000000000000000000002], 100000000000000000000 [1e20])
    │   │   └─ ← [Return] true
    │   ├─ [4690] MockReputation::updateReputation(RIPEMD-160: [0x0000000000000000000000000000000000000003], true)
    │   │   └─ ← [Return]
    │   ├─ [25606] MockWiraToken::transfer(RIPEMD-160: [0x0000000000000000000000000000000000000003], 100000000000000000000 [1e20])
    │   │   └─ ← [Return] true
    │   ├─ [4690] MockReputation::updateReputation(Identity: [0x0000000000000000000000000000000000000004], true)
    │   │   └─ ← [Return]
    │   ├─ [25606] MockWiraToken::transfer(Identity: [0x0000000000000000000000000000000000000004], 100000000000000000000 [1e20])
    │   │   └─ ← [Return] true
    │   └─ ← [Return]
    ├─ [1855] AttestationOracle::getAttestationInfo(0) [staticcall]
    │   └─ ← [Return] 3, 1
    ├─ [0] VM::assertTrue(true) [staticcall]
    │   └─ ← [Return]
    ├─ [0] VM::assertEq(1, 1) [staticcall]
    │   └─ ← [Return]
    └─ ← [Return]

[PASS] test_SetActiveTime() (gas: 50900)
Logs:
  Current time: 3603

Traces:
  [50900] AttestationOracleTestMin::test_SetActiveTime()
    ├─ [0] VM::prank(AttestationOracleTestMin: [0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496])
    │   └─ ← [Return]
    ├─ [14407] AttestationOracle::setActiveTime(21602 [2.16e4], 39602 [3.96e4])
    │   └─ ← [Return]
    ├─ [1192] AttestationOracle::attestStart() [staticcall]
    │   └─ ← [Return] 21602 [2.16e4]
    ├─ [0] VM::assertEq(21602 [2.16e4], 21602 [2.16e4]) [staticcall]
    │   └─ ← [Return]
    ├─ [1236] AttestationOracle::attestEnd() [staticcall]
    │   └─ ← [Return] 39602 [3.96e4]
    ├─ [0] VM::assertEq(39602 [3.96e4], 39602 [3.96e4]) [staticcall]
    │   └─ ← [Return]
    ├─ [0] VM::warp(3603)
    │   └─ ← [Return]
    ├─ [0] console::log("Current time:", 3603) [staticcall]
    │   └─ ← [Stop]
    ├─ [0] VM::expectRevert(custom error 0xf28dceb3:  Oracle inactive)
    │   └─ ← [Return]
    ├─ [0] VM::prank(SHA-256: [0x0000000000000000000000000000000000000002])
    │   └─ ← [Return]
    ├─ [4346] AttestationOracle::createAttestation("test")
    │   └─ ← [Revert] Oracle inactive
    └─ ← [Return]

[PASS] test_VerifyAttestation() (gas: 555739)
Logs:
  3601 10801
  0x0000000000000000000000000000000000000005

Traces:
  [595539] AttestationOracleTestMin::test_VerifyAttestation()
    ├─ [0] VM::prank(SHA-256: [0x0000000000000000000000000000000000000002])
    │   └─ ← [Return]
    ├─ [350191] AttestationOracle::createAttestation("ipfs://test-hash")
    │   ├─ [23838] MockAttestationRecord::safeMint(SHA-256: [0x0000000000000000000000000000000000000002], "ipfs://test-hash")
    │   │   └─ ← [Return] 1
    │   ├─ [3130] MockReputation::getReputationOf(SHA-256: [0x0000000000000000000000000000000000000002]) [staticcall]
    │   │   └─ ← [Return] 100
    │   ├─ [46369] MockWiraToken::mint(AttestationOracle: [0x5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A9], 100000000000000000000 [1e20])
    │   │   └─ ← [Return]
    │   ├─ emit AttestationCreated(id: 0, recordId: 1)
    │   └─ ← [Return] 0, 1
    ├─ [0] VM::prank(RIPEMD-160: [0x0000000000000000000000000000000000000003])
    │   └─ ← [Return]
    ├─ [93786] AttestationOracle::attest(0, 1, false, "")
    │   ├─ [3130] MockReputation::getReputationOf(RIPEMD-160: [0x0000000000000000000000000000000000000003]) [staticcall]
    │   │   └─ ← [Return] 100
    │   ├─ [2569] MockWiraToken::mint(AttestationOracle: [0x5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A9], 100000000000000000000 [1e20])
    │   │   └─ ← [Return]
    │   ├─ emit Attested()
    │   └─ ← [Return]
    ├─ [1192] AttestationOracle::attestStart() [staticcall]
    │   └─ ← [Return] 3601
    ├─ [1236] AttestationOracle::attestEnd() [staticcall]
    │   └─ ← [Return] 10801 [1.08e4]
    ├─ [0] console::log(3601, 10801 [1.08e4]) [staticcall]
    │   └─ ← [Stop]
    ├─ [0] VM::warp(14402 [1.44e4])
    │   └─ ← [Return]
    ├─ [28495] AttestationOracle::resolve(0)
    │   ├─ emit InitVerification(id: 0)
    │   └─ ← [Return]
    ├─ [3855] AttestationOracle::getAttestationInfo(0) [staticcall]
    │   └─ ← [Return] 2, 0
    ├─ [0] VM::assertEq(2, 2) [staticcall]
    │   └─ ← [Return]
    ├─ [0] VM::prank(ModExp: [0x0000000000000000000000000000000000000005])
    │   └─ ← [Return]
    ├─ [77257] AttestationOracle::verifyAttestation(0, 1)
    │   ├─ [4690] MockReputation::updateReputation(SHA-256: [0x0000000000000000000000000000000000000002], true)
    │   │   └─ ← [Return]
    │   ├─ [25606] MockWiraToken::transfer(SHA-256: [0x0000000000000000000000000000000000000002], 200000000000000000000 [2e20])
    │   │   └─ ← [Return] true
    │   ├─ [5407] MockReputation::updateReputation(RIPEMD-160: [0x0000000000000000000000000000000000000003], false)
    │   │   └─ ← [Return]
    │   └─ ← [Return]
    ├─ [0] console::log(ModExp: [0x0000000000000000000000000000000000000005]) [staticcall]
    │   └─ ← [Stop]
    ├─ [1855] AttestationOracle::getAttestationInfo(0) [staticcall]
    │   └─ ← [Return] 3, 1
    ├─ [0] VM::assertEq(3, 3) [staticcall]
    │   └─ ← [Return]
    └─ ← [Return]
```