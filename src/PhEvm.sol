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

    /// @notice Fork to the state before the assertion-triggering transaction
    /// @dev Allows inspection of pre-transaction state for comparison
    function forkPreTx() external;

    /// @notice Fork to the state after the assertion-triggering transaction
    /// @dev Allows inspection of post-transaction state for validation
    function forkPostTx() external;

    /// @notice Fork to the state before a specific call execution
    /// @dev Useful for inspecting state at specific points during transaction execution
    /// @param id The call identifier from CallInputs.id
    function forkPreCall(uint256 id) external;

    /// @notice Fork to the state after a specific call execution
    /// @dev Useful for inspecting state changes from specific calls
    /// @param id The call identifier from CallInputs.id
    function forkPostCall(uint256 id) external;

    /// @notice Load a storage slot value from any address
    /// @param target The address to read storage from
    /// @param slot The storage slot to read
    /// @return data The value stored at the slot
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
}
