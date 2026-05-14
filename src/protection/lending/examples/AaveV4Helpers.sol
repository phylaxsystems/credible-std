// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "../../../Assertion.sol";
import {PhEvm} from "../../../PhEvm.sol";
import {AssertionSpec} from "../../../SpecRecorder.sol";

import {IAaveV4Hub, IAaveV4Oracle, IAaveV4Spoke} from "./AaveV4Interfaces.sol";

/// @title AaveV4Helpers
/// @author Phylax Systems
/// @notice Fork-aware state readers and calldata decoders shared by the Aave v4 examples.
/// @dev The helpers read Hub, Spoke, and oracle state at V2 fork snapshots. Constructor
///      parameters are supplied explicitly by each assertion so deployment never needs to read
///      mutable target state from the isolated assertion runtime.
abstract contract AaveV4Helpers is Assertion {
    uint256 internal constant BPS = 10_000;
    uint256 internal constant WAD = 1e18;
    uint256 internal constant RAY = 1e27;
    uint8 internal constant ORACLE_DECIMALS = 8;
    uint256 internal constant HEALTH_FACTOR_LIQUIDATION_THRESHOLD = 1e18;

    constructor() {
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    function _viewFailureMessage() internal pure override returns (string memory) {
        return "AaveV4: fork view failed";
    }

    function _hubAssetAt(address hub, uint256 assetId, PhEvm.ForkId memory fork)
        internal
        view
        returns (IAaveV4Hub.Asset memory asset)
    {
        asset = abi.decode(_viewAt(hub, abi.encodeCall(IAaveV4Hub.getAsset, (assetId)), fork), (IAaveV4Hub.Asset));
    }

    function _hubSpokeAt(address hub, uint256 assetId, address spoke, PhEvm.ForkId memory fork)
        internal
        view
        returns (IAaveV4Hub.SpokeData memory data)
    {
        data = abi.decode(
            _viewAt(hub, abi.encodeCall(IAaveV4Hub.getSpoke, (assetId, spoke)), fork), (IAaveV4Hub.SpokeData)
        );
    }

    function _hubSpokeAddedSharesAt(address hub, uint256 assetId, address spoke, PhEvm.ForkId memory fork)
        internal
        view
        returns (uint256)
    {
        return _readUintAt(hub, abi.encodeCall(IAaveV4Hub.getSpokeAddedShares, (assetId, spoke)), fork);
    }

    function _hubSpokeAddedAssetsAt(address hub, uint256 assetId, address spoke, PhEvm.ForkId memory fork)
        internal
        view
        returns (uint256)
    {
        return _readUintAt(hub, abi.encodeCall(IAaveV4Hub.getSpokeAddedAssets, (assetId, spoke)), fork);
    }

    function _hubSpokeDrawnSharesAt(address hub, uint256 assetId, address spoke, PhEvm.ForkId memory fork)
        internal
        view
        returns (uint256)
    {
        return _readUintAt(hub, abi.encodeCall(IAaveV4Hub.getSpokeDrawnShares, (assetId, spoke)), fork);
    }

    function _hubSpokePremiumDataAt(address hub, uint256 assetId, address spoke, PhEvm.ForkId memory fork)
        internal
        view
        returns (uint256 premiumShares, int256 premiumOffsetRay)
    {
        (premiumShares, premiumOffsetRay) = abi.decode(
            _viewAt(hub, abi.encodeCall(IAaveV4Hub.getSpokePremiumData, (assetId, spoke)), fork), (uint256, int256)
        );
    }

    function _hubPreviewRemoveBySharesAt(address hub, uint256 assetId, uint256 shares, PhEvm.ForkId memory fork)
        internal
        view
        returns (uint256)
    {
        return _readUintAt(hub, abi.encodeCall(IAaveV4Hub.previewRemoveByShares, (assetId, shares)), fork);
    }

    function _hubDrawnIndexAt(address hub, uint256 assetId, PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(hub, abi.encodeCall(IAaveV4Hub.getAssetDrawnIndex, (assetId)), fork);
    }

    function _spokeReserveAt(address spoke, uint256 reserveId, PhEvm.ForkId memory fork)
        internal
        view
        returns (IAaveV4Spoke.Reserve memory reserve)
    {
        reserve = abi.decode(
            _viewAt(spoke, abi.encodeCall(IAaveV4Spoke.getReserve, (reserveId)), fork), (IAaveV4Spoke.Reserve)
        );
    }

    function _spokeDynamicConfigAt(address spoke, uint256 reserveId, uint32 dynamicConfigKey, PhEvm.ForkId memory fork)
        internal
        view
        returns (IAaveV4Spoke.DynamicReserveConfig memory config)
    {
        config = abi.decode(
            _viewAt(spoke, abi.encodeCall(IAaveV4Spoke.getDynamicReserveConfig, (reserveId, dynamicConfigKey)), fork),
            (IAaveV4Spoke.DynamicReserveConfig)
        );
    }

    function _spokeUserReserveStatusAt(address spoke, uint256 reserveId, address user, PhEvm.ForkId memory fork)
        internal
        view
        returns (bool collateral, bool borrowing)
    {
        (collateral, borrowing) = abi.decode(
            _viewAt(spoke, abi.encodeCall(IAaveV4Spoke.getUserReserveStatus, (reserveId, user)), fork), (bool, bool)
        );
    }

    function _spokeUserPositionAt(address spoke, uint256 reserveId, address user, PhEvm.ForkId memory fork)
        internal
        view
        returns (IAaveV4Spoke.UserPosition memory position)
    {
        position = abi.decode(
            _viewAt(spoke, abi.encodeCall(IAaveV4Spoke.getUserPosition, (reserveId, user)), fork),
            (IAaveV4Spoke.UserPosition)
        );
    }

    function _spokeAccountDataAt(address spoke, address user, PhEvm.ForkId memory fork)
        internal
        view
        returns (IAaveV4Spoke.UserAccountData memory accountData)
    {
        accountData = abi.decode(
            _viewAt(spoke, abi.encodeCall(IAaveV4Spoke.getUserAccountData, (user)), fork),
            (IAaveV4Spoke.UserAccountData)
        );
    }

    function _spokeLastRiskPremiumAt(address spoke, address user, PhEvm.ForkId memory fork)
        internal
        view
        returns (uint256)
    {
        return _readUintAt(spoke, abi.encodeCall(IAaveV4Spoke.getUserLastRiskPremium, (user)), fork);
    }

    function _oraclePriceAt(address oracle, uint256 reserveId, PhEvm.ForkId memory fork)
        internal
        view
        returns (uint256)
    {
        return _readUintAt(oracle, abi.encodeCall(IAaveV4Oracle.getReservePrice, (reserveId)), fork);
    }

    function _firstUint256Arg(bytes memory input) internal pure returns (uint256 value) {
        require(input.length >= 36, "AaveV4: short calldata");
        assembly ("memory-safe") {
            value := mload(add(input, 36))
        }
    }

    function _args(bytes memory input) internal pure returns (bytes memory args) {
        require(input.length >= 4, "AaveV4: short calldata");

        args = new bytes(input.length - 4);
        for (uint256 i; i < args.length; ++i) {
            args[i] = input[i + 4];
        }
    }

    function _requireAdopter(address expected, string memory message) internal view {
        require(ph.getAssertionAdopter() == expected, message);
    }

    function _fromRayUp(uint256 value) internal pure returns (uint256) {
        return value / RAY + (value % RAY == 0 ? 0 : 1);
    }

    function _divUp(uint256 value, uint256 denominator) internal pure returns (uint256) {
        return value / denominator + (value % denominator == 0 ? 0 : 1);
    }

    function _toValue(uint256 amount, uint8 decimals, uint256 price) internal pure returns (uint256) {
        return amount * price * (10 ** uint256(18 - decimals));
    }
}
