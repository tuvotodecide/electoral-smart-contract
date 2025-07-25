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

```compilacion
[⠊] Compiling...
No files changed, compilation skipped

Ran 8 tests for test/simulation/AttestationOracleMin.t.sol:AttestationOracleTestMin
[PASS] test_Attest() (gas: 481813)

```