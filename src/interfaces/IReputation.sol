// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IReputation {
  function getReputationOf(address user) external view returns(uint256);
  function updateReputation(address user, bool up) external;
}