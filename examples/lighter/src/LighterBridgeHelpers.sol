// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "credible-std/PhEvm.sol";

import {RollupBridgeStateMachineAssertion} from "./RollupBridgeStateMachineAssertion.sol";
import {IZkLighterLike} from "./LighterBridgeInterfaces.sol";

/// @title LighterBridgeHelpers
/// @author Phylax Systems
/// @notice Fork-aware state reads for the Lighter `ZkLighter` bridge example.
/// @dev Reads the rollup state machine through the `IZkLighterLike` getter surface at a given
///      snapshot fork. The bridge address is supplied to the constructor, so the assertion never
///      reads mutable target state at deploy time (the Credible assertion-deploy runtime is isolated
///      from the calling state). The bridge address is also the assertion adopter.
abstract contract LighterBridgeHelpers is RollupBridgeStateMachineAssertion {
    /// @notice The `ZkLighter` proxy: funds custody, rollup state machine, and assertion adopter.
    address internal immutable BRIDGE;

    constructor(address bridge_) {
        require(bridge_ != address(0), "LighterBridge: bridge zero");
        BRIDGE = bridge_;
    }

    /// @inheritdoc RollupBridgeStateMachineAssertion
    function _readRollupState(PhEvm.ForkId memory fork) internal view override returns (RollupState memory state) {
        state.committedBatches = _readUintAt(BRIDGE, abi.encodeCall(IZkLighterLike.committedBatchesCount, ()), fork);
        state.verifiedBatches = _readUintAt(BRIDGE, abi.encodeCall(IZkLighterLike.verifiedBatchesCount, ()), fork);
        state.executedBatches = _readUintAt(BRIDGE, abi.encodeCall(IZkLighterLike.executedBatchesCount, ()), fork);
        state.committedPriorityRequests =
            _readUintAt(BRIDGE, abi.encodeCall(IZkLighterLike.committedPriorityRequestCount, ()), fork);
        state.verifiedPriorityRequests =
            _readUintAt(BRIDGE, abi.encodeCall(IZkLighterLike.verifiedPriorityRequestCount, ()), fork);
        state.executedPriorityRequests =
            _readUintAt(BRIDGE, abi.encodeCall(IZkLighterLike.executedPriorityRequestCount, ()), fork);
        state.openPriorityRequests =
            _readUintAt(BRIDGE, abi.encodeCall(IZkLighterLike.openPriorityRequestCount, ()), fork);
        state.stateRoot = _readBytes32At(BRIDGE, abi.encodeCall(IZkLighterLike.stateRoot, ()), fork);
        state.inDesertMode = _readBoolAt(BRIDGE, abi.encodeCall(IZkLighterLike.desertMode, ()), fork);
    }

    /// @inheritdoc RollupBridgeStateMachineAssertion
    function _stateRootUpdateSelector() internal pure override returns (bytes4) {
        return IZkLighterLike.updateStateRoot.selector;
    }

    /// @notice Decodes a snapshot-time static call as `bytes32`.
    function _readBytes32At(address target, bytes memory data, PhEvm.ForkId memory fork)
        internal
        view
        returns (bytes32 value)
    {
        return abi.decode(_viewAt(target, data, fork), (bytes32));
    }

    function _viewFailureMessage() internal pure override returns (string memory) {
        return "LighterBridge: state read failed";
    }
}
