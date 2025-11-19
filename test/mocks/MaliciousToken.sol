pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AttestationOracle} from "../../src/AttestationOracle.sol";

// Malicious token to simulate reentrancy attack
contract MaliciousToken is ERC20 {
    AttestationOracle public oracle;
    string public reentryId;
    bool public attemptReentry;

    constructor(address recipient) ERC20("MaliciousToken", "MTK") {
        _mint(recipient, 1000000e18);
    }

    function setReentrancyData(address _oracle, string memory _reentryId) external {
        oracle = AttestationOracle(_oracle);
        reentryId = _reentryId;
        attemptReentry = true;
    }

    function transfer(address to, uint256 value) public override returns (bool) {
        address owner = _msgSender();
        _transfer(owner, to, value);
        // Attempt reentrancy if flag is set
        if (attemptReentry) {
            attemptReentry = false; // Prevent infinite loop
            oracle.resolve(reentryId);
        }
        return true;
    }
}