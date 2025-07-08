// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract Authorizable is Ownable {
  mapping(address => bool) private authorizations;
  event Authorized(address to);

  modifier onlyAuthorized {
    require(authorizations[msg.sender], "Only Authorized");
    _;
  }

  constructor(address initialOwner) Ownable(initialOwner) {
    _setAuthorized(initialOwner, true);
  }

  function setAuthorized(address to, bool authorized) public onlyOwner {
    _setAuthorized(to, authorized);
    emit Authorized(to);
  }

  function _setAuthorized(address to, bool authorized) private {
    authorizations[to] = authorized;
  }
}