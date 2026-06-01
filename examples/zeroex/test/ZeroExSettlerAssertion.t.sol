// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "../../../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {ZeroExSettlerAssertion} from "../src/ZeroExSettlerAssertion.sol";
import {ZeroExSettlerSlippage} from "../src/ZeroExSettlerInterfaces.sol";

contract MockZeroExRegistry {
    address public current;
    address public previous;

    function setCurrent(address current_) external {
        current = current_;
    }

    function ownerOf(uint256) external view returns (address) {
        return current;
    }

    function prev(uint128) external view returns (address) {
        return previous;
    }
}

contract MockZeroExSettler {
    uint256 public payout;

    function setPayout(uint256 payout_) external {
        payout = payout_;
    }

    function execute(ZeroExSettlerSlippage calldata slippage, bytes[] calldata, bytes32)
        external
        payable
        returns (bool)
    {
        ERC20Mock(slippage.buyToken).transfer(slippage.recipient, payout);
        return true;
    }
}

contract ZeroExSettlerAssertionTest is Test, CredibleTest {
    uint128 internal constant FEATURE_ID = 1;

    ERC20Mock internal buyToken;
    MockZeroExRegistry internal registry;
    MockZeroExSettler internal settler;
    address internal recipient = makeAddr("recipient");

    function setUp() public {
        buyToken = new ERC20Mock();
        registry = new MockZeroExRegistry();
        settler = new MockZeroExSettler();
        registry.setCurrent(address(settler));
        buyToken.mint(address(settler), 1_000 ether);
    }

    function _arm(bytes4 fnSelector) internal {
        bytes memory createData = abi.encodePacked(
            type(ZeroExSettlerAssertion).creationCode, abi.encode(address(settler), address(registry), FEATURE_ID)
        );
        cl.assertion(address(settler), createData, fnSelector);
    }

    function _execute(uint256 minAmountOut) internal {
        bytes[] memory actions = new bytes[](0);
        settler.execute(ZeroExSettlerSlippage(payable(recipient), address(buyToken), minAmountOut), actions, bytes32(0));
    }

    function testRecipientMinimumBuyAmountPasses() public {
        settler.setPayout(100 ether);

        _arm(ZeroExSettlerAssertion.assertRecipientReceivesMinimumBuyAmount.selector);
        _execute(100 ether);
    }

    function testRecipientMinimumBuyAmountTripsWhenCreditedBelowMinimum() public {
        settler.setPayout(99 ether);

        _arm(ZeroExSettlerAssertion.assertRecipientReceivesMinimumBuyAmount.selector);
        vm.expectRevert(bytes("0xSettler: recipient credited below minimum"));
        _execute(100 ether);
    }
}
