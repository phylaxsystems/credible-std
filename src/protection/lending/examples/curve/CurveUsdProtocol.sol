// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "../../../../Assertion.sol";
import {PhEvm} from "../../../../PhEvm.sol";

interface ICurveUsdController {
    function amm() external view returns (address);
    function debt(address user) external view returns (uint256);
    function loan_exists(address user) external view returns (bool);
    function total_debt() external view returns (uint256);
    function health(address user, bool full) external view returns (int256);
    function loans(uint256 i) external view returns (address);
    function loan_ix(address user) external view returns (uint256);
    function n_loans() external view returns (uint256);
}

interface ICurveUsdAMMLiquidity {
    function has_liquidity(address user) external view returns (bool);
}

library CurveUsdControllerSelectors {
    bytes4 internal constant CREATE_LOAN = bytes4(keccak256("create_loan(uint256,uint256,uint256)"));
    bytes4 internal constant CREATE_LOAN_FOR = bytes4(keccak256("create_loan(uint256,uint256,uint256,address)"));
    bytes4 internal constant CREATE_LOAN_CALLBACK =
        bytes4(keccak256("create_loan(uint256,uint256,uint256,address,address)"));
    bytes4 internal constant CREATE_LOAN_CALLBACK_DATA =
        bytes4(keccak256("create_loan(uint256,uint256,uint256,address,address,bytes)"));

    bytes4 internal constant BORROW_MORE = bytes4(keccak256("borrow_more(uint256,uint256)"));
    bytes4 internal constant BORROW_MORE_FOR = bytes4(keccak256("borrow_more(uint256,uint256,address)"));
    bytes4 internal constant BORROW_MORE_CALLBACK = bytes4(keccak256("borrow_more(uint256,uint256,address,address)"));
    bytes4 internal constant BORROW_MORE_CALLBACK_DATA =
        bytes4(keccak256("borrow_more(uint256,uint256,address,address,bytes)"));

    bytes4 internal constant REMOVE_COLLATERAL = bytes4(keccak256("remove_collateral(uint256)"));
    bytes4 internal constant REMOVE_COLLATERAL_FOR = bytes4(keccak256("remove_collateral(uint256,address)"));

    bytes4 internal constant LIQUIDATE = bytes4(keccak256("liquidate(address,uint256)"));
    bytes4 internal constant LIQUIDATE_FRAC = bytes4(keccak256("liquidate(address,uint256,uint256)"));
    bytes4 internal constant LIQUIDATE_CALLBACK = bytes4(keccak256("liquidate(address,uint256,uint256,address)"));
    bytes4 internal constant LIQUIDATE_CALLBACK_DATA =
        bytes4(keccak256("liquidate(address,uint256,uint256,address,bytes)"));
}

