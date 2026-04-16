// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// @title PhEvm
/// @author Phylax Systems
/// @notice Precompile interface for accessing transaction state within assertions
/// @dev This interface provides access to the Credible Layer's execution environment,
/// allowing assertions to inspect transaction state, logs, call inputs, and storage changes.
/// The precompile is available at a deterministic address during assertion execution.
interface PhEvm {
    /// @notice Represents an Ethereum log emitted during transaction execution
    /// @dev Used by getLogs() to return transaction logs for inspection
    struct Log {
        /// @notice The topics of the log, including the event signature if any
        bytes32[] topics;
        /// @notice The raw ABI-encoded data of the log
        bytes data;
        /// @notice The address of the contract that emitted the log
        address emitter;
    }

    /// @notice Query used to filter transaction logs by emitter and/or signature
    struct LogQuery {
        /// @notice address(0) matches any emitter
        address emitter;
        /// @notice bytes32(0) matches any topic0 signature
        bytes32 signature;
    }

    /// @notice Represents the inputs to a call made during transaction execution
    /// @dev Used by getCallInputs() and related functions to inspect call details
    struct CallInputs {
        /// @notice The calldata of the call
        bytes input;
        /// @notice The gas limit of the call
        uint64 gas_limit;
        /// @notice The address of the bytecode being executed (code address)
        address bytecode_address;
        /// @notice The target address whose storage may be modified
        address target_address;
        /// @notice The address that initiated this call
        address caller;
        /// @notice The ETH value sent with the call
        uint256 value;
        /// @notice Unique identifier for this call, used with forkPreCall/forkPostCall
        uint256 id;
    }

    /// @notice Contains data about the original assertion-triggering transaction
    /// @dev Provides access to transaction envelope data for inspection in assertions
    struct TxObject {
        /// @notice The address that initiated the transaction (tx.origin equivalent)
        address from;
        /// @notice The transaction recipient, or address(0) for contract creation
        address to;
        /// @notice The ETH value sent with the transaction
        uint256 value;
        /// @notice The chain ID, or 0 if not present
        uint64 chain_id;
        /// @notice The gas limit for the transaction
        uint64 gas_limit;
        /// @notice The gas price or max_fee_per_gas for EIP-1559 transactions
        uint128 gas_price;
        /// @notice The transaction calldata
        bytes input;
    }

    /// @notice Result of a nested static call executed against a snapshot.
    struct StaticCallResult {
        /// @notice Whether the nested call completed successfully
        bool ok;
        /// @notice Raw return data or revert data from the nested call
        bytes data;
    }

    /// @notice Decoded ERC20 Transfer event data from a snapshot fork.
    struct Erc20TransferData {
        /// @notice The token contract that emitted the Transfer event
        address token_addr;
        /// @notice The sender indexed in topic1
        address from;
        /// @notice The receiver indexed in topic2
        address to;
        /// @notice The transferred amount decoded from log data
        uint256 value;
    }

    /// @notice Identifies a read-only transaction snapshot.
    /// @dev forkType: 0 = PreTx, 1 = PostTx, 2 = PreCall, 3 = PostCall
    /// callIndex is used only for call-scoped snapshots.
    struct ForkId {
        uint8 forkType;
        uint256 callIndex;
    }

    /// @notice Context for an onFnCall-triggered assertion invocation.
    /// @dev Only valid inside an assertion function triggered by registerFnCallTrigger.
    struct TriggerContext {
        /// @notice The function selector that was called on the adopter
        bytes4 selector;
        /// @notice Call index for constructing PreCall ForkId
        uint256 callStart;
        /// @notice Call index for constructing PostCall ForkId
        uint256 callEnd;
    }

    /// @notice Filter criteria for matchingCalls queries.
    struct CallFilter {
        /// @notice Call type: 0 = any, 1 = CALL, 2 = STATICCALL, 3 = DELEGATECALL, 4 = CALLCODE
        uint8 callType;
        /// @notice Minimum call depth to include
        uint32 minDepth;
        /// @notice Maximum call depth to include
        uint32 maxDepth;
        /// @notice If true, only return top-level calls (depth == 1)
        bool topLevelOnly;
        /// @notice If true, only return calls that succeeded
        bool successOnly;
    }

