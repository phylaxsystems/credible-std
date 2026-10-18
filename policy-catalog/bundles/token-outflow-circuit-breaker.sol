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

// policy-catalog/policies/token-outflow-circuit-breaker/policy.sol

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
