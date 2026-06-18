// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {PhEvm} from "../../../src/PhEvm.sol";
import {AssertionSpec} from "../../../src/SpecRecorder.sol";
import {IPerpetualProtectionSuite} from "../../../src/protection/perpetual/IPerpetualProtectionSuite.sol";
import {PerpetualBaseAssertion} from "../../../src/protection/perpetual/PerpetualBaseAssertion.sol";

interface ITestPerp {
    function op(address account) external;
    function equityOf(address account) external view returns (int256);
}

/// @notice Minimal perp: a single risk-reducing `op(address)` plus a per-account equity getter.
contract MockPerp is ITestPerp {
    mapping(address => int256) internal equity;
    mapping(address => int256) internal pending;

    function setEquity(address account, int256 value) external {
        equity[account] = value;
    }

    function setPending(address account, int256 value) external {
        pending[account] = value;
    }

    function op(address account) external override {
        equity[account] = pending[account];
    }

    function equityOf(address account) external view override returns (int256) {
        return equity[account];
    }
}

/// @notice Minimal combined suite + perpetual base, returning itself as the suite. Implements the
///         `IPerpetualProtectionSuite` surface directly (rather than via `PerpetualProtectionSuiteBase`)
///         to stay under the contract-size limit, so the assertion actually deploys and exercises the
///         generic per-call decode + post-mutation risk path — including the getAllCallInputs
///         selector-prepend in `PerpetualBaseAssertion._resolveTriggeredCall`. Without that prepend,
///         `decodeOperation`'s `triggered.input[4:]` strips four bytes of the real first argument and
///         reads a corrupted account, so an honest op would no longer decode `borrower`.
contract TestPerpRiskAssertion is PerpetualBaseAssertion, IPerpetualProtectionSuite {
    address internal immutable PERP;

    constructor(address perp_) {
        PERP = perp_;
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    function _suite() internal view override returns (IPerpetualProtectionSuite) {
        return IPerpetualProtectionSuite(address(this));
    }

    function getMonitoredSelectors() external pure override returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = ITestPerp.op.selector;
    }

    /// @dev Disable every optional check family so the assertion runs decode + the post-mutation gate.
    function enabledCheckKinds() external pure override returns (EnabledCheckKinds memory enabled) {
        enabled;
    }

    function decodeOperation(TriggeredCall calldata triggered)
        external
        pure
        override
        returns (OperationContext memory operation)
    {
        operation.selector = triggered.selector;
        operation.caller = triggered.caller;
        operation.kind = OperationKind.IncreasePosition;
        operation.account = abi.decode(triggered.input[4:], (address));
        operation.reducesAccountSafety = true;
    }

    function shouldCheckPostMutationRisk(OperationContext calldata operation) external pure override returns (bool) {
        return operation.account != address(0) && operation.reducesAccountSafety;
    }

    /// @dev Reads the post-call equity for the decoded account and gates on `equity >= 0`.
    function getPostMutationSnapshot(
        TriggeredCall calldata,
        OperationContext calldata operation,
        PhEvm.ForkId calldata fork
    ) external view override returns (AccountSnapshot memory snapshot) {
        int256 equity = abi.decode(
            _viewAt(PERP, abi.encodeCall(ITestPerp.equityOf, (operation.account)), fork), (int256)
        );
        snapshot.risk.equity = equity;
        snapshot.risk.hasBadDebt = equity < 0;
        snapshot.risk.isHealthy = equity >= 0;
    }

    // --- Unused interface surface (the assertion never reaches these in this test) ---------------

    function getExecutionPriceChecks(
        TriggeredCall calldata,
        OperationContext calldata,
        PhEvm.ForkId calldata,
        PhEvm.ForkId calldata
    ) external pure override returns (ExecutionPriceCheck[] memory) {}

    function getLiquidityCoverageChecks(
        TriggeredCall calldata,
        OperationContext calldata,
        PhEvm.ForkId calldata,
        PhEvm.ForkId calldata
    ) external pure override returns (LiquidityCoverageCheck[] memory) {}

    function getFundingDeltaChecks(
        TriggeredCall calldata,
        OperationContext calldata,
        PhEvm.ForkId calldata,
        PhEvm.ForkId calldata
    ) external pure override returns (FundingDeltaCheck[] memory) {}

    function getLiquidationChecks(
        TriggeredCall calldata,
        OperationContext calldata,
        PhEvm.ForkId calldata,
        PhEvm.ForkId calldata
    ) external pure override returns (LiquidationCheck[] memory) {}

    function getOracleAnchorChecks(
        TriggeredCall calldata,
        OperationContext calldata,
        PhEvm.ForkId calldata,
        PhEvm.ForkId calldata
    ) external pure override returns (OracleAnchorCheck[] memory) {}

    function getAccountingConservationChecks(
        TriggeredCall calldata,
        OperationContext calldata,
        PhEvm.ForkId calldata,
        PhEvm.ForkId calldata
    ) external pure override returns (AccountingConservationCheck[] memory) {}

    function getAccountSnapshot(address, PhEvm.ForkId calldata)
        external
        pure
        override
        returns (AccountSnapshot memory)
    {}

    function getAccountState(address, PhEvm.ForkId calldata) external pure override returns (AccountState memory) {}

    function getAccountPositions(address, PhEvm.ForkId calldata)
        external
        pure
        override
        returns (PositionState[] memory)
    {}

    function evaluateRisk(AccountState calldata, PositionState[] calldata, PhEvm.ForkId calldata)
        external
        pure
        override
        returns (RiskState memory)
    {}
}

contract PerpetualOperationSafetyPerCallTest is Test, CredibleTest {
    MockPerp internal perp;
    address internal borrower = makeAddr("borrower");

    function setUp() public {
        perp = new MockPerp();
    }

    function _arm() internal {
        bytes memory createData = abi.encodePacked(type(TestPerpRiskAssertion).creationCode, abi.encode(address(perp)));
        cl.assertion(address(perp), createData, PerpetualBaseAssertion.assertOperationSafety.selector);
    }

    function testPerpHonestOpPasses() public {
        perp.setPending(borrower, 1); // ends healthy

        // Passing requires decoding `borrower` correctly, which only holds when the triggered
        // calldata is selector-prefixed. A double-strip would corrupt the decoded account.
        _arm();
        perp.op(borrower);
    }

    function testPerpBadDebtOpTrips() public {
        // Decoding the correct account is essential: the op names `borrower`, whose equity goes
        // negative at PostCall, creating self bad debt.
        perp.setPending(borrower, -1);

        _arm();
        vm.expectRevert();
        perp.op(borrower);
    }

    function testDecodeOperationUsesSelectorPrefixedInput() public {
        // `decodeOperation` expects selector-prefixed calldata (the base re-prepends the selector
        // that getAllCallInputs strips). Feeding it that shape must decode the account back exactly.
        TestPerpRiskAssertion suite = new TestPerpRiskAssertion(address(perp));
        IPerpetualProtectionSuite.OperationContext memory op = suite.decodeOperation(
            IPerpetualProtectionSuite.TriggeredCall({
                selector: ITestPerp.op.selector,
                caller: borrower,
                target: address(perp),
                input: abi.encodeCall(ITestPerp.op, (borrower)),
                callStart: 1,
                callEnd: 2
            })
        );

        assertEq(op.account, borrower);
        assertEq(op.selector, ITestPerp.op.selector);
    }
}
