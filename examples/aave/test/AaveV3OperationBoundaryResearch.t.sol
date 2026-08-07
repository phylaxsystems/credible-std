// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {CredibleTest} from "credible-std/CredibleTest.sol";
import {ForkUtils} from "credible-std/utils/ForkUtils.sol";
import {PhEvm} from "credible-std/PhEvm.sol";
import {ILendingProtectionSuite} from "credible-std/protection/lending/ILendingProtectionSuite.sol";
import {
    LendingBaseAssertion,
    LendingProtectionSuiteBase
} from "credible-std/protection/lending/LendingBaseAssertion.sol";

interface IBoundaryPool {
    function finalizeTransfer(
        address asset,
        address from,
        address to,
        uint256 amount,
        uint256 balanceFromBefore,
        uint256 balanceToBefore
    ) external;

    function healthOf(address account) external view returns (int256);
}

/// @notice A minimal Pool that can either change health inside finalizeTransfer or merely validate
///         state already changed by its aToken caller.
contract BoundaryPool is IBoundaryPool {
    mapping(address => int256) internal health;
    address internal pendingAccount;
    int256 internal pendingHealth;
    bool internal applyPending;

    function setHealth(address account, int256 value) external {
        health[account] = value;
    }

    function setPending(address account, int256 value, bool applyInside) external {
        pendingAccount = account;
        pendingHealth = value;
        applyPending = applyInside;
    }

    function finalizeTransfer(address, address, address, uint256, uint256, uint256) external {
        if (applyPending) {
            health[pendingAccount] = pendingHealth;
        }
    }

    function healthOf(address account) external view returns (int256) {
        return health[account];
    }
}

/// @notice Models AToken._transfer: balances change before Pool.finalizeTransfer is entered.
contract BoundaryAToken {
    function transferThenFinalize(BoundaryPool pool, address from, address to, int256 healthAfterTransfer) external {
        pool.setHealth(from, healthAfterTransfer);
        pool.finalizeTransfer(address(this), from, to, 1, 1, 0);
    }
}

/// @notice Flat research suite, avoiding the production child-contract runtime issue so this test
///         isolates the pre-call boundary selected for finalizeTransfer.
contract BoundaryTransferAssertion is LendingProtectionSuiteBase, LendingBaseAssertion {
    address internal immutable POOL;

    constructor(address pool_) {
        POOL = pool_;
    }

    function _suite() internal view override returns (ILendingProtectionSuite) {
        return ILendingProtectionSuite(address(this));
    }

    function getMonitoredSelectors() external pure override returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = IBoundaryPool.finalizeTransfer.selector;
    }

    function decodeOperation(TriggeredCall calldata triggered)
        external
        pure
        override
        returns (OperationContext memory operation)
    {
        (, address from,,,,) = abi.decode(triggered.input[4:], (address, address, address, uint256, uint256, uint256));
        operation.selector = triggered.selector;
        operation.caller = triggered.caller;
        operation.kind = OperationKind.TransferCollateral;
        operation.account = from;
        operation.reducesEffectiveCollateral = true;
    }

    function shouldCheckPostOperationSolvency(OperationContext calldata operation)
        external
        pure
        override
        returns (bool)
    {
        return operation.account != address(0) && operation.reducesEffectiveCollateral;
    }

    function getAccountSnapshot(address account, PhEvm.ForkId calldata fork)
        external
        view
        override
        returns (AccountSnapshot memory snapshot)
    {
        int256 health = abi.decode(_viewAt(POOL, abi.encodeCall(IBoundaryPool.healthOf, (account)), fork), (int256));
        snapshot.solvency.isSolvent = health >= 0;
        snapshot.solvency.metricName = "health";
        snapshot.solvency.metric = health;
        snapshot.solvency.threshold = 0;
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
        return "boundary research staticcall failed";
    }
}

contract AaveV3OperationBoundaryResearchTest is Test, CredibleTest {
    BoundaryPool internal pool;
    BoundaryAToken internal aToken;
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        pool = new BoundaryPool();
        aToken = new BoundaryAToken();
        pool.setHealth(alice, 1);
    }

    /// @dev Control: a health change made by finalizeTransfer itself is observed and rejected.
    function testHealthBreakInsideFinalizeTransferTrips() public {
        pool.setPending(alice, -1, true);
        _arm();

        vm.expectRevert();
        pool.finalizeTransfer(address(aToken), alice, bob, 1, 1, 0);
    }

    /// @dev Actual AToken ordering: the assertion's "pre-call" snapshot is already insolvent, so
    ///      LendingBaseAssertion deliberately skips the post-operation check.
    function testHealthBreakBeforeFinalizeTransferIsSkipped() public {
        pool.setPending(alice, -1, false);
        _arm();

        aToken.transferThenFinalize(pool, alice, bob, -1);
        assertEq(pool.healthOf(alice), -1);
    }

    function _arm() internal {
        bytes memory createData =
            abi.encodePacked(type(BoundaryTransferAssertion).creationCode, abi.encode(address(pool)));
        cl.assertion(address(pool), createData, LendingBaseAssertion.assertOperationSafety.selector);
    }
}
