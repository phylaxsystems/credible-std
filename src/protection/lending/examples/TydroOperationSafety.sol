// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ILendingProtectionSuite} from "../ILendingProtectionSuite.sol";
import {AaveV3LikeOperationSafetyAssertionBase, AaveV3LikeProtectionSuite} from "./AaveV3LikeOperationSafety.sol";
import {IAaveV3LikePool} from "./AaveV3LikeInterfaces.sol";

/// @notice Compact L2 Pool surface exposed by Tydro's Ink deployment.
interface ITydroL2Pool {
    function borrow(bytes32 args) external;
    function withdraw(bytes32 args) external returns (uint256);
    function liquidationCall(bytes32 args1, bytes32 args2) external;
    function setUserUseReserveAsCollateral(bytes32 args) external;
}

/// @title TydroProtectionSuite
/// @author Phylax Systems
/// @notice Aave v3-like lending suite for Tydro on Ink.
/// @dev Tydro's Pool keeps the normal Aave v3-compatible ABI and also exposes the calldata-
///      compressed L2Pool entrypoints. This suite reuses the shared Aave v3-like accounting
///      checks and adds selector/decode support for compact L2 user operations.
contract TydroProtectionSuite is AaveV3LikeProtectionSuite {
    uint256 internal constant L2_ASSET_ID_MASK = type(uint16).max;
    uint256 internal constant L2_SHORTENED_AMOUNT_MASK = type(uint128).max;
    uint256 internal constant L2_MAX_AMOUNT = type(uint128).max;

    constructor(address pool_, address addressesProvider_) AaveV3LikeProtectionSuite(pool_, addressesProvider_) {}

    /// @notice Returns standard Aave v3 selectors plus Tydro's compact L2 operation selectors.
    function getMonitoredSelectors() external pure override returns (bytes4[] memory selectors) {
        selectors = new bytes4[](10);
        selectors[0] = IAaveV3LikePool.borrow.selector;
        selectors[1] = IAaveV3LikePool.withdraw.selector;
        selectors[2] = IAaveV3LikePool.liquidationCall.selector;
        selectors[3] = IAaveV3LikePool.setUserUseReserveAsCollateral.selector;
        selectors[4] = IAaveV3LikePool.finalizeTransfer.selector;
        selectors[5] = IAaveV3LikePool.setUserEMode.selector;
        selectors[6] = ITydroL2Pool.borrow.selector;
        selectors[7] = ITydroL2Pool.withdraw.selector;
        selectors[8] = ITydroL2Pool.liquidationCall.selector;
        selectors[9] = ITydroL2Pool.setUserUseReserveAsCollateral.selector;
    }

    /// @notice Decodes standard Aave v3 operations and Tydro's compact L2 operation wrappers.
    function decodeOperation(TriggeredCall calldata triggered)
        external
        view
        override
        returns (OperationContext memory operation)
    {
        if (
            triggered.selector != ITydroL2Pool.borrow.selector && triggered.selector != ITydroL2Pool.withdraw.selector
                && triggered.selector != ITydroL2Pool.liquidationCall.selector
                && triggered.selector != ITydroL2Pool.setUserUseReserveAsCollateral.selector
        ) {
            return _decodeAaveV3Operation(triggered);
        }

        operation.selector = triggered.selector;
        operation.caller = triggered.caller;

        if (triggered.selector == ITydroL2Pool.borrow.selector) {
            bytes32 args = abi.decode(triggered.input[4:], (bytes32));

            operation.kind = OperationKind.Borrow;
            operation.account = triggered.caller;
            operation.asset = _assetByL2Id(args);
            operation.amount = _decodeL2Amount(args);
            operation.increasesDebt = operation.amount != 0;
            return operation;
        }

        if (triggered.selector == ITydroL2Pool.withdraw.selector) {
            bytes32 args = abi.decode(triggered.input[4:], (bytes32));

            operation.kind = OperationKind.WithdrawCollateral;
            operation.account = triggered.caller;
            operation.asset = _assetByL2Id(args);
            operation.counterparty = triggered.caller;
            operation.amount = _decodeL2Amount(args);
            operation.reducesEffectiveCollateral = operation.amount != 0;
            return operation;
        }

        if (triggered.selector == ITydroL2Pool.liquidationCall.selector) {
            (bytes32 args1, bytes32 args2) = abi.decode(triggered.input[4:], (bytes32, bytes32));

            operation.kind = OperationKind.Liquidation;
            operation.account = address(uint160(uint256(args1 >> 32)));
            operation.asset = _assetByL2Id(args1 >> 16);
            operation.relatedAsset = _assetByL2Id(args1);
            operation.counterparty = triggered.caller;
            operation.amount = _decodeL2Amount(args2);
            operation.metadata = abi.encode(((uint256(args2) >> 128) & 1) == 0);
            return operation;
        }

        if (triggered.selector == ITydroL2Pool.setUserUseReserveAsCollateral.selector) {
            bytes32 args = abi.decode(triggered.input[4:], (bytes32));
            bool disableCollateral = ((uint256(args) >> 16) & 1) != 0;

            if (disableCollateral) {
                operation.kind = OperationKind.DisableCollateral;
                operation.account = triggered.caller;
                operation.asset = _assetByL2Id(args);
                operation.reducesEffectiveCollateral = true;
            }
        }
    }

    /// @notice Internal standard ABI decoder kept overridable for the Tydro L2 extension.
    function _decodeAaveV3Operation(TriggeredCall calldata triggered)
        internal
        pure
        returns (OperationContext memory operation)
    {
        operation.selector = triggered.selector;
        operation.caller = triggered.caller;

        if (triggered.selector == IAaveV3LikePool.borrow.selector) {
            (address asset, uint256 amount,,, address onBehalfOf) =
                abi.decode(triggered.input[4:], (address, uint256, uint256, uint16, address));

            operation.kind = OperationKind.Borrow;
            operation.account = onBehalfOf;
            operation.asset = asset;
            operation.amount = amount;
            operation.increasesDebt = amount != 0;
            return operation;
        }

        if (triggered.selector == IAaveV3LikePool.withdraw.selector) {
            (address asset, uint256 amount, address to) = abi.decode(triggered.input[4:], (address, uint256, address));

            operation.kind = OperationKind.WithdrawCollateral;
            operation.account = triggered.caller;
            operation.asset = asset;
            operation.counterparty = to;
            operation.amount = amount;
            operation.reducesEffectiveCollateral = amount != 0;
            return operation;
        }

        if (triggered.selector == IAaveV3LikePool.liquidationCall.selector) {
            (address collateralAsset, address debtAsset, address user, uint256 debtToCover, bool receiveAToken) =
                abi.decode(triggered.input[4:], (address, address, address, uint256, bool));

            operation.kind = OperationKind.Liquidation;
            operation.account = user;
            operation.asset = debtAsset;
            operation.relatedAsset = collateralAsset;
            operation.counterparty = triggered.caller;
            operation.amount = debtToCover;
            operation.metadata = abi.encode(receiveAToken);
            return operation;
        }

        if (triggered.selector == IAaveV3LikePool.setUserUseReserveAsCollateral.selector) {
            (address asset, bool useAsCollateral) = abi.decode(triggered.input[4:], (address, bool));

            if (!useAsCollateral) {
                operation.kind = OperationKind.DisableCollateral;
                operation.account = triggered.caller;
                operation.asset = asset;
                operation.reducesEffectiveCollateral = true;
            }

            return operation;
        }

        if (triggered.selector == IAaveV3LikePool.finalizeTransfer.selector) {
            (address asset, address from, address to, uint256 amount,,) =
                abi.decode(triggered.input[4:], (address, address, address, uint256, uint256, uint256));

            operation.kind = OperationKind.TransferCollateral;
            operation.account = from;
            operation.asset = asset;
            operation.counterparty = to;
            operation.amount = amount;
            operation.reducesEffectiveCollateral = from != to && amount != 0;
            return operation;
        }

        if (triggered.selector == IAaveV3LikePool.setUserEMode.selector) {
            (uint8 categoryId) = abi.decode(triggered.input[4:], (uint8));

            operation.kind = OperationKind.SetEMode;
            operation.account = triggered.caller;
            operation.amount = uint256(categoryId);
            operation.metadata = abi.encode(categoryId);
            return operation;
        }
    }

    /// @notice Resolves the reserve address encoded by a compact L2 asset id.
    function _assetByL2Id(bytes32 args) internal view returns (address) {
        address[] memory reserves = IAaveV3LikePool(POOL).getReservesList();
        uint256 assetId = uint256(args) & L2_ASSET_ID_MASK;
        return reserves[assetId];
    }

    /// @notice Decodes Aave/Tydro's compact uint128 amount, including the max sentinel.
    function _decodeL2Amount(bytes32 args) internal pure returns (uint256 amount) {
        amount = (uint256(args) >> 16) & L2_SHORTENED_AMOUNT_MASK;
        if (amount == L2_MAX_AMOUNT) {
            return type(uint256).max;
        }
    }
}

/// @title TydroOperationSafetyAssertion
/// @author Phylax Systems
/// @notice Single-entry assertion bundle for Tydro on Ink.
/// @dev Covers both the normal Aave v3-compatible Pool ABI and Tydro's compact L2Pool entrypoints.
contract TydroOperationSafetyAssertion is AaveV3LikeOperationSafetyAssertionBase {
    constructor(address pool_, address addressesProvider_)
        AaveV3LikeOperationSafetyAssertionBase(address(new TydroProtectionSuite(pool_, addressesProvider_)))
    {}
}
