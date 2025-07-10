// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721, IERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract AttestationRecord is ERC721, ERC721Enumerable, ERC721URIStorage, AccessControl {
  bytes32 public constant AUTHORIZED_ROLE = keccak256("AUTHORIZED");
  uint256 private _nextTokenId;

  constructor(address initialOwner)
    ERC721("AttestationRecord", "ART")
  {
    _grantRole(DEFAULT_ADMIN_ROLE, initialOwner);
  }

  function safeMint(address to, string memory uri)
    public
    onlyRole(AUTHORIZED_ROLE)
    returns (uint256)
  {
    uint256 tokenId = ++_nextTokenId;
    _safeMint(to, tokenId);
    _setTokenURI(tokenId, uri);
    return tokenId;
  }

  // Make token non-transferrable
  function transferFrom(address from, address to, uint256 tokenId) public override(ERC721, IERC721) onlyRole(DEFAULT_ADMIN_ROLE) {
    if (to == address(0)) {
        revert ERC721InvalidReceiver(address(0));
    }
    // Setting an "auth" arguments enables the `_isAuthorized` check which verifies that the token exists
    // (from != 0). Therefore, it is not needed to verify that the return value is not 0 here.
    address previousOwner = _update(to, tokenId, _msgSender());
    if (previousOwner != from) {
        revert ERC721IncorrectOwner(from, tokenId, previousOwner);
    }
  }
  
  // The following functions are overrides required by Solidity.

  function _update(address to, uint256 tokenId, address auth)
    internal
    override(ERC721, ERC721Enumerable)
    returns (address)
  {
    return super._update(to, tokenId, auth);
  }

  function _increaseBalance(address account, uint128 value)
    internal
    override(ERC721, ERC721Enumerable)
  {
    super._increaseBalance(account, value);
  }

  function tokenURI(uint256 tokenId)
    public
    view
    override(ERC721, ERC721URIStorage)
    returns (string memory)
  {
    return super.tokenURI(tokenId);
  }

  function supportsInterface(bytes4 interfaceId)
    public
    view
    override(ERC721, ERC721Enumerable, ERC721URIStorage, AccessControl)
    returns (bool)
  {
    return super.supportsInterface(interfaceId);
  }
}