    /// @notice Detailed record of a call in the transaction trace.
    struct TriggerCall {
        uint256 callId;
        uint256 parentCallId;
        address caller;
        address target;
        address codeAddress;
        bytes4 selector;
        uint32 depth;
        uint8 callType;
        bool success;
        uint256 value;
        bytes input;
    }

    // ---------------------------------------------------------------
    //  Legacy fork-switching (deprecated — prefer ForkId-based access)
    // ---------------------------------------------------------------

    /// @notice Fork to the state before the assertion-triggering transaction
    /// @dev DEPRECATED: Use staticcallAt / loadStateAt with ForkId instead.
    function forkPreTx() external;

    /// @notice Fork to the state after the assertion-triggering transaction
    /// @dev DEPRECATED: Use staticcallAt / loadStateAt with ForkId instead.
    function forkPostTx() external;

    /// @notice Fork to the state before a specific call execution
    /// @dev DEPRECATED: Use staticcallAt / loadStateAt with ForkId instead.
    function forkPreCall(uint256 id) external;

    /// @notice Fork to the state after a specific call execution
    /// @dev DEPRECATED: Use staticcallAt / loadStateAt with ForkId instead.
    function forkPostCall(uint256 id) external;

    /// @notice Load a storage slot value from any address
    /// @dev DEPRECATED: Use loadStateAt with ForkId instead.
    function load(address target, bytes32 slot) external view returns (bytes32 data);

    /// @notice Read a storage slot from the current assertion adopter at a snapshot.
    /// @param slot The storage slot to read.
    /// @param fork The snapshot fork to read from.
    /// @return value The raw 32-byte value at the slot.
    function loadStateAt(bytes32 slot, ForkId calldata fork) external view returns (bytes32 value);

    /// @notice Read a storage slot from any account at a snapshot.
    /// @param target The address to read storage from.
    /// @param slot The storage slot to read.
    /// @param fork The snapshot fork to read from.
    /// @return value The raw 32-byte value at the slot.
    function loadStateAt(address target, bytes32 slot, ForkId calldata fork) external view returns (bytes32 value);

    /// @notice Execute a static call against a snapshot fork.
    /// @param target The contract to call.
    /// @param data The ABI-encoded function call.
    /// @param gas_limit The gas budget forwarded to the nested static call.
    /// @param fork The snapshot fork to execute against.
    /// @return result Success flag and return or revert bytes from the nested call.
    function staticcallAt(address target, bytes calldata data, uint64 gas_limit, ForkId calldata fork)
        external
        view
        returns (StaticCallResult memory result);

    /// @notice Get logs matching a query from a snapshot fork
    /// @param query The emitter and signature filters to apply
    /// @param fork The snapshot fork to read logs from
    /// @return logs Array of logs matching the query inside the selected snapshot window
    function getLogsQuery(LogQuery calldata query, ForkId calldata fork) external view returns (Log[] memory logs);

    /// @notice Returns all ERC20 transfers for a single token in the specified fork.
    /// @param token The ERC20 token address.
    /// @param fork The fork to query.
    /// @return transfers Array of decoded transfer records.
    function getErc20Transfers(address token, ForkId calldata fork)
        external
        view
        returns (Erc20TransferData[] memory transfers);

    /// @notice Returns all ERC20 transfers for multiple tokens in the specified fork.
    /// @param tokens Array of ERC20 token addresses.
    /// @param fork The fork to query.
    /// @return transfers Combined array of decoded transfer records across all tokens.
    function getErc20TransfersForTokens(address[] calldata tokens, ForkId calldata fork)
        external
        view
        returns (Erc20TransferData[] memory transfers);

    /// @notice Returns all transfers involving the given token for the specified fork.
    /// @dev Semantic alias of getErc20Transfers for balance-delta workflows.
    /// @param token The ERC20 token address.
    /// @param fork The fork to query.
    function changedErc20BalanceDeltas(address token, ForkId calldata fork)
        external
        view
        returns (Erc20TransferData[] memory deltas);

    /// @notice Reduces transfers into net balance deltas per unique (from, to) pair.
    /// @param token The ERC20 token address.
    /// @param fork The fork to query.
    /// @return deltas Aggregated transfer records in first-seen pair order.
    function reduceErc20BalanceDeltas(address token, ForkId calldata fork)
        external
        view
        returns (Erc20TransferData[] memory deltas);

