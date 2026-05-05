// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";

import {ILendingProtectionSuite} from "../../../src/protection/lending/ILendingProtectionSuite.sol";
import {IAaveV3LikePool} from "../../../src/protection/lending/examples/AaveV3LikeInterfaces.sol";
import {
    AaveV3HorizonOperationSafetyAssertion,
    AaveV3HorizonProtectionSuite
} from "../../../src/protection/lending/examples/AaveV3PostOperationSolvency.sol";
import {
    SparkLendV1OperationSafetyAssertion,
    SparkLendV1ProtectionSuite
} from "../../../src/protection/lending/examples/SparkLendV1OperationSafety.sol";
import {
    ITydroL2Pool,
    TydroOperationSafetyAssertion,
    TydroProtectionSuite
} from "../../../src/protection/lending/examples/TydroOperationSafety.sol";

contract MockAaveV3LikePool {
    address internal immutable PROVIDER;
    address[] internal reserves;

    constructor(address provider_) {
        PROVIDER = provider_;
        reserves.push(address(0xAAA1));
        reserves.push(address(0xAAA2));
        reserves.push(address(0xAAA3));
    }

    function ADDRESSES_PROVIDER() external view returns (address) {
        return PROVIDER;
    }

    function getReservesList() external view returns (address[] memory) {
        return reserves;
    }
}

