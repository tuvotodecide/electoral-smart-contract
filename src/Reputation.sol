// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Authorizable} from "./Authorizable.sol";

contract Reputation is Authorizable {
  mapping(address => uint256) private reputations;

  constructor(address initialOwner) Authorizable(initialOwner) { }

  function getReputation() external view returns(uint256) {
    return reputations[msg.sender];
  }

  function getReputationOf(address user) external view onlyAuthorized returns(uint256) {
    return reputations[user];
  }

  function updateReputation(address user, bool up) external onlyAuthorized {
    if(up) {
      reputations[user]++;
    } else if(reputations[user] > 0) {
      reputations[user]--;
    }
  }
}