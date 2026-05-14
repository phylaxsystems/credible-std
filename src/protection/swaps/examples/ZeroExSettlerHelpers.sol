// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "../../../Assertion.sol";
import {PhEvm} from "../../../PhEvm.sol";
import {AssertionSpec} from "../../../SpecRecorder.sol";

import {
    IERC20AllowanceReaderLike,
    IZeroExSettlerRegistryLike,
    ZeroExSettlerSlippage
} from "./ZeroExSettlerInterfaces.sol";

/// @title ZeroExSettlerHelpers
/// @author Phylax Systems
/// @notice Fork-aware helpers for 0x Settler router assertions.
abstract contract ZeroExSettlerHelpers is Assertion {
    address internal constant ETH_SENTINEL = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    bytes32 internal constant ERC20_TRANSFER_SIG = keccak256("Transfer(address,address,uint256)");

    address internal immutable SETTLER;
    address internal immutable REGISTRY;
    uint128 internal immutable FEATURE_ID;

    constructor(address settler_, address registry_, uint128 featureId_) {
        SETTLER = settler_;
        REGISTRY = registry_;
        FEATURE_ID = featureId_;
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    function _viewFailureMessage() internal pure override returns (string memory) {
        return "0xSettler: fork read failed";
    }

    function _requireConfiguredSettlerIsAdopter() internal view {
        require(ph.getAssertionAdopter() == SETTLER, "0xSettler: configured settler is not adopter");
    }

    function _requireRegisteredSettlerAt(PhEvm.ForkId memory fork) internal view {
        address current =
            _readAddressAt(REGISTRY, abi.encodeCall(IZeroExSettlerRegistryLike.ownerOf, (FEATURE_ID)), fork);

        if (current == SETTLER) {
            return;
        }

        address previous = _readAddressAt(REGISTRY, abi.encodeCall(IZeroExSettlerRegistryLike.prev, (FEATURE_ID)), fork);
        require(previous == SETTLER, "0xSettler: unregistered settler");
    }

    function _slippageFromCallInput(bytes memory input) internal pure returns (ZeroExSettlerSlippage memory slippage) {
        require(input.length >= 100, "0xSettler: short calldata");

        assembly {
            slippage := mload(0x40)
            mstore(0x40, add(slippage, 0x60))
            mstore(slippage, and(mload(add(input, 0x24)), 0xffffffffffffffffffffffffffffffffffffffff))
            mstore(add(slippage, 0x20), and(mload(add(input, 0x44)), 0xffffffffffffffffffffffffffffffffffffffff))
            mstore(add(slippage, 0x40), mload(add(input, 0x64)))
        }
    }

    function _assertNoPreCallAllowanceForTransferLogs(uint256 callId) internal view {
        PhEvm.LogQuery memory query = PhEvm.LogQuery({emitter: address(0), signature: ERC20_TRANSFER_SIG});
        PhEvm.Log[] memory logs = ph.getLogsForCall(query, callId);
        PhEvm.ForkId memory beforeFork = _preCall(callId);

        for (uint256 i; i < logs.length; ++i) {
            if (!_isErc20Transfer(logs[i])) {
                continue;
            }

            address from = _topicAddress(logs[i].topics[1]);
            uint256 amount = abi.decode(logs[i].data, (uint256));
            if (amount == 0) {
                continue;
            }

            uint256 allowance = _allowanceAt(logs[i].emitter, from, SETTLER, beforeFork);
            require(allowance == 0, "0xSettler: transfer source pre-approved settler");
        }
    }

    function _allowanceAt(address token, address owner, address spender, PhEvm.ForkId memory fork)
        internal
        view
        returns (uint256 allowance)
    {
        PhEvm.StaticCallResult memory result = ph.staticcallAt(
            token, abi.encodeCall(IERC20AllowanceReaderLike.allowance, (owner, spender)), FORK_VIEW_GAS, fork
        );
        require(result.ok, "0xSettler: allowance read failed");
        return abi.decode(result.data, (uint256));
    }

    function _isErc20Transfer(PhEvm.Log memory log) internal pure returns (bool) {
        return log.topics.length == 3 && log.topics[0] == ERC20_TRANSFER_SIG && log.data.length >= 32;
    }

    function _topicAddress(bytes32 topic) internal pure returns (address) {
        return address(uint160(uint256(topic)));
    }
}
