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

contract MockAaveV3LikePool {
    address internal immutable PROVIDER;

    constructor(address provider_) {
        PROVIDER = provider_;
    }

    function ADDRESSES_PROVIDER() external view returns (address) {
        return PROVIDER;
    }
}

contract AaveV3LikeOperationSafetyTest is Test {
    MockAaveV3LikePool internal pool;
    SparkLendV1ProtectionSuite internal sparkSuite;
    AaveV3HorizonProtectionSuite internal aaveSuite;

    function setUp() external {
        pool = new MockAaveV3LikePool(address(0xBEEF));
        sparkSuite = new SparkLendV1ProtectionSuite(address(pool));
        aaveSuite = new AaveV3HorizonProtectionSuite(address(pool));
    }

    function testMonitoredSelectorsMatchAaveV3LikeSurface() external view {
        bytes4[] memory selectors = sparkSuite.getMonitoredSelectors();

        assertEq(selectors.length, 5);
        assertEq(selectors[0], IAaveV3LikePool.borrow.selector);
        assertEq(selectors[1], IAaveV3LikePool.withdraw.selector);
        assertEq(selectors[2], IAaveV3LikePool.liquidationCall.selector);
        assertEq(selectors[3], IAaveV3LikePool.setUserUseReserveAsCollateral.selector);
        assertEq(selectors[4], IAaveV3LikePool.finalizeTransfer.selector);
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

    function testAaveAndSparkAssertionsDeploy() external {
        AaveV3HorizonOperationSafetyAssertion aaveAssertion = new AaveV3HorizonOperationSafetyAssertion(address(pool));
        SparkLendV1OperationSafetyAssertion sparkAssertion = new SparkLendV1OperationSafetyAssertion(address(pool));

        assertTrue(address(aaveAssertion) != address(0));
        assertTrue(address(sparkAssertion) != address(0));
        assertTrue(address(aaveSuite) != address(0));
        assertTrue(address(sparkSuite) != address(0));
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
}
