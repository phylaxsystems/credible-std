// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// @title TriggerRecorder
/// @author Phylax Systems
/// @notice Precompile interface for registering assertion triggers
/// @dev Used within the `triggers()` function of assertion contracts to specify
/// when assertions should be executed. Supports call triggers, storage change triggers,
/// and balance change triggers.
interface TriggerRecorder {
    /// @notice Registers storage change trigger for all slots
    /// @param fnSelector The function selector of the assertion function.
    function registerStorageChangeTrigger(bytes4 fnSelector) external view;

    /// @notice Registers storage change trigger for a slot
    /// @param fnSelector The function selector of the assertion function.
    /// @param slot The storage slot to trigger on.
    function registerStorageChangeTrigger(bytes4 fnSelector, bytes32 slot) external view;

    /// @notice Registers balance change trigger for the AA
    /// @param fnSelector The function selector of the assertion function.
    function registerBalanceChangeTrigger(bytes4 fnSelector) external view;

    /// @notice Registers a call trigger for calls to the AA.
    /// @param fnSelector The function selector of the assertion function.
    /// @param triggerSelector The function selector of the trigger function.
    function registerCallTrigger(bytes4 fnSelector, bytes4 triggerSelector) external view;

    /// @notice Records a call trigger for the specified assertion function.
    /// A call trigger signifies that the assertion function should be called
    /// if the assertion adopter is called.
    /// @param fnSelector The function selector of the assertion function.
    function registerCallTrigger(bytes4 fnSelector) external view;

    // ---------------------------------------------------------------
    //  V2 trigger types
    // ---------------------------------------------------------------

    /// @notice Registers a trigger that fires when the adopter receives a call
    ///         matching triggerSelector. The assertion fires once per matching call,
    ///         with TriggerContext available via ph.context().
    /// @param fnSelector The assertion function to invoke.
    /// @param triggerSelector The 4-byte selector on the adopter to watch for.
    function registerFnCallTrigger(bytes4 fnSelector, bytes4 triggerSelector) external view;

    /// @notice Registers a trigger that fires once after the entire transaction completes.
    /// @param fnSelector The assertion function to invoke.
    function registerTxEndTrigger(bytes4 fnSelector) external view;

    /// @notice Registers a trigger that fires when a token's balances change.
    /// @param fnSelector The assertion function to invoke.
    /// @param token The ERC20 token address to watch.
    function registerErc20ChangeTrigger(bytes4 fnSelector, address token) external view;

    /// @notice Registers a circuit breaker trigger that fires when cumulative
    ///         ERC20 outflow from the assertion adopter exceeds a percentage
    ///         threshold within a rolling time window.
    /// @dev The executor handles all persistent state tracking, TVL snapshots,
    ///      and threshold enforcement internally.
    /// @param token The ERC20 token address to monitor.
    /// @param thresholdBps Maximum cumulative outflow as basis points of the
    ///        TVL snapshot taken at window start. 1000 = 10%.
    /// @param windowDuration Rolling window length in seconds. Balance deltas are
    ///        stored in 10-second buckets; old buckets that fall outside the window
    ///        are dropped as the window slides forward.
    /// @param fnSelector The assertion function to invoke when the threshold
    ///        is breached.
    function watchCumulativeOutflow(address token, uint256 thresholdBps, uint256 windowDuration, bytes4 fnSelector)
        external
        view;
}
