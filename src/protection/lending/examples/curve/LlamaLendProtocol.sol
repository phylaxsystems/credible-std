// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "../../../../Assertion.sol";
import {PhEvm} from "../../../../PhEvm.sol";
import {ERC4626AssetFlowAssertion} from "../../../vault/ERC4626AssetFlowAssertion.sol";

interface ILlamaLendVault {
    function controller() external view returns (address);
}

interface ILlamaLendController {
    function borrowed_token() external view returns (address);
    function available_balance() external view returns (uint256);
    function total_debt() external view returns (uint256);
    function admin_fees() external view returns (uint256);
    function borrow_cap() external view returns (uint256);
}

library LlamaLendControllerSelectors {
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
}

abstract contract LlamaLendVaultProtocolHelpers is ERC4626AssetFlowAssertion {
    address internal immutable controller;

    constructor(address vault_) {
        controller = ILlamaLendVault(vault_).controller();
    }

    function _netAssetFlow() internal view virtual override returns (int256 netFlow) {
        PhEvm.Erc20TransferData[] memory deltas = _reducedErc20BalanceDeltasAt(asset, _postTx());

        for (uint256 i; i < deltas.length; ++i) {
            if (deltas[i].to == controller) {
                netFlow += int256(deltas[i].value);
            }
            if (deltas[i].from == controller) {
                netFlow -= int256(deltas[i].value);
            }
        }
    }

    function _llamaAvailableBalanceAt(PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(controller, abi.encodeCall(ILlamaLendController.available_balance, ()), fork);
    }

    function _llamaTotalDebtAt(PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(controller, abi.encodeCall(ILlamaLendController.total_debt, ()), fork);
    }

    function _llamaAdminFeesAt(PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(controller, abi.encodeCall(ILlamaLendController.admin_fees, ()), fork);
    }

    function _llamaExpectedTotalAssetsAt(PhEvm.ForkId memory fork) internal view returns (uint256 expectedAssets) {
        uint256 grossAssets = _llamaAvailableBalanceAt(fork) + _llamaTotalDebtAt(fork);
        uint256 adminFees = _llamaAdminFeesAt(fork);
        require(grossAssets >= adminFees, "LlamaLend: admin fees exceed assets");
        expectedAssets = grossAssets - adminFees;
    }

    function _llamaControllerAssetBalanceAt(PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _assetBalanceAt(controller, fork);
    }
}

abstract contract LlamaLendControllerProtocolHelpers is Assertion {
    address internal immutable controller;
    address internal immutable borrowedToken;
    uint256 internal immutable availableBalanceTolerance;

    constructor(address controller_, uint256 availableBalanceTolerance_) {
        controller = controller_;
        borrowedToken = ILlamaLendController(controller_).borrowed_token();
        availableBalanceTolerance = availableBalanceTolerance_;
    }

    function _registerLlamaLendDebtIncreasingTriggers(bytes4 assertionSelector) internal view {
        registerFnCallTrigger(assertionSelector, LlamaLendControllerSelectors.CREATE_LOAN);
        registerFnCallTrigger(assertionSelector, LlamaLendControllerSelectors.CREATE_LOAN_FOR);
        registerFnCallTrigger(assertionSelector, LlamaLendControllerSelectors.CREATE_LOAN_CALLBACK);
        registerFnCallTrigger(assertionSelector, LlamaLendControllerSelectors.CREATE_LOAN_CALLBACK_DATA);
        registerFnCallTrigger(assertionSelector, LlamaLendControllerSelectors.BORROW_MORE);
        registerFnCallTrigger(assertionSelector, LlamaLendControllerSelectors.BORROW_MORE_FOR);
        registerFnCallTrigger(assertionSelector, LlamaLendControllerSelectors.BORROW_MORE_CALLBACK);
        registerFnCallTrigger(assertionSelector, LlamaLendControllerSelectors.BORROW_MORE_CALLBACK_DATA);
    }

    function _llamaControllerAvailableBalanceAt(PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(controller, abi.encodeCall(ILlamaLendController.available_balance, ()), fork);
    }

    function _llamaControllerTotalDebtAt(PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(controller, abi.encodeCall(ILlamaLendController.total_debt, ()), fork);
    }

    function _llamaControllerBorrowCapAt(PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(controller, abi.encodeCall(ILlamaLendController.borrow_cap, ()), fork);
    }

    function _llamaControllerBorrowedBalanceAt(PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readBalanceAt(borrowedToken, controller, fork);
    }
}
