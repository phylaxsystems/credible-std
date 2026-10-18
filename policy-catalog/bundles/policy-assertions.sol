// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

// src/PhEvm.sol

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
        /// @notice The ABI-encoded call arguments, WITHOUT the 4-byte function selector.
        /// @dev The `get*CallInputs` queries (getAllCallInputs/getCallInputs/getStaticCallInputs/
        ///      getDelegateCallInputs/getCallCodeInputs) key on `selector`, so it is stripped from
        ///      this field and only the argument tail remains. To rebuild full calldata, prepend the
        ///      selector: `bytes.concat(selector, input)`. Do NOT slice `input[4:]`, the selector is
        ///      already gone, and slicing would drop the first argument word. Contrast `callinputAt`,
        ///      which returns the raw selector-prefixed calldata.
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
        /// @notice The ABI-encoded call arguments, WITHOUT the 4-byte function selector.
        /// @dev Same shape as `CallInputs.input`: `matchingCalls` keys on `selector`, so it is
        ///      stripped here. Prepend `selector` (`bytes.concat(selector, input)`) before decoding;
        ///      do not slice `input[4:]`.
        bytes input;
    }

    // ---------------------------------------------------------------
    //  Legacy fork-switching (deprecated, prefer ForkId-based access)
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
    /// @dev Includes CALL, STATICCALL, DELEGATECALL, and CALLCODE.
    ///      Each returned `CallInputs.input` is the ABI-encoded arguments WITHOUT the 4-byte
    ///      selector (the selector is the query key here). Prepend it with
    ///      `bytes.concat(selector, calls[i].input)` to reconstruct full calldata before decoding;
    ///      do not slice `input[4:]`. See the `CallInputs.input` field docs.
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
    function forbidChangeForSlot(bytes32 slot) external view returns (bool ok);

    /// @notice Checks that none of the given storage slots on the assertion adopter were modified.
    /// @param slots The slots to protect.
    /// @return ok True when none of the slots were written during the transaction.
    function forbidChangeForSlots(bytes32[] calldata slots) external view returns (bool ok);

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
    /// @dev Each returned `TriggerCall.input` is the ABI-encoded arguments WITHOUT the 4-byte
    ///      selector, prepend `selector` before decoding (see the `TriggerCall.input` field docs).
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
    //  V2: Protection suite. ERC4626 share price
    // ---------------------------------------------------------------

    /// @notice Checks ERC4626 share price consistency across all fork points.
    /// @param vault The ERC4626 vault address.
    /// @param toleranceBps Maximum allowed deviation in basis points.
    /// @return True if share price stays within tolerance at all forks.
    function assetsMatchSharePrice(address vault, uint256 toleranceBps) external view returns (bool);

    /// @notice Checks ERC4626 share price consistency between two specific forks.
    /// @param vault The ERC4626 vault address.
    /// @param toleranceBps Maximum allowed deviation in basis points.
    /// @param fork0 The baseline fork.
    /// @param fork1 The comparison fork.
    /// @return True if share price stays within tolerance.
    function assetsMatchSharePriceAt(address vault, uint256 toleranceBps, ForkId calldata fork0, ForkId calldata fork1)
        external
        view
        returns (bool);

    // ---------------------------------------------------------------
    //  V2: Protection suite, balance conservation
    // ---------------------------------------------------------------

    /// @notice Checks that an account's ERC20 balance is unchanged between two forks.
    /// @param fork0 The baseline fork.
    /// @param fork1 The comparison fork.
    /// @param token The ERC20 token address.
    /// @param account The account whose balance should remain unchanged.
    /// @return True if balanceOf(account) is identical at both forks.
    function conserveBalance(ForkId calldata fork0, ForkId calldata fork1, address token, address account)
        external
        view
        returns (bool);

    // ---------------------------------------------------------------
    //  V2: Protection suite, cumulative outflow circuit breaker
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
    //  V2: Protection suite, cumulative inflow circuit breaker
    // ---------------------------------------------------------------

    /// @notice Context about the inflow that triggered an assertion via watchCumulativeInflow.
    /// @dev Only valid inside an assertion function triggered by watchCumulativeInflow.
    ///      Returns a zeroed struct if called from a non-inflow trigger context.
    struct InflowContext {
        /// @notice The ERC20 token that breached the threshold
        address token;
        /// @notice Net inflow within the window (token units)
        uint256 cumulativeInflow;
        /// @notice Total absolute inflow within the window (token units, ignoring withdrawals)
        uint256 absoluteInflow;
        /// @notice Current inflow as basis points of TVL snapshot
        uint256 currentBps;
        /// @notice Adopter's token balance at window start
        uint256 tvlSnapshot;
        /// @notice Timestamp when the current window began
        uint256 windowStart;
        /// @notice Timestamp when the current window expires
        uint256 windowEnd;
    }

    /// @notice Returns context about the inflow that triggered this assertion.
    /// @dev Only valid inside an assertion function triggered by
    ///      watchCumulativeInflow. Returns a zeroed struct if called from a
    ///      non-inflow trigger context.
    /// @return ctx The inflow context for the current trigger invocation.
    function inflowContext() external view returns (InflowContext memory ctx);

    // ---------------------------------------------------------------
    //  Experimental: rate-of-change (first-derivative) flow signal
    // ---------------------------------------------------------------

    /// @notice Rate-of-change statistics for a cumulative-flow-triggered assertion.
    /// @dev All rate fields are basis points of `tvlSnapshot` per second, derived
    ///      from the same rolling-window buckets as the cumulative context (no
    ///      extra storage). A single 10s bucket draining the whole snapshot reads
    ///      ~1000 bps/s. Use this to suppress false positives of the cumulative
    ///      breaker: a large-but-slow withdrawal reads a benign peak rate. Never
    ///      gate the cumulative alert on it, treat it as OR-style escalation only.
    struct FlowRateContext {
        /// @notice The ERC20 token that triggered the assertion. address(0) if no flow trigger fired.
        address token;
        /// @notice Peak per-bucket net flow rate over the window (bps of TVL / second)
        uint256 peakRateBps;
        /// @notice Most recent in-window bucket's net flow rate (bps of TVL / second)
        uint256 lastRateBps;
        /// @notice Mean net flow rate across the active window span (bps of TVL / second)
        uint256 meanRateBps;
        /// @notice Adopter's token balance at window start
        uint256 tvlSnapshot;
        /// @notice Timestamp when the current window began
        uint256 windowStart;
        /// @notice Timestamp when the current window expires
        uint256 windowEnd;
    }

    /// @notice Returns the outflow rate-of-change context for the current invocation.
    /// @dev EXPERIMENTAL: requires registerAssertionSpec(AssertionSpec.Experimental).
    ///      Only valid inside an assertion function triggered by
    ///      watchCumulativeOutflow. Returns a zeroed struct otherwise.
    /// @return ctx The outflow rate-of-change context for the current invocation.
    function outflowRate() external view returns (FlowRateContext memory ctx);

    /// @notice Returns the inflow rate-of-change context for the current invocation.
    /// @dev EXPERIMENTAL: requires registerAssertionSpec(AssertionSpec.Experimental).
    ///      Only valid inside an assertion function triggered by
    ///      watchCumulativeInflow. Returns a zeroed struct otherwise.
    /// @return ctx The inflow rate-of-change context for the current invocation.
    function inflowRate() external view returns (FlowRateContext memory ctx);

    // ---------------------------------------------------------------
    //  V2: Anomaly detection
    // ---------------------------------------------------------------

    /// @notice Context returned by `anomalyContext(target)` describing the
    ///         anomaly detector's view of `target` for the current tx.
    /// @dev `firesAt` is the strictest sensitivity level (1..=10) the model's
    ///      score clears against `target`'s own ladder; 0 clears none. An
    ///      assertion registered at level `L` is anomalous when
    ///      `firesAt != 0 && L >= firesAt`, so a zero-filled context, meaning an
    ///      unscored target, fails open by construction.
    /// @dev The level is the whole verdict. The raw score is spent resolving it
    ///      against the ladder that lives with the model, and never reaches
    ///      Solidity: basis points mean nothing without that ladder, and a
    ///      threshold written against them belongs to one contract and one model
    ///      version. A level carries over to another contract and survives a
    ///      retrain.
    struct AnomalyContext {
        uint8 firesAt;
    }

    /// @notice Returns the anomaly detector's view of `target` for the
    ///         current transaction.
    /// @dev Returns a zero-filled context when `target` was not
    ///      able to be scored, such that it fails open.
    /// @param target The address whose anomaly context to read.
    /// @return ctx The anomaly context for `target` in the current tx.
    function anomalyContext(address target) external view returns (AnomalyContext memory ctx);

    // ---------------------------------------------------------------
    //  V2: Protection suite, oracle sanity
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

