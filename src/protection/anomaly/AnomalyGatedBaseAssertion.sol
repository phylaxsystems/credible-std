// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "../../Assertion.sol";
import {AssertionSpec} from "../../SpecRecorder.sol";
import {PhEvm} from "../../PhEvm.sol";

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
}

/// @title AnomalyGatedBaseAssertion
/// @author Phylax Systems
/// @notice Base contract for anomaly-gated assertions.
/// @dev The anomaly model is a recall-first trigger: it scores each transaction touching a watched
///      contract for the probability that it is anomalous. It over-fires by design, so it is not a
///      blocking signal on its own. An anomaly-gated assertion fires on the score, then requires a
///      deterministic damage check to confirm before it reverts.
///
///      Over the anomaly bit `a = score >= anomalyThresholdBps` and the enabled damage set `H`, a
///      transaction's disposition is:
///
///      | | H confirms | H silent |
///      | --- | --- | --- |
///      | **a** | block (revert) | alert (the exclusive set) |
///      | **not a** | pass (the benign whale) | pass (normal traffic) |
///
///      `block = a AND H`, `alert = a AND NOT H`, `pass = NOT a`. The assertion implements this in
///      control flow: the gate returns early on `NOT a` (pass), the corroboration reverts on
///      `a AND H` (block), and the fall-through with no revert is `a AND NOT H` (the alert cell, read
///      off-chain from the executor seeing a score and no invalidation). The alert cell does not
///      revert, so a benign-but-unusual transaction is not blocked on the model score alone.
///
///      This base holds the target, the operating threshold, and the corroboration primitives the
///      heuristic mixins and the composite share. Inherit it through a mixin or the composite, then
///      implement `triggers()`.
///
/// Example, an anomaly-gated drain check with one heuristic:
/// ```solidity
/// contract MyDrainGuard is AnomalyGatedOutflowAssertion {
///     constructor(address pool, address reserveToken)
///         AnomalyGatedBaseAssertion(pool, 205)          // 205 bps == a 2% probability
///         AnomalyGatedOutflowAssertion(pool, reserveToken, 250) // drain >= 2.5% of the reserve
///     {}
///
///     function triggers() external view override {
///         _registerOutflowTrigger();
///     }
///
/// }
/// ```
abstract contract AnomalyGatedBaseAssertion is Assertion {
    /// @notice Constructor guard: an enabled heuristic is missing a parameter it needs, whether a
    ///         zero custody, token, vault, or oracle address, an oracle query too short to hold a
    ///         selector, or a zero drain fraction, which corroborates on any transaction while
    ///         custody holds a balance. The constructor rejects these instead of shipping a
    ///         silently inert leg or a per-transaction false block.
    error HeuristicMisconfigured();
    /// @notice Constructor guard: the watched target is the zero address. `anomalyContext` can
    ///         never score it, so the gate would never open and the assertion would be permanently
    ///         inert.
    error ZeroTarget();
    /// @notice Constructor guard: the operating threshold must be in `[1, 10_000]`. At zero the
    ///         gate is satisfied by the zero-filled context of an unscored target, turning the
    ///         damage heuristics into ungated blockers; above 10_000 the gate is unreachable
    ///         (`scoreBps` caps at 10_000) and the assertion permanently inert.
    error ThresholdOutOfRange();

    /// @notice EIP-1967 implementation slot, `keccak256("eip1967.proxy.implementation") - 1`.
    bytes32 internal constant EIP1967_IMPLEMENTATION =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    /// @notice EIP-1967 admin slot, `keccak256("eip1967.proxy.admin") - 1`.
    bytes32 internal constant EIP1967_ADMIN = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    /// @notice The watched contract whose anomaly score gates this assertion (the adopter).
    address internal immutable target;

    /// @notice Scores at or above this (out of 10_000) are treated as anomalous. On the Aave family
    ///         the calibrated operating point for a 1% false-positive budget is 205, a 2% probability.
    uint16 internal immutable anomalyThresholdBps;

    /// @param _target The watched contract the model scores. Must be non-zero.
    /// @param _anomalyThresholdBps The operating point, in bps of anomaly probability. Must be in
    ///        `[1, 10_000]`.
    constructor(address _target, uint16 _anomalyThresholdBps) {
        if (_target == address(0)) {
            revert ZeroTarget();
        }
        if (_anomalyThresholdBps == 0 || _anomalyThresholdBps > 10_000) {
            revert ThresholdOutOfRange();
        }
        registerAssertionSpec(AssertionSpec.Reshiram);
        target = _target;
        anomalyThresholdBps = _anomalyThresholdBps;
    }

    // ---------------------------------------------------------------
    //  The anomaly gate
    // ---------------------------------------------------------------

    /// @notice Whether the model scored this transaction at or above the operating threshold.
    /// @dev `ph.anomalyContext` fails open: an unscored target reads 0, so a contract with no model
    ///      (too new to have history) does not gate true and the assertion stays inert; the
    ///      constructor's `[1, 10_000]` threshold range guarantees this. Virtual so an adopter can
    ///      override the gate, e.g. a per-function threshold or a second signal.
    function _anomalous() internal view virtual returns (bool) {
        return ph.anomalyContext(target).scoreBps >= anomalyThresholdBps;
    }

    /// @notice Register the anomaly trigger for `selector`.
    /// @dev Fires `selector` whenever the AnomalySubsystem produces a score for `target`. Call this
    ///      inside your `triggers()`.
    function _registerAnomalyTrigger(bytes4 selector) internal view {
        watchAnomaly(target, selector);
    }

    // ---------------------------------------------------------------
    //  Corroboration primitives (the damage set H)
    // ---------------------------------------------------------------

    /// @notice Whether `token` left `outflowTarget` this transaction by at least `fracBps` of its
    ///         pre-transaction balance. `outflowTarget` may differ from `target`: the anomaly focal
    ///         is often a pool while the drained reserve sits in a separate aToken.
    /// @dev Net outflow from the reduced ERC-20 balance deltas over the post-transaction fork, scaled
    ///      by the balance read at the pre-transaction fork. A zero pre-balance corroborates nothing.
    function _drains(address outflowTarget, address token, uint256 fracBps) internal view returns (bool) {
        uint256 preBalance = _balanceAt(token, outflowTarget, _preTx());
        if (preBalance == 0) {
            return false;
        }
        PhEvm.Erc20TransferData[] memory deltas = ph.reduceErc20BalanceDeltas(token, _postTx());
        uint256 outflow;
        uint256 inflow;
        for (uint256 i; i < deltas.length; ++i) {
            if (deltas[i].from == outflowTarget) {
                outflow += deltas[i].value;
            }
            if (deltas[i].to == outflowTarget) {
                inflow += deltas[i].value;
            }
        }
        uint256 net = outflow > inflow ? outflow - inflow : 0;
        return net * 10_000 / preBalance >= fracBps;
    }

    /// @notice Whether an EIP-1967 implementation or admin slot, or the supplied `ownerSlot` when
    ///         non-zero, changed on `watched` across the transaction. A zero `watched` reads
    ///         `target`: the rewritten proxy is usually the anomaly focal, but a custody contract
    ///         behind its own proxy (an aToken) can be named instead.
    /// @dev `bytes32(0)` disables the owner-slot leg, so an owner stored at slot 0 cannot be
    ///      watched through `ownerSlot`; the EIP-1967 slots are always watched.
    function _upgraded(address watched, bytes32 ownerSlot) internal view returns (bool) {
        address account = watched == address(0) ? target : watched;
        if (_slotChanged(account, EIP1967_IMPLEMENTATION) || _slotChanged(account, EIP1967_ADMIN)) {
            return true;
        }
        return ownerSlot != bytes32(0) && _slotChanged(account, ownerSlot);
    }

    /// @notice Whether the ERC-4626 share price of `vault` moved beyond `toleranceBps` across the
    ///         transaction. An empty vault (zero supply) is skipped by the precompile.
    function _accountingBroke(address vault, uint256 toleranceBps) internal view returns (bool) {
        return !ph.assetsMatchSharePriceAt(vault, toleranceBps, _preTx(), _postTx());
    }

    /// @notice Whether the oracle answer returned by `query` on `oracleTarget` moved beyond
    ///         `toleranceBps` across the transaction. Non-view: the oracle read executes.
    /// @dev `query` is the full ABI-encoded call: a zero-argument reader is
    ///      `abi.encodeWithSignature("latestAnswer()")`; an asset-priced feed is
    ///      `abi.encodeWithSignature("getAssetPrice(address)", asset)`.
    function _oracleDeviated(address oracleTarget, bytes memory query, uint256 toleranceBps) internal returns (bool) {
        return !ph.oracleSanityAt(oracleTarget, query, toleranceBps, _preTx(), _postTx());
    }

    /// @dev Whether `slot` on `account` differs between the pre- and post-transaction forks.
    function _slotChanged(address account, bytes32 slot) internal view returns (bool) {
        return ph.loadStateAt(account, slot, _preTx()) != ph.loadStateAt(account, slot, _postTx());
    }

    /// @dev `token.balanceOf(account)` read at `fork`; a failed probe reads 0. The length check
    ///      keeps a codeless `token` (whose staticcall succeeds with empty returndata) on the
    ///      reads-0 path instead of reverting in `abi.decode`.
    function _balanceAt(address token, address account, PhEvm.ForkId memory fork) internal view returns (uint256) {
        PhEvm.StaticCallResult memory result =
            ph.staticcallAt(token, abi.encodeCall(IERC20.balanceOf, (account)), 50_000, fork);
        return result.ok && result.data.length == 32 ? abi.decode(result.data, (uint256)) : 0;
    }
}
