pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {Reputation} from "../../src/Reputation.sol";
import { UnsafeUpgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract ReputationTest is Test {
    Reputation reputation;
    address initialOwner = makeAddr("initialOwner");

    function initReputation() internal {
        address implementation = address(new Reputation());
        address proxy = UnsafeUpgrades.deployUUPSProxy(
            implementation,
            abi.encodeCall(Reputation.initialize, (initialOwner))
        );
        reputation = Reputation(proxy);
    }

    function test_initializeReputation() public {
        initReputation();

        // Verify that the initial owner has the DEFAULT_ADMIN_ROLE
        bytes32 adminRole = reputation.DEFAULT_ADMIN_ROLE();
        assertTrue(reputation.hasRole(adminRole, initialOwner));
    }

    function test_reinitializeFails() public {
        initReputation();

        // Attempt to re-initialize should fail
        vm.expectRevert("InvalidInitialization()");
        reputation.initialize(initialOwner);
    }

    function test_initReputation_onlyCaller() public {
        initReputation();

        address[] memory users = new address[](3);
        users[0] = makeAddr("user");
        users[1] = makeAddr("user1");
        users[2] = makeAddr("user2");

        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];

            // Caller initializes their own reputation
            vm.startPrank(user);
            reputation.initReputation();
            uint256 rep = reputation.getReputation();
            vm.stopPrank();

            assertEq(rep, 1);
        }
    }

    function test_initReputationOf_authorized() public {
        initReputation();

        address authorized = makeAddr("authorized");
        address user = makeAddr("user");

        // Grant AUTHORIZED_ROLE to an address
        vm.startPrank(initialOwner);
        reputation.grantRole(reputation.AUTHORIZED_ROLE(), authorized);
        vm.stopPrank();

        // Authorized address initializes reputation
        vm.prank(authorized);
        reputation.initReputationOf(user);
        vm.prank(user);
        uint256 rep = reputation.getReputation();
        assertEq(rep, 1);
    }

    function test_initReputationOf_unauthorizedFails() public {
        initReputation();

        address unauthorized = makeAddr("unauthorized");
        address user = makeAddr("user");

        // Unauthorized address attempts to initialize reputation
        vm.startPrank(unauthorized);
        vm.expectRevert();
        reputation.initReputationOf(user);
        vm.stopPrank();
    }

    function test_getReputation_onlyCaller() public {
        initReputation();

        address user = makeAddr("user");

        // Get reputation only works for the caller
        vm.startPrank(user);
        reputation.initReputation();
        uint256 rep = reputation.getReputation();
        vm.stopPrank();
        assertEq(rep, 1);

        address other = makeAddr("other");
        vm.prank(other);
        uint256 otherRep = reputation.getReputation();
        assertEq(otherRep, 0);
    }

    function test_getReputationOf_authorized() public {
        initReputation();

        address authorized = makeAddr("authorized");
        address user = makeAddr("user");

        // Grant AUTHORIZED_ROLE to an address
        vm.startPrank(initialOwner);
        reputation.grantRole(reputation.AUTHORIZED_ROLE(), authorized);
        vm.stopPrank();

        // Initialize user's reputation
        vm.prank(user);
        reputation.initReputation();

        // Authorized address gets user's reputation
        vm.prank(authorized);
        uint256 rep = reputation.getReputationOf(user);
        assertEq(rep, 1);
    }

    function test_getReputationOf_unauthorizedFails() public {
        initReputation();

        address unauthorized = makeAddr("unauthorized");
        address user = makeAddr("user");

        // Initialize user's reputation
        vm.prank(user);
        reputation.initReputation();

        // Unauthorized address attempts to get user's reputation
        vm.prank(unauthorized);
        vm.expectRevert();
        reputation.getReputationOf(user);

        // User itself cannot get its own reputation via getReputationOf
        vm.prank(user);
        vm.expectRevert();
        reputation.getReputationOf(user);
    }

    function test_updateReputation_authorized() public {
        initReputation();

        address authorized = makeAddr("authorized");
        address user = makeAddr("user");

        // Grant AUTHORIZED_ROLE to an address
        vm.startPrank(initialOwner);
        reputation.grantRole(reputation.AUTHORIZED_ROLE(), authorized);
        vm.stopPrank();

        // Initialize user's reputation
        vm.prank(user);
        reputation.initReputation();

        // Authorized address updates user's reputation
        vm.startPrank(authorized);
        reputation.updateReputation(user, true); // Increase reputation
        uint256 rep = reputation.getReputationOf(user);
        vm.stopPrank();
        assertEq(rep, 2);

        vm.startPrank(authorized);
        reputation.updateReputation(user, false); // Decrease reputation
        rep = reputation.getReputationOf(user);
        vm.stopPrank();
        assertEq(rep, 1);
    }

    function test_updateReputation_unauthorizedFails() public {
        initReputation();

        address unauthorized = makeAddr("unauthorized");
        address user = makeAddr("user");

        // Initialize user's reputation
        vm.prank(user);
        reputation.initReputation();

        // Unauthorized address attempts to update user's reputation
        vm.startPrank(unauthorized);
        vm.expectRevert();
        reputation.updateReputation(user, true);
        vm.stopPrank();

        // User itself cannot update its own reputation
        vm.startPrank(user);
        vm.expectRevert();
        reputation.updateReputation(user, true);
        vm.stopPrank();
    }

    function test_updateReputation_withZero() public {
        initReputation();

        address authorized = makeAddr("authorized");
        address user = makeAddr("user");

        // Grant AUTHORIZED_ROLE to an address
        vm.startPrank(initialOwner);
        reputation.grantRole(reputation.AUTHORIZED_ROLE(), authorized);
        vm.stopPrank();

        // Initialize user's reputation
        vm.prank(user);
        reputation.initReputation();

        // Authorized address updates user's reputation
        vm.startPrank(authorized);
        reputation.updateReputation(user, false); // Decrease reputation
        uint256 rep = reputation.getReputationOf(user);
        vm.stopPrank();
        assertEq(rep, 0);

        // Attempt to decrease reputation below zero
        vm.startPrank(authorized);
        reputation.updateReputation(user, false); // Decrease reputation
        rep = reputation.getReputationOf(user);
        vm.stopPrank();
        assertEq(rep, 0); // Reputation should not go below zero
    }
}