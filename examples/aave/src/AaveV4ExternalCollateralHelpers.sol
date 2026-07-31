// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "credible-std/PhEvm.sol";

import {AaveV4Helpers} from "./AaveV4Helpers.sol";
import {IAaveV4Spoke} from "./AaveV4Interfaces.sol";

/// @notice ERC20 pause surface used by independently administered collateral and redemption tokens.
interface IExternalPausable {
    function paused() external view returns (bool);
}

/// @notice ether.fi timed-pause surface used by weETH.
interface IExternalTimedPausable {
    function pausedUntil() external view returns (uint256);
}

/// @notice ether.fi Blacklister surface used by weETH transfer hooks.
interface IExternalTimedBlacklist {
    function blacklistedUntil(address account) external view returns (uint256);
}

/// @notice Circle/Coinbase-style blacklist surface.
interface IExternalBlacklist {
    function isBlacklisted(address account) external view returns (bool);
}

/// @notice Tether-style blacklist surface. The capital `L` is part of the deployed ABI.
interface IExternalTetherBlacklist {
    function isBlackListed(address account) external view returns (bool);
}

/// @notice Tether Gold-style blocked-account surface.
interface IExternalBlockedAccount {
    function isBlocked(address account) external view returns (bool);
}

/// @notice AccessControl surface used by sUSDe transfer restrictions.
interface IExternalAccessControl {
    function hasRole(bytes32 role, address account) external view returns (bool);
}

/// @notice Paxos freeze surface used by USDG.
interface IExternalFrozenAccount {
    function isFrozen(address account) external view returns (bool);
}

/// @title AaveV4ExternalCollateralHelpers
/// @author Phylax Systems
/// @notice Shared call decoding and Aave exposure-scoping for external collateral assertions.
/// @dev Aave state is read only to decide whether the triggering user is increasing risk and
///      still relies on a configured collateral reserve. The protected facts themselves come
///      from independently administered token, issuer, and redemption contracts.
abstract contract AaveV4ExternalCollateralHelpers is AaveV4Helpers {
    /// @notice Decodes the affected user and rejects operations that do not increase collateral risk.
    /// @dev Borrow always increases debt. Withdraw and collateral-toggle paths are relevant only
    ///      when the user retains debt; non-collateral withdrawals are skipped. Collateral disable
    ///      remains checked because disabling good collateral can leave debt relying on an externally
    ///      frozen asset. A complete disable/exit of the frozen asset is allowed by the later
    ///      post-call reliance check.
    function _riskIncreasingUser(address spoke, PhEvm.TriggerContext memory ctx)
        internal
        view
        returns (address user, bool riskIncreasing)
    {
        bytes memory input = ph.callinputAt(ctx.callStart);
        PhEvm.ForkId memory preCall = _preCall(ctx.callStart);
        PhEvm.ForkId memory postCall = _postCall(ctx.callEnd);

        if (ctx.selector == IAaveV4Spoke.borrow.selector) {
            (,, user) = abi.decode(_args(input), (uint256, uint256, address));
            return (user, true);
        }

        if (ctx.selector == IAaveV4Spoke.withdraw.selector) {
            uint256 reserveId;
            (reserveId,, user) = abi.decode(_args(input), (uint256, uint256, address));
            if (!_hasDebtAt(spoke, user, postCall)) {
                return (user, false);
            }
            return (user, _isActiveCollateralAt(spoke, reserveId, user, preCall));
        }

        if (ctx.selector == IAaveV4Spoke.setUsingAsCollateral.selector) {
            uint256 reserveId;
            bool usingAsCollateral;
            (reserveId, usingAsCollateral, user) = abi.decode(_args(input), (uint256, bool, address));
            if (!_hasDebtAt(spoke, user, postCall)) {
                return (user, false);
            }

            (bool wasUsingAsCollateral,) = _spokeUserReserveStatusAt(spoke, reserveId, user, preCall);
            if (wasUsingAsCollateral == usingAsCollateral) {
                return (user, false);
            }

            // Enabling collateral with debt can make a restricted asset part of the solvency
            // calculation. Disabling is relevant only if the reserve was active before the call.
            return (user, usingAsCollateral || _hasPositiveCollateralFactorAt(spoke, reserveId, user, preCall));
        }

        revert("AaveV4External: unsupported trigger");
    }

    /// @notice Returns whether Aave counts a reserve toward the user's collateral at `fork`.
    /// @dev The user flag alone is insufficient: zero shares and a zero dynamic collateral factor
    ///      do not economically support debt.
    function _isActiveCollateralAt(address spoke, uint256 reserveId, address user, PhEvm.ForkId memory fork)
        internal
        view
        returns (bool)
    {
        (bool usingAsCollateral,) = _spokeUserReserveStatusAt(spoke, reserveId, user, fork);
        if (!usingAsCollateral) {
            return false;
        }

        IAaveV4Spoke.UserPosition memory position = _spokeUserPositionAt(spoke, reserveId, user, fork);
        return _hasPositiveCollateralFactorAt(spoke, reserveId, fork, position);
    }

    function _hasPositiveCollateralFactorAt(address spoke, uint256 reserveId, address user, PhEvm.ForkId memory fork)
        internal
        view
        returns (bool)
    {
        IAaveV4Spoke.UserPosition memory position = _spokeUserPositionAt(spoke, reserveId, user, fork);
        return _hasPositiveCollateralFactorAt(spoke, reserveId, fork, position);
    }

    function _hasPositiveCollateralFactorAt(
        address spoke,
        uint256 reserveId,
        PhEvm.ForkId memory fork,
        IAaveV4Spoke.UserPosition memory position
    ) internal view returns (bool) {
        if (position.suppliedShares == 0) {
            return false;
        }

        IAaveV4Spoke.DynamicReserveConfig memory config =
            _spokeDynamicConfigAt(spoke, reserveId, position.dynamicConfigKey, fork);
        return config.collateralFactor != 0;
    }

    function _hasDebtAt(address spoke, address user, PhEvm.ForkId memory fork) internal view returns (bool) {
        return _spokeAccountDataAt(spoke, user, fork).totalDebtValueRay != 0;
    }
}