    /// @notice Get all logs emitted during the transaction
    /// @dev Returns logs in emission order
    /// @return logs Array of Log structs containing all emitted events
    function getLogs() external returns (Log[] memory logs);

    /// @notice Get all call inputs for a target and selector (all call types)
    /// @dev Includes CALL, STATICCALL, DELEGATECALL, and CALLCODE
    /// @param target The target contract address
    /// @param selector The function selector to filter by
    /// @return calls Array of CallInputs matching the criteria
    function getAllCallInputs(address target, bytes4 selector) external view returns (CallInputs[] memory calls);

    /// @notice Get call inputs for regular CALL opcode only
    /// @param target The target contract address
    /// @param selector The function selector to filter by
    /// @return calls Array of CallInputs from CALL opcodes
    function getCallInputs(address target, bytes4 selector) external view returns (CallInputs[] memory calls);

    /// @notice Get call inputs for STATICCALL opcode only
    /// @param target The target contract address
    /// @param selector The function selector to filter by
    /// @return calls Array of CallInputs from STATICCALL opcodes
    function getStaticCallInputs(address target, bytes4 selector) external view returns (CallInputs[] memory calls);

    /// @notice Get call inputs for DELEGATECALL opcode only
    /// @param target The target/proxy contract address
    /// @param selector The function selector to filter by
    /// @return calls Array of CallInputs from DELEGATECALL opcodes
    function getDelegateCallInputs(address target, bytes4 selector) external view returns (CallInputs[] memory calls);

    /// @notice Get call inputs for CALLCODE opcode only
    /// @param target The target contract address
    /// @param selector The function selector to filter by
    /// @return calls Array of CallInputs from CALLCODE opcodes
    function getCallCodeInputs(address target, bytes4 selector) external view returns (CallInputs[] memory calls);

    /// @notice Returns the raw return or revert bytes for a traced call.
    /// @param callId The call identifier from CallInputs.id.
    /// @return output The raw ABI-encoded return bytes or revert bytes.
    function callOutputAt(uint256 callId) external view returns (bytes memory output);

    /// @notice Returns the calldata of a specific call.
    /// @param callId The call ID to read input from.
    /// @return input The raw calldata bytes (selector + ABI-encoded arguments).
    function callinputAt(uint256 callId) external view returns (bytes memory input);

    /// @notice Get all state changes for a specific storage slot
    /// @dev Returns the sequence of values the slot held during transaction execution
    /// @param contractAddress The contract whose storage to inspect
    /// @param slot The storage slot to get changes for
    /// @return stateChanges Array of values the slot held (in order of changes)
    function getStateChanges(address contractAddress, bytes32 slot)
        external
        view
        returns (bytes32[] memory stateChanges);

    /// @notice Checks that a single storage slot on the assertion adopter was not modified.
    /// @param slot The slot to protect.
    /// @return ok True when the slot was not written during the transaction.
    function forbidChangeForSlot(bytes32 slot) external returns (bool ok);

    /// @notice Checks that none of the given storage slots on the assertion adopter were modified.
    /// @param slots The slots to protect.
    /// @return ok True when none of the slots were written during the transaction.
    function forbidChangeForSlots(bytes32[] calldata slots) external returns (bool ok);

    /// @notice Get the assertion adopter address for the current transaction
    /// @dev The adopter is the contract that registered the assertion
    /// @return The address of the assertion adopter contract
    function getAssertionAdopter() external view returns (address);

    /// @notice Get the original transaction object that triggered the assertion
    /// @dev Returns the transaction envelope data for the assertion-triggering tx
    /// @return txObject The transaction data struct
    function getTxObject() external view returns (TxObject memory txObject);

    // ---------------------------------------------------------------
    //  V2: Trigger context
    // ---------------------------------------------------------------

    /// @notice Returns the context for the current onFnCall trigger invocation.
    /// @dev Only valid inside an assertion function triggered by registerFnCallTrigger.
    ///      Reverts if called outside of an onFnCall-triggered assertion.
    function context() external view returns (TriggerContext memory);

    // ---------------------------------------------------------------
    //  V2: Call inspection
    // ---------------------------------------------------------------

