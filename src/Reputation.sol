// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract Reputation is AccessControl {
  bytes32 constant AUTHORIZED_ROLE = keccak256("AUTHORIZED");

  mapping(address => uint256) private reputations;

  constructor(address initialOwner) {
    _grantRole(DEFAULT_ADMIN_ROLE, initialOwner);
  }

  function getReputation() external view returns(uint256) {
    return reputations[msg.sender];
  }

  function initReputation() external {
    reputations[msg.sender] = 1;
  }

  function getReputationOf(address user) external view onlyRole(AUTHORIZED_ROLE) returns(uint256) {
    return reputations[user];
  }

  function updateReputation(address user, bool up) external onlyRole(AUTHORIZED_ROLE) {
    if(up) {
      reputations[user]++;
    } else if(reputations[user] > 0) {
      reputations[user]--;
    }
  }
}