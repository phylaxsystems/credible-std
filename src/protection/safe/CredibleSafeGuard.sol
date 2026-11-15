// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ICredibleRegistry} from "./ICredibleRegistry.sol";
import {InitialProtocolManager} from "../credible_block/InitialProtocolManager.sol";

/// @notice Minimal subset of Safe's `Enum` library, vendored so the guard does not
///         depend on the Safe contracts package.
library Enum {
    enum Operation {
        Call,
        DelegateCall
    }
}

/// @notice ERC-165 interface (EIP-165 / OpenZeppelin `IERC165`).
interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

/// @notice Safe transaction guard interface, identical to Safe's `Guard` (v1.3.0/v1.4.1)
///         and `ITransactionGuard` (v1.5.0).
/// @dev `type(ITransactionGuard).interfaceId == 0xe6d7a83a`, the same value Safe's
///      `GuardManager.setGuard` checks via ERC-165 (error `GS300` otherwise), so a
///      {CredibleSafeGuard} can be installed on any Safe that supports transaction guards.
interface ITransactionGuard is IERC165 {
    /// @notice Called by the Safe before executing an owner-authorized transaction.
    /// @dev Reverting here blocks the Safe transaction from executing.
    function checkTransaction(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address payable refundReceiver,
        bytes memory signatures,
        address msgSender
    ) external;

    /// @notice Called by the Safe after executing the transaction.
    function checkAfterExecution(bytes32 hash, bool success) external;
}

