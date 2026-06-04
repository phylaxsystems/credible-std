// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {ForkUtils} from "../../../src/utils/ForkUtils.sol";
import {PhEvm} from "../../../src/PhEvm.sol";
import {ILendingProtectionSuite} from "../../../src/protection/lending/ILendingProtectionSuite.sol";
import {LendingBaseAssertion, LendingProtectionSuiteBase} from "../../../src/protection/lending/LendingBaseAssertion.sol";

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
///         deploy (unlike the full AaveV3-like suite), so it exercises the generic tx-end solvency
///         enumerate + decode path — including the getAllCallInputs selector-prepend fix.
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

contract OpBatcher {
    ITestLendingPool internal immutable POOL;

    constructor(ITestLendingPool pool_) {
        POOL = pool_;
    }

    function twoOps(address account) external {
        POOL.op(account);
        POOL.op(account);
    }
}

contract LendingSolvencyTxEndTest is Test, CredibleTest {
    MockLendingPool internal pool;
    address internal borrower = makeAddr("borrower");

    function setUp() public {
        pool = new MockLendingPool();
    }

    function _arm() internal {
        bytes memory createData =
            abi.encodePacked(type(TestLendingSolvencyAssertion).creationCode, abi.encode(address(pool)));
        cl.assertion(address(pool), createData, LendingBaseAssertion.assertAccountSolvency.selector);
    }

    function testSolvencyHonestOpPasses() public {
        pool.setPending(borrower, 1); // ends solvent

        _arm();
        pool.op(borrower);
    }

    function testSolvencyBreakingOpTrips() public {
        // Decoding the correct account is essential: the op names `borrower`, who is solvent at
        // PreTx (health 0) and insolvent at PostTx (health -1).
        pool.setPending(borrower, -1);

        _arm();
        vm.expectRevert();
        pool.op(borrower);
    }

    function testSolvencyPreInsolventAccountSkipped() public {
        pool.setHealth(borrower, -5); // already insolvent at PreTx
        pool.setPending(borrower, -5);

        _arm();
        pool.op(borrower);
    }

    function testSolvencyFiresOnceForBatchedOps() public {
        pool.setPending(borrower, 1);
        OpBatcher batcher = new OpBatcher(pool);

        _arm();
        batcher.twoOps(borrower);
    }
}
