// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "../../../../Assertion.sol";
import {PhEvm} from "../../../../PhEvm.sol";

interface IERC20MetadataLike {
    function balanceOf(address account) external view returns (uint256);
    function decimals() external view returns (uint8);
}

interface ICurveLlammaAMM {
    function coins(uint256 i) external view returns (address);
    function active_band() external view returns (int256);
    function min_band() external view returns (int256);
    function max_band() external view returns (int256);
    function bands_x(int256 n) external view returns (uint256);
    function bands_y(int256 n) external view returns (uint256);
    function get_p() external view returns (uint256);
    function p_current_down(int256 n) external view returns (uint256);
    function p_current_up(int256 n) external view returns (uint256);
}

library CurveLlammaSelectors {
    bytes4 internal constant EXCHANGE = bytes4(keccak256("exchange(uint256,uint256,uint256,uint256)"));
    bytes4 internal constant EXCHANGE_FOR = bytes4(keccak256("exchange(uint256,uint256,uint256,uint256,address)"));
    bytes4 internal constant EXCHANGE_DY = bytes4(keccak256("exchange_dy(uint256,uint256,uint256,uint256)"));
    bytes4 internal constant EXCHANGE_DY_FOR =
        bytes4(keccak256("exchange_dy(uint256,uint256,uint256,uint256,address)"));
}

abstract contract CurveLlammaProtocolHelpers is Assertion {
    address internal immutable amm;
    address internal immutable borrowedToken;
    address internal immutable collateralToken;
    uint256 internal immutable borrowedPrecision;
    uint256 internal immutable collateralPrecision;
    uint256 internal immutable maxBandsToScan;
    uint256 internal immutable dustTolerance;
    uint256 internal immutable priceTolerance;

    constructor(
        address amm_,
        uint256 borrowedPrecision_,
        uint256 collateralPrecision_,
        uint256 maxBandsToScan_,
        uint256 dustTolerance_,
        uint256 priceTolerance_
    ) {
        amm = amm_;
        borrowedToken = ICurveLlammaAMM(amm_).coins(0);
        collateralToken = ICurveLlammaAMM(amm_).coins(1);

        borrowedPrecision = borrowedPrecision_ == 0
            ? _precisionFromDecimals(IERC20MetadataLike(borrowedToken).decimals())
            : borrowedPrecision_;
        collateralPrecision = collateralPrecision_ == 0
            ? _precisionFromDecimals(IERC20MetadataLike(collateralToken).decimals())
            : collateralPrecision_;

        maxBandsToScan = maxBandsToScan_;
        dustTolerance = dustTolerance_;
        priceTolerance = priceTolerance_;
    }

    function _registerLlammaSwapTriggers(bytes4 assertionSelector) internal view {
        registerFnCallTrigger(assertionSelector, CurveLlammaSelectors.EXCHANGE);
        registerFnCallTrigger(assertionSelector, CurveLlammaSelectors.EXCHANGE_FOR);
        registerFnCallTrigger(assertionSelector, CurveLlammaSelectors.EXCHANGE_DY);
        registerFnCallTrigger(assertionSelector, CurveLlammaSelectors.EXCHANGE_DY_FOR);
    }

    function _precisionFromDecimals(uint8 decimals_) internal pure returns (uint256 precision) {
        require(decimals_ <= 18, "CurveLLAMMA: token decimals too high");
        precision = 10 ** (18 - uint256(decimals_));
    }

    function _readIntAt(address target, bytes memory data, PhEvm.ForkId memory fork)
        internal
        view
        returns (int256 value)
    {
        value = abi.decode(_viewAt(target, data, fork), (int256));
    }

    function _bandSpan(int256 minBand, int256 maxBand) internal view returns (uint256 span) {
        require(maxBand >= minBand, "CurveLLAMMA: invalid band range");
        span = uint256(maxBand - minBand) + 1;
        require(span <= maxBandsToScan, "CurveLLAMMA: band scan too large");
    }

    function _bandAt(int256 minBand, uint256 offset) internal pure returns (int256) {
        require(offset <= uint256(type(int256).max), "CurveLLAMMA: band offset too large");
        return minBand + int256(offset);
    }

    function _ammMinBandAt(PhEvm.ForkId memory fork) internal view returns (int256) {
        return _readIntAt(amm, abi.encodeCall(ICurveLlammaAMM.min_band, ()), fork);
    }

    function _ammMaxBandAt(PhEvm.ForkId memory fork) internal view returns (int256) {
        return _readIntAt(amm, abi.encodeCall(ICurveLlammaAMM.max_band, ()), fork);
    }

    function _ammActiveBandAt(PhEvm.ForkId memory fork) internal view returns (int256) {
        return _readIntAt(amm, abi.encodeCall(ICurveLlammaAMM.active_band, ()), fork);
    }

    function _ammBandXAt(int256 band, PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(amm, abi.encodeCall(ICurveLlammaAMM.bands_x, (band)), fork);
    }

    function _ammBandYAt(int256 band, PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(amm, abi.encodeCall(ICurveLlammaAMM.bands_y, (band)), fork);
    }

    function _ammPriceAt(PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(amm, abi.encodeCall(ICurveLlammaAMM.get_p, ()), fork);
    }

    function _ammBandPriceDownAt(int256 band, PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(amm, abi.encodeCall(ICurveLlammaAMM.p_current_down, (band)), fork);
    }

    function _ammBandPriceUpAt(int256 band, PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(amm, abi.encodeCall(ICurveLlammaAMM.p_current_up, (band)), fork);
    }
}
