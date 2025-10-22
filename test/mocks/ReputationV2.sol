// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// @custom:oz-upgrades-from src/Reputation.sol:Reputation
contract ReputationV2 is Initializable, UUPSUpgradeable, OwnableUpgradeable, AccessControlUpgradeable {
  bytes32 public constant AUTHORIZED_ROLE = keccak256("AUTHORIZED");

  mapping(address => uint256) private reputations;
  bool public active;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(address _initialOwner) public initializer {
    __AccessControl_init();
    __Ownable_init(_initialOwner);
    __UUPSUpgradeable_init();
    _grantRole(DEFAULT_ADMIN_ROLE, _initialOwner);
  }

  function setActive(bool _active) external onlyRole(DEFAULT_ADMIN_ROLE) {
    active = _active;
  }

  function getReputation() external view returns(uint256) {
    return reputations[msg.sender];
  }

  function initReputation() external {
    require(reputations[msg.sender] == 0, "Reputation already initialized");
    reputations[msg.sender] = 1;
  }

  function initReputationOf(address to) external onlyRole(AUTHORIZED_ROLE) {
    require(reputations[to] == 0, "Reputation already initialized");
    reputations[to] = 1;
  }

  function getReputationOf(address user) external view onlyRole(AUTHORIZED_ROLE) returns(uint256) {
    return reputations[user];
  }

  function updateReputation(address user, bool up) external onlyRole(AUTHORIZED_ROLE) {
    if(up) {
      reputations[user] += 2;
    } else if(reputations[user] > 0) {
      reputations[user]--;
    }
  }

  function removeReputationOf(address user) external onlyRole(AUTHORIZED_ROLE) {
    delete reputations[user];
  }

  function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}