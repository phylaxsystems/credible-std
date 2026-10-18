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

// src/protection/safe/SafeTxShapeHelpers.sol

/// @title SafeTxShapeHelpers
/// @author Phylax Systems
/// @notice Shared decoding and policy helpers for Safe transaction-shape assertions.
abstract contract SafeTxShapeHelpers is Assertion {
    uint8 internal constant OPERATION_CALL = 0;
    uint8 internal constant OPERATION_DELEGATECALL = 1;

    uint8 public constant APPROVAL_KIND_ERC20_APPROVE = 1;
    uint8 public constant APPROVAL_KIND_ERC20_INCREASE_ALLOWANCE = 2;
    uint8 public constant APPROVAL_KIND_ERC721_APPROVE = 3;
    uint8 public constant APPROVAL_KIND_ERC721_SET_APPROVAL_FOR_ALL = 4;
    uint8 public constant APPROVAL_KIND_ERC1155_SET_APPROVAL_FOR_ALL = 5;

    bytes4 public constant EXEC_TRANSACTION_SELECTOR =
        bytes4(keccak256("execTransaction(address,uint256,bytes,uint8,uint256,uint256,uint256,address,address,bytes)"));
    bytes4 public constant EXEC_TRANSACTION_FROM_MODULE_SELECTOR =
        bytes4(keccak256("execTransactionFromModule(address,uint256,bytes,uint8)"));
    bytes4 public constant EXEC_TRANSACTION_FROM_MODULE_RETURN_DATA_SELECTOR =
        bytes4(keccak256("execTransactionFromModuleReturnData(address,uint256,bytes,uint8)"));

    bytes4 public constant MULTISEND_SELECTOR = bytes4(keccak256("multiSend(bytes)"));
    bytes4 public constant APPROVE_SELECTOR = bytes4(keccak256("approve(address,uint256)"));
    bytes4 public constant INCREASE_ALLOWANCE_SELECTOR = bytes4(keccak256("increaseAllowance(address,uint256)"));
    bytes4 public constant SET_APPROVAL_FOR_ALL_SELECTOR = bytes4(keccak256("setApprovalForAll(address,bool)"));

    uint256 internal constant MULTISEND_HEADER_LENGTH = 85;
    uint64 internal constant ALLOWANCE_READ_GAS = 500_000;
    uint256 internal constant MAX_BATCH_ACTIONS = 4;

    struct TargetPolicy {
        address target;
        bool allowAnySelector;
        bool allowEmptyCalldata;
        bool allowFallbackCalldata;
        bool allowNonzeroValue;
    }

    struct SelectorPolicy {
        address target;
        bytes4 selector;
        bool allowNonzeroValue;
    }

    struct BatchExecutorPolicy {
        address executor;
        bytes4 selector;
        bool allowDelegateCall;
        uint256 maxActions;
        bool allowNested;
    }

    struct ApprovalPolicy {
        address token;
        address spender;
        uint8 kind;
        uint256 maxAmount;
        bool allowUnlimited;
    }

    struct TriggeredSafeCall {
        bytes4 selector;
        address caller;
        bytes input;
        uint256 callStart;
        uint256 callEnd;
    }

    struct OwnerTx {
        address to;
        uint256 value;
        bytes data;
        uint8 operation;
    }

    struct ModuleTx {
        address to;
        uint256 value;
        bytes data;
        uint8 operation;
    }

    struct Action {
        address safe;
        address caller;
        address module;
        address target;
        uint256 value;
        bytes data;
        uint256 dataOffset;
        uint256 dataLength;
        uint8 operation;
        bool fromModule;
        bool fromBatch;
    }

    error SafeTxShapeDuplicateTarget(address target);
    error SafeTxShapeDuplicateSelector(address target, bytes4 selector);
    error SafeTxShapeDuplicateBatchExecutor(address executor, bytes4 selector);
    error SafeTxShapeDuplicateApprovalPolicy(address token, address spender, uint8 kind);
    error SafeTxShapeDuplicateModule(address module);
    error SafeTxShapeInvalidPolicy();
    error SafeTxShapeTriggeredCallNotFound(bytes4 selector, uint256 callStart);
    error SafeTxShapeUnsupportedEntrypoint(bytes4 selector);
    error SafeTxShapeModuleExecutionDisabled(address module);
    error SafeTxShapeModuleNotAllowed(address module);
    error SafeTxShapeUnknownOperation(uint8 operation);
    error SafeTxShapeDelegateCallBlocked(address target);
    error SafeTxShapeInnerDelegateCallBlocked(address target);
    error SafeTxShapeUnknownTarget(address target);
    error SafeTxShapeSelectorNotAllowed(address target, bytes4 selector);
    error SafeTxShapeCalldataTooShort(address target, uint256 length);
    error SafeTxShapeEmptyCalldataBlocked(address target);
    error SafeTxShapeFallbackCalldataBlocked(address target, uint256 length);
    error SafeTxShapeNativeValueBlocked(address target, bytes4 selector, uint256 value);
    error SafeTxShapeBatchDelegateCallNotAllowed(address executor);
    error SafeTxShapeBatchPayloadMalformed();
    error SafeTxShapeBatchTooManyActions(uint256 maxActions);
    error SafeTxShapeNestedBatchBlocked(address executor);
    error SafeTxShapeApprovalMalformed(address token, bytes4 selector);
    error SafeTxShapeApprovalTokenUnconfigured(address token, bytes4 selector);
    error SafeTxShapeApprovalSpenderNotAllowed(address token, address spender, uint8 kind);
    error SafeTxShapeApprovalUnlimitedBlocked(address token, address spender, uint8 kind);
    error SafeTxShapeApprovalAmountAboveCap(
        address token, address spender, uint8 kind, uint256 amount, uint256 maxAmount
    );
    error SafeTxShapeMixedApprovalMethodsBlocked();
    error SafeTxShapeAllowanceReadFailed(address token, address spender);
    error SafeTxShapeGasRefundBlocked(uint256 gasPrice);

    TargetPolicy[] public targetPolicies;
    SelectorPolicy[] public selectorPolicies;
    BatchExecutorPolicy[] public batchExecutorPolicies;
    ApprovalPolicy[] public approvalPolicies;
    address[] public allowedModules;

    mapping(address target => uint256 indexPlusOne) internal _targetPolicyIndexPlusOne;
    mapping(address target => mapping(bytes4 selector => uint256 indexPlusOne)) internal _selectorPolicyIndexPlusOne;
    mapping(address executor => mapping(bytes4 selector => uint256 indexPlusOne)) internal _batchPolicyIndexPlusOne;
    mapping(address token => mapping(address spender => mapping(uint8 kind => ApprovalPolicy))) internal
        _approvalPolicyByKey;
    mapping(address token => mapping(address spender => mapping(uint8 kind => bool))) internal _approvalPolicyExists;
    mapping(address token => mapping(address spender => mapping(uint8 kind => uint256 indexPlusOne))) internal
        _approvalPolicyIndexPlusOne;
    mapping(address token => mapping(uint8 kind => bool)) internal _tokenApprovalKindRegistered;
    mapping(address module => bool allowed) internal _allowedModule;

    bool public immutable moduleExecutionEnabled;

    constructor(
        TargetPolicy[] memory targetPolicies_,
        SelectorPolicy[] memory selectorPolicies_,
        BatchExecutorPolicy[] memory batchExecutorPolicies_,
        ApprovalPolicy[] memory approvalPolicies_,
        bool moduleExecutionEnabled_,
        address[] memory allowedModules_
    ) {
        if (targetPolicies_.length == 0) revert SafeTxShapeInvalidPolicy();
        if (moduleExecutionEnabled_ && allowedModules_.length == 0) revert SafeTxShapeInvalidPolicy();

        moduleExecutionEnabled = moduleExecutionEnabled_;

        _storeTargetPolicies(targetPolicies_);
        _storeSelectorPolicies(selectorPolicies_);
        _storeBatchExecutorPolicies(batchExecutorPolicies_);
        _storeApprovalPolicies(approvalPolicies_);
        _storeAllowedModules(allowedModules_);

        _registerReshiramSpec();
    }

    function targetPolicyCount() external view returns (uint256) {
        return targetPolicies.length;
    }

    function selectorPolicyCount() external view returns (uint256) {
        return selectorPolicies.length;
    }

    function batchExecutorPolicyCount() external view returns (uint256) {
        return batchExecutorPolicies.length;
    }

    function approvalPolicyCount() external view returns (uint256) {
        return approvalPolicies.length;
    }

    function allowedModuleCount() external view returns (uint256) {
        return allowedModules.length;
    }

    function _triggeredAction() internal view returns (Action memory action) {
        TriggeredSafeCall memory triggered = _resolveTriggeredSafeCall();
        address safe = ph.getAssertionAdopter();

        if (triggered.selector == EXEC_TRANSACTION_SELECTOR) {
            return _decodeOwnerAction(safe, triggered.input);
        }

        if (
            triggered.selector == EXEC_TRANSACTION_FROM_MODULE_SELECTOR
                || triggered.selector == EXEC_TRANSACTION_FROM_MODULE_RETURN_DATA_SELECTOR
        ) {
            return _decodeModuleAction(safe, triggered.caller, triggered.input);
        }

        revert SafeTxShapeUnsupportedEntrypoint(triggered.selector);
    }

    function _validateInnerDelegateCallPolicy(Action memory action) internal pure {
        if (action.operation > OPERATION_DELEGATECALL) revert SafeTxShapeUnknownOperation(action.operation);
        if (action.operation == OPERATION_DELEGATECALL) revert SafeTxShapeInnerDelegateCallBlocked(action.target);
    }

    function _validateInnerTargetSelectorPolicy(Action memory action) internal view {
        if (action.operation > OPERATION_DELEGATECALL) revert SafeTxShapeUnknownOperation(action.operation);
        if (action.operation == OPERATION_DELEGATECALL) return;

        _validateTargetAndSelector(action);
    }

    function _validateInnerApprovalPolicy(Action memory action) internal view {
        if (action.operation > OPERATION_DELEGATECALL) revert SafeTxShapeUnknownOperation(action.operation);
        if (action.operation == OPERATION_DELEGATECALL) return;

        if (action.dataLength < 4) return;
        _validateApproval(action, _selectorAt(action.data, action.dataOffset));
    }

    function _validateMultiSendDelegateCallPolicy(Action memory action, BatchExecutorPolicy storage batchPolicy)
        internal
        view
    {
        (uint256 transactionsOffset, uint256 transactionsLength) = _multiSendTransactions(action, batchPolicy);
        uint256 offset;
        while (offset < transactionsLength) {
            (Action memory innerAction, uint256 nextOffset) =
                _readMultiSendAction(action, transactionsOffset, transactionsLength, offset);
            _validateInnerDelegateCallPolicy(innerAction);
            offset = nextOffset;
        }
    }

    function _validateMultiSendTargetSelectorPolicy(Action memory action, BatchExecutorPolicy storage batchPolicy)
        internal
        view
    {
        (uint256 transactionsOffset, uint256 transactionsLength) = _multiSendTransactions(action, batchPolicy);
        uint256 offset;
        while (offset < transactionsLength) {
            (Action memory innerAction, uint256 nextOffset) =
                _readMultiSendAction(action, transactionsOffset, transactionsLength, offset);
            _validateInnerTargetSelectorPolicy(innerAction);
            offset = nextOffset;
        }
    }

    function _validateMultiSendBatchPolicy(Action memory action, BatchExecutorPolicy storage batchPolicy)
        internal
        view
    {
        (uint256 transactionsOffset, uint256 transactionsLength) = _multiSendTransactions(action, batchPolicy);
        uint256 offset;
        uint256 actionCount;

        while (offset < transactionsLength) {
            (Action memory innerAction, uint256 nextOffset) =
                _readMultiSendAction(action, transactionsOffset, transactionsLength, offset);

            ++actionCount;
            if (actionCount > batchPolicy.maxActions) revert SafeTxShapeBatchTooManyActions(batchPolicy.maxActions);
            if (innerAction.operation == OPERATION_DELEGATECALL) {
                revert SafeTxShapeInnerDelegateCallBlocked(innerAction.target);
            }
            if (_isConfiguredBatchCall(
                    innerAction.target, innerAction.data, innerAction.dataOffset, innerAction.dataLength
                )) {
                revert SafeTxShapeNestedBatchBlocked(innerAction.target);
            }

            offset = nextOffset;
        }
    }

    function _validateMultiSendApprovalPolicy(Action memory action, BatchExecutorPolicy storage batchPolicy)
        internal
        view
    {
        (uint256 transactionsOffset, uint256 transactionsLength) = _multiSendTransactions(action, batchPolicy);
        uint256[] memory cumulativeIncreases = new uint256[](approvalPolicies.length);
        uint256[] memory initialAllowances = new uint256[](approvalPolicies.length);
        bool[] memory allowanceLoaded = new bool[](approvalPolicies.length);
        bool approveSeen;
        bool increaseAllowanceSeen;
        uint256 offset;
        uint256 actionCount;
        while (offset < transactionsLength) {
            (Action memory innerAction, uint256 nextOffset) =
                _readMultiSendAction(action, transactionsOffset, transactionsLength, offset);
            ++actionCount;
            if (actionCount > batchPolicy.maxActions) revert SafeTxShapeBatchTooManyActions(batchPolicy.maxActions);
            bytes4 selector =
                innerAction.dataLength >= 4 ? _selectorAt(innerAction.data, innerAction.dataOffset) : bytes4(0);
            if (innerAction.operation == OPERATION_CALL && innerAction.dataLength == 68 && selector == APPROVE_SELECTOR)
            {
                _validateInnerApprovalPolicy(innerAction);
                if (_tokenHasApprovalKind(innerAction.target, APPROVAL_KIND_ERC20_APPROVE)) {
                    if (increaseAllowanceSeen) revert SafeTxShapeMixedApprovalMethodsBlocked();
                    approveSeen = true;
                }
            } else if (
                innerAction.operation == OPERATION_CALL && innerAction.dataLength == 68
                    && selector == INCREASE_ALLOWANCE_SELECTOR
            ) {
                if (_readUint256(innerAction.data, innerAction.dataOffset + 36) == 0) {
                    _validateInnerApprovalPolicy(innerAction);
                    offset = nextOffset;
                    continue;
                }
                if (approveSeen) revert SafeTxShapeMixedApprovalMethodsBlocked();
                increaseAllowanceSeen = true;
                _accumulateIncreaseAllowance(innerAction, cumulativeIncreases, initialAllowances, allowanceLoaded);
            } else {
                _validateInnerApprovalPolicy(innerAction);
            }
            offset = nextOffset;
        }
    }

    function _accumulateIncreaseAllowance(
        Action memory action,
        uint256[] memory cumulativeIncreases,
        uint256[] memory initialAllowances,
        bool[] memory allowanceLoaded
    ) internal view {
        address spender = _readAbiAddress(action.data, action.dataOffset + 4);
        uint256 addedValue = _readUint256(action.data, action.dataOffset + 36);
        uint256 policyIndexPlusOne =
            _approvalPolicyIndexPlusOne[action.target][spender][APPROVAL_KIND_ERC20_INCREASE_ALLOWANCE];
        if (policyIndexPlusOne == 0) {
            revert SafeTxShapeApprovalSpenderNotAllowed(action.target, spender, APPROVAL_KIND_ERC20_INCREASE_ALLOWANCE);
        }

        uint256 policyIndex = policyIndexPlusOne - 1;
        if (!allowanceLoaded[policyIndex]) {
            initialAllowances[policyIndex] = _readAllowanceFromPreState(action.caller, action.target, spender);
            allowanceLoaded[policyIndex] = true;
        }

        uint256 cumulativeIncrease = cumulativeIncreases[policyIndex];
        cumulativeIncrease =
            addedValue > type(uint256).max - cumulativeIncrease ? type(uint256).max : cumulativeIncrease + addedValue;
        cumulativeIncreases[policyIndex] = cumulativeIncrease;
        _validateAllowancePeak(action.target, spender, initialAllowances[policyIndex], cumulativeIncrease);
    }

    function _multiSendTransactions(Action memory action, BatchExecutorPolicy storage batchPolicy)
        internal
        view
        returns (uint256 transactionsOffset, uint256 transactionsLength)
    {
        if (action.operation == OPERATION_CALL && action.value != 0) {
            revert SafeTxShapeNativeValueBlocked(action.target, batchPolicy.selector, action.value);
        }
        if (action.operation == OPERATION_DELEGATECALL && !batchPolicy.allowDelegateCall) {
            revert SafeTxShapeBatchDelegateCallNotAllowed(action.target);
        }

        return _decodeSingleBytesArgument(action.data, action.dataOffset, action.dataLength, batchPolicy.selector);
    }

    function _readMultiSendAction(
        Action memory parent,
        uint256 transactionsOffset,
        uint256 transactionsLength,
        uint256 offset
    ) internal pure returns (Action memory innerAction, uint256 nextOffset) {
        if (offset > transactionsLength || transactionsLength - offset < MULTISEND_HEADER_LENGTH) {
            revert SafeTxShapeBatchPayloadMalformed();
        }

        uint256 entryOffset = transactionsOffset + offset;
        uint8 operation = uint8(parent.data[entryOffset]);
        if (operation > OPERATION_DELEGATECALL) revert SafeTxShapeUnknownOperation(operation);

        address target = _readPackedAddress(parent.data, entryOffset + 1);

        uint256 value = _readUint256(parent.data, entryOffset + 21);
        uint256 dataLength = _readUint256(parent.data, entryOffset + 53);
        uint256 dataOffset = entryOffset + MULTISEND_HEADER_LENGTH;
        uint256 transactionsEnd = transactionsOffset + transactionsLength;
        if (dataOffset > transactionsEnd || dataLength > transactionsEnd - dataOffset) {
            revert SafeTxShapeBatchPayloadMalformed();
        }

        innerAction = Action({
            safe: parent.safe,
            caller: parent.operation == OPERATION_CALL ? parent.target : parent.caller,
            module: parent.module,
            target: target,
            value: value,
            data: parent.data,
            dataOffset: dataOffset,
            dataLength: dataLength,
            operation: operation,
            fromModule: parent.fromModule,
            fromBatch: true
        });
        nextOffset = offset + MULTISEND_HEADER_LENGTH + dataLength;
    }

    function _validateTargetAndSelector(Action memory action) internal view returns (bytes4 selector) {
        if (action.target == address(0)) revert SafeTxShapeUnknownTarget(action.target);

        (bool knownTarget, uint256 targetIndex) = _targetPolicyIndex(action.target);
        if (!knownTarget) revert SafeTxShapeUnknownTarget(action.target);

        TargetPolicy storage targetPolicy = targetPolicies[targetIndex];

        if (action.dataLength == 0) {
            if (!targetPolicy.allowEmptyCalldata) revert SafeTxShapeEmptyCalldataBlocked(action.target);
            if (action.value != 0 && !targetPolicy.allowNonzeroValue) {
                revert SafeTxShapeNativeValueBlocked(action.target, bytes4(0), action.value);
            }
            return bytes4(0);
        }

        if (action.dataLength < 4) {
            if (!targetPolicy.allowFallbackCalldata) {
                revert SafeTxShapeFallbackCalldataBlocked(action.target, action.dataLength);
            }
            if (action.value != 0 && !targetPolicy.allowNonzeroValue) {
                revert SafeTxShapeNativeValueBlocked(action.target, bytes4(0), action.value);
            }
            return bytes4(0);
        }

        selector = _selectorAt(action.data, action.dataOffset);

        if (targetPolicy.allowAnySelector) {
            if (action.value != 0 && !targetPolicy.allowNonzeroValue) {
                revert SafeTxShapeNativeValueBlocked(action.target, selector, action.value);
            }
            return selector;
        }

        (bool selectorAllowed, uint256 selectorIndex) = _selectorPolicyIndex(action.target, selector);
        if (!selectorAllowed) revert SafeTxShapeSelectorNotAllowed(action.target, selector);

        if (action.value != 0 && !selectorPolicies[selectorIndex].allowNonzeroValue) {
            revert SafeTxShapeNativeValueBlocked(action.target, selector, action.value);
        }
    }

    function _validateApproval(Action memory action, bytes4 selector) internal view {
        if (selector == APPROVE_SELECTOR) {
            if (action.dataLength != 68) revert SafeTxShapeApprovalMalformed(action.target, selector);

            address spender = _readAbiAddress(action.data, action.dataOffset + 4);
            uint256 amountOrTokenId = _readUint256(action.data, action.dataOffset + 36);
            bool erc20 = _tokenHasApprovalKind(action.target, APPROVAL_KIND_ERC20_APPROVE);
            bool erc721 = _tokenHasApprovalKind(action.target, APPROVAL_KIND_ERC721_APPROVE);

            if (erc20) {
                if (amountOrTokenId == 0) return;
                _validateNumericApproval(action.target, spender, APPROVAL_KIND_ERC20_APPROVE, amountOrTokenId);
                return;
            }

            if (erc721) {
                if (spender == address(0)) return;
                _validateOperatorApproval(action.target, spender, APPROVAL_KIND_ERC721_APPROVE);
                return;
            }

            revert SafeTxShapeApprovalTokenUnconfigured(action.target, selector);
        }

        if (selector == INCREASE_ALLOWANCE_SELECTOR) {
            if (action.dataLength != 68) revert SafeTxShapeApprovalMalformed(action.target, selector);
            if (!_tokenHasApprovalKind(action.target, APPROVAL_KIND_ERC20_INCREASE_ALLOWANCE)) {
                revert SafeTxShapeApprovalTokenUnconfigured(action.target, selector);
            }

            address spender = _readAbiAddress(action.data, action.dataOffset + 4);
            uint256 addedValue = _readUint256(action.data, action.dataOffset + 36);
            if (addedValue == 0) return;

            _validateIncreaseAllowanceFromPreState(action.caller, action.target, spender, addedValue);
            return;
        }

        if (selector == SET_APPROVAL_FOR_ALL_SELECTOR) {
            if (action.dataLength != 68) revert SafeTxShapeApprovalMalformed(action.target, selector);

            bool erc721 = _tokenHasApprovalKind(action.target, APPROVAL_KIND_ERC721_SET_APPROVAL_FOR_ALL);
            bool erc1155 = _tokenHasApprovalKind(action.target, APPROVAL_KIND_ERC1155_SET_APPROVAL_FOR_ALL);
            if (!erc721 && !erc1155) revert SafeTxShapeApprovalTokenUnconfigured(action.target, selector);

            address operator = _readAbiAddress(action.data, action.dataOffset + 4);
            bool approved = _readAbiBool(action.data, action.dataOffset + 36);
            if (!approved) return;

            if (erc721 && _operatorApprovalAllowed(action.target, operator, APPROVAL_KIND_ERC721_SET_APPROVAL_FOR_ALL))
            {
                return;
            }
            if (
                erc1155 && _operatorApprovalAllowed(action.target, operator, APPROVAL_KIND_ERC1155_SET_APPROVAL_FOR_ALL)
            ) {
                return;
            }

            revert SafeTxShapeApprovalSpenderNotAllowed(
                action.target,
                operator,
                erc721 ? APPROVAL_KIND_ERC721_SET_APPROVAL_FOR_ALL : APPROVAL_KIND_ERC1155_SET_APPROVAL_FOR_ALL
            );
        }
    }

    function _validateNumericApproval(address token, address spender, uint8 kind, uint256 amount) internal view {
        if (!_approvalPolicyExists[token][spender][kind]) {
            revert SafeTxShapeApprovalSpenderNotAllowed(token, spender, kind);
        }

        ApprovalPolicy storage policy = _approvalPolicyByKey[token][spender][kind];
        if (amount == type(uint256).max) {
            if (!policy.allowUnlimited) revert SafeTxShapeApprovalUnlimitedBlocked(token, spender, kind);
            return;
        }

        if (amount > policy.maxAmount) {
            revert SafeTxShapeApprovalAmountAboveCap(token, spender, kind, amount, policy.maxAmount);
        }
    }

    function _validateIncreaseAllowanceFromPreState(
        address owner,
        address token,
        address spender,
        uint256 cumulativeIncrease
    ) internal view {
        if (!_approvalPolicyExists[token][spender][APPROVAL_KIND_ERC20_INCREASE_ALLOWANCE]) {
            revert SafeTxShapeApprovalSpenderNotAllowed(token, spender, APPROVAL_KIND_ERC20_INCREASE_ALLOWANCE);
        }

        uint256 initialAllowance = _readAllowanceFromPreState(owner, token, spender);
        _validateAllowancePeak(token, spender, initialAllowance, cumulativeIncrease);
    }

    function _readAllowanceFromPreState(address owner, address token, address spender) internal view returns (uint256) {
        PhEvm.TriggerContext memory triggerCtx = ph.context();
        PhEvm.ForkId memory preFork = _preCall(triggerCtx.callStart);
        PhEvm.StaticCallResult memory result = ph.staticcallAt(
            token, abi.encodeWithSignature("allowance(address,address)", owner, spender), ALLOWANCE_READ_GAS, preFork
        );
        if (!result.ok || result.data.length != 32) revert SafeTxShapeAllowanceReadFailed(token, spender);
        return abi.decode(result.data, (uint256));
    }

    function _validateAllowancePeak(
        address token,
        address spender,
        uint256 initialAllowance,
        uint256 cumulativeIncrease
    ) internal view {
        ApprovalPolicy storage policy = _approvalPolicyByKey[token][spender][APPROVAL_KIND_ERC20_INCREASE_ALLOWANCE];
        if (cumulativeIncrease > policy.maxAmount || initialAllowance > policy.maxAmount - cumulativeIncrease) {
            uint256 peakAllowance = cumulativeIncrease > type(uint256).max - initialAllowance
                ? type(uint256).max
                : initialAllowance + cumulativeIncrease;
            if (peakAllowance == type(uint256).max && policy.allowUnlimited) return;
            revert SafeTxShapeApprovalAmountAboveCap(
                token, spender, APPROVAL_KIND_ERC20_INCREASE_ALLOWANCE, peakAllowance, policy.maxAmount
            );
        }
    }

    function _validateOperatorApproval(address token, address operator, uint8 kind) internal view {
        if (!_operatorApprovalAllowed(token, operator, kind)) {
            revert SafeTxShapeApprovalSpenderNotAllowed(token, operator, kind);
        }
    }

    function _operatorApprovalAllowed(address token, address operator, uint8 kind) internal view returns (bool) {
        if (operator == address(0)) return false;
        return _approvalPolicyExists[token][operator][kind];
    }

    function _validateModuleCaller(address module) internal view {
        if (!moduleExecutionEnabled) revert SafeTxShapeModuleExecutionDisabled(module);
        if (!_allowedModule[module]) revert SafeTxShapeModuleNotAllowed(module);
    }

    function _resolveTriggeredSafeCall() internal view returns (TriggeredSafeCall memory triggered) {
        address safe = ph.getAssertionAdopter();
        PhEvm.TriggerContext memory context = ph.context();

        if (context.selector == EXEC_TRANSACTION_SELECTOR) {
            return TriggeredSafeCall({
                selector: context.selector,
                caller: address(0),
                input: ph.callinputAt(context.callStart),
                callStart: context.callStart,
                callEnd: context.callEnd
            });
        }

        PhEvm.CallInputs[] memory calls = ph.getAllCallInputs(safe, context.selector);

        for (uint256 i; i < calls.length; ++i) {
            if (calls[i].id == context.callStart) {
                return TriggeredSafeCall({
                    selector: context.selector,
                    caller: calls[i].caller,
                    input: ph.callinputAt(context.callStart),
                    callStart: context.callStart,
                    callEnd: context.callEnd
                });
            }
        }

        revert SafeTxShapeTriggeredCallNotFound(context.selector, context.callStart);
    }

    function _decodeOwnerTx(bytes memory input) internal pure returns (OwnerTx memory ownerTx) {
        if (input.length < 388 || _selector(input) != EXEC_TRANSACTION_SELECTOR) {
            revert SafeTxShapeBatchPayloadMalformed();
        }

        ownerTx.to = _readAbiAddress(input, 4);
        ownerTx.value = _readUint256(input, 36);
        ownerTx.data = _readDynamicBytes(input, 4, _readUint256(input, 68));
        ownerTx.operation = _readAbiUint8(input, 100);
    }

    function _decodeModuleTx(bytes memory input) internal pure returns (ModuleTx memory moduleTx) {
        if (
            input.length < 164
                || (_selector(input) != EXEC_TRANSACTION_FROM_MODULE_SELECTOR
                    && _selector(input) != EXEC_TRANSACTION_FROM_MODULE_RETURN_DATA_SELECTOR)
        ) {
            revert SafeTxShapeBatchPayloadMalformed();
        }

        moduleTx.to = _readAbiAddress(input, 4);
        moduleTx.value = _readUint256(input, 36);
        moduleTx.data = _readDynamicBytes(input, 4, _readUint256(input, 68));
        moduleTx.operation = _readAbiUint8(input, 100);
    }

    function _decodeOwnerAction(address safe, bytes memory input) internal pure returns (Action memory action) {
        if (input.length < 388 || _selector(input) != EXEC_TRANSACTION_SELECTOR) {
            revert SafeTxShapeBatchPayloadMalformed();
        }

        _requireNoOwnerGasRefund(input);

        (uint256 dataOffset, uint256 dataLength) = _dynamicBytesBounds(input, 4, _readUint256(input, 68));
        action = Action({
            safe: safe,
            caller: safe,
            module: address(0),
            target: _readAbiAddress(input, 4),
            value: _readUint256(input, 36),
            data: input,
            dataOffset: dataOffset,
            dataLength: dataLength,
            operation: _readAbiUint8(input, 100),
            fromModule: false,
            fromBatch: false
        });
    }

    function _requireNoOwnerGasRefund(bytes memory input) internal pure {
        if (input.length < 388 || _selector(input) != EXEC_TRANSACTION_SELECTOR) {
            revert SafeTxShapeBatchPayloadMalformed();
        }

        // Safe performs a second, protocol-native transfer after the requested action whenever
        // signed gasPrice is nonzero. That recipient/token is outside the action tuple, so this
        // policy explicitly disables refunds instead of silently leaving the transfer free.
        uint256 gasPrice = _readUint256(input, 196);
        if (gasPrice != 0) revert SafeTxShapeGasRefundBlocked(gasPrice);
    }

    function _decodeModuleAction(address safe, address module, bytes memory input)
        internal
        pure
        returns (Action memory action)
    {
        if (
            input.length < 164
                || (_selector(input) != EXEC_TRANSACTION_FROM_MODULE_SELECTOR
                    && _selector(input) != EXEC_TRANSACTION_FROM_MODULE_RETURN_DATA_SELECTOR)
        ) {
            revert SafeTxShapeBatchPayloadMalformed();
        }

        (uint256 dataOffset, uint256 dataLength) = _dynamicBytesBounds(input, 4, _readUint256(input, 68));
        action = Action({
            safe: safe,
            caller: safe,
            module: module,
            target: _readAbiAddress(input, 4),
            value: _readUint256(input, 36),
            data: input,
            dataOffset: dataOffset,
            dataLength: dataLength,
            operation: _readAbiUint8(input, 100),
            fromModule: true,
            fromBatch: false
        });
    }

    function _decodeSingleBytesArgument(
        bytes memory input,
        uint256 inputOffset,
        uint256 inputLength,
        bytes4 expectedSelector
    ) internal pure returns (uint256 argumentOffset, uint256 argumentLength) {
        if (inputOffset > input.length || inputLength > input.length - inputOffset || inputLength < 68) {
            revert SafeTxShapeBatchPayloadMalformed();
        }
        if (_selectorAt(input, inputOffset) != expectedSelector) revert SafeTxShapeBatchPayloadMalformed();

        uint256 offset = _readUint256(input, inputOffset + 4);
        if (offset != 32) revert SafeTxShapeBatchPayloadMalformed();

        uint256 inputEnd = inputOffset + inputLength;
        uint256 lengthOffset = inputOffset + 4 + offset;
        argumentLength = _readUint256(input, lengthOffset);
        argumentOffset = lengthOffset + 32;
        if (argumentOffset > inputEnd) revert SafeTxShapeBatchPayloadMalformed();
        if (argumentLength > inputEnd - argumentOffset) revert SafeTxShapeBatchPayloadMalformed();

        uint256 paddedLength = argumentLength;
        uint256 remainder = argumentLength % 32;
        if (remainder != 0) paddedLength += 32 - remainder;

        uint256 paddedEnd = argumentOffset + paddedLength;
        if (paddedEnd != inputEnd) revert SafeTxShapeBatchPayloadMalformed();
        for (uint256 i = argumentLength; i < paddedLength; ++i) {
            if (input[argumentOffset + i] != 0) revert SafeTxShapeBatchPayloadMalformed();
        }
    }

    function _batchPolicyForAction(address target, bytes memory data, uint256 dataOffset, uint256 dataLength)
        internal
        view
        returns (bool found, uint256 index)
    {
        if (dataLength < 4) return (false, 0);
        return _batchPolicyIndex(target, _selectorAt(data, dataOffset));
    }

    function _isConfiguredBatchCall(address target, bytes memory data, uint256 dataOffset, uint256 dataLength)
        internal
        view
        returns (bool)
    {
        if (dataLength < 4) return false;
        (bool found,) = _batchPolicyIndex(target, _selectorAt(data, dataOffset));
        return found;
    }

    function _targetPolicyIndex(address target) internal view returns (bool found, uint256 index) {
        uint256 indexPlusOne = _targetPolicyIndexPlusOne[target];
        if (indexPlusOne == 0) return (false, 0);
        return (true, indexPlusOne - 1);
    }

    function _selectorPolicyIndex(address target, bytes4 selector) internal view returns (bool found, uint256 index) {
        uint256 indexPlusOne = _selectorPolicyIndexPlusOne[target][selector];
        if (indexPlusOne == 0) return (false, 0);
        return (true, indexPlusOne - 1);
    }

    function _batchPolicyIndex(address executor, bytes4 selector) internal view returns (bool found, uint256 index) {
        uint256 indexPlusOne = _batchPolicyIndexPlusOne[executor][selector];
        if (indexPlusOne == 0) return (false, 0);
        return (true, indexPlusOne - 1);
    }

    function _tokenHasApprovalKind(address token, uint8 kind) internal view returns (bool) {
        return _tokenApprovalKindRegistered[token][kind];
    }

    function _storeTargetPolicies(TargetPolicy[] memory policies) private {
        for (uint256 i; i < policies.length; ++i) {
            if (policies[i].target == address(0)) revert SafeTxShapeInvalidPolicy();
            if (_targetPolicyIndexPlusOne[policies[i].target] != 0) {
                revert SafeTxShapeDuplicateTarget(policies[i].target);
            }

            targetPolicies.push(policies[i]);
            _targetPolicyIndexPlusOne[policies[i].target] = targetPolicies.length;
        }
    }

    function _storeSelectorPolicies(SelectorPolicy[] memory policies) private {
        for (uint256 i; i < policies.length; ++i) {
            if (policies[i].target == address(0) || policies[i].selector == bytes4(0)) {
                revert SafeTxShapeInvalidPolicy();
            }
            if (!_targetPolicyExistsInMemory(policies[i].target)) revert SafeTxShapeInvalidPolicy();
            if (_selectorPolicyIndexPlusOne[policies[i].target][policies[i].selector] != 0) {
                revert SafeTxShapeDuplicateSelector(policies[i].target, policies[i].selector);
            }

            selectorPolicies.push(policies[i]);
            _selectorPolicyIndexPlusOne[policies[i].target][policies[i].selector] = selectorPolicies.length;
        }
    }

    function _storeBatchExecutorPolicies(BatchExecutorPolicy[] memory policies) private {
        for (uint256 i; i < policies.length; ++i) {
            if (
                policies[i].executor == address(0) || policies[i].selector == bytes4(0) || policies[i].maxActions == 0
                    || policies[i].maxActions > MAX_BATCH_ACTIONS || policies[i].allowNested
            ) {
                revert SafeTxShapeInvalidPolicy();
            }
            if (_batchPolicyIndexPlusOne[policies[i].executor][policies[i].selector] != 0) {
                revert SafeTxShapeDuplicateBatchExecutor(policies[i].executor, policies[i].selector);
            }

            batchExecutorPolicies.push(policies[i]);
            _batchPolicyIndexPlusOne[policies[i].executor][policies[i].selector] = batchExecutorPolicies.length;
        }
    }

    function _storeApprovalPolicies(ApprovalPolicy[] memory policies) private {
        for (uint256 i; i < policies.length; ++i) {
            if (
                policies[i].token == address(0) || policies[i].spender == address(0)
                    || !_isSupportedApprovalKind(policies[i].kind)
            ) {
                revert SafeTxShapeInvalidPolicy();
            }

            for (uint256 j; j < i; ++j) {
                if (
                    policies[j].token == policies[i].token && policies[j].spender == policies[i].spender
                        && policies[j].kind == policies[i].kind
                ) {
                    revert SafeTxShapeDuplicateApprovalPolicy(policies[i].token, policies[i].spender, policies[i].kind);
                }

                if (
                    policies[j].token == policies[i].token
                        && ((policies[j].kind == APPROVAL_KIND_ERC20_APPROVE
                                && policies[i].kind == APPROVAL_KIND_ERC721_APPROVE)
                            || (policies[j].kind == APPROVAL_KIND_ERC721_APPROVE
                                && policies[i].kind == APPROVAL_KIND_ERC20_APPROVE))
                ) {
                    revert SafeTxShapeInvalidPolicy();
                }
            }

            approvalPolicies.push(policies[i]);
            _approvalPolicyByKey[policies[i].token][policies[i].spender][policies[i].kind] = policies[i];
            _approvalPolicyExists[policies[i].token][policies[i].spender][policies[i].kind] = true;
            _approvalPolicyIndexPlusOne[policies[i].token][policies[i].spender][policies[i].kind] =
            approvalPolicies.length;
            _tokenApprovalKindRegistered[policies[i].token][policies[i].kind] = true;
        }
    }

    function _storeAllowedModules(address[] memory modules) private {
        for (uint256 i; i < modules.length; ++i) {
            if (modules[i] == address(0)) revert SafeTxShapeInvalidPolicy();
            if (_allowedModule[modules[i]]) revert SafeTxShapeDuplicateModule(modules[i]);

            allowedModules.push(modules[i]);
            _allowedModule[modules[i]] = true;
        }
    }

    function _targetPolicyExistsInMemory(address target) private view returns (bool) {
        return _targetPolicyIndexPlusOne[target] != 0;
    }

    function _isSupportedApprovalKind(uint8 kind) private pure returns (bool) {
        return kind == APPROVAL_KIND_ERC20_APPROVE || kind == APPROVAL_KIND_ERC20_INCREASE_ALLOWANCE
            || kind == APPROVAL_KIND_ERC721_APPROVE || kind == APPROVAL_KIND_ERC721_SET_APPROVAL_FOR_ALL
            || kind == APPROVAL_KIND_ERC1155_SET_APPROVAL_FOR_ALL;
    }

    function _registerReshiramSpec() internal {
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    function _stripSelector(bytes memory input) internal pure returns (bytes memory args) {
        if (input.length < 4) revert SafeTxShapeCalldataTooShort(address(0), input.length);
        args = _slice(input, 4, input.length - 4);
    }

    function _selector(bytes memory input) internal pure returns (bytes4 selector) {
        if (input.length < 4) revert SafeTxShapeCalldataTooShort(address(0), input.length);
        selector = _selectorAt(input, 0);
    }

    function _selectorAt(bytes memory input, uint256 offset) internal pure returns (bytes4 selector) {
        if (offset > input.length || input.length - offset < 4) {
            revert SafeTxShapeCalldataTooShort(address(0), input.length);
        }
        selector = bytes4(
            (uint32(uint8(input[offset])) << 24) | (uint32(uint8(input[offset + 1])) << 16)
                | (uint32(uint8(input[offset + 2])) << 8) | uint32(uint8(input[offset + 3]))
        );
    }

    function _readAbiAddress(bytes memory data, uint256 offset) internal pure returns (address value) {
        value = address(uint160(_readUint256(data, offset)));
    }

    function _readAbiUint8(bytes memory data, uint256 offset) internal pure returns (uint8 value) {
        uint256 raw = _readUint256(data, offset);
        if (raw > type(uint8).max) revert SafeTxShapeBatchPayloadMalformed();
        value = uint8(raw);
    }

    function _readAbiBool(bytes memory data, uint256 offset) internal pure returns (bool value) {
        uint256 raw = _readUint256(data, offset);
        if (raw > 1) revert SafeTxShapeApprovalMalformed(address(0), bytes4(0));
        value = raw == 1;
    }

    function _readDynamicBytes(bytes memory data, uint256 headStart, uint256 relativeOffset)
        internal
        pure
        returns (bytes memory value)
    {
        (uint256 valueOffset, uint256 valueLength) = _dynamicBytesBounds(data, headStart, relativeOffset);
        value = _slice(data, valueOffset, valueLength);
    }

    function _dynamicBytesBounds(bytes memory data, uint256 headStart, uint256 relativeOffset)
        internal
        pure
        returns (uint256 valueOffset, uint256 valueLength)
    {
        if (headStart > data.length || relativeOffset > data.length - headStart) {
            revert SafeTxShapeBatchPayloadMalformed();
        }
        uint256 lengthOffset = headStart + relativeOffset;
        valueLength = _readUint256(data, lengthOffset);
        valueOffset = lengthOffset + 32;
        if (valueOffset > data.length) revert SafeTxShapeBatchPayloadMalformed();
        if (valueLength > data.length - valueOffset) revert SafeTxShapeBatchPayloadMalformed();
    }

    function _readPackedAddress(bytes memory data, uint256 offset) internal pure returns (address value) {
        if (offset > data.length || data.length - offset < 20) revert SafeTxShapeBatchPayloadMalformed();
        uint160 result;
        for (uint256 i; i < 20; ++i) {
            result = (result << 8) | uint160(uint8(data[offset + i]));
        }
        value = address(result);
    }

    function _readUint256(bytes memory data, uint256 offset) internal pure returns (uint256 value) {
        if (offset > data.length || data.length - offset < 32) revert SafeTxShapeBatchPayloadMalformed();
        for (uint256 i; i < 32; ++i) {
            value = (value << 8) | uint256(uint8(data[offset + i]));
        }
    }

    function _slice(bytes memory data, uint256 offset, uint256 length) internal pure returns (bytes memory out) {
        if (offset > data.length || length > data.length - offset) revert SafeTxShapeBatchPayloadMalformed();
        out = new bytes(length);
        for (uint256 i; i < length; ++i) {
            out[i] = data[offset + i];
        }
    }
}

// policy-catalog/sources/policy-assertions.sol

interface IVerifierGateway {
    function routes(bytes4 selector) external view returns (address verifier, bool frozen);
}

/// @title RollingOutflowCircuitBreakerAssertion
/// @notice Reusable rolling outflow protection with configurable soft or hard transaction caps.
/// @dev The adopter is the custody contract. A zero transaction cap creates a hard stop once
///      cumulative outflow crosses the configured threshold and floor.
contract RollingOutflowCircuitBreakerAssertion is Assertion {
    address public immutable TOKEN;
    uint256 public immutable THRESHOLD_BPS;
    uint256 public immutable WINDOW;
    uint256 public immutable FLOOR;
    uint256 public immutable TX_CAP_BPS;

    constructor(address token_, uint256 thresholdBps_, uint256 window_, uint256 floor_, uint256 txCapBps_) {
        require(token_ != address(0), "Outflow breaker: token zero");
        require(thresholdBps_ > 0 && thresholdBps_ < 10_000, "Outflow breaker: threshold");
        require(window_ >= 10 && window_ <= type(uint64).max, "Outflow breaker: window");
        require(txCapBps_ < thresholdBps_, "Outflow breaker: cap");
        TOKEN = token_;
        THRESHOLD_BPS = thresholdBps_;
        WINDOW = window_;
        FLOOR = floor_;
        TX_CAP_BPS = txCapBps_;
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    function triggers() external view override {
        watchCumulativeOutflow(TOKEN, THRESHOLD_BPS, WINDOW, this.assertionOutflowWithinBreaker.selector);
    }

    function assertionOutflowWithinBreaker() external view {
        PhEvm.OutflowContext memory context = ph.outflowContext();
        if (context.cumulativeOutflow < FLOOR) return;

        uint256 grossOutflow;
        PhEvm.Erc20TransferData[] memory transfers = ph.getErc20Transfers(TOKEN, _postTx());
        address adopter = ph.getAssertionAdopter();
        for (uint256 i; i < transfers.length; ++i) {
            if (transfers[i].from == adopter && transfers[i].to != adopter) grossOutflow += transfers[i].value;
        }
        if (grossOutflow == 0) return;
        if (TX_CAP_BPS == 0) revert("Outflow breaker: hard stop");

        uint256 balance = _readBalanceAt(TOKEN, adopter, _preTx());
        if (context.tvlSnapshot != 0 && context.tvlSnapshot < balance) balance = context.tvlSnapshot;
        require(grossOutflow * 10_000 <= balance * TX_CAP_BPS, "Outflow breaker: transaction cap");
    }
}

/// @title TieredOutflowCircuitBreakerAssertion
/// @notice Reusable soft and hard rolling outflow limits, generalized from bridge and vault controls.
contract TieredOutflowCircuitBreakerAssertion is Assertion {
    address public immutable TOKEN;
    uint256 public immutable WINDOW;
    uint256 public immutable SOFT_THRESHOLD_BPS;
    uint256 public immutable HARD_THRESHOLD_BPS;
    uint256 public immutable SOFT_WITHDRAWAL_LIMIT;

    error SoftOutflowLimitExceeded(uint256 outgoing);
    error HardOutflowLimitExceeded(uint256 outgoing);

    constructor(
        address token_,
        uint256 window_,
        uint256 softThresholdBps_,
        uint256 hardThresholdBps_,
        uint256 softWithdrawalLimit_
    ) {
        require(token_ != address(0), "Tiered breaker: token zero");
        require(window_ >= 10 && window_ <= type(uint64).max, "Tiered breaker: window");
        require(softThresholdBps_ > 0 && softThresholdBps_ < hardThresholdBps_, "Tiered breaker: thresholds");
        require(hardThresholdBps_ < 10_000, "Tiered breaker: hard threshold");
        require(softWithdrawalLimit_ > 0, "Tiered breaker: soft limit");
        TOKEN = token_;
        WINDOW = window_;
        SOFT_THRESHOLD_BPS = softThresholdBps_;
        HARD_THRESHOLD_BPS = hardThresholdBps_;
        SOFT_WITHDRAWAL_LIMIT = softWithdrawalLimit_;
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    function triggers() external view override {
        watchCumulativeOutflow(TOKEN, SOFT_THRESHOLD_BPS, WINDOW, this.assertSoftOutflowLimit.selector);
        watchCumulativeOutflow(TOKEN, HARD_THRESHOLD_BPS, WINDOW, this.assertHardOutflowLimit.selector);
    }

    function assertSoftOutflowLimit() external view {
        uint256 outgoing = _grossOutflow();
        if (outgoing >= SOFT_WITHDRAWAL_LIMIT) revert SoftOutflowLimitExceeded(outgoing);
    }

    function assertHardOutflowLimit() external view {
        uint256 outgoing = _grossOutflow();
        if (outgoing != 0) revert HardOutflowLimitExceeded(outgoing);
    }

    function _grossOutflow() internal view returns (uint256 outgoing) {
        address adopter = ph.getAssertionAdopter();
        PhEvm.Erc20TransferData[] memory transfers = ph.getErc20Transfers(TOKEN, _postTx());
        for (uint256 i; i < transfers.length; ++i) {
            if (transfers[i].from == adopter && transfers[i].to != adopter) outgoing += transfers[i].value;
        }
    }
}

/// @title SafeActionPolicyAssertion
/// @notice Constructor-driven Safe transaction-shape policy for owner and module execution.
/// @dev The same contract can serve any Safe role. All target, selector, batch, approval, and
///      module rules are supplied by the policy configuration rather than hard-coded in a subclass.
contract SafeActionPolicyAssertion is SafeTxShapeHelpers {
    address public immutable EXPECTED_SAFE;

    constructor(
        address expectedSafe_,
        TargetPolicy[] memory targetPolicies_,
        SelectorPolicy[] memory selectorPolicies_,
        BatchExecutorPolicy[] memory batchExecutorPolicies_,
        ApprovalPolicy[] memory approvalPolicies_,
        bool moduleExecutionEnabled_,
        address[] memory allowedModules_
    )
        SafeTxShapeHelpers(
            targetPolicies_,
            selectorPolicies_,
            batchExecutorPolicies_,
            approvalPolicies_,
            moduleExecutionEnabled_,
            allowedModules_
        )
    {
        require(expectedSafe_ != address(0), "Safe policy: safe zero");
        EXPECTED_SAFE = expectedSafe_;
    }

    function triggers() external view override {
        registerFnCallTrigger(this.assertAllowedAction.selector, EXEC_TRANSACTION_SELECTOR);
        registerFnCallTrigger(this.assertAllowedAction.selector, EXEC_TRANSACTION_FROM_MODULE_SELECTOR);
        registerFnCallTrigger(this.assertAllowedAction.selector, EXEC_TRANSACTION_FROM_MODULE_RETURN_DATA_SELECTOR);
    }

    function assertAllowedAction() external view {
        Action memory action = _triggeredAction();
        require(action.safe == EXPECTED_SAFE, "Safe policy: unexpected adopter");
        if (action.fromModule) _validateModuleCaller(action.module);
        if (action.operation > OPERATION_DELEGATECALL) revert SafeTxShapeUnknownOperation(action.operation);

        (bool isBatchExecutor, uint256 batchIndex) =
            _batchPolicyForAction(action.target, action.data, action.dataOffset, action.dataLength);
        if (isBatchExecutor) {
            if (action.operation != OPERATION_DELEGATECALL) revert SafeTxShapeDelegateCallBlocked(action.target);
            if (action.value != 0) {
                revert SafeTxShapeNativeValueBlocked(action.target, MULTISEND_SELECTOR, action.value);
            }
            BatchExecutorPolicy storage policy = batchExecutorPolicies[batchIndex];
            _validateMultiSendBatchPolicy(action, policy);
            _validateMultiSendTargetSelectorPolicy(action, policy);
            _validateMultiSendApprovalPolicy(action, policy);
            return;
        }

        if (action.operation == OPERATION_DELEGATECALL) revert SafeTxShapeDelegateCallBlocked(action.target);
        _validateTargetAndSelector(action);
        if (action.dataLength >= 4) _validateApproval(action, _selectorAt(action.data, action.dataOffset));
    }
}

/// @title SafeConfigurationLockAssertion
/// @notice Exact Safe owner, threshold, module, guard, fallback, and singleton lock.
contract SafeConfigurationLockAssertion is SafeConfigLockHelpers {
    bytes32 public immutable OWNER_SET_HASH;
    bytes32 public immutable MODULE_SET_HASH;
    uint256 public immutable OWNER_COUNT;
    uint256 public immutable THRESHOLD;
    address public immutable SINGLETON;
    address public immutable FALLBACK_HANDLER;
    address public immutable GUARD;
    address public immutable MODULE_GUARD;

    constructor(
        address[] memory owners_,
        uint256 threshold_,
        address singleton_,
        address fallbackHandler_,
        address guard_,
        address moduleGuard_,
        address[] memory allowedModules_
    ) {
        require(owners_.length != 0 && threshold_ != 0 && threshold_ <= owners_.length, "Safe lock: owners");
        require(singleton_ != address(0), "Safe lock: singleton");
        OWNER_SET_HASH = hashAddressSet(owners_);
        MODULE_SET_HASH = hashAddressSet(allowedModules_);
        OWNER_COUNT = owners_.length;
        THRESHOLD = threshold_;
        SINGLETON = singleton_;
        FALLBACK_HANDLER = fallbackHandler_;
        GUARD = guard_;
        MODULE_GUARD = moduleGuard_;
        _registerReshiramSpec();
    }

    function triggers() external view override {
        registerStorageChangeTrigger(this.assertionSafeConfigurationUnchanged.selector);
    }

    function assertionSafeConfigurationUnchanged() external view {
        address safe = ph.getAssertionAdopter();
        PhEvm.ForkId memory post = _postTx();
        require(_addressSlotAt(safe, bytes32(0), post) == SINGLETON, "Safe lock: singleton changed");
        address[] memory owners = _ownersAt(safe, post);
        require(owners.length == OWNER_COUNT && hashAddressSet(owners) == OWNER_SET_HASH, "Safe lock: owners changed");
        require(_thresholdAt(safe, post) == THRESHOLD, "Safe lock: threshold changed");
        require(hashAddressSet(_modulesAt(safe, post)) == MODULE_SET_HASH, "Safe lock: modules changed");
        require(_guardAt(safe, post) == GUARD, "Safe lock: guard changed");
        require(_moduleGuardAt(safe, post) == MODULE_GUARD, "Safe lock: module guard changed");
        require(_fallbackHandlerAt(safe, post) == FALLBACK_HANDLER, "Safe lock: fallback changed");
    }
}

/// @title UpgradeGateStateLockAssertion
/// @notice Generalized gatekeeper state lock for Safe-controlled upgrade authorities.
contract UpgradeGateStateLockAssertion is Assertion {
    bytes32 public immutable VERSION_SLOT;
    bytes32 public immutable STATUS_SLOT;
    bytes32 public immutable START_SLOT;
    bytes32 public immutable MANAGED_LENGTH_SLOT;
    bytes32 public immutable MASTER_SLOT;
    uint256 public immutable LOCKED_VERSION_ID;
    bytes4 public immutable TRIGGER_SELECTOR;

    constructor(
        address gatekeeper_,
        uint256 lockedVersionId_,
        bytes32 versionSlot_,
        bytes32 statusSlot_,
        bytes32 startSlot_,
        bytes32 managedLengthSlot_,
        bytes32 masterSlot_,
        bytes4 triggerSelector_
    ) {
        require(gatekeeper_ != address(0) && triggerSelector_ != bytes4(0), "Upgrade lock: config");
        GATEKEEPER = gatekeeper_;
        LOCKED_VERSION_ID = lockedVersionId_;
        VERSION_SLOT = versionSlot_;
        STATUS_SLOT = statusSlot_;
        START_SLOT = startSlot_;
        MANAGED_LENGTH_SLOT = managedLengthSlot_;
        MASTER_SLOT = masterSlot_;
        TRIGGER_SELECTOR = triggerSelector_;
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    address public immutable GATEKEEPER;

    function triggers() external view override {
        registerFnCallTrigger(this.assertUpgradeLocked.selector, TRIGGER_SELECTOR);
    }

    function assertUpgradeLocked() external view {
        PhEvm.ForkId memory pre = _preTx();
        PhEvm.ForkId memory post = _postTx();
        uint256 actualVersion = uint256(ph.loadStateAt(GATEKEEPER, VERSION_SLOT, post));
        require(actualVersion == LOCKED_VERSION_ID, "Upgrade lock: version changed");

        uint256 preStatus = uint256(ph.loadStateAt(GATEKEEPER, STATUS_SLOT, pre));
        uint256 postStatus = uint256(ph.loadStateAt(GATEKEEPER, STATUS_SLOT, post));
        if (postStatus != 0) {
            bool sameUpgrade = postStatus == preStatus
                && ph.loadStateAt(GATEKEEPER, START_SLOT, pre) == ph.loadStateAt(GATEKEEPER, START_SLOT, post);
            require(sameUpgrade, "Upgrade lock: upgrade advanced");
        }

        address master = address(uint160(uint256(ph.loadStateAt(GATEKEEPER, MASTER_SLOT, post))));
        require(master == ph.getAssertionAdopter(), "Upgrade lock: master changed");
        require(
            ph.loadStateAt(GATEKEEPER, MANAGED_LENGTH_SLOT, pre)
                == ph.loadStateAt(GATEKEEPER, MANAGED_LENGTH_SLOT, post),
            "Upgrade lock: managed set changed"
        );
    }
}

/// @title SettlementIntegrityPinAssertion
/// @notice Constructor-driven pin for verifier, program, state-root, and data-availability calls.
contract SettlementIntegrityPinAssertion is Assertion {
    address public immutable ROUTE_VERIFIER;
    bytes32 public immutable VERIFIER_SLOT;
    bytes32 public immutable PROGRAM_SLOT;
    bytes32 public immutable STATE_ROOT_SLOT;
    bytes4 public immutable SUBMIT_BATCH_SELECTOR;
    uint256 public immutable PROOF_OFFSET_WORD;
    bytes4[] public PINNED_CALL_SELECTORS;
    bytes4[] public FORBIDDEN_CALL_SELECTORS;
    uint256 internal constant MAX_CALLS_PER_SELECTOR = 32;
    uint64 internal constant ROUTE_VIEW_GAS = 500_000;

    constructor(
        address routeVerifier_,
        bytes32 verifierSlot_,
        bytes32 programSlot_,
        bytes32 stateRootSlot_,
        bytes4 submitBatchSelector_,
        uint256 proofOffsetWord_,
        bytes4[] memory pinnedCallSelectors_,
        bytes4[] memory forbiddenCallSelectors_
    ) {
        require(submitBatchSelector_ != bytes4(0), "Settlement pin: submit selector");
        ROUTE_VERIFIER = routeVerifier_;
        VERIFIER_SLOT = verifierSlot_;
        PROGRAM_SLOT = programSlot_;
        STATE_ROOT_SLOT = stateRootSlot_;
        SUBMIT_BATCH_SELECTOR = submitBatchSelector_;
        PROOF_OFFSET_WORD = proofOffsetWord_;
        PINNED_CALL_SELECTORS = pinnedCallSelectors_;
        FORBIDDEN_CALL_SELECTORS = forbiddenCallSelectors_;
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    function triggers() external view override {
        registerTxEndTrigger(this.assertProofSystemPinned.selector);
        registerTxEndTrigger(this.assertStateRootPinned.selector);
        registerTxEndTrigger(this.assertDataAvailabilityPinned.selector);
    }

    function assertProofSystemPinned() external view {
        address app = ph.getAssertionAdopter();
        require(
            ph.loadStateAt(app, VERIFIER_SLOT, _postTx()) == ph.loadStateAt(app, VERIFIER_SLOT, _preTx()),
            "Settlement pin: verifier changed"
        );
        require(
            ph.loadStateAt(app, PROGRAM_SLOT, _postTx()) == ph.loadStateAt(app, PROGRAM_SLOT, _preTx()),
            "Settlement pin: program changed"
        );
        for (uint256 i; i < PINNED_CALL_SELECTORS.length; ++i) {
            _requireSlotsUnchangedAcross(PINNED_CALL_SELECTORS[i]);
        }
        if (ROUTE_VERIFIER == address(0)) return;

        PhEvm.TriggerCall[] memory batches = _callsTo(SUBMIT_BATCH_SELECTOR);
        for (uint256 i; i < batches.length; ++i) {
            PhEvm.ForkId memory pre = _preCall(batches[i].callId);
            address gateway = address(uint160(uint256(ph.loadStateAt(app, VERIFIER_SLOT, pre))));
            PhEvm.StaticCallResult memory route = ph.staticcallAt(
                gateway,
                abi.encodeCall(IVerifierGateway.routes, (_proofSelector(_args(batches[i])))),
                ROUTE_VIEW_GAS,
                pre
            );
            require(route.ok, "Settlement pin: route lookup failed");
            (address verifier, bool frozen) = abi.decode(route.data, (address, bool));
            require(verifier == ROUTE_VERIFIER && !frozen, "Settlement pin: route changed");
        }
    }

    function assertStateRootPinned() external view {
        require(
            ph.loadStateAt(ph.getAssertionAdopter(), STATE_ROOT_SLOT, _postTx())
                == ph.loadStateAt(ph.getAssertionAdopter(), STATE_ROOT_SLOT, _preTx()),
            "Settlement pin: root changed"
        );
    }

    function assertDataAvailabilityPinned() external view {
        for (uint256 i; i < FORBIDDEN_CALL_SELECTORS.length; ++i) {
            PhEvm.CallFilter memory filter = PhEvm.CallFilter({
                callType: 1, minDepth: 0, maxDepth: type(uint32).max, topLevelOnly: false, successOnly: true
            });
            PhEvm.TriggerCall[] memory calls =
                ph.matchingCalls(ph.getAssertionAdopter(), FORBIDDEN_CALL_SELECTORS[i], filter, 1);
            require(calls.length == 0, "Settlement pin: forbidden call");
        }
    }

    function pinnedCallSelectorCount() external view returns (uint256) {
        return PINNED_CALL_SELECTORS.length;
    }

    function _callsTo(bytes4 selector) internal view returns (PhEvm.TriggerCall[] memory calls) {
        PhEvm.CallFilter memory filter = PhEvm.CallFilter({
            callType: 1, minDepth: 0, maxDepth: type(uint32).max, topLevelOnly: false, successOnly: true
        });
        calls = ph.matchingCalls(ph.getAssertionAdopter(), selector, filter, MAX_CALLS_PER_SELECTOR + 1);
        require(calls.length <= MAX_CALLS_PER_SELECTOR, "Settlement pin: too many calls");
    }

    function _args(PhEvm.TriggerCall memory call) internal view returns (bytes memory args) {
        if (call.input.length > 0) return call.input;
        bytes memory raw = ph.callinputAt(call.callId);
        if (raw.length <= 4) return new bytes(0);
        args = new bytes(raw.length - 4);
        for (uint256 i; i < args.length; ++i) {
            args[i] = raw[i + 4];
        }
    }

    function _requireSlotsUnchangedAcross(bytes4 selector) internal view {
        address app = ph.getAssertionAdopter();
        PhEvm.TriggerCall[] memory calls = _callsTo(selector);
        for (uint256 i; i < calls.length; ++i) {
            require(
                ph.loadStateAt(app, VERIFIER_SLOT, _postCall(calls[i].callId))
                    == ph.loadStateAt(app, VERIFIER_SLOT, _preCall(calls[i].callId)),
                "Settlement pin: verifier changed"
            );
            require(
                ph.loadStateAt(app, PROGRAM_SLOT, _postCall(calls[i].callId))
                    == ph.loadStateAt(app, PROGRAM_SLOT, _preCall(calls[i].callId)),
                "Settlement pin: program changed"
            );
        }
    }

    function _proofSelector(bytes memory args) internal view returns (bytes4 selector) {
        require(args.length >= (PROOF_OFFSET_WORD + 1) * 32, "Settlement pin: malformed proof");
        uint256 offset = uint256(_word(args, PROOF_OFFSET_WORD));
        require(offset + 36 <= args.length, "Settlement pin: malformed proof");
        bytes32 head;
        assembly {
            head := mload(add(add(args, 32), offset))
        }
        // The proof selector occupies the first four bytes of the ABI word.
        // forge-lint: disable-next-line(unsafe-typecast)
        selector = bytes4(head);
    }

    function _word(bytes memory data, uint256 index) internal pure returns (bytes32 value) {
        assembly {
            value := mload(add(add(data, 32), mul(index, 32)))
        }
    }
}
