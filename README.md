## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```

## Technical Limits

- Is not possible to have the same oracle with shared state across different networks.
- You can obtain the total reputation as the sum of users’ reputations across different networks. However, to reduce a user’s total reputation, the contracts must handle negative reputation.
- While it is possible to migrate an oracle with its data to a new network, there are no tools to do this easily; it would be a hard manual task.

According to OpenZeppelin’s documentation, the following limits apply:
- You cannot use selfdestruct or delegatecall in contracts.
- You cannot change the order or type of variables or remove variables; you can add them, but only at the end of the variable list.
- You can change a variable’s name while preserving its value.
- You cannot change the order of inheritance.
- You cannot add variables to parent contracts unless a gap has been reserved:
```
contract Base {
    uint256 base1;
    uint256 base2;
    uint256[48] __gap;
}
```