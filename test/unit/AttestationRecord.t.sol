// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AttestationRecord} from "../../src/AttestationRecord.sol";

contract TestAttestationRecord is Test {
    AttestationRecord attestation;
    address owner = makeAddr("owner");
    address authorized = makeAddr("authorized");
    address recipient = makeAddr("recipient");

    function setUp() public {
        vm.startPrank(owner);
        attestation = new AttestationRecord(owner);
        attestation.grantRole(attestation.AUTHORIZED_ROLE(), authorized);
        vm.stopPrank();
    }

    function testSafeMint() public {
        vm.prank(authorized);
        uint256 tokenId = attestation.safeMint(recipient, "test-uri");
        assertEq(tokenId, 1);
        assertEq(attestation.ownerOf(1), recipient);
        assertEq(attestation.tokenURI(1), "test-uri");
    }

    function testTokenIdNotOverflow() public {
        // Set _nextTokenId to type(uint256).max - 1
        vm.store(address(attestation), bytes32(uint256(12)), bytes32(type(uint256).max - 1));
        
        // Mint should succeed
        vm.prank(authorized);
        uint256 tokenId = attestation.safeMint(recipient, "test-uri");
        assertEq(tokenId, type(uint256).max);
        
        // Next mint should revert due to overflow
        vm.prank(authorized);
        vm.expectRevert("Token ID overflow");
        attestation.safeMint(recipient, "test-uri");
    }
}