abstract contract CurveUsdControllerProtocolHelpers is Assertion {
    address internal immutable controller;
    address internal immutable amm;
    uint256 internal immutable maxLoansToScan;
    uint256 internal immutable debtTolerance;

    struct CurveUsdTriggeredCall {
        bytes4 selector;
        address caller;
        bytes input;
        uint256 callStart;
        uint256 callEnd;
    }

    constructor(address controller_, uint256 maxLoansToScan_, uint256 debtTolerance_) {
        controller = controller_;
        amm = ICurveUsdController(controller_).amm();
        maxLoansToScan = maxLoansToScan_;
        debtTolerance = debtTolerance_;
    }

    function _registerCurveUsdRiskIncreasingTriggers(bytes4 assertionSelector) internal view {
        registerFnCallTrigger(assertionSelector, CurveUsdControllerSelectors.CREATE_LOAN);
        registerFnCallTrigger(assertionSelector, CurveUsdControllerSelectors.CREATE_LOAN_FOR);
        registerFnCallTrigger(assertionSelector, CurveUsdControllerSelectors.CREATE_LOAN_CALLBACK);
        registerFnCallTrigger(assertionSelector, CurveUsdControllerSelectors.CREATE_LOAN_CALLBACK_DATA);
        registerFnCallTrigger(assertionSelector, CurveUsdControllerSelectors.BORROW_MORE);
        registerFnCallTrigger(assertionSelector, CurveUsdControllerSelectors.BORROW_MORE_FOR);
        registerFnCallTrigger(assertionSelector, CurveUsdControllerSelectors.BORROW_MORE_CALLBACK);
        registerFnCallTrigger(assertionSelector, CurveUsdControllerSelectors.BORROW_MORE_CALLBACK_DATA);
        registerFnCallTrigger(assertionSelector, CurveUsdControllerSelectors.REMOVE_COLLATERAL);
        registerFnCallTrigger(assertionSelector, CurveUsdControllerSelectors.REMOVE_COLLATERAL_FOR);
    }

    function _registerCurveUsdLiquidationTriggers(bytes4 assertionSelector) internal view {
        registerFnCallTrigger(assertionSelector, CurveUsdControllerSelectors.LIQUIDATE);
        registerFnCallTrigger(assertionSelector, CurveUsdControllerSelectors.LIQUIDATE_FRAC);
        registerFnCallTrigger(assertionSelector, CurveUsdControllerSelectors.LIQUIDATE_CALLBACK);
        registerFnCallTrigger(assertionSelector, CurveUsdControllerSelectors.LIQUIDATE_CALLBACK_DATA);
    }

    function _resolveCurveUsdTriggeredCall() internal view returns (CurveUsdTriggeredCall memory triggered) {
        PhEvm.TriggerContext memory context = ph.context();
        PhEvm.CallInputs[] memory calls = ph.getAllCallInputs(ph.getAssertionAdopter(), context.selector);

        for (uint256 i; i < calls.length; ++i) {
            if (calls[i].id == context.callStart) {
                return CurveUsdTriggeredCall({
                    selector: context.selector,
                    caller: calls[i].caller,
                    input: calls[i].input,
                    callStart: context.callStart,
                    callEnd: context.callEnd
                });
            }
        }

        revert("CurveUSD: triggered call not found");
    }

    function _curveUsdAccountFromCall(CurveUsdTriggeredCall memory triggered) internal pure returns (address) {
        bytes4 selector = triggered.selector;

        if (selector == CurveUsdControllerSelectors.CREATE_LOAN) {
            return triggered.caller;
        }
        if (
            selector == CurveUsdControllerSelectors.CREATE_LOAN_FOR
                || selector == CurveUsdControllerSelectors.CREATE_LOAN_CALLBACK
                || selector == CurveUsdControllerSelectors.CREATE_LOAN_CALLBACK_DATA
        ) {
            return _addressArg(triggered.input, 3);
        }

        if (selector == CurveUsdControllerSelectors.BORROW_MORE) {
            return triggered.caller;
        }
        if (
            selector == CurveUsdControllerSelectors.BORROW_MORE_FOR
                || selector == CurveUsdControllerSelectors.BORROW_MORE_CALLBACK
                || selector == CurveUsdControllerSelectors.BORROW_MORE_CALLBACK_DATA
        ) {
            return _addressArg(triggered.input, 2);
        }

        if (selector == CurveUsdControllerSelectors.REMOVE_COLLATERAL) {
            return triggered.caller;
        }
        if (selector == CurveUsdControllerSelectors.REMOVE_COLLATERAL_FOR) {
            return _addressArg(triggered.input, 1);
        }

        if (
            selector == CurveUsdControllerSelectors.LIQUIDATE || selector == CurveUsdControllerSelectors.LIQUIDATE_FRAC
                || selector == CurveUsdControllerSelectors.LIQUIDATE_CALLBACK
                || selector == CurveUsdControllerSelectors.LIQUIDATE_CALLBACK_DATA
        ) {
            return _addressArg(triggered.input, 0);
        }

        return address(0);
    }

    function _controllerNLoansAt(PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(controller, abi.encodeCall(ICurveUsdController.n_loans, ()), fork);
    }

    function _controllerLoanAt(uint256 i, PhEvm.ForkId memory fork) internal view returns (address) {
        return _readAddressAt(controller, abi.encodeCall(ICurveUsdController.loans, (i)), fork);
    }

    function _controllerLoanIndexAt(address user, PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(controller, abi.encodeCall(ICurveUsdController.loan_ix, (user)), fork);
    }

    function _controllerLoanExistsAt(address user, PhEvm.ForkId memory fork) internal view returns (bool) {
        return _readBoolAt(controller, abi.encodeCall(ICurveUsdController.loan_exists, (user)), fork);
    }

    function _controllerDebtAt(address user, PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(controller, abi.encodeCall(ICurveUsdController.debt, (user)), fork);
    }

    function _controllerTotalDebtAt(PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(controller, abi.encodeCall(ICurveUsdController.total_debt, ()), fork);
    }

    function _controllerHealthAt(address user, bool full, PhEvm.ForkId memory fork) internal view returns (int256) {
        return abi.decode(_viewAt(controller, abi.encodeCall(ICurveUsdController.health, (user, full)), fork), (int256));
    }

    function _ammHasLiquidityAt(address user, PhEvm.ForkId memory fork) internal view returns (bool) {
        return _readBoolAt(amm, abi.encodeCall(ICurveUsdAMMLiquidity.has_liquidity, (user)), fork);
    }

    function _addressArg(bytes memory input, uint256 argIndex) internal pure returns (address) {
        return address(uint160(uint256(_wordArg(input, argIndex))));
    }

    function _wordArg(bytes memory input, uint256 argIndex) internal pure returns (bytes32 word) {
        uint256 offset = 4 + argIndex * 32;
        require(input.length >= offset + 32, "CurveUSD: calldata arg missing");
        assembly {
            word := mload(add(add(input, 0x20), offset))
        }
    }
}