// src/SpecRecorder.sol

/// @notice The assertion spec defines what subset of precompiles are available.
/// All new specs derive and expose all precompiles from the old definitions,
/// unless specified otherwise.
enum AssertionSpec {
    /// @notice Standard set of PhEvm precompiles available at launch.
    Legacy,
    /// @notice Contains tx object precompiles.
    Reshiram,
    /// @notice Unrestricted access to all available precompiles. May be untested and dangerous.
    Experimental
}

/// @title SpecRecorder
/// @author Phylax Systems
/// @notice Precompile interface for registering the desired assertion spec
/// @dev Used within the constructor of assertion contracts to specify which
/// subset of PhEvm precompiles should be available during assertion execution.
/// You can only call registerAssertionSpec once per assertion.
interface SpecRecorder {
    /// @notice Called within the constructor to set the desired assertion spec.
    /// The assertion spec defines what subset of precompiles are available.
    /// You can only call this function once. For an assertion to be valid,
    /// it needs to have a defined spec.
    /// @param spec The desired AssertionSpec.
    function registerAssertionSpec(AssertionSpec spec) external view;
}

// src/TriggerRecorder.sol

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

    /// @notice Registers a circuit breaker trigger that fires when cumulative
    ///         ERC20 inflow into the assertion adopter exceeds a percentage
    ///         threshold within a rolling time window.
    /// @dev The executor handles all persistent state tracking, TVL snapshots,
    ///      and threshold enforcement internally.
    /// @param token The ERC20 token address to monitor.
    /// @param thresholdBps Maximum cumulative inflow as basis points of the
    ///        TVL snapshot taken at window start. 1000 = 10%.
    /// @param windowDuration Rolling window length in seconds. Balance deltas are
    ///        stored in 10-second buckets; old buckets that fall outside the window
    ///        are dropped as the window slides forward.
    /// @param fnSelector The assertion function to invoke when the threshold
    ///        is breached.
    function watchCumulativeInflow(address token, uint256 thresholdBps, uint256 windowDuration, bytes4 fnSelector)
        external
        view;

    /// @notice Registers an anomaly-detection trigger at a sensitivity level.
    ///         Fires when the executor's configured AnomalySubsystem scores
    ///         `target` anomalously enough to clear `sensitivity`.
    /// @dev The level is resolved against `target`'s own model where the
    ///      trigger is evaluated, so a sub-threshold transaction never spawns
    ///      the assertion at all. The assertion may still read the level back
    ///      via `ph.anomalyContext(target)`, which reports `firesAt` and
    ///      nothing else. There is no score to re-read.
    /// @param target The address whose anomaly score this assertion observes.
    /// @param fnSelector The assertion function to invoke when `target` clears
    ///        the level.
    /// @param sensitivity The level from `Sensitivity`, 1..=10. Reverts the
    ///        registration if outside that range.
    function watchAnomaly(address target, bytes4 fnSelector, uint8 sensitivity) external view;
}

// src/Credible.sol

/// @title Credible
/// @author Phylax Systems
/// @notice Base contract providing access to the PhEvm precompile interface
/// @dev All assertion contracts should inherit from this contract (via Assertion) to access
/// the PhEvm precompile for reading transaction state, logs, and call inputs.
abstract contract Credible {
    /// @notice The PhEvm precompile instance for accessing transaction state
    /// @dev The address is derived from a deterministic hash to ensure consistency
    PhEvm constant ph = PhEvm(address(uint160(uint256(keccak256("Kim Jong Un Sucks")))));
}

// src/utils/ForkUtils.sol

/// @notice Minimal token balance surface used by fork-read helpers.
interface IERC20BalanceReaderLike {
    function balanceOf(address account) external view returns (uint256);
}

/// @title ForkUtils
/// @author Phylax Systems
/// @notice Shared fork-aware read and ERC20-delta helpers for assertions and protection suites.
abstract contract ForkUtils is Credible {
    /// @notice Gas forwarded to snapshot-time protocol view calls made through `ph.staticcallAt`.
    uint64 internal constant FORK_VIEW_GAS = 500_000;

    /// @notice Revert string used when a fork-time static call fails.
    /// @dev Override this when a more specific failure message is useful for a derived contract.
    function _viewFailureMessage() internal pure virtual returns (string memory) {
        return "staticcallAt failed";
    }

    /// @notice Executes a static call against `target` at a specific snapshot fork.
    /// @param target The protocol contract to query.
    /// @param data ABI-encoded calldata for the target view.
    /// @param fork The snapshot fork the read should execute against.
    /// @return resultData Raw return bytes from the static call.
    function _viewAt(address target, bytes memory data, PhEvm.ForkId memory fork)
        internal
        view
        returns (bytes memory resultData)
    {
        PhEvm.StaticCallResult memory result = ph.staticcallAt(target, data, FORK_VIEW_GAS, fork);
        require(result.ok, _viewFailureMessage());
        return result.data;
    }

    /// @notice Convenience wrapper that decodes a snapshot-time static call as `uint256`.
    function _readUintAt(address target, bytes memory data, PhEvm.ForkId memory fork)
        internal
        view
        returns (uint256 value)
    {
        return abi.decode(_viewAt(target, data, fork), (uint256));
    }

    /// @notice Convenience wrapper that decodes a snapshot-time static call as `uint8`.
    function _readUint8At(address target, bytes memory data, PhEvm.ForkId memory fork)
        internal
        view
        returns (uint8 value)
    {
        return abi.decode(_viewAt(target, data, fork), (uint8));
    }

    /// @notice Convenience wrapper that decodes a snapshot-time static call as `address`.
    function _readAddressAt(address target, bytes memory data, PhEvm.ForkId memory fork)
        internal
        view
        returns (address value)
    {
        return abi.decode(_viewAt(target, data, fork), (address));
    }

    /// @notice Convenience wrapper that decodes a snapshot-time static call as `bool`.
    function _readBoolAt(address target, bytes memory data, PhEvm.ForkId memory fork)
        internal
        view
        returns (bool value)
    {
        return abi.decode(_viewAt(target, data, fork), (bool));
    }

    /// @notice Convenience wrapper that reads an ERC20-style `balanceOf(account)` at a snapshot fork.
    function _readBalanceAt(address token, address account, PhEvm.ForkId memory fork)
        internal
        view
        returns (uint256 balance)
    {
        return _readUintAt(token, abi.encodeCall(IERC20BalanceReaderLike.balanceOf, (account)), fork);
    }

    /// @notice Returns reduced ERC20 transfer deltas for a token within the selected fork scope.
    function _reducedErc20BalanceDeltasAt(address token, PhEvm.ForkId memory fork)
        internal
        view
        returns (PhEvm.Erc20TransferData[] memory deltas)
    {
        return ph.reduceErc20BalanceDeltas(token, fork);
    }

    /// @notice Returns the total amount of `token` transferred from `from` to `to` in the fork scope.
    function _transferredValueAt(address token, address from, address to, PhEvm.ForkId memory fork)
        internal
        view
        returns (uint256 value)
    {
        PhEvm.Erc20TransferData[] memory deltas = _reducedErc20BalanceDeltasAt(token, fork);

        for (uint256 i; i < deltas.length; ++i) {
            if (deltas[i].from == from && deltas[i].to == to) {
                value += deltas[i].value;
            }
        }
    }

    /// @notice Computes the non-negative decrease between two snapshot values.
    function _consumedBetween(uint256 beforeValue, uint256 afterValue) internal pure returns (uint256 consumed) {
        return beforeValue > afterValue ? beforeValue - afterValue : 0;
    }
}

// src/StateChanges.sol

/**
 * @title StateChanges
 * @notice Helper contract for converting state changes from bytes32 arrays to typed arrays
 * @dev Inherits from Credible to access the PhEvm interface
 */
