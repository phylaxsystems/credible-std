// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {CurveUsdControllerProtocolHelpers} from "../src/CurveUsdProtocol.sol";

contract CurveUsdAccountDecoderHarness is CurveUsdControllerProtocolHelpers {
    constructor() CurveUsdControllerProtocolHelpers(address(0), address(0), 0, 0) {}

    function triggers() external view override {}

    function account(bytes4 selector, address caller, bytes calldata selectorStrippedArgs)
        external
        pure
        returns (address)
    {
        return _curveUsdAccountFromCall(
            CurveUsdTriggeredCall({
                selector: selector, caller: caller, input: selectorStrippedArgs, callStart: 1, callEnd: 2
            })
        );
    }
}

contract CurveUsdProtocolTest is Test {
    CurveUsdAccountDecoderHarness internal decoder;
    address internal caller = makeAddr("caller");
    address internal borrower = makeAddr("borrower");
    address internal callback = makeAddr("callback");

    function setUp() public {
        decoder = new CurveUsdAccountDecoderHarness();
    }

    function testCreateLoanExplicitAccountUsesFourthWord() public view {
        bytes4 selector = bytes4(keccak256("create_loan(uint256,uint256,uint256,address,address,bytes)"));
        bytes memory args = abi.encode(11, 22, 33, borrower, callback, hex"aabb");
        assertEq(decoder.account(selector, caller, args), borrower);
    }

    function testBorrowMoreExplicitAccountUsesThirdWord() public view {
        bytes4 selector = bytes4(keccak256("borrow_more(uint256,uint256,address,address)"));
        bytes memory args = abi.encode(11, 22, borrower, callback);
        assertEq(decoder.account(selector, caller, args), borrower);
    }

    function testRemoveCollateralExplicitAccountUsesSecondWord() public view {
        bytes4 selector = bytes4(keccak256("remove_collateral(uint256,address)"));
        bytes memory args = abi.encode(11, borrower);
        assertEq(decoder.account(selector, caller, args), borrower);
    }

    function testLiquidationExplicitAccountUsesFirstWord() public view {
        bytes4 selector = bytes4(keccak256("liquidate(address,uint256,uint256,address,bytes)"));
        bytes memory args = abi.encode(borrower, 22, 33, callback, hex"ccdd");
        assertEq(decoder.account(selector, caller, args), borrower);
    }
}
