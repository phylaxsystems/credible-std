// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "../../../src/Assertion.sol";
import {PhEvm} from "../../../src/PhEvm.sol";
import {AssertionSpec} from "../../../src/SpecRecorder.sol";
import {IAaveV3LikePool} from "../../../src/protection/lending/examples/AaveV3LikeInterfaces.sol";

/// @title AaveV3FlatAssertion
/// @notice Self-contained Aave v3-like post-borrow solvency assertion used by the credible-std
///         regression tests.
/// @dev The production `AaveV3LikeProtectionSuite` lives in a separate contract that the
///      assertion `new`s in its constructor. The Credible Layer's assertion-deploy runtime does
///      not preserve those child contracts, so a separate suite cannot be reached at trigger
///      registration or at execution time. This flat variant fuses the Aave borrow → health
///      factor check directly into the assertion contract.
contract AaveV3FlatAssertion is Assertion {
    error AaveV3NewlyUnhealthyAfterBorrow(address account, uint256 beforeHealthFactor, uint256 afterHealthFactor);

    uint256 internal constant HEALTH_FACTOR_THRESHOLD = 1e18;

    address internal immutable POOL;

    constructor(address pool_) {
        POOL = pool_;
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    function triggers() external view override {
        registerFnCallTrigger(this.assertBorrowSolvency.selector, IAaveV3LikePool.borrow.selector);
    }

    /// @notice Asserts that a borrow does not move the borrower from healthy to unhealthy.
    /// @dev Reads `getUserAccountData(onBehalfOf)` before and after the call. Accounts that were
    ///      already below 1.0 before the call are allowed so existing unhealthy positions do not
    ///      cause false positives.
    function assertBorrowSolvency() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        bytes memory input = ph.callinputAt(ctx.callStart);
        (,,,, address onBehalfOf) = abi.decode(_args(input), (address, uint256, uint256, uint16, address));

        uint256 beforeHealthFactor = _healthFactorAt(onBehalfOf, _preCall(ctx.callStart));
        if (beforeHealthFactor < HEALTH_FACTOR_THRESHOLD) {
            return;
        }

        uint256 afterHealthFactor = _healthFactorAt(onBehalfOf, _postCall(ctx.callEnd));

        if (afterHealthFactor < HEALTH_FACTOR_THRESHOLD) {
            revert AaveV3NewlyUnhealthyAfterBorrow(onBehalfOf, beforeHealthFactor, afterHealthFactor);
        }
    }

    function _healthFactorAt(address account, PhEvm.ForkId memory fork) internal view returns (uint256 healthFactor) {
        bytes memory data = abi.encodeCall(IAaveV3LikePool.getUserAccountData, (account));
        PhEvm.StaticCallResult memory result = ph.staticcallAt(POOL, data, 500_000, fork);
        require(result.ok, "AaveV3FlatAssertion: pool view failed");
        (,,,,, healthFactor) = abi.decode(result.data, (uint256, uint256, uint256, uint256, uint256, uint256));
    }

    function _args(bytes memory input) internal pure returns (bytes memory args) {
        require(input.length >= 4, "short calldata");
        args = new bytes(input.length - 4);
        for (uint256 i; i < args.length; ++i) {
            args[i] = input[i + 4];
        }
    }
}