contract StateChanges is Credible {
    /**
     * @notice Converts state changes for a slot to uint256 array
     * @param contractAddress The address of the contract to get state changes from
     * @param slot The storage slot to get state changes for
     * @return Array of state changes as uint256 values
     */
    function getStateChangesUint(address contractAddress, bytes32 slot) internal view returns (uint256[] memory) {
        bytes32[] memory stateChanges = ph.getStateChanges(contractAddress, slot);

        // Explicit cast to uint256[]
        uint256[] memory uintChanges;
        assembly {
            uintChanges := stateChanges
        }

        return uintChanges;
    }

    /**
     * @notice Converts state changes for a slot to address array
     * @param contractAddress The address of the contract to get state changes from
     * @param slot The storage slot to get state changes for
     * @return Array of state changes as address values
     */
    function getStateChangesAddress(address contractAddress, bytes32 slot) internal view returns (address[] memory) {
        bytes32[] memory stateChanges = ph.getStateChanges(contractAddress, slot);

        assembly {
            // Zero out the upper 96 bits for each element to ensure clean address casting
            for { let i := 0 } lt(i, mload(stateChanges)) { i := add(i, 1) } {
                let addr :=
                    and(
                        mload(add(add(stateChanges, 0x20), mul(i, 0x20))),
                        0x000000000000000000000000ffffffffffffffffffffffffffffffffffffffff
                    )
                mstore(add(add(stateChanges, 0x20), mul(i, 0x20)), addr)
            }
        }

        // Explicit cast to address[]
        address[] memory addressChanges;
        assembly {
            addressChanges := stateChanges
        }

        return addressChanges;
    }

    /**
     * @notice Converts state changes for a slot to boolean array
     * @param contractAddress The address of the contract to get state changes from
     * @param slot The storage slot to get state changes for
     * @return Array of state changes as boolean values
     */
    function getStateChangesBool(address contractAddress, bytes32 slot) internal view returns (bool[] memory) {
        bytes32[] memory stateChanges = ph.getStateChanges(contractAddress, slot);

        assembly {
            // Convert each bytes32 to bool
            for { let i := 0 } lt(i, mload(stateChanges)) { i := add(i, 1) } {
                // Any non-zero value is true, zero is false
                let boolValue := iszero(iszero(mload(add(add(stateChanges, 0x20), mul(i, 0x20)))))
                mstore(add(add(stateChanges, 0x20), mul(i, 0x20)), boolValue)
            }
        }

        // Explicit cast to bool[]
        bool[] memory boolChanges;
        assembly {
            boolChanges := stateChanges
        }

        return boolChanges;
    }

    /**
     * @notice Gets raw state changes as bytes32 array
     * @param contractAddress The address of the contract to get state changes from
     * @param slot The storage slot to get state changes for
     * @return Array of state changes as bytes32 values
     */
    function getStateChangesBytes32(address contractAddress, bytes32 slot) internal view returns (bytes32[] memory) {
        return ph.getStateChanges(contractAddress, slot);
    }

    /**
     * @notice Calculates the storage slot for a mapping with a given key and offset
     * @param slot The base storage slot of the mapping
     * @param key The key in the mapping
     * @param offset Additional offset to add to the calculated slot
     * @return The storage slot for the mapping entry
     */
    function getSlotMapping(bytes32 slot, uint256 key, uint256 offset) private pure returns (bytes32) {
        return bytes32(uint256(keccak256(abi.encodePacked(key, slot))) + offset);
    }

    // Helper functions for mapping access with keys

    /**
     * @notice Gets uint256 state changes for a mapping entry
     * @param contractAddress The contract address
     * @param slot The mapping's slot
     * @param key The mapping key
     * @return Array of state changes as uint256 values
     */
    function getStateChangesUint(address contractAddress, bytes32 slot, uint256 key)
        internal
        view
        returns (uint256[] memory)
    {
        return getStateChangesUint(contractAddress, slot, key, 0);
    }

    /**
     * @notice Gets address state changes for a mapping entry
     * @param contractAddress The contract address
     * @param slot The mapping's slot
     * @param key The mapping key
     * @return Array of state changes as address values
     */
    function getStateChangesAddress(address contractAddress, bytes32 slot, uint256 key)
        internal
        view
        returns (address[] memory)
    {
        return getStateChangesAddress(contractAddress, slot, key, 0);
    }

    /**
     * @notice Gets boolean state changes for a mapping entry
     * @param contractAddress The contract address
     * @param slot The mapping's slot
     * @param key The mapping key
     * @return Array of state changes as boolean values
     */
    function getStateChangesBool(address contractAddress, bytes32 slot, uint256 key)
        internal
        view
        returns (bool[] memory)
    {
        return getStateChangesBool(contractAddress, slot, key, 0);
    }

    /**
     * @notice Gets bytes32 state changes for a mapping entry
     * @param contractAddress The contract address
     * @param slot The mapping's slot
     * @param key The mapping key
     * @return Array of state changes as bytes32 values
     */
    function getStateChangesBytes32(address contractAddress, bytes32 slot, uint256 key)
        internal
        view
        returns (bytes32[] memory)
    {
        return getStateChangesBytes32(contractAddress, slot, key, 0);
    }

    // Helper functions for mapping access with keys and offsets

    /**
     * @notice Gets uint256 state changes for a mapping entry with offset
     * @param contractAddress The contract address
     * @param slot The mapping's slot
     * @param key The mapping key
     * @param slotOffset Additional offset to add to the slot
     * @return Array of state changes as uint256 values
     */
    function getStateChangesUint(address contractAddress, bytes32 slot, uint256 key, uint256 slotOffset)
        internal
        view
        returns (uint256[] memory)
    {
        return getStateChangesUint(contractAddress, getSlotMapping(slot, key, slotOffset));
    }

    /**
     * @notice Gets address state changes for a mapping entry with offset
     * @param contractAddress The contract address
     * @param slot The mapping's slot
     * @param key The mapping key
     * @param slotOffset Additional offset to add to the slot
     * @return Array of state changes as address values
     */
    function getStateChangesAddress(address contractAddress, bytes32 slot, uint256 key, uint256 slotOffset)
        internal
        view
        returns (address[] memory)
    {
        return getStateChangesAddress(contractAddress, getSlotMapping(slot, key, slotOffset));
    }

    /**
     * @notice Gets boolean state changes for a mapping entry with offset
     * @param contractAddress The contract address
     * @param slot The mapping's slot
     * @param key The mapping key
     * @param slotOffset Additional offset to add to the slot
     * @return Array of state changes as boolean values
     */
    function getStateChangesBool(address contractAddress, bytes32 slot, uint256 key, uint256 slotOffset)
        internal
        view
        returns (bool[] memory)
    {
        return getStateChangesBool(contractAddress, getSlotMapping(slot, key, slotOffset));
    }

    /**
     * @notice Gets bytes32 state changes for a mapping entry with offset
     * @param contractAddress The contract address
     * @param slot The mapping's slot
     * @param key The mapping key
     * @param slotOffset Additional offset to add to the slot
     * @return Array of state changes as bytes32 values
     */
    function getStateChangesBytes32(address contractAddress, bytes32 slot, uint256 key, uint256 slotOffset)
        internal
        view
        returns (bytes32[] memory)
    {
        return getStateChangesBytes32(contractAddress, getSlotMapping(slot, key, slotOffset));
    }
}

