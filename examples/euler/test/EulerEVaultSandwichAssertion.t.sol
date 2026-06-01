// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {EulerERC4626CallSandwichAssertion} from "../src/EulerEVaultSandwichAssertion.sol";

contract MockEulerEVault {
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);

    bool public breakPreview;

    function setBreakPreview(bool enabled) external {
        breakPreview = enabled;
    }

    function previewDeposit(uint256 assets) external pure returns (uint256) {
        return assets;
    }

    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        shares = breakPreview ? assets - 1 : assets;
        emit Deposit(msg.sender, receiver, assets, shares);
    }
}

contract EulerEVaultSandwichAssertionTest is Test, CredibleTest {
    MockEulerEVault internal vault;

    function setUp() public {
        vault = new MockEulerEVault();
    }

    function _arm() internal {
        bytes memory createData = abi.encodePacked(type(EulerERC4626CallSandwichAssertion).creationCode);
        cl.assertion(address(vault), createData, EulerERC4626CallSandwichAssertion.assertErc4626CallWasHonest.selector);
    }

    function testDepositMatchesPreCallPreview() public {
        _arm();
        vault.deposit(100 ether, address(this));
    }

    function testDepositReturnBelowPreviewTrips() public {
        vault.setBreakPreview(true);

        _arm();
        vm.expectRevert(bytes("EulerEVault: deposit return != pre-call preview"));
        vault.deposit(100 ether, address(this));
    }
}
