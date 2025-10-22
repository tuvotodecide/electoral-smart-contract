pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {Reputation} from "../../src/Reputation.sol";
import { UnsafeUpgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {ReputationV2} from "../mocks/ReputationV2.sol";

contract ReputationUpgradeTest is Test {
    Reputation reputation;
    address initialOwner = makeAddr("initialOwner");

    function initReputation() internal {
        vm.startPrank(initialOwner);
        address implementation = address(new Reputation());
        address proxy = UnsafeUpgrades.deployUUPSProxy(
            implementation,
            abi.encodeCall(Reputation.initialize, (initialOwner))
        );
        vm.stopPrank();
        reputation = Reputation(proxy);
    }

    function upgradeReputation() internal {
        vm.startPrank(initialOwner);
        address newImplementation = address(new ReputationV2());
        UnsafeUpgrades.upgradeProxy(address(reputation), newImplementation, "");
        vm.stopPrank();
    }

    function test_initializeReputation_upgrading() public {
        initReputation();

        // Verify that the initial owner has the DEFAULT_ADMIN_ROLE
        bytes32 adminRole = reputation.DEFAULT_ADMIN_ROLE();
        assertTrue(reputation.hasRole(adminRole, initialOwner));

        // Upgrade to ReputationV2
        upgradeReputation();

        // Verify that the initial owner has the DEFAULT_ADMIN_ROLE
        assertTrue(reputation.hasRole(adminRole, initialOwner));
    }

    function test_reinitializeFails_upgrading() public {
        initReputation();

        // Attempt to re-initialize should fail
        vm.expectRevert("InvalidInitialization()");
        reputation.initialize(initialOwner);

        upgradeReputation();

        // Attempt to re-initialize after upgrade should also fail
        vm.expectRevert("InvalidInitialization()");
        reputation.initialize(initialOwner);
    }

    function test_initReputation_onlyCaller_upgrade() public {
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

        upgradeReputation();

        // Verify that existing reputations are preserved after upgrade
        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];

            // Caller initializes their own reputation
            vm.prank(user);
            uint256 rep = reputation.getReputation();
            assertEq(rep, 1);
        }
    }

    function test_initReputation_alreadyInitialized() public {
        initReputation();

        address user = makeAddr("user");

        // Caller initializes their own reputation
        vm.startPrank(user);
        reputation.initReputation();
        uint256 rep = reputation.getReputation();
        vm.stopPrank();

        assertEq(rep, 1);

        // Attempt to initialize again should work in V1
        vm.startPrank(user);
        reputation.initReputation();
        uint256 rep1 = reputation.getReputation();
        vm.stopPrank();

        assertEq(rep1, 1);

        upgradeReputation();

        // Attempt to initialize again should fail in V2
        vm.startPrank(user);
        vm.expectRevert("Reputation already initialized");
        reputation.initReputation();
        vm.stopPrank();
    }

    function test_initReputationOf_authorized_upgrading() public {
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

        upgradeReputation();

        // Check user reputation after upgrade
        vm.prank(user);
        rep = reputation.getReputation();
        assertEq(rep, 1);
    }

    function test_initReputationOf_unauthorizedFails_upgrade() public {
        initReputation();

        address unauthorized = makeAddr("unauthorized");
        address user = makeAddr("user");

        // Unauthorized address attempts to initialize reputation
        vm.startPrank(unauthorized);
        vm.expectRevert();
        reputation.initReputationOf(user);
        vm.stopPrank();

        upgradeReputation();

        // Unauthorized address attempts to initialize reputation after upgrade
        vm.startPrank(unauthorized);
        vm.expectRevert();
        reputation.initReputationOf(user);
        vm.stopPrank();
    }

    function test_initReputationOf_alreadyInitialied() public {
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

        // Attempt to initialize again should work in V1
        vm.prank(authorized);
        reputation.initReputationOf(user);
        vm.prank(user);
        uint256 rep1 = reputation.getReputation();
        assertEq(rep1, 1);

        upgradeReputation();

        // Attempt to initialize again should fail in V2
        vm.startPrank(authorized);
        vm.expectRevert("Reputation already initialized");
        reputation.initReputationOf(user);
        vm.stopPrank();
    }

    function test_getReputation_onlyCaller_upgrade() public {
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

        upgradeReputation();

        // State should be preserved after upgrade
        vm.prank(user);
        uint256 repV2 = reputation.getReputation();
        assertEq(repV2, 1);

        vm.prank(other);
        uint256 otherRepV2 = reputation.getReputation();
        assertEq(otherRepV2, 0);
    }

    function test_getReputationOf_authorized_upgrade() public {
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

        upgradeReputation();

        // Authorized address still gets user's reputation after upgrade
        vm.prank(authorized);
        uint256 repV2 = reputation.getReputationOf(user);
        assertEq(repV2, 1);
    }

    function test_getReputationOf_unauthorizedFails_upgrade() public {
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

        upgradeReputation();

        // Unauthorized address still cannot get user's reputation after upgrade
        vm.prank(unauthorized);
        vm.expectRevert();
        reputation.getReputationOf(user);

        vm.prank(user);
        vm.expectRevert();
        reputation.getReputationOf(user);
    }

    function test_updateReputation_authorized_upgrade() public {
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

        upgradeReputation();

        // User reputation should be preserved after upgrade
        vm.prank(user);
        uint256 repV2 = reputation.getReputation();
        assertEq(repV2, 2);
    }

    function test_updateReputation_unauthorizedFails_upgrade() public {
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

        upgradeReputation();

        // Unauthorized address still cannot update user's reputation after upgrade
        vm.startPrank(unauthorized);
        vm.expectRevert();
        reputation.updateReputation(user, true);
        vm.stopPrank();

        vm.startPrank(user);
        vm.expectRevert();
        reputation.updateReputation(user, true);
        vm.stopPrank();
    }

    function test_updateReputation_withZero_upgrade() public {
        initReputation();
        upgradeReputation();

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

    function test_updateReputation_increase_modified() public {
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
        reputation.updateReputation(user, true); // Increase reputation +1 in V1
        uint256 rep = reputation.getReputationOf(user);
        vm.stopPrank();
        assertEq(rep, 2);

        upgradeReputation();

        vm.startPrank(authorized);
        reputation.updateReputation(user, true); // Increase reputation +2 in V2
        uint256 rep2 = reputation.getReputationOf(user);
        vm.stopPrank();
        assertEq(rep2, 4);
    }

    function test_removeReputationOf() public {
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

        upgradeReputation();

        // Cast to ReputationV2 to make new functions accessible, preserve proxy address
        ReputationV2 reputationV2 = ReputationV2(address(reputation));

        // V2 function: remove user reputation
        vm.startPrank(authorized);
        reputationV2.removeReputationOf(user);

        // Check that user's reputation is zero
        uint256 rep = reputation.getReputationOf(user);
        vm.stopPrank();

        assertEq(rep, 0);
    }

    function test_activeFlag_afterUpgrade() public {
        initReputation();

        upgradeReputation();

        // Cast to ReputationV2 to make new functions accessible, preserve proxy address
        ReputationV2 reputationV2 = ReputationV2(address(reputation));

        // Check that active flag is false after upgrade
        bool isActive = reputationV2.active();
        assertFalse(isActive);

        // Set active flag to true
        vm.startPrank(initialOwner);
        reputationV2.setActive(true);
        vm.stopPrank();

        // Verify that active flag is now true
        bool isActiveAfter = reputationV2.active();
        assertTrue(isActiveAfter);
    }

    function test_reputations_notOverlap_activeFlag() public {
        initReputation();

        // Fill reputations with multiple users
        address[] memory users = new address[](3);
        users[0] = makeAddr("user");
        users[1] = makeAddr("user1");
        users[2] = makeAddr("user2");

        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];

            vm.startPrank(user);
            reputation.initReputation();
            uint256 rep = reputation.getReputation();
            vm.stopPrank();

            assertEq(rep, 1);
        }

        upgradeReputation();

        // Cast to ReputationV2 to make new functions accessible, preserve proxy address
        ReputationV2 reputationV2 = ReputationV2(address(reputation));

        // Set active flag to false
        vm.prank(initialOwner);
        reputationV2.setActive(false);

        bool isActive = reputationV2.active();
        assertFalse(isActive);

        // Check that user's reputation is preserved
        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];

            vm.prank(user);
            uint256 rep = reputation.getReputation();

            assertEq(rep, 1);
        }
    }
}