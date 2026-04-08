// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Credible} from "./Credible.sol";
import {PhEvm} from "./PhEvm.sol";
import {TriggerRecorder} from "./TriggerRecorder.sol";
import {SpecRecorder, AssertionSpec} from "./SpecRecorder.sol";
import {StateChanges} from "./StateChanges.sol";

/// @title Assertion
/// @author Phylax Systems
/// @notice Base contract for creating Credible Layer assertions
/// @dev Inherit from this contract to create custom assertions. Assertions can inspect
/// transaction state via the inherited `ph` precompile and register triggers to specify
/// when the assertion should be executed.
///
/// Example:
/// ```solidity
/// contract MyAssertion is Assertion {
///     function triggers() external view override {
///         registerCallTrigger(this.checkInvariant.selector, ITarget.deposit.selector);
///     }
///
///     function checkInvariant() external {
///         ph.forkPostTx();
///         // Check invariants...
///     }
/// }
/// ```
abstract contract Assertion is Credible, StateChanges {
    /// @notice Gas budget forwarded to staticcallAt view calls.
    uint64 internal constant VIEW_GAS = 500_000;

    /// @notice The trigger recorder precompile for registering assertion triggers
    /// @dev Address is derived from a deterministic hash for consistency
    TriggerRecorder constant triggerRecorder = TriggerRecorder(address(uint160(uint256(keccak256("TriggerRecorder")))));

    /// @notice The spec recorder precompile for registering the assertion spec
    /// @dev Address is derived from keccak256("SpecRecorder")
    SpecRecorder constant specRecorder = SpecRecorder(address(uint160(uint256(keccak256("SpecRecorder")))));

    /// @notice Used to record fn selectors and their triggers.
    function triggers() external view virtual;

    // ---------------------------------------------------------------
    //  Legacy trigger registration
    // ---------------------------------------------------------------

    /// @notice Registers a call trigger for the AA without specifying an AA function selector.
    /// This will trigger the assertion function on any call to the AA.
    /// @param fnSelector The function selector of the assertion function.
    function registerCallTrigger(bytes4 fnSelector) internal view {
        triggerRecorder.registerCallTrigger(fnSelector);
    }

    /// @notice Registers a call trigger for calls to the AA with a specific AA function selector.
    /// @param fnSelector The function selector of the assertion function.
    /// @param triggerSelector The function selector upon which the assertion will be triggered.
    function registerCallTrigger(bytes4 fnSelector, bytes4 triggerSelector) internal view {
        triggerRecorder.registerCallTrigger(fnSelector, triggerSelector);
    }

    /// @notice Registers storage change trigger for any slot
    /// @param fnSelector The function selector of the assertion function.
    function registerStorageChangeTrigger(bytes4 fnSelector) internal view {
        triggerRecorder.registerStorageChangeTrigger(fnSelector);
    }

    /// @notice Registers storage change trigger for a specific slot
    /// @param fnSelector The function selector of the assertion function.
    /// @param slot The storage slot to trigger on.
    function registerStorageChangeTrigger(bytes4 fnSelector, bytes32 slot) internal view {
        triggerRecorder.registerStorageChangeTrigger(fnSelector, slot);
    }

    /// @notice Registers balance change trigger for the AA
    /// @param fnSelector The function selector of the assertion function.
    function registerBalanceChangeTrigger(bytes4 fnSelector) internal view {
        triggerRecorder.registerBalanceChangeTrigger(fnSelector);
    }

    // ---------------------------------------------------------------
    //  V2 trigger registration
    // ---------------------------------------------------------------

    /// @notice Registers an onFnCall trigger. The assertion fires once per matching call,
    ///         with TriggerContext available via ph.context().
    /// @param fnSelector The assertion function to invoke.
    /// @param triggerSelector The 4-byte selector on the adopter to watch for.
    function registerFnCallTrigger(bytes4 fnSelector, bytes4 triggerSelector) internal view {
        triggerRecorder.registerFnCallTrigger(fnSelector, triggerSelector);
    }

    /// @notice Registers a trigger that fires once after the entire transaction completes.
    /// @param fnSelector The assertion function to invoke.
    function registerTxEndTrigger(bytes4 fnSelector) internal view {
        triggerRecorder.registerTxEndTrigger(fnSelector);
    }

    /// @notice Registers a trigger that fires when a token's balances change.
    /// @param fnSelector The assertion function to invoke.
    /// @param token The ERC20 token address to watch.
    function registerErc20ChangeTrigger(bytes4 fnSelector, address token) internal view {
        triggerRecorder.registerErc20ChangeTrigger(fnSelector, token);
    }

    // ---------------------------------------------------------------
    //  V2 call matching
    // ---------------------------------------------------------------

    /// @notice Returns a CallFilter that only matches successful calls at any depth.
    function _successOnlyFilter() internal pure returns (PhEvm.CallFilter memory filter) {
        filter = PhEvm.CallFilter({
            callType: 0, minDepth: 0, maxDepth: type(uint32).max, topLevelOnly: false, successOnly: true
        });
    }

    /// @notice Returns successful calls matching target and selector, up to limit.
    function _matchingCalls(address target, bytes4 selector, uint256 limit)
        internal
        view
        returns (PhEvm.TriggerCall[] memory)
    {
        return ph.matchingCalls(target, selector, _successOnlyFilter(), limit);
    }

    // ---------------------------------------------------------------
    //  V2 state-reading helpers
    // ---------------------------------------------------------------

    /// @notice Execute a view call against a snapshot fork and return the raw result bytes.
    function _viewAt(address target, bytes memory data, PhEvm.ForkId memory fork) internal view returns (bytes memory) {
        PhEvm.StaticCallResult memory result = ph.staticcallAt(target, data, VIEW_GAS, fork);
        require(result.ok, "staticcallAt failed");
        return result.data;
    }

    /// @notice Read a single uint256 from target at fork.
    function _readUintAt(address target, bytes memory data, PhEvm.ForkId memory fork) internal view returns (uint256) {
        return abi.decode(_viewAt(target, data, fork), (uint256));
    }

    /// @notice Read a single address from target at fork.
    function _readAddressAt(address target, bytes memory data, PhEvm.ForkId memory fork)
        internal
        view
        returns (address)
    {
        return abi.decode(_viewAt(target, data, fork), (address));
    }

    /// @notice Read a single bool from target at fork.
    function _readBoolAt(address target, bytes memory data, PhEvm.ForkId memory fork) internal view returns (bool) {
        return abi.decode(_viewAt(target, data, fork), (bool));
    }

    // ---------------------------------------------------------------
    //  ForkId constructors
    // ---------------------------------------------------------------

    function _preTx() internal pure returns (PhEvm.ForkId memory) {
        return PhEvm.ForkId({forkType: 0, callIndex: 0});
    }

    function _postTx() internal pure returns (PhEvm.ForkId memory) {
        return PhEvm.ForkId({forkType: 1, callIndex: 0});
    }

    function _preCall(uint256 callId) internal pure returns (PhEvm.ForkId memory) {
        return PhEvm.ForkId({forkType: 2, callIndex: callId});
    }

    function _postCall(uint256 callId) internal pure returns (PhEvm.ForkId memory) {
        return PhEvm.ForkId({forkType: 3, callIndex: callId});
    }

    // ---------------------------------------------------------------
    //  Spec registration
    // ---------------------------------------------------------------


    /// @notice Registers the desired assertion spec. Must be called within the constructor.
    /// The assertion spec defines what subset of precompiles are available.
    /// Can only be called once. For an assertion to be valid, it needs a defined spec.
    /// @param spec The desired AssertionSpec.
    function registerAssertionSpec(AssertionSpec spec) internal view {
        specRecorder.registerAssertionSpec(spec);
    }
}
