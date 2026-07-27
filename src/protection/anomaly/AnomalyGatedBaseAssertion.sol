// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "../../Assertion.sol";
import {AssertionSpec} from "../../SpecRecorder.sol";
import {PhEvm} from "../../PhEvm.sol";
import {Sensitivity} from "../../Sensitivity.sol";

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
///      Over the anomaly bit `a = the score cleared this assertion's sensitivity level` and the
///      enabled damage set `H`, a transaction's disposition is:
///
///      | | H confirms | H silent |
///      | --- | --- | --- |
///      | **a** | block (revert) | alert (the exclusive set) |
///      | **not a** | pass (the benign whale) | pass (normal traffic) |
///
///      `block = a AND H`, `alert = a AND NOT H`, `pass = NOT a`. The trigger and the body split
///      this between them: `NOT a` never reaches the assertion, because the trigger fires only when
///      the score clears the level, so the whole bottom row costs no execution. Inside the body,
///      the corroboration reverts on `a AND H` (block), and the fall-through with no revert is
///      `a AND NOT H` (the alert cell, read off-chain from the executor seeing a score and no
///      invalidation). The alert cell does not revert, so a benign-but-unusual transaction is
///      never blocked on the model score alone.
///
///      A body therefore checks damage and nothing else. The level comparison happens where the
///      model's ladder lives, so the body has no score to re-read.
///
///      This base holds the target, the sensitivity level, and the corroboration primitives the
///      heuristic mixins and the composite share. Inherit it through a mixin or the composite, then
///      implement `triggers()`.
///
/// Example, an anomaly-gated drain check with one heuristic:
/// ```solidity
/// contract MyDrainGuard is AnomalyGatedOutflowAssertion {
///     constructor(address pool, address reserveToken)
///         AnomalyGatedBaseAssertion(pool, Sensitivity.RECOMMENDED)
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
    ///         selector, or a drain fraction outside `[1, 10_000]`. A zero fraction corroborates on
    ///         any transaction while custody holds a balance; above 10_000 the leg can never
    ///         corroborate because net outflow is capped by the pre-transaction balance. The
    ///         constructor rejects these instead of shipping a silently inert leg or a
    ///         per-transaction false block.
    error HeuristicMisconfigured();
    /// @notice Constructor guard: the watched target is the zero address. `anomalyContext` can
    ///         never score it, so the gate would never open and the assertion would be permanently
    ///         inert.
    error ZeroTarget();
    /// @notice Constructor guard: the sensitivity must name a rung of the ladder, `[1, 10]`.
    ///         Level 0 is the "cleared nothing" sentinel an unscored target reads back, so
    ///         accepting it would turn the damage heuristics into ungated blockers; above 10 names
    ///         no level at all and the assertion would be permanently inert.
    error SensitivityOutOfRange();

    /// @notice EIP-1967 implementation slot, `keccak256("eip1967.proxy.implementation") - 1`.
    bytes32 internal constant EIP1967_IMPLEMENTATION =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    /// @notice EIP-1967 admin slot, `keccak256("eip1967.proxy.admin") - 1`.
    bytes32 internal constant EIP1967_ADMIN = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    /// @notice The watched contract whose anomaly score gates this assertion (the adopter).
    address internal immutable target;

    /// @notice How aggressively the trigger fires, as a level on the `Sensitivity` ladder rather
    ///         than a basis-point score. Level 7 — the recommended point — fires on 1% of the
    ///         contract's own transactions. The threshold behind it is resolved per contract at
    ///         evaluation time, so this assertion is portable and survives a retrain untouched.
    uint8 internal immutable sensitivity;

    /// @param _target The watched contract the model scores. Must be non-zero.
    /// @param _sensitivity The level from `Sensitivity`, 1..=10.
    constructor(address _target, uint8 _sensitivity) {
        if (_target == address(0)) {
            revert ZeroTarget();
        }
        if (!Sensitivity.isValid(_sensitivity)) {
            revert SensitivityOutOfRange();
        }
        registerAssertionSpec(AssertionSpec.Reshiram);
        target = _target;
        sensitivity = _sensitivity;
    }

    // ---------------------------------------------------------------
    //  The anomaly gate
    // ---------------------------------------------------------------

    /// @notice Register the anomaly trigger for `selector` at this assertion's sensitivity level.
    /// @dev The trigger is the gate. `selector` runs only when the AnomalySubsystem scores `target`
    ///      anomalously enough to clear `sensitivity`, so the assertion body checks damage and
    ///      nothing else. A transaction below the level never spawns the assertion at all.
    ///
    ///      The gate fails open at both ends. An unscored target, or one whose model carries no
    ///      resolved ladder, clears no level, so nothing fires. Call this inside your `triggers()`.
    ///
    ///      `ph.anomalyContext(target)` still reports the score and the level it cleared, for an
    ///      assertion that wants to act on how anomalous a transaction was.
    function _registerAnomalyTrigger(bytes4 selector) internal view {
        watchAnomaly(target, selector, sensitivity);
    }

    // ---------------------------------------------------------------
    //  Corroboration primitives (the damage set H)
    // ---------------------------------------------------------------

    /// @notice Whether `token` left `outflowTarget` this transaction by at least `fracBps` of its
    ///         pre-transaction balance. `outflowTarget` may differ from `target`: the anomaly focal
    ///         is often a pool while the drained reserve sits in a separate aToken.
    /// @dev Net outflow from the reduced ERC-20 balance deltas over the post-transaction fork, scaled
    ///      by the balance read at the pre-transaction fork. A zero pre-balance corroborates nothing.
    ///      The ratio uses `ph.mulDivDown`, whose 512-bit intermediates keep a huge-balance token
    ///      from overflowing `net * 10_000` and blocking without corroboration.
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
        return ph.mulDivDown(net, 10_000, preBalance) >= fracBps;
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
