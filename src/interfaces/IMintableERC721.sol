// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

<<<<<<< HEAD:src/interfaces/IMintableERC721.sol
interface IMintableERC721 is IERC721 {
  function safeMint(address to, string memory uri)
    external
    returns (uint256);
}
=======
interface IAttestationRecord is IERC721 {
    function safeMint(address to, string memory uri) external returns (uint256);
}
>>>>>>> origin/ronaldo-smart:src/interfaces/IAttestationRecord.sol