// src/Assertion.sol

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
abstract contract Assertion is ForkUtils, StateChanges {
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

    /// @notice Registers a circuit breaker trigger that fires when cumulative
    ///         ERC20 outflow from the assertion adopter exceeds a percentage
    ///         threshold within a rolling time window.
    /// @param token The ERC20 token address to monitor.
    /// @param thresholdBps Maximum cumulative outflow as basis points of the
    ///        TVL snapshot taken at window start. 1000 = 10%.
    /// @param windowDuration Rolling window length in seconds.
    /// @param fnSelector The assertion function to invoke when the threshold
    ///        is breached.
    function watchCumulativeOutflow(address token, uint256 thresholdBps, uint256 windowDuration, bytes4 fnSelector)
        internal
        view
    {
        triggerRecorder.watchCumulativeOutflow(token, thresholdBps, windowDuration, fnSelector);
    }

    /// @notice Registers a circuit breaker trigger that fires when cumulative
    ///         ERC20 inflow into the assertion adopter exceeds a percentage
    ///         threshold within a rolling time window.
    /// @param token The ERC20 token address to monitor.
    /// @param thresholdBps Maximum cumulative inflow as basis points of the
    ///        TVL snapshot taken at window start. 1000 = 10%.
    /// @param windowDuration Rolling window length in seconds.
    /// @param fnSelector The assertion function to invoke when the threshold
    ///        is breached.
    function watchCumulativeInflow(address token, uint256 thresholdBps, uint256 windowDuration, bytes4 fnSelector)
        internal
        view
    {
        triggerRecorder.watchCumulativeInflow(token, thresholdBps, windowDuration, fnSelector);
    }

    /// @notice Registers an anomaly-detection trigger at a sensitivity level.
    ///         Fires when the executor's configured AnomalySubsystem scores
    ///         `target` anomalously enough to clear `sensitivity`.
    /// @dev The level is a point on the detector's recall-versus-false-positive
    ///      curve, fixed to the same budget on every contract, see
    ///      `Sensitivity`. The threshold behind it is resolved from `target`'s
    ///      own model where the trigger is evaluated, so this code is portable
    ///      across contracts and survives a retrain untouched.
    ///
    ///      ```solidity
    ///      function triggers() external view override {
    ///          watchAnomaly(aUSDC, this.checkSolvency.selector, Sensitivity.LEVEL_7);
    ///      }
    ///      ```
    /// @param target The address whose anomaly score this assertion observes.
    /// @param fnSelector The assertion function to invoke when `target` clears
    ///        the level.
    /// @param sensitivity The level from `Sensitivity`, 1..=10.
    function watchAnomaly(address target, bytes4 fnSelector, uint8 sensitivity) internal view {
        triggerRecorder.watchAnomaly(target, fnSelector, sensitivity);
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
    function registerAssertionSpec(AssertionSpec spec) internal {
        (bool ok,) = address(specRecorder).call(abi.encodeCall(SpecRecorder.registerAssertionSpec, (spec)));
        require(ok, "Assertion: spec registration failed");
    }
}

// src/protection/access_control/AccessControlBaseAssertion.sol

/// @title AccessControlBaseAssertion
/// @author Phylax Systems
/// @notice Base contract for access-control assertions (V2 syntax).
/// @dev Provides the protected target address and shared helpers for the access-control suite.
///      Inherit from this (and one or more invariant contracts), then implement `triggers()`.
///      Each inherited mixin must have its `_register*Triggers()` helper called explicitly;
///      forgetting one disables that mixin's check without a runtime warning.
///
/// Example -- combine slot protection and balance conservation:
/// ```solidity
/// contract MyProtocolGuard is SlotProtectionAssertion, BalanceConservationAssertion {
///     constructor(address _target)
///         AccessControlBaseAssertion(_target)
///     {}
///
///     function _protectedSlots() internal pure override returns (bytes32[] memory) { ... }
///     function _conservedBalances() internal view override returns (ConservedBalance[] memory) { ... }
///
///     function triggers() external view override {
///         _registerSlotProtectionTriggers();
///         _registerBalanceConservationTriggers();
///     }
/// }
/// ```
abstract contract AccessControlBaseAssertion is Assertion {
    /// @notice The contract whose access control is being protected (assertion adopter).
    address internal immutable target;

    constructor(address _target) {
        target = _target;
    }
}

// src/protection/safe/SafeConfigLockHelpers.sol

interface ISafeConfigLockTarget {
    function getThreshold() external view returns (uint256);
    function getOwners() external view returns (address[] memory);
    function getModulesPaginated(address start, uint256 pageSize)
        external
        view
        returns (address[] memory array, address next);
}

/// @title SafeConfigLockHelpers
/// @author Phylax Systems
/// @notice Shared constants and snapshot readers for Safe configuration assertions.
abstract contract SafeConfigLockHelpers is Assertion {
    address internal constant SENTINEL_MODULES = address(0x1);

    uint256 internal constant MODULE_PAGE_SIZE = 256;
    uint64 internal constant MODULE_PAGE_VIEW_GAS = 2_000_000;

    bytes32 internal constant FALLBACK_HANDLER_STORAGE_SLOT =
        0x6c9a6c4a39284e37ed1cf53d337577d14212a4870fb976a4366c693b939918d5;
    bytes32 internal constant GUARD_STORAGE_SLOT = 0x4a204f620c8c5ccdca3fd54d003badd85ba500436a431f0cbda4f558c93c34c8;
    bytes32 internal constant MODULE_GUARD_STORAGE_SLOT =
        0xb104e0b93118902c651344349b610029d694cfdec91c589c91ebafbcd0289947;

    /// @notice Computes the deterministic hash used by owner and module allow lists.
    /// @dev Sorts a copy before hashing, so Safe linked-list order does not affect the
    ///      resulting set hash and the caller's memory array is left unchanged.
    function hashAddressSet(address[] memory accounts) public pure returns (bytes32) {
        address[] memory sorted = new address[](accounts.length);
        for (uint256 i; i < accounts.length; ++i) {
            sorted[i] = accounts[i];
        }

        _sortAddresses(sorted);
        return keccak256(abi.encode(sorted));
    }

    function _ownersAt(address safe, PhEvm.ForkId memory fork) internal view returns (address[] memory owners) {
        owners = abi.decode(_viewAt(safe, abi.encodeCall(ISafeConfigLockTarget.getOwners, ()), fork), (address[]));
    }

    function _thresholdAt(address safe, PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(safe, abi.encodeCall(ISafeConfigLockTarget.getThreshold, ()), fork);
    }

    function _modulesAt(address safe, PhEvm.ForkId memory fork) internal view returns (address[] memory modules) {
        address next = SENTINEL_MODULES;
        while (true) {
            PhEvm.StaticCallResult memory result = ph.staticcallAt(
                safe,
                abi.encodeCall(ISafeConfigLockTarget.getModulesPaginated, (next, MODULE_PAGE_SIZE)),
                MODULE_PAGE_VIEW_GAS,
                fork
            );
            require(result.ok, _viewFailureMessage());

            (address[] memory page, address pageNext) = abi.decode(result.data, (address[], address));

            modules = _appendAddresses(modules, page);
            if (pageNext == SENTINEL_MODULES) return modules;
            next = pageNext;
        }
    }

    function _guardAt(address safe, PhEvm.ForkId memory fork) internal view returns (address) {
        return _addressSlotAt(safe, GUARD_STORAGE_SLOT, fork);
    }

    function _moduleGuardAt(address safe, PhEvm.ForkId memory fork) internal view returns (address) {
        return _addressSlotAt(safe, MODULE_GUARD_STORAGE_SLOT, fork);
    }

    function _fallbackHandlerAt(address safe, PhEvm.ForkId memory fork) internal view returns (address) {
        return _addressSlotAt(safe, FALLBACK_HANDLER_STORAGE_SLOT, fork);
    }

    function _addressSlotAt(address safe, bytes32 slot, PhEvm.ForkId memory fork) internal view returns (address) {
        return address(uint160(uint256(ph.loadStateAt(safe, slot, fork))));
    }

    function _isApprovedHash(bytes32 actualHash, bytes32[] storage approvedHashes, bool emptySet)
        internal
        view
        returns (bool)
    {
        for (uint256 i; i < approvedHashes.length; ++i) {
            if (approvedHashes[i] == actualHash) {
                return true;
            }

            if (emptySet && approvedHashes[i] == bytes32(0)) {
                return true;
            }
        }

        return false;
    }

    function _sortAddresses(address[] memory accounts) internal pure {
        if (accounts.length < 2) return;
        _quickSortAddresses(accounts, 0, accounts.length - 1);
    }

    function _quickSortAddresses(address[] memory accounts, uint256 left, uint256 right) private pure {
        uint256 i = left;
        uint256 j = right;
        uint160 pivot = uint160(accounts[left + (right - left) / 2]);

        while (i <= j) {
            while (uint160(accounts[i]) < pivot) {
                ++i;
            }
            while (uint160(accounts[j]) > pivot) {
                if (j == 0) break;
                --j;
            }

            if (i <= j) {
                (accounts[i], accounts[j]) = (accounts[j], accounts[i]);
                ++i;
                if (j == 0) break;
                --j;
            }
        }

        if (left < j) _quickSortAddresses(accounts, left, j);
        if (i < right) _quickSortAddresses(accounts, i, right);
    }

    function _appendAddresses(address[] memory left, address[] memory right)
        private
        pure
        returns (address[] memory combined)
    {
        combined = new address[](left.length + right.length);
        for (uint256 i; i < left.length; ++i) {
            combined[i] = left[i];
        }
        for (uint256 i; i < right.length; ++i) {
            combined[left.length + i] = right[i];
        }
    }

    function _viewFailureMessage() internal pure override returns (string memory) {
        return "SafeConfigLock: safe view failed";
    }

    function _registerReshiramSpec() internal {
        registerAssertionSpec(AssertionSpec.Reshiram);
    }
}

// src/protection/access_control/SlotProtectionAssertion.sol

/// @title SlotProtectionAssertion
/// @author Phylax Systems
/// @notice Asserts that critical storage slots on the assertion adopter are not modified
///         during the transaction.
///
/// Invariants covered:
///   - **Ownership immutability**: proxy admin, owner, sentinel, and implementation slots
///     cannot be changed outside expected governance choreography.
///   - **Timelock integrity**: delay values, proposer/executor/canceller role slots are
///     frozen so an attacker cannot shorten a delay before exploiting a governance path.
///   - **Role stability**: admin roles, operator roles, manager roles remain unchanged
///     unless an authorized governance action modifies them.
///   - **Configuration guards**: fee parameters, oracle addresses, whitelist/blocklist
///     settings, and other safety-critical configuration slots.
///
/// @dev Uses the V2 `forbidChangeForSlots` precompile which checks the transaction journal
///      for any SSTORE to the specified slots. A write is flagged even if it sets the same
///      value (conservative -- a write is suspicious regardless of whether the value changed).
///      Writes inside reverted internal calls are rolled back in the journal and do not
///      trigger a violation.
///
///      Implementers must override `_protectedSlots()` to declare which slots to protect.
///      For mapping entries (e.g., `roles[account]`), compute the slot off-chain via
///      `keccak256(abi.encode(key, mappingSlot))`.
///
///      The policy enforced is: **fail by default** on any watched-slot mutation. Protocols
///      that need conditional slot changes should use per-function triggers instead and
///      verify the change follows the expected governance path.
abstract contract SlotProtectionAssertion is AccessControlBaseAssertion {
    error ProtectedSlotChanged(bytes32[] slots);

    /// @notice Returns the storage slots that must not be modified during the transaction.
    /// @dev Override to declare the protocol-specific critical slots. Common examples:
    ///      - EIP-1967 admin slot: `0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103`
    ///      - EIP-1967 implementation slot: `0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc`
    ///      - Gnosis Safe owner sentinel (slot 2), threshold (slot 4), singleton (slot 0)
    ///      - Timelock delay parameters, proposer/executor/canceller roles
    ///      - Protocol-specific admin, fee, oracle, and permission level slots
    /// @return slots Array of storage slot identifiers to protect.
    function _protectedSlots() internal pure virtual returns (bytes32[] memory slots);

    /// @notice Register the default trigger set for slot protection.
    /// @dev Registers one storage-change trigger per protected slot, so the check runs only when a
    ///      watched slot is actually written during the transaction instead of on every adopter
    ///      transaction. This narrows execution to the exact risk surface without weakening the
    ///      invariant: `assertSlotProtection` still inspects the whole journal via
    ///      `forbidChangeForSlots`, which flags any SSTORE to a protected slot. A storage-change
    ///      trigger fires off that same journal, so same-value writes (which `forbidChangeForSlots`
    ///      treats as suspicious) still arm the assertion. Call this inside your `triggers()`.
    function _registerSlotProtectionTriggers() internal view {
        bytes32[] memory slots = _protectedSlots();
        for (uint256 i; i < slots.length; ++i) {
            registerStorageChangeTrigger(this.assertSlotProtection.selector, slots[i]);
        }
    }

    /// @notice Verifies that none of the protected storage slots were written to during the tx.
    /// @dev Uses `ph.forbidChangeForSlots()` for a single precompile call covering all slots.
    ///      Reverts if any protected slot was modified.
    function assertSlotProtection() external view {
        bytes32[] memory slots = _protectedSlots();
        if (!ph.forbidChangeForSlots(slots)) {
            revert ProtectedSlotChanged(slots);
        }
    }
}

// policy-catalog/sources/policy-assertions.sol

/// @title TokenOutflowCircuitBreakerAssertion
/// @notice A constructor-configured rolling token outflow limit for any custody adopter.
/// @dev Generalizes the independent Derive SpotVault breaker and Lighter bridge breaker. The
///      executor maintains the rolling net-outflow context; this assertion decides whether an
///      armed transaction is a hard stop when transactionCapBps is zero, or a soft per-transaction cap.
///      Deploy one instance per token and threshold tier. minimumOutflow is zero when the
///      adopter does not need Derive's thin-asset floor.
contract TokenOutflowCircuitBreakerAssertion is Assertion {
    address public immutable TOKEN;
    uint256 public immutable THRESHOLD_BPS;
    uint256 public immutable WINDOW;
    uint256 public immutable MINIMUM_OUTFLOW;
    uint256 public immutable TRANSACTION_CAP_BPS;

    constructor(
        address token_,
        uint256 thresholdBps_,
        uint256 window_,
        uint256 minimumOutflow_,
        uint256 transactionCapBps_
    ) {
        require(token_ != address(0), "Outflow breaker: token zero");
        require(thresholdBps_ > 0 && thresholdBps_ < 10_000, "Outflow breaker: invalid threshold");
        require(window_ >= 10 && window_ <= type(uint64).max, "Outflow breaker: invalid window");
        require(transactionCapBps_ < thresholdBps_, "Outflow breaker: cap must be below threshold");
        TOKEN = token_;
        THRESHOLD_BPS = thresholdBps_;
        WINDOW = window_;
        MINIMUM_OUTFLOW = minimumOutflow_;
        TRANSACTION_CAP_BPS = transactionCapBps_;
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    function triggers() external view override {
        watchCumulativeOutflow(TOKEN, THRESHOLD_BPS, WINDOW, this.assertionOutflowWithinLimit.selector);
    }

    function assertionOutflowWithinLimit() external view {
        PhEvm.OutflowContext memory context = ph.outflowContext();
        if (context.cumulativeOutflow < MINIMUM_OUTFLOW) return;

        address adopter = ph.getAssertionAdopter();
        uint256 grossOutflow;
        PhEvm.Erc20TransferData[] memory transfers = ph.getErc20Transfers(TOKEN, _postTx());
        for (uint256 i; i < transfers.length; ++i) {
            if (transfers[i].from == adopter && transfers[i].to != adopter) grossOutflow += transfers[i].value;
        }
        if (grossOutflow == 0) return;
        if (TRANSACTION_CAP_BPS == 0) revert("Outflow breaker: hard limit reached");

        uint256 balance = _readBalanceAt(TOKEN, adopter, _preTx());
        if (context.tvlSnapshot != 0 && context.tvlSnapshot < balance) balance = context.tvlSnapshot;
        require(grossOutflow * 10_000 <= balance * TRANSACTION_CAP_BPS, "Outflow breaker: transaction cap exceeded");
    }
}

/// @title UpgradeGovernancePolicyAssertion
/// @author Phylax Systems
/// @notice Requires governance to replace or disable the active assertion release before changing
///         the protected proxy implementation.
/// @dev Protects the EIP-1967 implementation slot on one adopter. This assertion does not inspect
///      finality, priority-request accounting, desert mode, Safe actions, or bridge outflows.
contract UpgradeGovernancePolicyAssertion is SlotProtectionAssertion {
    error InvalidProtectedProxy();

    /// @notice EIP-1967 implementation slot, `keccak256("eip1967.proxy.implementation") - 1`.
    bytes32 internal constant EIP1967_IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    constructor(address protectedProxy_) AccessControlBaseAssertion(protectedProxy_) {
        if (protectedProxy_ == address(0)) revert InvalidProtectedProxy();
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    /// @notice Registers one storage-change trigger for the proxy implementation slot.
    function triggers() external view override {
        _registerSlotProtectionTriggers();
    }

    function _protectedSlots() internal pure override returns (bytes32[] memory slots) {
        slots = new bytes32[](1);
        slots[0] = EIP1967_IMPLEMENTATION_SLOT;
    }
}

/// @title SafeConfigurationPolicyAssertion
/// @notice A Safe ends every transaction with the signers, threshold and plumbing it started
///         the package with.
/// @dev Adopted by each Safe. Who can sign, how many must sign, and which code runs behind the
///      Safe are what every other assertion relies on. Pinned exactly, not as a minimum:
///      - the owner set (any order) and the threshold;
///      - no modules, since a module executes without signatures and outside the action policy;
///      - the transaction guard, the module guard (Safe 1.5.0) and the fallback handler;
///      - the singleton in storage slot 0, which a delegatecall could otherwise rewrite.
///      It runs at transaction end on every transaction that writes the Safe's storage, which is
///      every executed Safe transaction (the nonce moves), whatever path made the change. Rotating a
///      signer or installing a guard follows the agreed flow: disable, change, re-enable with the new
///      configuration.
contract SafeConfigurationPolicyAssertion is SafeConfigLockHelpers {
    bytes32 public immutable OWNER_SET_HASH;
    uint256 public immutable OWNER_COUNT;
    uint256 public immutable THRESHOLD;
    address public immutable SINGLETON;
    address public immutable FALLBACK_HANDLER;
    address public immutable GUARD;

    constructor(address[] memory owners, uint256 threshold, address singleton, address fallbackHandler, address guard) {
        require(owners.length != 0 && threshold != 0 && threshold <= owners.length, "Safe lock: bad owners");
        require(singleton != address(0), "Safe lock: singleton zero");
        OWNER_SET_HASH = hashAddressSet(owners);
        OWNER_COUNT = owners.length;
        THRESHOLD = threshold;
        SINGLETON = singleton;
        FALLBACK_HANDLER = fallbackHandler;
        GUARD = guard;
        _registerReshiramSpec();
    }

    function triggers() external view override {
        registerStorageChangeTrigger(this.assertionSafeConfigUnchanged.selector);
    }

    /// @notice The Safe's configuration at transaction end is the pinned one.
    /// - A failure names the part that moved: owners, threshold, modules, guard, fallback handler or
    ///   singleton.
    function assertionSafeConfigUnchanged() external view {
        address safe = ph.getAssertionAdopter();
        PhEvm.ForkId memory post = _postTx();

        // First: every other read below runs the singleton's code, which a new singleton controls.
        require(_addressSlotAt(safe, bytes32(0), post) == SINGLETON, "Safe: singleton changed");
        address[] memory owners = _ownersAt(safe, post);
        require(owners.length == OWNER_COUNT && hashAddressSet(owners) == OWNER_SET_HASH, "Safe: owner set changed");
        require(_thresholdAt(safe, post) == THRESHOLD, "Safe: threshold changed");
        require(_modulesAt(safe, post).length == 0, "Safe: module enabled");
        require(_guardAt(safe, post) == GUARD, "Safe: guard changed");
        require(_moduleGuardAt(safe, post) == address(0), "Safe: module guard set");
        require(_fallbackHandlerAt(safe, post) == FALLBACK_HANDLER, "Safe: fallback handler changed");
    }
}

/// @title SafeOutflowCircuitBreakerAssertion
/// @notice Caps how much of one token can leave a Safe in a rolling window, at a limit fitted
///         to the Safe's own history.
/// @dev Adopted by a Safe, one instance per (token, window). The action policy decides how
///      funds may leave; this decides how fast. It counts every way the Safe's balance can fall: a
///      Safe transaction, a batch, or a `transferFrom` pull by a contract the Safe approved, even in a
///      transaction the Safe never signed.
///      - The window counter is the Safe's net outflow of the token (out minus in) over the last
///        `WINDOW` seconds, kept by the executor. The trigger threshold is 1 bps of the window-start
///        balance, so the absolute `LIMIT` is what decides.
///      - Once the counter reaches `LIMIT`, any transaction that moves the token out of the Safe is
///        rejected until the window rolls forward. Inflows always pass.
///      - Transfers to other Safes count like any other. Inflows offset the counter, so an
///        exemption for them would let funds pass through: a Safe could receive a sibling's balance
///        and send it on with its counter near zero. Without one, a drain through any chain of Derive
///        Safes is bounded by the sum of their limits per window. Sweeps larger than a limit are
///        planned one-offs: disable, sweep, re-enable.
///      - Burns (a LayerZero OFT `send`) count: the tokens leave the Safe's custody.
contract SafeOutflowCircuitBreakerAssertion is Assertion {
    /// @notice The ERC-20 this instance watches.
    address public immutable TOKEN;
    /// @notice Rolling window length in seconds.
    uint256 public immutable WINDOW;
    /// @notice Net outflow over the window, in token units, at which outflows stop.
    uint256 public immutable LIMIT;

    constructor(address token, uint256 window, uint256 limit) {
        require(token != address(0), "Safe breaker: token zero");
        require(window >= 10 && window <= type(uint64).max, "Safe breaker: invalid window");
        require(limit != 0, "Safe breaker: limit zero");
        TOKEN = token;
        WINDOW = window;
        LIMIT = limit;
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    function triggers() external view virtual override {
        watchCumulativeOutflow(TOKEN, 1, WINDOW, this.assertionOutflowWithinLimit.selector);
    }

    /// @notice While the window's net outflow is at or above `LIMIT`, the token cannot leave the Safe.
    /// - The counter includes this transaction, so the transaction that reaches the limit is rejected.
    /// - A failure means the Safe tried to pay out more of the token, in the window, than its history
    ///   supports.
    function assertionOutflowWithinLimit() external view {
        if (_windowOutflow() < LIMIT) return;
        address safe = ph.getAssertionAdopter();
        PhEvm.Erc20TransferData[] memory transfers = ph.getErc20Transfers(TOKEN, _postTx());
        for (uint256 i; i < transfers.length; ++i) {
            if (transfers[i].from == safe && transfers[i].to != safe && transfers[i].value != 0) {
                revert("Safe: outflow limit reached");
            }
        }
    }

    /// @dev The executor's net outflow for the window, including this transaction.
    function _windowOutflow() internal view virtual returns (uint256) {
        return ph.outflowContext().cumulativeOutflow;
    }
}

/// @title SafeActionPolicyAssertion
/// @notice A Safe may only make the calls its history shows it makes.
/// @dev Adopted by each Safe, with that Safe's policy as constructor arguments (rendered into
///      assertions/credible.toml). It runs on every `execTransaction` into the Safe and
///      checks each call the Safe is about to make: the call itself, or every call in a batch run
///      through an approved MultiSendCallOnly. A stolen signer quorum, a compromised signing UI or a
///      blind-signed payload can still only produce calls of an allowed shape:
///      - Allowed calls are `(target, selector)` pairs. `ANY` as the target allows the selector on
///        every contract. That is used only for calls that do nothing unless the Safe holds a role on
///        the target (claiming ownership, updating Socket limits, revoking roles), or for calls whose
///        arguments are pinned (a token sweep that may only go to another Safe). An exact rule
///        takes precedence over the wildcard, with only its own pins.
///      - Each rule caps the ETH the call may carry. `EMPTY` as the selector is a plain ETH transfer.
///      - Argument pins fix a calldata word to a value, to the Safe itself (`SELF`) or to any Derive
///        Safe (`INTERNAL`). Pin word `TARGET_WORD` pins the call target instead.
///      - ERC-20 `approve` is checked against per-(token, spender) caps instead of a rule. Setting an
///        allowance to zero is always allowed. `increaseAllowance` and `setApprovalForAll` may only
///        lower or revoke.
///      - Everything else is rejected: unknown calls, delegatecall outside the batch executors, inner
///        delegatecalls, nested batches, calls to the Safe itself (owner, threshold, module, guard,
///        fallback and singleton changes), signed gas refunds and module executions. the adopter's Safes
///        have never used modules or refunds.
///      - The ETH all calls carry together is capped per transaction.
///      Funds can still leave through allowed calls, such as a token `transfer`. The outflow
///      breakers bound how fast; this policy bounds how. Planned changes outside the policy follow
///      the agreed flow: disable, change, re-enable.
contract SafeActionPolicyAssertion is Assertion {
    struct CallRule {
        address target;
        bytes4 selector;
        uint256 maxValue;
    }

    struct ArgPin {
        address target;
        bytes4 selector;
        uint8 word;
        bytes32 value;
    }

    struct ApprovalCap {
        address token;
        address spender;
        uint256 maxAmount;
    }

    struct Pin {
        uint8 word;
        bytes32 value;
    }

    /// @notice Rule target matching every contract.
    address public constant ANY = address(0);
    /// @notice Rule selector for a call with empty calldata (a plain ETH transfer).
    bytes4 public constant EMPTY = bytes4(0);
    /// @notice Pin value standing for the adopting Safe.
    bytes32 public constant SELF = keccak256("credible.safe-policy.self");
    /// @notice Pin value standing for any address in the configured internal set.
    bytes32 public constant INTERNAL = keccak256("credible.safe-policy.internal");
    /// @notice Pin word that checks the call target instead of a calldata word.
    uint8 public constant TARGET_WORD = type(uint8).max;
    /// @notice Most calls one batch may hold; a larger batch fails closed.
    uint256 public constant MAX_BATCH_CALLS = 200;

    /// @notice Most Safe transactions one Ethereum transaction may execute; more fails closed.
    uint256 public constant MAX_EXECS_PER_TX = 8;

    bytes4 internal constant EXEC_TRANSACTION = 0x6a761202;
    bytes4 internal constant EXEC_FROM_MODULE = 0x468721a7;
    bytes4 internal constant EXEC_FROM_MODULE_RETURN_DATA = 0x5229073f;
    bytes4 internal constant MULTI_SEND = 0x8d80ff0a;
    bytes4 internal constant APPROVE = 0x095ea7b3;
    bytes4 internal constant INCREASE_ALLOWANCE = 0x39509351;
    bytes4 internal constant SET_APPROVAL_FOR_ALL = 0xa22cb465;

    uint8 internal constant CALL = 0;
    uint8 internal constant DELEGATECALL = 1;
    /// @dev Packed MultiSend entry header: operation (1), to (20), value (32), data length (32).
    uint256 internal constant ENTRY_HEADER = 85;

    /// @notice Most ETH one Safe transaction may send, summed over all of its calls.
    uint256 public immutable MAX_ETH_PER_TX;

    mapping(bytes32 key => uint256 maxValuePlusOne) internal _rules;
    mapping(bytes32 key => Pin[]) internal _pins;
    mapping(address token => mapping(address spender => uint256 capPlusOne)) internal _approvalCaps;
    mapping(address executor => bool) public isBatchExecutor;
    mapping(address account => bool) public isInternal;

    error SafeActionPolicyModuleExecutionBlocked(bytes4 entrypoint);
    error SafeActionPolicyTooManyExecutions(uint256 maxExecutions);
    error SafeActionPolicyGasRefundBlocked(uint256 gasPrice);
    error SafeActionPolicyDelegateCallBlocked(address target);
    error SafeActionPolicyInnerDelegateCallBlocked(address target);
    error SafeActionPolicyNestedBatchBlocked(address target);
    error SafeActionPolicyUnknownOperation(uint8 operation);
    error SafeActionPolicyMalformedCalldata();
    error SafeActionPolicyBatchTooLarge(uint256 maxCalls);
    error SafeActionPolicySelfCallBlocked(bytes4 selector);
    error SafeActionPolicyCallNotAllowed(address target, bytes4 selector);
    error SafeActionPolicyValueNotAllowed(address target, bytes4 selector, uint256 value, uint256 maxValue);
    error SafeActionPolicyArgumentNotAllowed(address target, bytes4 selector, uint8 word, bytes32 value);
    error SafeActionPolicyApprovalNotAllowed(address token, address spender, uint256 amount);
    error SafeActionPolicyApprovalAboveCap(address token, address spender, uint256 amount, uint256 cap);
    error SafeActionPolicyEthCapExceeded(uint256 value, uint256 cap);
    error SafeActionPolicyInvalidPolicy();

    constructor(
        address[] memory batchExecutors,
        address[] memory internalSet,
        CallRule[] memory rules,
        ArgPin[] memory pins,
        ApprovalCap[] memory approvalCaps,
        uint256 maxEthPerTx
    ) {
        for (uint256 i; i < batchExecutors.length; ++i) {
            if (batchExecutors[i] == address(0)) revert SafeActionPolicyInvalidPolicy();
            isBatchExecutor[batchExecutors[i]] = true;
        }
        for (uint256 i; i < internalSet.length; ++i) {
            isInternal[internalSet[i]] = true;
        }
        for (uint256 i; i < rules.length; ++i) {
            CallRule memory rule = rules[i];
            bytes32 key = _key(rule.target, rule.selector);
            // Approvals have their own caps, and batches are expanded rather than called.
            if (
                _rules[key] != 0 || rule.selector == APPROVE || rule.selector == INCREASE_ALLOWANCE
                    || rule.selector == SET_APPROVAL_FOR_ALL || isBatchExecutor[rule.target]
                    || rule.maxValue == type(uint256).max
            ) revert SafeActionPolicyInvalidPolicy();
            _rules[key] = rule.maxValue + 1;
        }
        for (uint256 i; i < pins.length; ++i) {
            ArgPin memory pin = pins[i];
            bytes32 key = _key(pin.target, pin.selector);
            if (_rules[key] == 0) revert SafeActionPolicyInvalidPolicy();
            _pins[key].push(Pin({word: pin.word, value: pin.value}));
        }
        for (uint256 i; i < approvalCaps.length; ++i) {
            ApprovalCap memory cap = approvalCaps[i];
            if (
                cap.token == address(0) || cap.spender == address(0) || cap.maxAmount == 0
                    || cap.maxAmount == type(uint256).max || _approvalCaps[cap.token][cap.spender] != 0
            ) revert SafeActionPolicyInvalidPolicy();
            _approvalCaps[cap.token][cap.spender] = cap.maxAmount + 1;
        }
        MAX_ETH_PER_TX = maxEthPerTx;
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    function triggers() external view override {
        registerTxEndTrigger(this.assertionSafeCallsAllowed.selector);
    }

    /// @notice Every call the Safe made in this transaction matches its policy.
    /// - Walks every successful CALL into the Safe with `execTransaction`, at any depth: one Safe
    ///   transaction, several in one transaction, or one sent through a relayer or another Safe. The
    ///   proxy's DELEGATECALL into the singleton carries the same calldata and is not counted twice.
    /// - Rejects any module execution: the adopter's Safes have no modules.
    /// - A failure names the call that broke the policy.
    function assertionSafeCallsAllowed() external view {
        address safe = ph.getAssertionAdopter();
        PhEvm.CallFilter memory frames = PhEvm.CallFilter({
            callType: 1, minDepth: 0, maxDepth: type(uint32).max, topLevelOnly: false, successOnly: true
        });
        if (ph.matchingCalls(safe, EXEC_FROM_MODULE, frames, 1).length != 0) {
            revert SafeActionPolicyModuleExecutionBlocked(EXEC_FROM_MODULE);
        }
        if (ph.matchingCalls(safe, EXEC_FROM_MODULE_RETURN_DATA, frames, 1).length != 0) {
            revert SafeActionPolicyModuleExecutionBlocked(EXEC_FROM_MODULE_RETURN_DATA);
        }
        PhEvm.TriggerCall[] memory execs = ph.matchingCalls(safe, EXEC_TRANSACTION, frames, MAX_EXECS_PER_TX + 1);
        if (execs.length > MAX_EXECS_PER_TX) revert SafeActionPolicyTooManyExecutions(MAX_EXECS_PER_TX);
        for (uint256 i; i < execs.length; ++i) {
            _checkExecTransaction(safe, ph.callinputAt(execs[i].callId));
        }
    }

    /// @dev One `execTransaction`: the Safe transaction and, for a batch, every call inside it.
    function _checkExecTransaction(address safe, bytes memory input) internal view {
        // execTransaction(to, value, data, operation, safeTxGas, baseGas, gasPrice, gasToken,
        //                 refundReceiver, signatures): ten head words.
        if (input.length < 4 + 32 * 10) revert SafeActionPolicyMalformedCalldata();
        uint256 gasPrice = _word(input, 4 + 32 * 6);
        if (gasPrice != 0) revert SafeActionPolicyGasRefundBlocked(gasPrice);

        address to = _address(input, 4);
        uint256 value = _word(input, 4 + 32);
        (uint256 dataOffset, uint256 dataLength) = _bytesArg(input, 4, _word(input, 4 + 32 * 2));
        uint256 operation = _word(input, 4 + 32 * 3);

        uint256 eth;
        if (operation == CALL) {
            eth = _checkCall(safe, to, value, input, dataOffset, dataLength);
        } else if (operation == DELEGATECALL) {
            if (!isBatchExecutor[to]) revert SafeActionPolicyDelegateCallBlocked(to);
            if (value != 0) revert SafeActionPolicyValueNotAllowed(to, MULTI_SEND, value, 0);
            eth = _checkBatch(safe, input, dataOffset, dataLength);
        } else {
            revert SafeActionPolicyUnknownOperation(uint8(operation > type(uint8).max ? type(uint8).max : operation));
        }
        if (eth > MAX_ETH_PER_TX) revert SafeActionPolicyEthCapExceeded(eth, MAX_ETH_PER_TX);
    }

    /// @notice Whether `(target, selector)` has a rule, and the ETH it may carry.
    function ruleFor(address target, bytes4 selector) external view returns (bool allowed, uint256 maxValue) {
        uint256 stored = _rules[_key(target, selector)];
        return stored == 0 ? (false, 0) : (true, stored - 1);
    }

    /// @notice The approval cap for `(token, spender)`, zero if none.
    function approvalCap(address token, address spender) external view returns (uint256) {
        uint256 stored = _approvalCaps[token][spender];
        return stored == 0 ? 0 : stored - 1;
    }

    // ---------------------------------------------------------------
    //  Checks
    // ---------------------------------------------------------------

    /// @dev Expands `multiSend(bytes)` run by delegatecall from the Safe. Only canonical ABI encoding
    ///      is accepted, and the packed entries must tile the payload exactly.
    function _checkBatch(address safe, bytes memory input, uint256 dataOffset, uint256 dataLength)
        internal
        view
        returns (uint256 eth)
    {
        if (dataLength < 4 + 64 || _selectorAt(input, dataOffset) != MULTI_SEND) {
            revert SafeActionPolicyMalformedCalldata();
        }
        if (_word(input, dataOffset + 4) != 32) revert SafeActionPolicyMalformedCalldata();
        uint256 payloadLength = _word(input, dataOffset + 4 + 32);
        uint256 payload = dataOffset + 4 + 64;
        if (payloadLength > dataOffset + dataLength - payload) revert SafeActionPolicyMalformedCalldata();

        uint256 end = payload + payloadLength;
        uint256 cursor = payload;
        uint256 calls;
        while (cursor < end) {
            if (end - cursor < ENTRY_HEADER) revert SafeActionPolicyMalformedCalldata();
            uint8 operation = uint8(input[cursor]);
            address target = _packedAddress(input, cursor + 1);
            uint256 value = _word(input, cursor + 21);
            uint256 length = _word(input, cursor + 53);
            uint256 data = cursor + ENTRY_HEADER;
            if (length > end - data) revert SafeActionPolicyMalformedCalldata();
            if (++calls > MAX_BATCH_CALLS) revert SafeActionPolicyBatchTooLarge(MAX_BATCH_CALLS);
            if (operation != CALL) revert SafeActionPolicyInnerDelegateCallBlocked(target);
            if (isBatchExecutor[target]) revert SafeActionPolicyNestedBatchBlocked(target);
            // Safe 1.5.0's MultiSendCallOnly sends a zero `to` to the Safe itself.
            if (target == address(0)) target = safe;
            eth += _checkCall(safe, target, value, input, data, length);
            cursor = data + length;
        }
    }

    /// @dev One call from the Safe. Returns the ETH it carries.
    function _checkCall(address safe, address target, uint256 value, bytes memory input, uint256 offset, uint256 length)
        internal
        view
        returns (uint256)
    {
        bytes4 selector;
        if (length != 0) {
            if (length < 4) revert SafeActionPolicyMalformedCalldata();
            selector = _selectorAt(input, offset);
            // A real zero selector would collide with the plain-transfer rule.
            if (selector == EMPTY) revert SafeActionPolicyCallNotAllowed(target, selector);
        }

        if (target == safe) {
            // An empty self-call with no value only burns a nonce (Safe's "reject transaction").
            if (length == 0 && value == 0) return 0;
            revert SafeActionPolicySelfCallBlocked(selector);
        }

        if (selector == APPROVE || selector == INCREASE_ALLOWANCE || selector == SET_APPROVAL_FOR_ALL) {
            if (value != 0) revert SafeActionPolicyValueNotAllowed(target, selector, value, 0);
            _checkApproval(target, selector, input, offset, length);
            return 0;
        }

        // An exact rule takes precedence over the wildcard, together with its own pins.
        bytes32 key = _key(target, selector);
        uint256 stored = _rules[key];
        if (stored == 0) {
            key = _key(ANY, selector);
            stored = _rules[key];
        }
        if (stored == 0) revert SafeActionPolicyCallNotAllowed(target, selector);
        if (value > stored - 1) revert SafeActionPolicyValueNotAllowed(target, selector, value, stored - 1);

        _checkPins(_pins[key], safe, target, selector, input, offset, length);
        return value;
    }

    function _checkPins(
        Pin[] storage pins,
        address safe,
        address target,
        bytes4 selector,
        bytes memory input,
        uint256 offset,
        uint256 length
    ) internal view {
        for (uint256 i; i < pins.length; ++i) {
            Pin memory pin = pins[i];
            bytes32 actual;
            if (pin.word == TARGET_WORD) {
                actual = bytes32(uint256(uint160(target)));
            } else {
                uint256 at = 4 + 32 * uint256(pin.word);
                if (length < at + 32) {
                    revert SafeActionPolicyArgumentNotAllowed(target, selector, pin.word, bytes32(0));
                }
                actual = bytes32(_word(input, offset + at));
            }
            bool ok;
            if (pin.value == SELF) {
                ok = actual == bytes32(uint256(uint160(safe)));
            } else if (pin.value == INTERNAL) {
                ok = uint256(actual) >> 160 == 0 && isInternal[address(uint160(uint256(actual)))];
            } else {
                ok = actual == pin.value;
            }
            if (!ok) revert SafeActionPolicyArgumentNotAllowed(target, selector, pin.word, actual);
        }
    }

    /// @dev `approve(spender, amount)` must be zero or within the (token, spender) cap. Allowances only
    ///      go down through `increaseAllowance(spender, 0)` and `setApprovalForAll(operator, false)`.
    function _checkApproval(address token, bytes4 selector, bytes memory input, uint256 offset, uint256 length)
        internal
        view
    {
        if (length != 4 + 64) revert SafeActionPolicyMalformedCalldata();
        address spender = _address(input, offset + 4);
        uint256 amount = _word(input, offset + 36);
        if (amount == 0) return;
        uint256 stored = selector == APPROVE ? _approvalCaps[token][spender] : 0;
        if (stored == 0) revert SafeActionPolicyApprovalNotAllowed(token, spender, amount);
        if (amount > stored - 1) revert SafeActionPolicyApprovalAboveCap(token, spender, amount, stored - 1);
    }

    // ---------------------------------------------------------------
    //  Calldata reads (bounds-checked)
    // ---------------------------------------------------------------

    function _key(address target, bytes4 selector) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(target, selector));
    }

    function _word(bytes memory data, uint256 offset) internal pure returns (uint256 value) {
        if (offset > data.length || data.length - offset < 32) revert SafeActionPolicyMalformedCalldata();
        assembly {
            value := mload(add(add(data, 32), offset))
        }
    }

    function _address(bytes memory data, uint256 offset) internal pure returns (address) {
        uint256 raw = _word(data, offset);
        if (raw >> 160 != 0) revert SafeActionPolicyMalformedCalldata();
        return address(uint160(raw));
    }

    function _packedAddress(bytes memory data, uint256 offset) internal pure returns (address) {
        return address(uint160(_word(data, offset) >> 96));
    }

    function _selectorAt(bytes memory data, uint256 offset) internal pure returns (bytes4 selector) {
        if (offset > data.length || data.length - offset < 4) revert SafeActionPolicyMalformedCalldata();
        assembly {
            selector := and(mload(add(add(data, 32), offset)), shl(224, 0xffffffff))
        }
    }

    /// @dev Bounds of an ABI `bytes` argument whose head word holds `relativeOffset` from `headStart`.
    function _bytesArg(bytes memory data, uint256 headStart, uint256 relativeOffset)
        internal
        pure
        returns (uint256 offset, uint256 length)
    {
        if (relativeOffset > data.length) revert SafeActionPolicyMalformedCalldata();
        uint256 lengthAt = headStart + relativeOffset;
        length = _word(data, lengthAt);
        offset = lengthAt + 32;
        if (length > data.length - offset) revert SafeActionPolicyMalformedCalldata();
    }
}
