// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "credible-std/Assertion.sol";
import {PhEvm} from "credible-std/PhEvm.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";

import {
    IERC20AllowanceReaderLike,
    IKyberMetaAggregationRouterV2Like,
    SwapDescriptionV2,
    SwapExecutionParams
} from "./KyberMetaAggregationRouterInterfaces.sol";

/// @title KyberMetaAggregationRouterHelpers
/// @author Phylax Systems
/// @notice Fork-aware helpers for KyberSwap MetaAggregationRouterV2 router assertions.
/// @dev Holds calldata decoding, allowance reads, and Transfer-log scanning so the public
///      assertion contract stays focused on stated invariants.
abstract contract KyberMetaAggregationRouterHelpers is Assertion {
    /// @notice KyberSwap native-asset sentinel used in place of an ERC20 address.
    address internal constant ETH_SENTINEL = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    bytes32 internal constant ERC20_TRANSFER_SIG = keccak256("Transfer(address,address,uint256)");
    bytes32 internal constant ERC20_APPROVAL_SIG = keccak256("Approval(address,address,uint256)");

    /// @notice `desc.flags` bit that marks an order the router may fill only partially.
    /// @dev Mirrors `MetaAggregationRouterV2._PARTIAL_FILL`. When set, the router enforces a
    ///      pro-rated minimum (`returnAmount * amount >= minReturnAmount * spentAmount`) it
    ///      measures from the actual spent amount, so a flat `minReturnAmount` floor does not hold.
    uint256 internal constant PARTIAL_FILL = 0x01;

    /// @notice The single fixed-address MetaAggregationRouterV2 this assertion protects.
    address internal immutable ROUTER;

    constructor(address router_) {
        ROUTER = router_;
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    function _viewFailureMessage() internal pure override returns (string memory) {
        return "Kyber: fork read failed";
    }

    /// @notice Confirms the adopter that armed this assertion is the configured router.
    function _requireConfiguredRouterIsAdopter() internal view {
        require(ph.getAssertionAdopter() == ROUTER, "Kyber: configured router is not adopter");
    }

    // ---------------------------------------------------------------
    //  Calldata decoding
    // ---------------------------------------------------------------

    /// @notice Decodes the swap description from the triggered call's calldata.
    /// @dev Dispatches on the entry-point selector because `swap`/`swapGeneric` wrap the
    ///      description in `SwapExecutionParams` while `swapSimpleMode` passes it as a standalone
    ///      argument.
    function _swapDescriptionFor(bytes4 selector, bytes memory raw)
        internal
        pure
        returns (SwapDescriptionV2 memory desc)
    {
        bytes memory args = _stripSelector(raw);

        if (
            selector == IKyberMetaAggregationRouterV2Like.swap.selector
                || selector == IKyberMetaAggregationRouterV2Like.swapGeneric.selector
        ) {
            return abi.decode(args, (SwapExecutionParams)).desc;
        }
        if (selector == IKyberMetaAggregationRouterV2Like.swapSimpleMode.selector) {
            (, desc,,) = abi.decode(args, (address, SwapDescriptionV2, bytes, bytes));
            return desc;
        }
        revert("Kyber: unsupported swap selector");
    }

    /// @notice Returns true if `flag` is set in `flags`. Mirrors `MetaAggregationRouterV2._flagsChecked`.
    function _flagsChecked(uint256 flags, uint256 flag) internal pure returns (bool) {
        return flags & flag != 0;
    }

    /// @notice Returns the ABI-encoded argument region of `raw`, dropping the 4-byte selector.
    /// @dev Word-wise copy. Both buffers are 32-byte aligned, so reading/writing the trailing
    ///      partial word stays inside allocated memory.
    function _stripSelector(bytes memory raw) internal pure returns (bytes memory args) {
        uint256 len = raw.length;
        require(len >= 4, "Kyber: short calldata");
        uint256 outLen = len - 4;
        args = new bytes(outLen);
        assembly {
            let src := add(raw, 36) // 32-byte length prefix + 4-byte selector
            let dst := add(args, 32)
            let end := add(dst, outLen)
            for {} lt(dst, end) {
                dst := add(dst, 32)
                src := add(src, 32)
            } { mstore(dst, mload(src)) }
        }
    }

    // ---------------------------------------------------------------
    //  Call-frame introspection
    // ---------------------------------------------------------------

    /// @notice Resolves the account that initiated the triggered router call.
    /// @dev The initiator is the account the router is expected to debit (it pulls `srcToken`
    ///      from `msg.sender`). Returns address(0) if the call frame cannot be matched.
    function _swapInitiator(uint256 callId, bytes4 selector) internal view returns (address initiator) {
        PhEvm.CallInputs[] memory calls = ph.getCallInputs(ROUTER, selector);
        for (uint256 i; i < calls.length; ++i) {
            if (calls[i].id == callId) {
                return calls[i].caller;
            }
        }
        return address(0);
    }

    // ---------------------------------------------------------------
    //  Authorization scanning
    // ---------------------------------------------------------------

    /// @notice Reverts if the triggered swap pulled tokens from any account, other than the
    ///         swap initiator, whose router allowance the swap exercised.
    /// @dev Scans ERC20 Transfer logs emitted inside the call frame. For each non-initiator
    ///      source the swap is treated as exercising a bystander's approval when either:
    ///      - it held a nonzero `allowance(from, router)` at the pre-call fork (a standing
    ///        approval, finite or max — a nonzero pre-call read catches both, which a post/pre
    ///        delta check alone would miss); or
    ///      - it granted the router an allowance *inside this same call* via an in-frame
    ///        `Approval(from, router, …)` log. The router's `_permit` path lets a swap submit a
    ///        bystander's signed EIP-2612 permit (attacker-supplied `owner`/`spender`), creating
    ///        `allowance(from, router)` mid-call. That allowance is invisible to the pre-call read,
    ///        so the standing-approval check alone would let a permit-then-drain through.
    function _assertOnlyInitiatorAllowanceExercised(uint256 callId, address initiator) internal view {
        PhEvm.Log[] memory transfers =
            ph.getLogsForCall(PhEvm.LogQuery({emitter: address(0), signature: ERC20_TRANSFER_SIG}), callId);
        PhEvm.Log[] memory approvals =
            ph.getLogsForCall(PhEvm.LogQuery({emitter: address(0), signature: ERC20_APPROVAL_SIG}), callId);
        PhEvm.ForkId memory beforeFork = _preCall(callId);

        for (uint256 i; i < transfers.length; ++i) {
            if (!_isErc20Transfer(transfers[i])) {
                continue;
            }

            address from = _topicAddress(transfers[i].topics[1]);
            if (from == ROUTER || from == initiator || from == address(0)) {
                continue;
            }

            uint256 amount = abi.decode(transfers[i].data, (uint256));
            if (amount == 0) {
                continue;
            }

            uint256 standingAllowance = _allowanceAt(transfers[i].emitter, from, ROUTER, beforeFork);
            bool grantedInCall = _approvedRouterInCall(approvals, transfers[i].emitter, from);
            require(
                standingAllowance == 0 && !grantedInCall,
                "Kyber: swap exercised third-party router allowance"
            );
        }
    }

    /// @notice Returns true if `owner` emitted an `Approval(owner, router, …)` on `token` inside
    ///         the scanned call, i.e. granted the router an allowance mid-call (e.g. via permit).
    function _approvedRouterInCall(PhEvm.Log[] memory approvals, address token, address owner)
        internal
        view
        returns (bool)
    {
        for (uint256 i; i < approvals.length; ++i) {
            PhEvm.Log memory log = approvals[i];
            if (log.emitter != token || log.topics.length != 3 || log.topics[0] != ERC20_APPROVAL_SIG) {
                continue;
            }
            if (_topicAddress(log.topics[1]) == owner && _topicAddress(log.topics[2]) == ROUTER) {
                return true;
            }
        }
        return false;
    }

    function _allowanceAt(address token, address owner, address spender, PhEvm.ForkId memory fork)
        internal
        view
        returns (uint256 allowance)
    {
        PhEvm.StaticCallResult memory result = ph.staticcallAt(
            token, abi.encodeCall(IERC20AllowanceReaderLike.allowance, (owner, spender)), FORK_VIEW_GAS, fork
        );
        require(result.ok, "Kyber: allowance read failed");
        return abi.decode(result.data, (uint256));
    }

    function _isErc20Transfer(PhEvm.Log memory log) internal pure returns (bool) {
        return log.topics.length == 3 && log.topics[0] == ERC20_TRANSFER_SIG && log.data.length >= 32;
    }

    function _topicAddress(bytes32 topic) internal pure returns (address) {
        return address(uint160(uint256(topic)));
    }
}