/// @title CredibleSafeGuard
/// @author Phylax Systems
/// @notice Safe transaction guard that only allows owner/multisig Safe transactions while the
///         current block is credible, i.e. built by a Credible Layer builder that enforces
///         assertions. When the credible builder set or registry is unavailable the guard fails
///         open for ordinary calls, including owner recovery. Owner-only restrictions never fail open.
/// @dev Installed on a Safe via `setGuard(address(thisGuard))`. The Safe calls
///      {checkTransaction} before every owner-path execution; a revert blocks that execution.
///
///      Scope. This guard implements only Safe's transaction-guard interface ({ITransactionGuard}),
///      so it gates the owner/multisig `execTransaction` path only. Module executions
///      (`execTransactionFromModule`/`...ReturnData`) do not run transaction guards, so an enabled
///      module can still execute while the current block is not credible. Install only on fresh
///      or independently proven-clean Safes with no authorized modules and no self fallback
///      handler. An empty enumerated module list does NOT rule out orphan mapping entries.
///      The guard prevents new module authorization by rejecting enableModule self-calls and
///      delegatecalls except configured owner signMessage(bytes) calls (never MultiSend or modules).
///      Signing targets must be reviewed immutable libraries, not proxies or arbitrary writers.
///      It also rejects self fallback handlers
///      consistently with newer Safe releases. Module support is disabled on all versions.
///      Removing/replacing the guard ends these guarantees.
///
///      Decision in {checkTransaction}:
///      0. Reject unapproved delegatecalls, module enablement, and self fallback handlers, even during fail-open.
///      1. If a required registry read reverts or returns malformed data, FAIL OPEN and allow the
///         remaining transaction. This prevents an unavailable registry from locking owner recovery.
///      2. If the current block is credible, the remaining transaction is allowed.
///      3. Otherwise, if the credible builder set looks offline (the most recent credible block
///         is more than `failOpenBlockThreshold` blocks behind the current block), FAIL OPEN and
///         allow the transaction. This prevents a stalled builder set from permanently locking
///         the Safe. A `lastCredibleBlock` reported beyond the current block is impossible for a
///         sound registry, so it is treated as a broken read and also fails open (see
///         {_failOpenActive}) rather than blocking every transaction until that height is reached.
///      4. Otherwise the builder set is live and the current block is not credible, so the
///         transaction is blocked with {NonCredibleBlock}.
///
///      Fail-open on registry failure (intentional, signed-off product decision).
///      Every registry probe is a bounded staticcall (see {_tryIsCredibleBlock} /
///      {_tryLastCredibleBlock}). The guard treats the registry as UNAVAILABLE and FAILS OPEN,
///      allowing the owner transaction, whenever a probe:
///        - reverts, or
///        - hits an address with no deployed code, or
///        - returns malformed data (a non-canonical boolean, or fewer/more than exactly 32 bytes,
///          so an over-long "returndata bomb" cannot be trusted or copied unbounded), or
///        - exceeds the {REGISTRY_READ_GAS_LIMIT} (50k) gas budget and runs out of gas.
///      Rationale: this guard must NEVER permanently brick the Safe's owner-transaction path
///      because of an unavailable, broken, or misconfigured registry. Registry unavailability
///      therefore degrades to "no credibility protection" rather than a frozen Safe. This is a
///      deliberate, reviewed decision, not an accidental side effect of the bounded-call
///      hardening.
///      Security tradeoff (stated plainly): a broken, absent, or malicious registry that fails
///      any of the above ways lets ordinary calls through without credibility checks. The mitigation is at
///      DEPLOY TIME, not runtime: the deployment script's `validateRegistry` step rejects a
///      codeless / EOA registry address and verifies that both `isCredibleBlock` and
///      `lastCredibleBlock` return well-formed data before broadcasting, so a guard is never
///      deployed already pointed at a permanently-fail-open registry. The registry address is
///      immutable, so this deploy-time check is the enforcement point for a sound registry.
///
///      Fail-open window. The product requirement is "fail open after ~15 minutes with no
///      credible blocks". The {ICredibleRegistry} records credibility by block number and does
///      not expose timestamps, so the window is expressed as a block count that the credible
///      builder set would produce in ~15 minutes on the target chain, e.g.:
///        - ~12s blocks (Ethereum mainnet): 15 min  ~= 75 blocks
///        - ~2s blocks  (typical L2):       15 min  ~= 450 blocks
///        - ~1s blocks:                     15 min  ~= 900 blocks
///      Both the registry address and the fail-open threshold are immutable; re-pointing or
///      re-tuning means deploying a new guard and calling `setGuard` again.
///
///      Onboarding. The guard also implements {IInitialProtocolManager} (via {InitialProtocolManager}),
///      exposing the address allowed to manage this deployment's assertions in the Credible Layer.
///      The state oracle reads it when the protocol is initialized, so deploying the guard is itself
///      the ownership proof — no separate manual review round.
contract CredibleSafeGuard is ITransactionGuard, InitialProtocolManager {
    /// @dev Bounds the gas and returndata exposure of each registry probe. A registry that cannot
    ///      answer within this budget is treated as unavailable and the guard fails open.
    uint256 internal constant REGISTRY_READ_GAS_LIMIT = 50_000;

    /// @notice The on-chain Credible Registry queried for block credibility.
    ICredibleRegistry public immutable credibleRegistry;

    /// @notice Number of blocks the most recent credible block may lag the current block before
    ///         the guard fails open. Should approximate the chain's 15-minute block budget.
    uint256 public immutable failOpenBlockThreshold;

    /// @notice Runtime hashes of reviewed, immutable, non-proxy owner-signing libraries.
    /// @dev No setters. A listed address permits only signMessage(bytes), not arbitrary delegatecalls.
    mapping(address => bytes32) public ownerSigningLibraryCodeHashes;

    /// @notice Thrown when the current block is not credible and the builder set is live.
    error NonCredibleBlock();
    /// @notice The delegatecall is not an approved owner-signing call.
    error DelegateCallBlocked();
    error InvalidOwnerSigningLibrary(address libraryAddress);
    /// @notice New module authorization is incompatible with owner-only protection.
    error ModuleEnableBlocked();
    /// @notice Self fallback handlers are unsupported, matching newer Safe versions.
    error SelfFallbackHandlerBlocked();
    /// @notice Thrown when constructed with the zero address as the registry.
    error ZeroCredibleRegistryAddress();
    /// @notice Thrown when constructed with a zero fail-open threshold.
    error ZeroFailOpenBlockThreshold();

    /// @param credibleRegistry_ The Credible Registry address (configurable per deployment).
    /// @param failOpenBlockThreshold_ Blocks of builder silence tolerated before failing open.
    /// @param initialProtocolManager_ Address allowed to manage this deployment's assertions in the
    ///        Credible Layer, exposed via {initialProtocolManager}. Must be non-zero.
    /// @param ownerSigningLibraries_ Reviewed immutable signing libraries; empty disables all delegatecalls.
    constructor(
        ICredibleRegistry credibleRegistry_,
        uint256 failOpenBlockThreshold_,
        address initialProtocolManager_,
        address[] memory ownerSigningLibraries_
    ) InitialProtocolManager(initialProtocolManager_) {
        if (address(credibleRegistry_) == address(0)) {
            revert ZeroCredibleRegistryAddress();
        }
        if (failOpenBlockThreshold_ == 0) revert ZeroFailOpenBlockThreshold();

        credibleRegistry = credibleRegistry_;
        failOpenBlockThreshold = failOpenBlockThreshold_;
        for (uint256 i; i < ownerSigningLibraries_.length; ++i) {
            address libraryAddress = ownerSigningLibraries_[i];
            if (libraryAddress.code.length == 0 || ownerSigningLibraryCodeHashes[libraryAddress] != bytes32(0)) {
                revert InvalidOwnerSigningLibrary(libraryAddress);
            }
            ownerSigningLibraryCodeHashes[libraryAddress] = libraryAddress.codehash;
        }
    }

    /// @inheritdoc ITransactionGuard
    /// @dev Owner-only restrictions precede the credibility gate and have no fail-open exception.
    ///      `msg.sender` is the Safe; the final ABI argument is the transaction submitter, not the Safe.
    function checkTransaction(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation,
        uint256,
        uint256,
        uint256,
        address,
        address payable,
        bytes memory,
        address
    ) external view override {
        if (operation == Enum.Operation.DelegateCall && !_isOwnerSigningCall(to, value, data)) {
            revert DelegateCallBlocked();
        }
        if (to == msg.sender && data.length >= 4) {
            bytes4 selector;
            assembly ("memory-safe") {
                selector := mload(add(data, 0x20))
            }
            if (selector == bytes4(keccak256("enableModule(address)"))) revert ModuleEnableBlocked();
            if (selector == bytes4(keccak256("setFallbackHandler(address)")) && data.length >= 36) {
                uint256 handler;
                assembly ("memory-safe") {
                    handler := mload(add(data, 0x24))
                }
                if (address(uint160(handler)) == msg.sender) revert SelfFallbackHandlerBlocked();
            }
        }
        _checkCredibleBlock();
    }

    /// @dev This hook is reached only for owner-authorized Safe transactions. Modules do not
    ///      inherit this exception. Code-hash pinning detects changed runtime, not proxy upgrades:
    ///      operators must review the target as an immutable, non-proxy signing library.
    function _isOwnerSigningCall(address to, uint256 value, bytes memory data) internal view returns (bool) {
        bytes32 expectedHash = ownerSigningLibraryCodeHashes[to];
        if (value != 0 || expectedHash == bytes32(0) || to.codehash != expectedHash || data.length < 68) return false;
        if (bytes4(data) != bytes4(keccak256("signMessage(bytes)"))) return false;
        uint256 offset;
        uint256 length;
        assembly ("memory-safe") {
            offset := mload(add(data, 0x24))
            length := mload(add(data, 0x44))
        }
        uint256 available = data.length - 68;
        if (offset != 32 || length > available || available % 32 != 0 || available - length >= 32) return false;
        // Canonical ABI includes exactly the padded bytes payload, with zero padding.
        for (uint256 i = 68 + length; i < data.length; ++i) {
            if (data[i] != 0) return false;
        }
        return true;
    }

    /// @inheritdoc ITransactionGuard
    /// @dev No post-execution checks are performed.
    function checkAfterExecution(bytes32, bool) external pure override {}

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(ITransactionGuard).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    /// @notice Whether the credibility gate currently permits ordinary owner calls.
    /// @dev Does not evaluate the independent owner-only restrictions in {checkTransaction}.
    /// @return True if the block is credible, the builder set is offline, or a required registry
    ///         read is unavailable or malformed.
    function isCurrentBlockAllowed() external view returns (bool) {
        (bool readable, bool credible) = _tryIsCredibleBlock(block.number);
        return !readable || credible || _failOpenActive();
    }

    /// @notice Whether a registry failure or builder outage currently activates fail-open.
    /// @return True if a required registry read is unavailable or malformed, or the latest credible
    ///         block is too old.
    function failOpenActive() external view returns (bool) {
        (bool readable,) = _tryIsCredibleBlock(block.number);
        return !readable || _failOpenActive();
    }

    /// @dev Core gate: allow credible blocks, otherwise fail open when a required registry read
    ///      fails or the builder set is offline. The credibility check runs first so the expected
    ///      hot path (credible block, live builder set) costs a single registry call.
    ///
    ///      The `!readable` disjunct is the intentional, signed-off fail-open-on-registry-failure
    ///      decision (see the contract-level NatSpec): when the bounded probe cannot get a
    ///      well-formed answer within its gas/returndata budget the transaction is ALLOWED rather
    ///      than blocked, so an unavailable/broken/misconfigured registry can never permanently
    ///      brick the Safe's owner path. Security tradeoff: such a registry lets all owner
    ///      transactions through; this is mitigated at deploy time by the deployment script's
    ///      `validateRegistry` check, not here. Only reachable if the builder set is live and the
    ///      current block is genuinely not credible do we `revert NonCredibleBlock()`.
    function _checkCredibleBlock() internal view {
        (bool readable, bool credible) = _tryIsCredibleBlock(block.number);
        if (!readable || credible || _failOpenActive()) return;
        revert NonCredibleBlock();
    }

    /// @dev Fail-open is active when the last-block read fails, the registry reports a last credible
    ///      block beyond the current block, or the current block is strictly more than
    ///      `failOpenBlockThreshold` blocks ahead of the last credible block.
    ///
    ///      A `lastCredibleBlock_ > block.number` reading is impossible for a sound registry (the
    ///      registry defines this value as the highest block marked credible so far, which cannot
    ///      exceed the chain head), so it is treated as an unreadable/broken response and fails open.
    ///      Otherwise a broken registry reporting a far-future height with the current block not
    ///      credible would keep fail-open disabled and revert every owner transaction until the chain
    ///      reached that height — effectively bricking the Safe, the exact outcome this guard must
    ///      never produce on registry failure. Rejecting the future height also removes the
    ///      subtraction underflow it would otherwise cause.
    function _failOpenActive() internal view returns (bool) {
        (bool readable, uint256 lastCredibleBlock_) = _tryLastCredibleBlock();
        if (!readable || lastCredibleBlock_ > block.number) return true;
        return block.number - lastCredibleBlock_ > failOpenBlockThreshold;
    }

    /// @dev Probes `isCredibleBlock` without allowing a revert, malformed boolean, or returndata
    ///      bomb from the registry to bubble into the Safe transaction. Returns `readable == false`
    ///      (the intentional fail-open signal, see {_checkCredibleBlock}) when the staticcall
    ///      reverts, the registry has no code, the call exceeds {REGISTRY_READ_GAS_LIMIT} and runs
    ///      out of gas, the returndata is not exactly 32 bytes (rejecting an over-long returndata
    ///      bomb while copying at most one word), or the word is a non-canonical boolean (> 1).
    function _tryIsCredibleBlock(uint256 blockNumber) internal view returns (bool readable, bool credible) {
        address registry = address(credibleRegistry);
        uint256 selector = uint32(ICredibleRegistry.isCredibleBlock.selector);
        uint256 value;

        assembly ("memory-safe") {
            mstore(0x00, shl(224, selector))
            mstore(0x04, blockNumber)
            readable := staticcall(REGISTRY_READ_GAS_LIMIT, registry, 0x00, 0x24, 0x00, 0x20)
            readable := and(readable, eq(returndatasize(), 0x20))
            value := mload(0x00)
        }

        if (!readable || value > 1) return (false, false);
        return (true, value == 1);
    }

    /// @dev Probes `lastCredibleBlock` while copying at most one word of returndata. Returns
    ///      `readable == false` on the same failure set as {_tryIsCredibleBlock} (revert, no code,
    ///      >50k gas / OOG, or returndata not exactly 32 bytes); {_failOpenActive} maps that to
    ///      fail-open, consistent with the intentional signed-off registry-failure policy.
    function _tryLastCredibleBlock() internal view returns (bool readable, uint256 lastCredibleBlock_) {
        address registry = address(credibleRegistry);
        uint256 selector = uint32(ICredibleRegistry.lastCredibleBlock.selector);

        assembly ("memory-safe") {
            mstore(0x00, shl(224, selector))
            readable := staticcall(REGISTRY_READ_GAS_LIMIT, registry, 0x00, 0x04, 0x00, 0x20)
            readable := and(readable, eq(returndatasize(), 0x20))
            lastCredibleBlock_ := mload(0x00)
        }
    }
}
