// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "../../../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {RoycoKernelAssertion} from "../src/RoycoKernelAssertion.sol";

contract MockRoycoKernel {
    ERC20Mock public immutable asset;

    constructor(ERC20Mock asset_) {
        asset = asset_;
    }

    function deposit(uint256 amount) external {
        asset.transferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint256 amount) external {
        asset.transfer(msg.sender, amount);
    }
}

contract RoycoKernelAssertionTest is Test, CredibleTest {
    ERC20Mock internal asset;
    MockRoycoKernel internal kernel;
    address internal alice = makeAddr("alice");

    function setUp() public {
        asset = new ERC20Mock();
        kernel = new MockRoycoKernel(asset);

        asset.mint(address(kernel), 100 ether);
        asset.mint(alice, 100 ether);
        vm.prank(alice);
        asset.approve(address(kernel), type(uint256).max);
    }

    function _arm(bytes4 fnSelector) internal {
        bytes memory createData = abi.encodePacked(
            type(RoycoKernelAssertion).creationCode,
            abi.encode(
                address(kernel),
                makeAddr("accountant"),
                makeAddr("seniorTranche"),
                address(asset),
                makeAddr("juniorTranche"),
                address(asset),
                2_500,
                1 days,
                2_500,
                1 days
            )
        );
        cl.assertion(address(kernel), createData, fnSelector);
    }

    function testLargeInflowTripsBreaker() public {
        _arm(bytes4(keccak256("assertCumulativeInflow()")));

        vm.prank(alice);
        vm.expectRevert(bytes("Royco: cumulative tranche-asset inflow breaker tripped"));
        kernel.deposit(50 ether);
    }

    function testLargeOutflowTripsBreaker() public {
        _arm(bytes4(keccak256("assertCumulativeOutflow()")));

        vm.expectRevert(bytes("Royco: cumulative tranche-asset outflow breaker tripped"));
        kernel.withdraw(50 ether);
    }
}