    /// @notice Returns calls matching the given target, selector, and filter criteria.
    /// @param target The target contract address.
    /// @param selector The function selector to filter by.
    /// @param filter Filtering criteria (call type, depth, success).
    /// @param limit Maximum number of results to return.
    /// @return calls Array of matching call records.
    function matchingCalls(address target, bytes4 selector, CallFilter calldata filter, uint256 limit)
        external
        view
        returns (TriggerCall[] memory calls);

    // ---------------------------------------------------------------
    //  V2: Call-scoped log query
    // ---------------------------------------------------------------

    /// @notice Returns logs emitted during a specific call frame.
    /// @param query The emitter and signature filters to apply.
    /// @param callId The call ID to scope the log query to.
    /// @return logs Array of logs emitted during the call.
    function getLogsForCall(LogQuery calldata query, uint256 callId) external view returns (Log[] memory logs);

    // ---------------------------------------------------------------
    //  V2: Persistent assertion storage
    // ---------------------------------------------------------------

    /// @notice Write a bytes32 value to persistent assertion storage.
    /// @param key The storage key.
    /// @param value The value to store.
    function store(bytes32 key, bytes32 value) external;

    /// @notice Read a bytes32 value from persistent assertion storage.
    /// @param key The storage key.
    /// @return value The stored value.
    function load(bytes32 key) external view returns (bytes32 value);

    /// @notice Check if a key exists in persistent assertion storage.
    /// @param key The storage key.
    /// @return doesExist True if the key has been written to.
    function exists(bytes32 key) external view returns (bool doesExist);

    /// @notice Returns remaining storage slots available to this assertion.
    function values_left() external view returns (uint256 remaining);

    // ---------------------------------------------------------------
    //  V2: Mapping tracing
    // ---------------------------------------------------------------

    /// @notice Returns canonical Solidity key encodings h(key) for keys
    ///         whose mapping entry at baseSlot was written during the tx.
    /// @dev Best-effort heuristic: traces KECCAK256 -> SSTORE provenance in the
    ///      execution trace. Custom inline assembly or precomputed hashed slots
    ///      can bypass the visible keccak chain and produce false negatives.
    /// @param target The contract whose storage was modified.
    /// @param baseSlot The Solidity mapping's base storage slot.
    /// @return keys Array of encoded keys (each is the h(key) preimage).
    function changedMappingKeys(address target, bytes32 baseSlot) external view returns (bytes[] memory keys);

    /// @notice Returns the pre/post values for a specific mapping entry.
    /// @dev Computes slot = keccak256(key ++ baseSlot) + fieldOffset, then reads
    ///      pre from the PreTx fork and post from the PostTx fork.
    /// @param target The contract address.
    /// @param baseSlot The mapping's base slot.
    /// @param key The canonical encoding h(key) of the mapping key.
    /// @param fieldOffset Struct field offset (0 for the first slot of the value).
    /// @return pre The PreTx value.
    /// @return post The PostTx value.
    /// @return changed True if pre != post.
    function mappingValueDiff(address target, bytes32 baseSlot, bytes calldata key, uint256 fieldOffset)
        external
        view
        returns (bytes32 pre, bytes32 post, bool changed);

    // ---------------------------------------------------------------
    //  V2: Protection suite — ERC4626 share price
    // ---------------------------------------------------------------

    /// @notice Checks ERC4626 share price consistency across all fork points.
    /// @param vault The ERC4626 vault address.
    /// @param toleranceBps Maximum allowed deviation in basis points.
    /// @return True if share price stays within tolerance at all forks.
    function assetsMatchSharePrice(address vault, uint256 toleranceBps) external returns (bool);

    /// @notice Checks ERC4626 share price consistency between two specific forks.
    /// @param vault The ERC4626 vault address.
    /// @param toleranceBps Maximum allowed deviation in basis points.
    /// @param fork0 The baseline fork.
    /// @param fork1 The comparison fork.
    /// @return True if share price stays within tolerance.
    function assetsMatchSharePriceAt(address vault, uint256 toleranceBps, ForkId calldata fork0, ForkId calldata fork1)
        external
        returns (bool);

    // ---------------------------------------------------------------
    //  V2: Protection suite — supply conservation
    // ---------------------------------------------------------------

