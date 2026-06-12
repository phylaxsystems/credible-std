// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "credible-std/Assertion.sol";
import {PhEvm} from "credible-std/PhEvm.sol";
import {
    ICapFractionalReserveLike,
    ICapPriceOracleLike,
    ICapVaultLike,
    IERC20Like
} from "./CapMintBackingInterfaces.sol";

/// @title CapMintBackingHelpers
/// @author Phylax Systems
/// @notice Fork-aware reads and USD valuation for the Cap mint-backing assertion.
/// @dev Valuation mirrors Cap's own `MinterLogic`: `value = amount * price / 10**decimals`,
///      with oracle prices expressed in 8-decimal USD. cUSD is valued at its $1 face peg
///      (`FACE_PRICE_USD8`) rather than at the CapToken oracle, because that oracle reports
///      cUSD as backing-over-supply and would make a backing check circular.
///
///      POLICY — fail-closed on read failure (decide with Cap): the reads below revert on infra
///      errors (`require(res.ok …)`, `require(price > 0)`). Because a reverting assertion blocks
///      the transaction, this couples mint/burn/redeem liveness to oracle liveness — a transiently
///      down/stale/zero oracle blocks all mint/burn/redeem, possibly when the protocol is already
///      stressed (and blocked redeems/burns can trap users). For a solvency invariant that is a
///      defensible default (halt rather than allow an unbacked mint), but it is Cap's tradeoff to
///      own. The alternative is fail-open on infra-level read failures (oracle revert/stale ⇒ skip
///      the check) while keeping the *solvency comparison itself* strict. Pending Cap sign-off.
///
///      DRIFT — static asset set (must resolve before production): `ASSET0..ASSET4` are immutable,
///      fixed at deploy (see constructor). Any reserve-set change (asset added/removed/migrated)
///      silently under-counts backing — false-positives on honest mints — and drops inflow-watcher
///      coverage for the new asset, with no way for the assertion to detect the change. Before
///      mainnet either (a) enforce a redeploy-on-reserve-change operational contract, or (b) drive
///      the asset set from on-chain state. Do not ship the static list unaddressed.
abstract contract CapMintBackingHelpers is Assertion {
    /// @dev USD price scale used by the Cap oracle (8 decimals).
    uint256 internal constant FACE_PRICE_USD8 = 1e8;

    /// @dev Gas budget for nested static reads against a fork snapshot.
    uint64 internal constant READ_GAS = 3_000_000;

    address internal immutable ORACLE;
    address internal immutable ASSET0;
    address internal immutable ASSET1;
    address internal immutable ASSET2;
    address internal immutable ASSET3;
    address internal immutable ASSET4;

    constructor(address oracle_, address asset0_, address asset1_, address asset2_, address asset3_, address asset4_) {
        ORACLE = oracle_;
        ASSET0 = asset0_;
        ASSET1 = asset1_;
        ASSET2 = asset2_;
        ASSET3 = asset3_;
        ASSET4 = asset4_;
    }

    /// @notice USD value (8 decimals) of all backing reserves at a fork snapshot.
    /// @dev Sums `totalSupplies(asset) * price(asset) / 10**decimals(asset)` over the
    ///      configured assets. `totalSupplies` already includes idle, borrowed, and
    ///      fractional-reserve-deployed units, so borrow/invest do not move this total.
    function _backingValueUsd8(PhEvm.ForkId memory fork) internal view returns (uint256 value) {
        value = _assetValueUsd8(ASSET0, fork) + _assetValueUsd8(ASSET1, fork) + _assetValueUsd8(ASSET2, fork)
            + _assetValueUsd8(ASSET3, fork) + _assetValueUsd8(ASSET4, fork);
    }

    /// @notice cUSD supply valued at its $1 face peg, in 8-decimal USD.
    function _capFaceValueUsd8(PhEvm.ForkId memory fork) internal view returns (uint256 value) {
        address adopter = ph.getAssertionAdopter();
        uint256 supply = _readUint(adopter, abi.encodeCall(IERC20Like.totalSupply, ()), fork);
        uint256 decimalsPow = _readDecimalsPow(adopter, fork);
        value = ph.mulDivDown(supply, FACE_PRICE_USD8, decimalsPow);
    }

    /// @notice Backing surplus over cUSD face value (positive = over-collateralized).
    function _surplusUsd8(PhEvm.ForkId memory fork) internal view returns (int256 surplus) {
        surplus = int256(_backingValueUsd8(fork)) - int256(_capFaceValueUsd8(fork));
    }

    /// @notice Idle custody minus accounted backing for one asset.
    /// @dev `idle + borrowed + loaned - totalSupplies`. A direct donation raises idle
    ///      without touching the accounting terms, so this slack jumps upward.
    function _idleSlack(address token, PhEvm.ForkId memory fork) internal view returns (int256 slack) {
        address adopter = ph.getAssertionAdopter();
        uint256 idle = _readUint(token, abi.encodeCall(IERC20Like.balanceOf, (adopter)), fork);
        uint256 borrowed = _readUint(adopter, abi.encodeCall(ICapVaultLike.totalBorrows, (token)), fork);
        uint256 loaned = _readUint(adopter, abi.encodeCall(ICapFractionalReserveLike.loaned, (token)), fork);
        uint256 supplied = _readUint(adopter, abi.encodeCall(ICapVaultLike.totalSupplies, (token)), fork);
        // forge-lint: disable-next-line(unsafe-typecast) — asset amounts are far below int256 max
        slack = int256(idle) + int256(borrowed) + int256(loaned) - int256(supplied);
    }

    function _assetValueUsd8(address asset, PhEvm.ForkId memory fork) private view returns (uint256 value) {
        if (asset == address(0)) return 0;
        address adopter = ph.getAssertionAdopter();
        uint256 supplied = _readUint(adopter, abi.encodeCall(ICapVaultLike.totalSupplies, (asset)), fork);
        if (supplied == 0) return 0;
        uint256 price = _readPriceUsd8(asset, fork);
        uint256 decimalsPow = _readDecimalsPow(asset, fork);
        value = ph.mulDivDown(supplied, price, decimalsPow);
    }

    function _readPriceUsd8(address asset, PhEvm.ForkId memory fork) private view returns (uint256 price) {
        PhEvm.StaticCallResult memory res =
            ph.staticcallAt(ORACLE, abi.encodeCall(ICapPriceOracleLike.getPrice, (asset)), READ_GAS, fork);
        require(res.ok && res.data.length >= 64, "CapBacking: price read failed");
        (price,) = abi.decode(res.data, (uint256, uint256));
        require(price > 0, "CapBacking: zero price");
    }

    function _readDecimalsPow(address token, PhEvm.ForkId memory fork) private view returns (uint256 pow) {
        uint256 decimals = _readUint(token, abi.encodeCall(IERC20Like.decimals, ()), fork);
        require(decimals <= 36, "CapBacking: bad decimals");
        pow = 10 ** decimals;
    }

    function _readUint(address target, bytes memory data, PhEvm.ForkId memory fork)
        private
        view
        returns (uint256 result)
    {
        PhEvm.StaticCallResult memory res = ph.staticcallAt(target, data, READ_GAS, fork);
        require(res.ok && res.data.length >= 32, "CapBacking: read failed");
        result = abi.decode(res.data, (uint256));
    }
}
