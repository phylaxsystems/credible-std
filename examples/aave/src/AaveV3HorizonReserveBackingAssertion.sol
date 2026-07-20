// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "credible-std/PhEvm.sol";

import {AaveV3LikeTypes} from "credible-std/protection/lending/examples/AaveV3LikeInterfaces.sol";
import {IAaveV3HorizonDeficitPool, IAaveV3HorizonToken} from "./AaveV3HorizonInterfaces.sol";
import {AaveV3HorizonHelpers} from "./AaveV3HorizonHelpers.sol";

/// @title AaveV3HorizonReserveBackingAssertion
/// @author Phylax Systems
/// @notice Protects Horizon reserve accounting against external underlying-token balance changes.
/// @dev A Pool require can validate Pool-owned supply, borrow, repay, and withdraw paths, but it
///      cannot run when an underlying token balance changes directly on an aToken through token
///      admin action, rebasing, hooks, or other cross-protocol side effects. This assertion checks
///      transaction-end reserve backing from external token balances and debt-token supply.
contract AaveV3HorizonReserveBackingAssertion is AaveV3HorizonHelpers {
    address internal immutable POOL;
    uint256 internal immutable MAX_BACKING_DEFICIT;
    address[] internal RESERVE_ASSETS;

    constructor(address pool_, address[] memory reserveAssets_, uint256 maxBackingDeficit_) {
        require(pool_ != address(0), "AaveV3Horizon: pool zero");
        require(reserveAssets_.length != 0, "AaveV3Horizon: no reserve assets");

        POOL = pool_;
        MAX_BACKING_DEFICIT = maxBackingDeficit_;
        RESERVE_ASSETS = reserveAssets_;
    }

    /// @notice Registers a transaction-end backing check for configured Horizon reserve assets.
    /// @dev The trigger intentionally runs after the whole transaction, including direct reserve
    ///      token movements outside the Pool call surface. That transaction envelope is not a place
    ///      where Horizon can add a Pool-level require.
    function triggers() external view override {
        registerTxEndTrigger(this.assertReserveBacking.selector);
    }

    /// @notice Checks all configured reserves remain backed at transaction end.
    /// @dev For each reserve, compares aToken supply with underlying held by the aToken plus
    ///      stable debt, variable debt, unbacked bridge debt, and Horizon's first-class reserve
    ///      deficit. A liquidation may legitimately convert debt into deficit, so excluding that
    ///      field rejects official recovery accounting.
    function assertReserveBacking() external view {
        require(ph.getAssertionAdopter() == POOL, "AaveV3Horizon: configured pool is not adopter");
        PhEvm.ForkId memory pre = _preTx();
        PhEvm.ForkId memory post = _postTx();

        for (uint256 i; i < RESERVE_ASSETS.length; ++i) {
            _assertReserveBacking(RESERVE_ASSETS[i], pre, post);
        }
    }

    function _assertReserveBacking(address asset, PhEvm.ForkId memory pre, PhEvm.ForkId memory post) internal view {
        // Read both endpoints so a dropped/misconfigured reserve fails at the transaction where
        // the configuration changed, instead of silently beginning from an unvalidated baseline.
        _reserveBackingAt(asset, pre);
        ReserveBacking memory afterBacking = _reserveBackingAt(asset, post);
        require(_isBacked(afterBacking), "AaveV3Horizon: reserve backing deficit");
    }

    struct ReserveBacking {
        uint256 aTokenSupply;
        uint256 backingClaims;
    }

    function _reserveBackingAt(address asset, PhEvm.ForkId memory fork)
        internal
        view
        returns (ReserveBacking memory backing)
    {
        AaveV3LikeTypes.ReserveData memory reserveData = _reserveDataAt(POOL, asset, fork);
        require(reserveData.aTokenAddress != address(0), "AaveV3Horizon: reserve not listed");

        uint256 availableLiquidity = _readBalanceAt(asset, reserveData.aTokenAddress, fork);
        uint256 stableDebt = _optionalTotalSupplyAt(reserveData.stableDebtTokenAddress, fork);
        uint256 variableDebt = _optionalTotalSupplyAt(reserveData.variableDebtTokenAddress, fork);
        uint256 deficit = _readUintAt(POOL, abi.encodeCall(IAaveV3HorizonDeficitPool.getReserveDeficit, (asset)), fork);

        backing.aTokenSupply = _totalSupplyAt(reserveData.aTokenAddress, fork);
        backing.backingClaims = availableLiquidity + stableDebt + variableDebt + reserveData.unbacked + deficit;
    }

    function _isBacked(ReserveBacking memory backing) internal view returns (bool) {
        return backing.aTokenSupply <= backing.backingClaims + MAX_BACKING_DEFICIT;
    }

    function _optionalTotalSupplyAt(address token, PhEvm.ForkId memory fork) internal view returns (uint256) {
        if (token == address(0)) {
            return 0;
        }

        return _totalSupplyAt(token, fork);
    }

    function _totalSupplyAt(address token, PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(token, abi.encodeCall(IAaveV3HorizonToken.totalSupply, ()), fork);
    }
}
