// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {Assertion} from "../../../src/Assertion.sol";
import {CredibleTest} from "../../../src/CredibleTest.sol";
import {AssertionSpec} from "../../../src/SpecRecorder.sol";
import {ILendingProtectionSuite} from "../../../src/protection/lending/ILendingProtectionSuite.sol";
import {IAaveV3LikePool} from "../../../src/protection/lending/examples/AaveV3LikeInterfaces.sol";
import {TydroProtectionSuite, ITydroL2Pool} from "../src/TydroOperationSafety.sol";

contract TydroCompactBorrowAssertion is Assertion {
    uint256 internal constant L2_SHORTENED_AMOUNT_MASK = type(uint128).max;

    constructor() {
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    function triggers() external view override {
        registerFnCallTrigger(this.assertCompactBorrowIsZeroAmount.selector, ITydroL2Pool.borrow.selector);
    }

    function assertCompactBorrowIsZeroAmount() external view {
        bytes memory input = ph.callinputAt(ph.context().callStart);
        bytes32 args = abi.decode(_stripSelector(input), (bytes32));
        uint256 amount = (uint256(args) >> 16) & L2_SHORTENED_AMOUNT_MASK;

        require(amount == 0, "Tydro: compact borrow amount nonzero");
    }

    function _stripSelector(bytes memory input) internal pure returns (bytes memory args) {
        require(input.length >= 4, "Tydro: short call input");
        args = new bytes(input.length - 4);
        for (uint256 i; i < args.length; ++i) {
            args[i] = input[i + 4];
        }
    }
}

contract MockTydroPool is ITydroL2Pool {
    address[] internal reserves;

    constructor(address reserve) {
        reserves.push(reserve);
    }

    function getReservesList() external view returns (address[] memory) {
        return reserves;
    }

    function borrow(bytes32) external override {}

    function withdraw(bytes32) external pure override returns (uint256) {
        return 0;
    }

    function liquidationCall(bytes32, bytes32) external pure override {}

    function setUserUseReserveAsCollateral(bytes32) external pure override {}
}

contract TydroOperationSafetyTest is Test, CredibleTest {
    MockTydroPool internal pool;
    TydroProtectionSuite internal suite;
    address internal reserve = makeAddr("reserve");
    address internal addressesProvider = makeAddr("addressesProvider");
    address internal caller = makeAddr("caller");

    function setUp() public {
        pool = new MockTydroPool(reserve);
        suite = new TydroProtectionSuite(address(pool), addressesProvider);
    }

    function testCompactSelectorsAreIncluded() public view {
        bytes4[] memory selectors = suite.getMonitoredSelectors();

        assertEq(selectors.length, 10);
        assertEq(selectors[6], ITydroL2Pool.borrow.selector);
        assertEq(selectors[7], ITydroL2Pool.withdraw.selector);
        assertEq(selectors[8], ITydroL2Pool.liquidationCall.selector);
        assertEq(selectors[9], ITydroL2Pool.setUserUseReserveAsCollateral.selector);
    }

    // --- Shipped TydroProtectionSuite.decodeOperation coverage -------------------------
    // These exercise the production suite that TydroOperationSafetyAssertion.assertOperationSafety
    // actually runs, rather than the test-local assertion above. They focus on Tydro's compact
    // L2 calldata decoder and the standard Aave v3 delegation path.

    function testL2BorrowDecodesAssetAndAmount() public view {
        uint256 amount = 250e6;
        bytes32 args = _packL2Amount(0, amount);

        ILendingProtectionSuite.OperationContext memory op = suite.decodeOperation(
            _triggered(ITydroL2Pool.borrow.selector, abi.encodeCall(ITydroL2Pool.borrow, (args)))
        );

        assertEq(uint256(op.kind), uint256(ILendingProtectionSuite.OperationKind.Borrow));
        assertEq(op.account, caller);
        assertEq(op.asset, reserve);
        assertEq(op.amount, amount);
        assertTrue(op.increasesDebt);
        assertTrue(suite.shouldCheckPostOperationSolvency(op));
    }

    function testL2WithdrawDecodesMaxAmountSentinel() public view {
        // The compact uint128 max sentinel must expand to a full uint256 max withdrawal.
        bytes32 args = _packL2Amount(0, type(uint128).max);

        ILendingProtectionSuite.OperationContext memory op = suite.decodeOperation(
            _triggered(ITydroL2Pool.withdraw.selector, abi.encodeCall(ITydroL2Pool.withdraw, (args)))
        );

        assertEq(uint256(op.kind), uint256(ILendingProtectionSuite.OperationKind.WithdrawCollateral));
        assertEq(op.account, caller);
        assertEq(op.asset, reserve);
        assertEq(op.counterparty, caller);
        assertEq(op.amount, type(uint256).max);
        assertTrue(op.reducesEffectiveCollateral);
        assertTrue(suite.shouldCheckPostOperationSolvency(op));
    }

    function testL2LiquidationDecodesUserAndAssets() public {
        address user = makeAddr("borrower");
        uint256 debtToCover = 55e6;
        // args1: user packed above bit 32; both compact asset ids resolve to reserve index 0.
        bytes32 args1 = bytes32(uint256(uint160(user)) << 32);
        bytes32 args2 = _packL2Amount(0, debtToCover);

        ILendingProtectionSuite.OperationContext memory op = suite.decodeOperation(
            _triggered(
                ITydroL2Pool.liquidationCall.selector, abi.encodeCall(ITydroL2Pool.liquidationCall, (args1, args2))
            )
        );

        assertEq(uint256(op.kind), uint256(ILendingProtectionSuite.OperationKind.Liquidation));
        assertEq(op.account, user);
        assertEq(op.asset, reserve);
        assertEq(op.relatedAsset, reserve);
        assertEq(op.counterparty, caller);
        assertEq(op.amount, debtToCover);
        // Liquidations are not self-inflicted, so the post-op solvency gate must not fire.
        assertFalse(suite.shouldCheckPostOperationSolvency(op));
    }

    function testL2DisableCollateralOnlyTriggersWhenTurningOff() public view {
        bytes32 disableArgs = bytes32((uint256(1) << 16) | 0); // disable bit set, asset id 0
        bytes32 enableArgs = bytes32(uint256(0)); // disable bit clear

        ILendingProtectionSuite.OperationContext memory disableOp = suite.decodeOperation(
            _triggered(
                ITydroL2Pool.setUserUseReserveAsCollateral.selector,
                abi.encodeCall(ITydroL2Pool.setUserUseReserveAsCollateral, (disableArgs))
            )
        );
        ILendingProtectionSuite.OperationContext memory enableOp = suite.decodeOperation(
            _triggered(
                ITydroL2Pool.setUserUseReserveAsCollateral.selector,
                abi.encodeCall(ITydroL2Pool.setUserUseReserveAsCollateral, (enableArgs))
            )
        );

        assertEq(uint256(disableOp.kind), uint256(ILendingProtectionSuite.OperationKind.DisableCollateral));
        assertEq(disableOp.account, caller);
        assertEq(disableOp.asset, reserve);
        assertTrue(disableOp.reducesEffectiveCollateral);
        assertTrue(suite.shouldCheckPostOperationSolvency(disableOp));

        assertEq(uint256(enableOp.kind), uint256(ILendingProtectionSuite.OperationKind.Unknown));
        assertFalse(suite.shouldCheckPostOperationSolvency(enableOp));
    }

    function testStandardAaveBorrowDelegatesToBaseDecoder() public {
        // Non-compact selectors must fall through to the shared Aave v3 decoder.
        ILendingProtectionSuite.OperationContext memory op = suite.decodeOperation(
            _triggered(
                IAaveV3LikePool.borrow.selector,
                abi.encodeCall(IAaveV3LikePool.borrow, (reserve, 123e18, 2, 0, makeAddr("onBehalfOf")))
            )
        );

        assertEq(uint256(op.kind), uint256(ILendingProtectionSuite.OperationKind.Borrow));
        assertEq(op.account, makeAddr("onBehalfOf"));
        assertEq(op.asset, reserve);
        assertEq(op.amount, 123e18);
        assertTrue(op.increasesDebt);
    }

    /// @notice Packs Tydro's compact L2 calldata word: low 16 bits = asset id, next 128 = amount.
    function _packL2Amount(uint16 assetId, uint256 amount) internal pure returns (bytes32) {
        return bytes32((amount << 16) | uint256(assetId));
    }

    function _triggered(bytes4 selector, bytes memory input)
        internal
        view
        returns (ILendingProtectionSuite.TriggeredCall memory)
    {
        return ILendingProtectionSuite.TriggeredCall({
            selector: selector, caller: caller, target: address(pool), input: input, callStart: 1, callEnd: 2
        });
    }

    function testZeroAmountCompactBorrowPasses() public {
        bytes memory createData = abi.encodePacked(type(TydroCompactBorrowAssertion).creationCode);
        cl.assertion(address(pool), createData, TydroCompactBorrowAssertion.assertCompactBorrowIsZeroAmount.selector);

        pool.borrow(bytes32(0));
    }

    function testNonzeroAmountCompactBorrowTrips() public {
        bytes memory createData = abi.encodePacked(type(TydroCompactBorrowAssertion).creationCode);
        cl.assertion(address(pool), createData, TydroCompactBorrowAssertion.assertCompactBorrowIsZeroAmount.selector);

        bytes32 args = bytes32(uint256(1) << 16);
        vm.expectRevert(bytes("Tydro: compact borrow amount nonzero"));
        pool.borrow(args);
    }
}
