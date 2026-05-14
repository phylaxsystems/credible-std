// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "../../../Assertion.sol";
import {PhEvm} from "../../../PhEvm.sol";
import {AssertionSpec} from "../../../SpecRecorder.sol";

import {AaveV3LikeTypes, IAaveV3LikeAddressesProvider, IAaveV3LikePool} from "./AaveV3LikeInterfaces.sol";
import {IAaveV3HorizonOracle} from "./AaveV3HorizonInterfaces.sol";

/// @title AaveV3HorizonHelpers
/// @author Phylax Systems
/// @notice Shared fork-aware readers and decoders for Aave v3 Horizon examples.
/// @dev Horizon assertions intentionally read through the Pool, AddressesProvider, AaveOracle,
///      Chainlink-compatible sources, aTokens, and debt tokens rather than restating one local
///      require branch. Constructor inputs are explicit so assertion deployment does not depend
///      on target-state reads in an isolated runtime.
abstract contract AaveV3HorizonHelpers is Assertion {
    uint256 internal constant BPS = 10_000;

    constructor() {
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    function _viewFailureMessage() internal pure override returns (string memory) {
        return "AaveV3Horizon: fork view failed";
    }

    function _oracleAt(address addressesProvider, PhEvm.ForkId memory fork) internal view returns (address) {
        return _readAddressAt(addressesProvider, abi.encodeCall(IAaveV3LikeAddressesProvider.getPriceOracle, ()), fork);
    }

    function _reservesListAt(address pool, PhEvm.ForkId memory fork) internal view returns (address[] memory reserves) {
        reserves = abi.decode(_viewAt(pool, abi.encodeCall(IAaveV3LikePool.getReservesList, ()), fork), (address[]));
    }

    function _reserveDataAt(address pool, address asset, PhEvm.ForkId memory fork)
        internal
        view
        returns (AaveV3LikeTypes.ReserveData memory reserveData)
    {
        reserveData = abi.decode(
            _viewAt(pool, abi.encodeCall(IAaveV3LikePool.getReserveData, (asset)), fork), (AaveV3LikeTypes.ReserveData)
        );
    }

    function _userConfigDataAt(address pool, address account, PhEvm.ForkId memory fork)
        internal
        view
        returns (uint256)
    {
        AaveV3LikeTypes.UserConfigurationMap memory userConfig = abi.decode(
            _viewAt(pool, abi.encodeCall(IAaveV3LikePool.getUserConfiguration, (account)), fork),
            (AaveV3LikeTypes.UserConfigurationMap)
        );
        return userConfig.data;
    }

    function _assetPriceAt(address oracle, address asset, PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(oracle, abi.encodeCall(IAaveV3HorizonOracle.getAssetPrice, (asset)), fork);
    }

    function _sourceOfAssetAt(address oracle, address asset, PhEvm.ForkId memory fork) internal view returns (address) {
        return _readAddressAt(oracle, abi.encodeCall(IAaveV3HorizonOracle.getSourceOfAsset, (asset)), fork);
    }

    function _assertPriceBounded(
        address oracle,
        address asset,
        PhEvm.ForkId memory pre,
        PhEvm.ForkId memory post,
        uint256 deviationBps
    ) internal view {
        uint256 prePrice = _assetPriceAt(oracle, asset, pre);
        uint256 postPrice = _assetPriceAt(oracle, asset, post);
        require(prePrice > 0 && postPrice > 0, "AaveV3Horizon: reserve oracle price invalid");
        require(
            ph.ratioGe(postPrice, 1, prePrice, 1, deviationBps) && ph.ratioGe(prePrice, 1, postPrice, 1, deviationBps),
            "AaveV3Horizon: reserve oracle price drift"
        );
    }

    function _requireAdopter(address expected, string memory message) internal view {
        require(ph.getAssertionAdopter() == expected, message);
    }

    function _isBorrowing(uint256 userConfigData, uint256 reserveId) internal pure returns (bool) {
        return ((userConfigData >> (reserveId * 2)) & 1) != 0;
    }

    function _isUsingAsCollateral(uint256 userConfigData, uint256 reserveId) internal pure returns (bool) {
        return ((userConfigData >> (reserveId * 2 + 1)) & 1) != 0;
    }
}
