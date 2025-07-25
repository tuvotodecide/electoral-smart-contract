// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IAttestationRecord is IERC721 {
    function safeMint(address to, string memory uri) external returns (uint256);
}
