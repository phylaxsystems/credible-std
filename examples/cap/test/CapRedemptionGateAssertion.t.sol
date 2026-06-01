// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "../../../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {CapRedemptionGateAssertion} from "../src/CapRedemptionGateAssertion.sol";

contract MockCapVault {
    mapping(address => uint256) public loaned;

    function borrow(address asset, uint256 amount, address receiver) external {
        ERC20Mock(asset).transfer(receiver, amount);
    }

    function setLoaned(address asset, uint256 amount) external {
        loaned[asset] = amount;
    }
}

contract CapRedemptionGateAssertionTest is Test, CredibleTest {
    ERC20Mock internal asset;
    MockCapVault internal vault;
    address internal receiver = makeAddr("receiver");

    function setUp() public {
        asset = new ERC20Mock();
        vault = new MockCapVault();
        asset.mint(address(vault), 100 ether);
    }

    function _arm() internal {
        bytes memory createData = abi.encodePacked(
            type(CapRedemptionGateAssertion).creationCode,
            abi.encode(address(asset), address(0), address(0), address(0), address(0))
        );
        cl.assertion(address(vault), createData, CapRedemptionGateAssertion.assertCapRedemptionGate.selector);
    }

    function testSmallBorrowOutflowPassesBelowGateTier() public {
        _arm();
        vault.borrow(address(asset), 1 ether, receiver);
    }

    function testAssertionDeploysWithWatchedAsset() public {
        CapRedemptionGateAssertion assertion =
            new CapRedemptionGateAssertion(address(asset), address(0), address(0), address(0), address(0));
        assertTrue(address(assertion) != address(0));
    }
}
