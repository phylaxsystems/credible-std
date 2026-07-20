// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {ForkUtils} from "../../../src/utils/ForkUtils.sol";
import {PhEvm} from "../../../src/PhEvm.sol";
import {ILendingProtectionSuite} from "../../../src/protection/lending/ILendingProtectionSuite.sol";
import {
    LendingBaseAssertion,
    LendingProtectionSuiteBase
} from "../../../src/protection/lending/LendingBaseAssertion.sol";

interface ITestLendingPool {
    function op(address account) external;
    function healthOf(address account) external view returns (int256);
}

/// @notice Minimal pool: a single risk-increasing `op(address)` plus a per-account health getter.
contract MockLendingPool is ITestLendingPool {
    mapping(address => int256) internal health;
    mapping(address => int256) internal pending;

    function setHealth(address account, int256 value) external {
        health[account] = value;
    }

    function setPending(address account, int256 value) external {
        pending[account] = value;
    }

    function op(address account) external override {
        health[account] = pending[account];
    }

    function healthOf(address account) external view override returns (int256) {
        return health[account];
    }
}

/// @notice Minimal combined suite + lending base, returning itself as the suite. Small enough to
///         deploy (unlike the full AaveV3-like suite), so it exercises the generic per-call
///         operation-safety decode + solvency path — including the getAllCallInputs selector-prepend
///         fix in `_resolveTriggeredCall`.
contract TestLendingSolvencyAssertion is LendingProtectionSuiteBase, LendingBaseAssertion {
    address internal immutable POOL;

    constructor(address pool_) {
        POOL = pool_;
    }

    function _suite() internal view override returns (ILendingProtectionSuite) {
        return ILendingProtectionSuite(address(this));
    }

    function getMonitoredSelectors() external pure override returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = ITestLendingPool.op.selector;
    }

    function decodeOperation(TriggeredCall calldata triggered)
        external
        pure
        override
        returns (OperationContext memory operation)
    {
        operation.selector = triggered.selector;
        operation.caller = triggered.caller;
        operation.kind = OperationKind.Borrow;
        operation.account = abi.decode(triggered.input[4:], (address));
        operation.increasesDebt = true;
    }

    function shouldCheckPostOperationSolvency(OperationContext calldata operation)
        external
        pure
        override
        returns (bool)
    {
        return operation.account != address(0) && operation.increasesDebt;
    }

    function getAccountSnapshot(address account, PhEvm.ForkId calldata fork)
        external
        view
        override
        returns (AccountSnapshot memory snapshot)
    {
        int256 health = abi.decode(_viewAt(POOL, abi.encodeCall(ITestLendingPool.healthOf, (account)), fork), (int256));
        snapshot.solvency.isSolvent = health >= 0;
        snapshot.solvency.metric = health;
    }

    function getAccountState(address, PhEvm.ForkId calldata) external pure override returns (AccountState memory) {}

    function getAccountBalances(address, PhEvm.ForkId calldata)
        external
        pure
        override
        returns (AccountBalance[] memory)
    {}

    function evaluateSolvency(AccountState calldata, AccountBalance[] calldata, PhEvm.ForkId calldata)
        external
        pure
        override
        returns (SolvencyState memory)
    {}

    function _viewFailureMessage()
        internal
        pure
        override(ForkUtils, LendingProtectionSuiteBase)
        returns (string memory)
    {
        return "lending suite staticcall failed";
    }
}

contract TestLegacyLendingSolvencyAssertion is TestLendingSolvencyAssertion {
    constructor(address pool_) TestLendingSolvencyAssertion(pool_) {}

    function triggers() external view override {
        registerFnCallTrigger(LendingBaseAssertion.assertPostOperationSolvency.selector, ITestLendingPool.op.selector);
    }
}

/// @notice Router that makes an account insolvent on the first op and repairs it on the second,
///         within the same transaction. Net tx-start -> tx-end state is solvent, but the
///         intermediate state after the first op is not.
contract RepairBatcher {
    MockLendingPool internal immutable POOL;

    constructor(MockLendingPool pool_) {
        POOL = pool_;
    }

    function breakThenRepair(address account) external {
        POOL.setPending(account, -1);
        POOL.op(account); // health -> -1 (insolvent intermediate state)
        POOL.setPending(account, 1);
        POOL.op(account); // health -> 1 (repaired before tx end)
    }
}

contract LendingSolvencyPerCallTest is Test, CredibleTest {
    MockLendingPool internal pool;
    address internal borrower = makeAddr("borrower");

    function setUp() public {
        pool = new MockLendingPool();
    }

    function _arm() internal {
        _armSelector(LendingBaseAssertion.assertOperationSafety.selector);
    }

    function _armSelector(bytes4 assertionSelector) internal {
        bytes memory createData = assertionSelector == LendingBaseAssertion.assertPostOperationSolvency.selector
            ? abi.encodePacked(type(TestLegacyLendingSolvencyAssertion).creationCode, abi.encode(address(pool)))
            : abi.encodePacked(type(TestLendingSolvencyAssertion).creationCode, abi.encode(address(pool)));
        cl.assertion(address(pool), createData, assertionSelector);
    }

    function testSolvencyHonestOpPasses() public {
        pool.setPending(borrower, 1); // ends solvent

        _arm();
        pool.op(borrower);
    }

    function testSolvencyBreakingOpTrips() public {
        // Decoding the correct account is essential: the op names `borrower`, who is solvent at
        // PreCall (health 0) and insolvent at PostCall (health -1).
        pool.setPending(borrower, -1);

        _arm();
        vm.expectRevert();
        pool.op(borrower);
    }

    function testSolvencyPreInsolventAccountSkipped() public {
        pool.setHealth(borrower, -5); // already insolvent at PreCall
        pool.setPending(borrower, -5);

        _arm();
        pool.op(borrower);
    }

    function testSolvencyTransientInsolvencyRepairedStillTrips() public {
        // The whole point of the per-call check: an account made insolvent by an individual op is
        // caught at that exact call, even though a later op in the same transaction repairs it before
        // tx end. A tx-end-only check would miss this because the net tx-start -> tx-end state is solvent.
        RepairBatcher batcher = new RepairBatcher(pool);

        _arm();
        vm.expectRevert();
        batcher.breakThenRepair(borrower);
    }

    function testLegacySolvencyAliasPassesHonestOperation() public {
        pool.setPending(borrower, 1);

        _armSelector(LendingBaseAssertion.assertPostOperationSolvency.selector);
        pool.op(borrower);
    }

    function testLegacySolvencyAliasTripsOnInsolvency() public {
        pool.setPending(borrower, -1);

        _armSelector(LendingBaseAssertion.assertPostOperationSolvency.selector);
        vm.expectRevert();
        pool.op(borrower);
    }
}
