// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "credible-std/Assertion.sol";
import {PhEvm} from "credible-std/PhEvm.sol";

import {IAaveV3PoolLike, IChainlinkFeedLike, IRateProviderLike} from "./LidoVaultInterfaces.sol";

/// @title LidoVaultHelpers
/// @author Phylax Systems
/// @notice Shared fork-aware state accessors for Lido stETH vault example assertions.
/// @dev Written against the generic shape of a Lido stETH vault: a contract custodying
///      stETH/wstETH that allocates into an Aave v3-like lending market and prices its
///      shares through some rate source. Nothing here depends on a specific vault stack.
abstract contract LidoVaultHelpers is Assertion {
    /// @notice Reads a vault's aggregate Aave v3-like position at a snapshot fork.
    /// @dev Collateral and debt are denominated in the market base currency (USD, 8 decimals on
    ///      mainnet Aave). The health factor is 1e18-scaled and `type(uint256).max` without debt.
    function _aaveAccountDataAt(address pool, address account, PhEvm.ForkId memory fork)
        internal
        view
        returns (uint256 collateralBase, uint256 debtBase, uint256 healthFactor)
    {
        (collateralBase, debtBase,,,, healthFactor) = abi.decode(
            _viewAt(pool, abi.encodeCall(IAaveV3PoolLike.getUserAccountData, (account)), fork),
            (uint256, uint256, uint256, uint256, uint256, uint256)
        );
    }

    /// @notice Returns whether the stETH/ETH market price has left the configured peg band.
    /// @dev A zero feed address disables the check. An unreadable feed or non-positive answer
    ///      counts as depegged so the protected paths fail closed.
    function _isStEthDepeggedAt(address feed, uint256 pegUnit, uint256 maxDepegBps, PhEvm.ForkId memory fork)
        internal
        view
        returns (bool)
    {
        if (feed == address(0)) {
            return false;
        }

        PhEvm.StaticCallResult memory result =
            ph.staticcallAt(feed, abi.encodeCall(IChainlinkFeedLike.latestRoundData, ()), FORK_VIEW_GAS, fork);
        if (!result.ok) {
            return true;
        }

        (, int256 answer,,,) = abi.decode(result.data, (uint80, int256, uint256, uint256, uint80));
        if (answer <= 0) {
            return true;
        }

        uint256 price = uint256(answer);
        uint256 deviation = price > pegUnit ? price - pegUnit : pegUnit - price;
        return deviation * 10_000 > pegUnit * maxDepegBps;
    }

    /// @notice Returns whether a share/asset rate source can currently report a rate.
    /// @dev A zero source address counts as readable (signal disabled). A reverting or
    ///      zero-rate source means share pricing is not trustworthy — paused accountants and
    ///      stale oracles surface exactly this way — so risk-adding paths should fail closed.
    function _canReadRateAt(address rateSource, PhEvm.ForkId memory fork) internal view returns (bool) {
        if (rateSource == address(0)) {
            return true;
        }

        PhEvm.StaticCallResult memory result =
            ph.staticcallAt(rateSource, abi.encodeCall(IRateProviderLike.getRate, ()), FORK_VIEW_GAS, fork);
        if (!result.ok || result.data.length < 32) {
            return false;
        }

        return abi.decode(result.data, (uint256)) != 0;
    }
}