contract AaveV3LikeOperationSafetyTest is Test {
    MockAaveV3LikePool internal pool;
    SparkLendV1ProtectionSuite internal sparkSuite;
    AaveV3HorizonProtectionSuite internal aaveSuite;
    TydroProtectionSuite internal tydroSuite;

    function setUp() external {
        pool = new MockAaveV3LikePool(address(0xBEEF));
        sparkSuite = new SparkLendV1ProtectionSuite(address(pool), address(0xBEEF));
        aaveSuite = new AaveV3HorizonProtectionSuite(address(pool), address(0xBEEF));
        tydroSuite = new TydroProtectionSuite(address(pool), address(0xBEEF));
    }

    function testMonitoredSelectorsMatchAaveV3LikeSurface() external view {
        bytes4[] memory selectors = sparkSuite.getMonitoredSelectors();

        assertEq(selectors.length, 6);
        assertEq(selectors[0], IAaveV3LikePool.borrow.selector);
        assertEq(selectors[1], IAaveV3LikePool.withdraw.selector);
        assertEq(selectors[2], IAaveV3LikePool.liquidationCall.selector);
        assertEq(selectors[3], IAaveV3LikePool.setUserUseReserveAsCollateral.selector);
        assertEq(selectors[4], IAaveV3LikePool.finalizeTransfer.selector);
        assertEq(selectors[5], IAaveV3LikePool.setUserEMode.selector);
    }

    function testSparkBorrowDecodeMarksDebtIncrease() external view {
        ILendingProtectionSuite.OperationContext memory operation = sparkSuite.decodeOperation(
            _triggered(
                IAaveV3LikePool.borrow.selector,
                address(0xCA11E2),
                abi.encodeCall(IAaveV3LikePool.borrow, (address(0xAAA1), 123e18, 2, 0, address(0xB0B0B0)))
            )
        );

        assertEq(operation.selector, IAaveV3LikePool.borrow.selector);
        assertEq(uint256(operation.kind), uint256(ILendingProtectionSuite.OperationKind.Borrow));
        assertEq(operation.caller, address(0xCA11E2));
        assertEq(operation.account, address(0xB0B0B0));
        assertEq(operation.asset, address(0xAAA1));
        assertEq(operation.amount, 123e18);
        assertTrue(operation.increasesDebt);
        assertFalse(operation.reducesEffectiveCollateral);
        assertTrue(sparkSuite.shouldCheckPostOperationSolvency(operation));
    }

    function testSparkWithdrawDecodeMarksCollateralReduction() external view {
        ILendingProtectionSuite.OperationContext memory operation = sparkSuite.decodeOperation(
            _triggered(
                IAaveV3LikePool.withdraw.selector,
                address(0xBEEF12),
                abi.encodeCall(IAaveV3LikePool.withdraw, (address(0xAAA2), type(uint256).max, address(0xFEEE)))
            )
        );

        assertEq(uint256(operation.kind), uint256(ILendingProtectionSuite.OperationKind.WithdrawCollateral));
        assertEq(operation.account, address(0xBEEF12));
        assertEq(operation.asset, address(0xAAA2));
        assertEq(operation.counterparty, address(0xFEEE));
        assertEq(operation.amount, type(uint256).max);
        assertFalse(operation.increasesDebt);
        assertTrue(operation.reducesEffectiveCollateral);
        assertTrue(sparkSuite.shouldCheckPostOperationSolvency(operation));
    }

    function testSparkLiquidationDecodeTracksBothAssetsAndMetadata() external view {
        ILendingProtectionSuite.OperationContext memory operation = sparkSuite.decodeOperation(
            _triggered(
                IAaveV3LikePool.liquidationCall.selector,
                address(0x1100A1),
                abi.encodeCall(
                    IAaveV3LikePool.liquidationCall, (address(0xC011), address(0xDE87), address(0xABCD01), 55e6, true)
                )
            )
        );

        assertEq(uint256(operation.kind), uint256(ILendingProtectionSuite.OperationKind.Liquidation));
        assertEq(operation.account, address(0xABCD01));
        assertEq(operation.asset, address(0xDE87));
        assertEq(operation.relatedAsset, address(0xC011));
        assertEq(operation.counterparty, address(0x1100A1));
        assertEq(operation.amount, 55e6);
        assertEq(operation.metadata, abi.encode(true));
        assertFalse(operation.increasesDebt);
        assertFalse(operation.reducesEffectiveCollateral);
        assertFalse(sparkSuite.shouldCheckPostOperationSolvency(operation));
    }

    function testSparkDisableCollateralOnlyTriggersWhenTurningCollateralOff() external view {
        ILendingProtectionSuite.OperationContext memory disableOperation = sparkSuite.decodeOperation(
            _triggered(
                IAaveV3LikePool.setUserUseReserveAsCollateral.selector,
                address(0xABCD01),
                abi.encodeCall(IAaveV3LikePool.setUserUseReserveAsCollateral, (address(0xC011), false))
            )
        );
        ILendingProtectionSuite.OperationContext memory enableOperation = sparkSuite.decodeOperation(
            _triggered(
                IAaveV3LikePool.setUserUseReserveAsCollateral.selector,
                address(0xABCD01),
                abi.encodeCall(IAaveV3LikePool.setUserUseReserveAsCollateral, (address(0xC011), true))
            )
        );

        assertEq(uint256(disableOperation.kind), uint256(ILendingProtectionSuite.OperationKind.DisableCollateral));
        assertEq(disableOperation.account, address(0xABCD01));
        assertTrue(disableOperation.reducesEffectiveCollateral);
        assertTrue(sparkSuite.shouldCheckPostOperationSolvency(disableOperation));

        assertEq(uint256(enableOperation.kind), uint256(ILendingProtectionSuite.OperationKind.Unknown));
        assertEq(enableOperation.account, address(0));
        assertFalse(enableOperation.reducesEffectiveCollateral);
        assertFalse(sparkSuite.shouldCheckPostOperationSolvency(enableOperation));
    }

    function testSparkFinalizeTransferIgnoresSelfTransfers() external view {
        ILendingProtectionSuite.OperationContext memory transferOperation = sparkSuite.decodeOperation(
            _triggered(
                IAaveV3LikePool.finalizeTransfer.selector,
                address(pool),
                abi.encodeCall(
                    IAaveV3LikePool.finalizeTransfer,
                    (address(0xA710), address(0xF00D01), address(0x7000), 1 ether, 2 ether, 0)
                )
            )
        );
        ILendingProtectionSuite.OperationContext memory selfTransferOperation = sparkSuite.decodeOperation(
            _triggered(
                IAaveV3LikePool.finalizeTransfer.selector,
                address(pool),
                abi.encodeCall(
                    IAaveV3LikePool.finalizeTransfer,
                    (address(0xA710), address(0xF00D01), address(0xF00D01), 1 ether, 2 ether, 2 ether)
                )
            )
        );

        assertEq(uint256(transferOperation.kind), uint256(ILendingProtectionSuite.OperationKind.TransferCollateral));
        assertEq(transferOperation.account, address(0xF00D01));
        assertEq(transferOperation.counterparty, address(0x7000));
        assertTrue(transferOperation.reducesEffectiveCollateral);
        assertTrue(sparkSuite.shouldCheckPostOperationSolvency(transferOperation));

        assertEq(selfTransferOperation.account, address(0xF00D01));
        assertFalse(selfTransferOperation.reducesEffectiveCollateral);
        assertFalse(sparkSuite.shouldCheckPostOperationSolvency(selfTransferOperation));
    }

    function testSparkSetUserEModeChecksPostOperationSolvency() external view {
        ILendingProtectionSuite.OperationContext memory operation = sparkSuite.decodeOperation(
            _triggered(
                IAaveV3LikePool.setUserEMode.selector,
                address(0xABCD01),
                abi.encodeCall(IAaveV3LikePool.setUserEMode, (uint8(1)))
            )
        );

        assertEq(uint256(operation.kind), uint256(ILendingProtectionSuite.OperationKind.SetEMode));
        assertEq(operation.account, address(0xABCD01));
        assertEq(operation.amount, 1);
        assertEq(operation.metadata, abi.encode(uint8(1)));
        assertFalse(operation.increasesDebt);
        assertFalse(operation.reducesEffectiveCollateral);
        assertTrue(sparkSuite.shouldCheckPostOperationSolvency(operation));
    }

    function testAaveAndSparkAssertionsDeploy() external {
        AaveV3HorizonOperationSafetyAssertion aaveAssertion =
            new AaveV3HorizonOperationSafetyAssertion(address(pool), address(0xBEEF));
        SparkLendV1OperationSafetyAssertion sparkAssertion =
            new SparkLendV1OperationSafetyAssertion(address(pool), address(0xBEEF));
        TydroOperationSafetyAssertion tydroAssertion = new TydroOperationSafetyAssertion(address(pool), address(0xBEEF));

        assertTrue(address(aaveAssertion) != address(0));
        assertTrue(address(sparkAssertion) != address(0));
        assertTrue(address(tydroAssertion) != address(0));
        assertTrue(address(aaveSuite) != address(0));
        assertTrue(address(sparkSuite) != address(0));
        assertTrue(address(tydroSuite) != address(0));
    }

    function testTydroMonitorsStandardAndL2Selectors() external view {
        bytes4[] memory selectors = tydroSuite.getMonitoredSelectors();

        assertEq(selectors.length, 10);
        assertEq(selectors[0], IAaveV3LikePool.borrow.selector);
        assertEq(selectors[1], IAaveV3LikePool.withdraw.selector);
        assertEq(selectors[2], IAaveV3LikePool.liquidationCall.selector);
        assertEq(selectors[3], IAaveV3LikePool.setUserUseReserveAsCollateral.selector);
        assertEq(selectors[4], IAaveV3LikePool.finalizeTransfer.selector);
        assertEq(selectors[5], IAaveV3LikePool.setUserEMode.selector);
        assertEq(selectors[6], ITydroL2Pool.borrow.selector);
        assertEq(selectors[7], ITydroL2Pool.withdraw.selector);
        assertEq(selectors[8], ITydroL2Pool.liquidationCall.selector);
        assertEq(selectors[9], ITydroL2Pool.setUserUseReserveAsCollateral.selector);
    }

    function testTydroL2BorrowDecodeMarksCallerDebtIncrease() external view {
        bytes32 args = _l2Args(1, 123e18);

        ILendingProtectionSuite.OperationContext memory operation = tydroSuite.decodeOperation(
            _triggered(ITydroL2Pool.borrow.selector, address(0xCA11E2), abi.encodeCall(ITydroL2Pool.borrow, (args)))
        );

        assertEq(uint256(operation.kind), uint256(ILendingProtectionSuite.OperationKind.Borrow));
        assertEq(operation.account, address(0xCA11E2));
        assertEq(operation.asset, address(0xAAA2));
        assertEq(operation.amount, 123e18);
        assertTrue(operation.increasesDebt);
        assertTrue(tydroSuite.shouldCheckPostOperationSolvency(operation));
    }

    function testTydroL2WithdrawDecodeMarksCallerCollateralReduction() external view {
        bytes32 args = _l2Args(2, type(uint128).max);

        ILendingProtectionSuite.OperationContext memory operation = tydroSuite.decodeOperation(
            _triggered(ITydroL2Pool.withdraw.selector, address(0xBEEF12), abi.encodeCall(ITydroL2Pool.withdraw, (args)))
        );

        assertEq(uint256(operation.kind), uint256(ILendingProtectionSuite.OperationKind.WithdrawCollateral));
        assertEq(operation.account, address(0xBEEF12));
        assertEq(operation.asset, address(0xAAA3));
        assertEq(operation.counterparty, address(0xBEEF12));
        assertEq(operation.amount, type(uint256).max);
        assertTrue(operation.reducesEffectiveCollateral);
        assertTrue(tydroSuite.shouldCheckPostOperationSolvency(operation));
    }

    function testTydroL2LiquidationDecodeTracksAssetsAndReceiveATokenFlag() external view {
        bytes32 args1 = bytes32(uint256(0) | (uint256(1) << 16) | (uint256(uint160(address(0xABCD01))) << 32));
        bytes32 args2 = _l2Args(0, 55e6);

        ILendingProtectionSuite.OperationContext memory operation = tydroSuite.decodeOperation(
            _triggered(
                ITydroL2Pool.liquidationCall.selector,
                address(0x1100A1),
                abi.encodeCall(ITydroL2Pool.liquidationCall, (args1, args2))
            )
        );

        assertEq(uint256(operation.kind), uint256(ILendingProtectionSuite.OperationKind.Liquidation));
        assertEq(operation.account, address(0xABCD01));
        assertEq(operation.asset, address(0xAAA2));
        assertEq(operation.relatedAsset, address(0xAAA1));
        assertEq(operation.counterparty, address(0x1100A1));
        assertEq(operation.amount, 55e6);
        assertEq(operation.metadata, abi.encode(true));
    }

    function testTydroL2DisableCollateralOnlyTriggersWhenTurningCollateralOff() external view {
        bytes32 disableArgs = bytes32(uint256(1) | (uint256(1) << 16));
        bytes32 enableArgs = bytes32(uint256(1));

        ILendingProtectionSuite.OperationContext memory disableOperation = tydroSuite.decodeOperation(
            _triggered(
                ITydroL2Pool.setUserUseReserveAsCollateral.selector,
                address(0xABCD01),
                abi.encodeCall(ITydroL2Pool.setUserUseReserveAsCollateral, (disableArgs))
            )
        );
        ILendingProtectionSuite.OperationContext memory enableOperation = tydroSuite.decodeOperation(
            _triggered(
                ITydroL2Pool.setUserUseReserveAsCollateral.selector,
                address(0xABCD01),
                abi.encodeCall(ITydroL2Pool.setUserUseReserveAsCollateral, (enableArgs))
            )
        );

        assertEq(uint256(disableOperation.kind), uint256(ILendingProtectionSuite.OperationKind.DisableCollateral));
        assertEq(disableOperation.account, address(0xABCD01));
        assertEq(disableOperation.asset, address(0xAAA2));
        assertTrue(disableOperation.reducesEffectiveCollateral);
        assertTrue(tydroSuite.shouldCheckPostOperationSolvency(disableOperation));

        assertEq(uint256(enableOperation.kind), uint256(ILendingProtectionSuite.OperationKind.Unknown));
        assertEq(enableOperation.account, address(0));
        assertFalse(enableOperation.reducesEffectiveCollateral);
        assertFalse(tydroSuite.shouldCheckPostOperationSolvency(enableOperation));
    }

    function _triggered(bytes4 selector, address caller, bytes memory input)
        internal
        view
        returns (ILendingProtectionSuite.TriggeredCall memory)
    {
        return ILendingProtectionSuite.TriggeredCall({
            selector: selector, caller: caller, target: address(pool), input: input, callStart: 1, callEnd: 2
        });
    }

    function _l2Args(uint256 assetId, uint256 amount) internal pure returns (bytes32) {
        return bytes32(assetId | (amount << 16));
    }
}