    /// @notice Checks that a token's totalSupply is unchanged between two forks.
    /// @param fork0 The baseline fork.
    /// @param fork1 The comparison fork.
    /// @param token The ERC20 token address.
    /// @return True if totalSupply is identical at both forks.
    function conserveBalance(ForkId calldata fork0, ForkId calldata fork1, address token) external returns (bool);

    /// @notice Checks that an account's token balance is unchanged between two forks.
    /// @dev Compares balanceOf(account) at fork0 and fork1. Returns false if the values differ.
    /// @param fork0 The baseline fork (typically PreTx or PreCall).
    /// @param fork1 The comparison fork (typically PostTx or PostCall).
    /// @param token The ERC20 token address to check.
    /// @param account The account whose balance should remain unchanged.
    /// @return True if balanceOf(account) is identical at both forks, false otherwise.
    function conserveBalance(ForkId calldata fork0, ForkId calldata fork1, address token, address account)
        external
        returns (bool);

    // ---------------------------------------------------------------
    //  V2: Protection suite — cumulative outflow circuit breaker
    // ---------------------------------------------------------------

    /// @notice Context about the outflow that triggered an assertion via watchCumulativeOutflow.
    /// @dev Only valid inside an assertion function triggered by watchCumulativeOutflow.
    ///      Returns a zeroed struct if called from a non-outflow trigger context.
    struct OutflowContext {
        /// @notice The ERC20 token that breached the threshold
        address token;
        /// @notice Net outflow within the window (token units)
        uint256 cumulativeOutflow;
        /// @notice Total absolute outflow within the window (token units, ignoring deposits)
        uint256 absoluteOutflow;
        /// @notice Current outflow as basis points of TVL snapshot
        uint256 currentBps;
        /// @notice Adopter's token balance at window start
        uint256 tvlSnapshot;
        /// @notice Timestamp when the current window began
        uint256 windowStart;
        /// @notice Timestamp when the current window expires
        uint256 windowEnd;
    }

    /// @notice Returns context about the outflow that triggered this assertion.
    /// @dev Only valid inside an assertion function triggered by
    ///      watchCumulativeOutflow. Returns a zeroed struct if called from a
    ///      non-outflow trigger context.
    /// @return ctx The outflow context for the current trigger invocation.
    function outflowContext() external view returns (OutflowContext memory ctx);

    // ---------------------------------------------------------------
    //  V2: Protection suite — oracle sanity
    // ---------------------------------------------------------------

    /// @notice Checks oracle price consistency across all fork points.
    /// @param target The oracle contract address.
    /// @param data The ABI-encoded oracle query.
    /// @param bpsDeviation Maximum allowed deviation in basis points.
    /// @return True if oracle price stays within tolerance.
    function oracleSanity(address target, bytes calldata data, uint256 bpsDeviation) external returns (bool);

    /// @notice Checks oracle price consistency between two specific forks.
    /// @param target The oracle contract address.
    /// @param data The ABI-encoded oracle query.
    /// @param bpsDeviation Maximum allowed deviation in basis points.
    /// @param initialFork The baseline fork.
    /// @param currentFork The comparison fork.
    /// @return True if oracle price stays within tolerance.
    function oracleSanityAt(
        address target,
        bytes calldata data,
        uint256 bpsDeviation,
        ForkId calldata initialFork,
        ForkId calldata currentFork
    ) external returns (bool);

    // ---------------------------------------------------------------
    //  V2: Math precompiles
    // ---------------------------------------------------------------

    /// @notice Computes (x * y) / denominator, rounded down. Uses 512-bit intermediates.
    function mulDivDown(uint256 x, uint256 y, uint256 denominator) external pure returns (uint256 result);

    /// @notice Computes (x * y) / denominator, rounded up. Uses 512-bit intermediates.
    function mulDivUp(uint256 x, uint256 y, uint256 denominator) external pure returns (uint256 result);

    /// @notice Scales an amount from one decimal base to another.
    function normalizeDecimals(uint256 amount, uint8 fromDecimals, uint8 toDecimals)
        external
        pure
        returns (uint256 result);

    /// @notice Compares two ratios with tolerance: num1/den1 >= num2/den2 * (1 - toleranceBps/10000).
    /// @dev Uses cross-multiplication with wide intermediates to avoid division and overflow.
    function ratioGe(uint256 num1, uint256 den1, uint256 num2, uint256 den2, uint256 toleranceBps)
        external
        pure
        returns (bool);
}
