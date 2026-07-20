// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ILendingProtectionSuite} from "credible-std/protection/lending/ILendingProtectionSuite.sol";
import {
    AaveV3LikeOperationSafetyAssertionBase
} from "credible-std/protection/lending/examples/AaveV3LikeOperationSafety.sol";
import {AaveV3LikeProtectionSuite} from "credible-std/protection/lending/examples/AaveV3LikeHelpers.sol";
import {IAaveV3LikePool} from "credible-std/protection/lending/examples/AaveV3LikeInterfaces.sol";

/// @notice Compact L2 Pool surface exposed by Tydro's Ink deployment.
interface ITydroL2Pool {
    function borrow(bytes32 args) external;
    function withdraw(bytes32 args) external returns (uint256);
    function liquidationCall(bytes32 args1, bytes32 args2) external;
    function setUserUseReserveAsCollateral(bytes32 args) external;
}

interface ITydroPoolCurrent {
    function finalizeTransfer(
        address asset,
        address from,
        address to,
        uint256 amount,
        uint256 scaledBalanceFromBefore,
        uint256 scaledBalanceToBefore
    ) external;
    function setUserUseReserveAsCollateralOnBehalfOf(address asset, bool useAsCollateral, address onBehalfOf) external;
    function setUserEModeOnBehalfOf(uint8 categoryId, address onBehalfOf) external;
    function flashLoan(
        address receiverAddress,
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata interestRateModes,
        address onBehalfOf,
        bytes calldata params,
        uint16 referralCode
    ) external;
    function getReserveAddressById(uint16 id) external view returns (address);
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
        selectors = new bytes4[](13);
        selectors[0] = IAaveV3LikePool.borrow.selector;
        selectors[1] = IAaveV3LikePool.withdraw.selector;
        selectors[2] = IAaveV3LikePool.liquidationCall.selector;
        selectors[3] = IAaveV3LikePool.setUserUseReserveAsCollateral.selector;
        selectors[4] = ITydroPoolCurrent.finalizeTransfer.selector;
        selectors[5] = IAaveV3LikePool.setUserEMode.selector;
        selectors[6] = ITydroL2Pool.borrow.selector;
        selectors[7] = ITydroL2Pool.withdraw.selector;
        selectors[8] = ITydroL2Pool.liquidationCall.selector;
        selectors[9] = ITydroL2Pool.setUserUseReserveAsCollateral.selector;
        selectors[10] = ITydroPoolCurrent.setUserUseReserveAsCollateralOnBehalfOf.selector;
        selectors[11] = ITydroPoolCurrent.setUserEModeOnBehalfOf.selector;
        selectors[12] = ITydroPoolCurrent.flashLoan.selector;
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
            return _decodeCurrentOrStandardOperation(triggered);
        }

        operation.selector = triggered.selector;
        operation.caller = triggered.caller;

        if (triggered.selector == ITydroL2Pool.borrow.selector) {
            bytes32 args = abi.decode(triggered.input[4:], (bytes32));

            operation.kind = OperationKind.Borrow;
            operation.account = triggered.caller;
            operation.asset = _assetByL2Id(args);
            // Borrow shares the compact uint128 max sentinel: the Pool reads type(uint128).max as a
            // full type(uint256).max borrow, so the operation context must expand it the same way
            // withdraw does, or downstream amount checks see a shortened value.
            operation.amount = _decodeL2Amount(args, true);
            operation.increasesDebt = operation.amount != 0;
            return operation;
        }

        if (triggered.selector == ITydroL2Pool.withdraw.selector) {
            bytes32 args = abi.decode(triggered.input[4:], (bytes32));

            operation.kind = OperationKind.WithdrawCollateral;
            operation.account = triggered.caller;
            operation.asset = _assetByL2Id(args);
            operation.counterparty = triggered.caller;
            operation.amount = _decodeL2Amount(args, true);
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
            operation.amount = uint256(args2) & L2_SHORTENED_AMOUNT_MASK;
            if (operation.amount == L2_MAX_AMOUNT) {
                operation.amount = type(uint256).max;
            }
            operation.metadata = abi.encode(((uint256(args2) >> 128) & 1) == 0);
            return operation;
        }

        if (triggered.selector == ITydroL2Pool.setUserUseReserveAsCollateral.selector) {
            bytes32 args = abi.decode(triggered.input[4:], (bytes32));
            bool useAsCollateral = ((uint256(args) >> 16) & 1) == 0;

            if (!useAsCollateral) {
                operation.kind = OperationKind.DisableCollateral;
                operation.account = triggered.caller;
                operation.asset = _assetByL2Id(args);
                operation.reducesEffectiveCollateral = true;
            }
        }
    }

    function _decodeCurrentOrStandardOperation(TriggeredCall calldata triggered)
        internal
        pure
        returns (OperationContext memory operation)
    {
        operation.selector = triggered.selector;
        operation.caller = triggered.caller;

        if (triggered.selector == ITydroPoolCurrent.finalizeTransfer.selector) {
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

        if (triggered.selector == ITydroPoolCurrent.setUserUseReserveAsCollateralOnBehalfOf.selector) {
            (address asset, bool useAsCollateral, address onBehalfOf) =
                abi.decode(triggered.input[4:], (address, bool, address));
            if (!useAsCollateral) {
                operation.kind = OperationKind.DisableCollateral;
                operation.account = onBehalfOf;
                operation.asset = asset;
                operation.reducesEffectiveCollateral = true;
            }
            return operation;
        }

        if (triggered.selector == ITydroPoolCurrent.setUserEModeOnBehalfOf.selector) {
            (uint8 categoryId, address onBehalfOf) = abi.decode(triggered.input[4:], (uint8, address));
            operation.kind = OperationKind.SetEMode;
            operation.account = onBehalfOf;
            operation.amount = categoryId;
            operation.metadata = abi.encode(categoryId);
            return operation;
        }

        if (triggered.selector == ITydroPoolCurrent.flashLoan.selector) {
            (,,, uint256[] memory interestRateModes, address onBehalfOf,,) =
                abi.decode(triggered.input[4:], (address, address[], uint256[], uint256[], address, bytes, uint16));
            for (uint256 i; i < interestRateModes.length; ++i) {
                if (interestRateModes[i] != 0) {
                    operation.kind = OperationKind.Borrow;
                    operation.account = onBehalfOf;
                    operation.increasesDebt = true;
                    break;
                }
            }
            return operation;
        }

        if (triggered.selector == IAaveV3LikePool.borrow.selector) {
            return _decodeBorrowOperation(triggered);
        }

        if (triggered.selector == IAaveV3LikePool.withdraw.selector) {
            return _decodeWithdrawOperation(triggered);
        }

        if (triggered.selector == IAaveV3LikePool.liquidationCall.selector) {
            return _decodeLiquidationOperation(triggered);
        }

        if (triggered.selector == IAaveV3LikePool.setUserUseReserveAsCollateral.selector) {
            return _decodeCollateralToggleOperation(triggered);
        }

        if (triggered.selector == IAaveV3LikePool.setUserEMode.selector) {
            return _decodeSetUserEModeOperation(triggered);
        }

        return operation;
    }

    /// @notice Resolves the reserve address encoded by a compact L2 asset id.
    function _assetByL2Id(bytes32 args) internal view returns (address) {
        uint16 assetId = uint16(uint256(args) & L2_ASSET_ID_MASK);
        return ITydroPoolCurrent(POOL).getReserveAddressById(assetId);
    }

    /// @notice Decodes Aave/Tydro's compact uint128 amount, including the max sentinel.
    function _decodeL2Amount(bytes32 args, bool expandMax) internal pure returns (uint256 amount) {
        amount = (uint256(args) >> 16) & L2_SHORTENED_AMOUNT_MASK;
        if (expandMax && amount == L2_MAX_AMOUNT) {
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
        AaveV3LikeOperationSafetyAssertionBase(new TydroProtectionSuite(pool_, addressesProvider_))
    {}
}
