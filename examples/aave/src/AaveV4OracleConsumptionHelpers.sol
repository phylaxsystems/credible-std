// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "credible-std/PhEvm.sol";

import {AaveV4Helpers} from "./AaveV4Helpers.sol";
import {IAaveV4Oracle, IAaveV4PriceFeed, IAaveV4Spoke} from "./AaveV4Interfaces.sol";

/// @title AaveV4OracleConsumptionHelpers
/// @author Phylax Systems
/// @notice Fork-aware readers and trace filters for Aave v4 consumed-price protection.
/// @dev Constants are pinned to Aave v4 release v0.5.11 and the Ethereum Main Spoke deployment:
///      - AaveOracle `_sources` mapping is storage slot 1.
///      - Main Spoke is a TransparentUpgradeableProxy using the ERC-1967 implementation slot.
///      - AaveOracle returns 8-decimal positive prices from `IPriceFeed.latestAnswer()`.
abstract contract AaveV4OracleConsumptionHelpers is AaveV4Helpers {
    uint256 internal constant AAVE_ORACLE_SOURCES_MAPPING_SLOT = 1;

    bytes32 internal constant ERC1967_IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    bytes32 internal constant ERC1967_BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;

    function _spokeOracleAt(address spoke, PhEvm.ForkId memory fork) internal view returns (address) {
        return _readAddressAt(spoke, abi.encodeCall(IAaveV4Spoke.ORACLE, ()), fork);
    }

    function _reserveCountAt(address spoke, PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(spoke, abi.encodeCall(IAaveV4Spoke.getReserveCount, ()), fork);
    }

    function _oracleSpokeAt(address oracle, PhEvm.ForkId memory fork) internal view returns (address) {
        return _readAddressAt(oracle, abi.encodeCall(IAaveV4Oracle.spoke, ()), fork);
    }

    function _oracleDecimalsAt(address oracle, PhEvm.ForkId memory fork) internal view returns (uint8) {
        return _readUint8At(oracle, abi.encodeCall(IAaveV4Oracle.decimals, ()), fork);
    }

    function _reserveSourceAt(address oracle, uint256 reserveId, PhEvm.ForkId memory fork)
        internal
        view
        returns (address)
    {
        return _readAddressAt(oracle, abi.encodeCall(IAaveV4Oracle.getReserveSource, (reserveId)), fork);
    }

    function _reservePricesAt(address oracle, uint256[] memory reserveIds, PhEvm.ForkId memory fork)
        internal
        view
        returns (uint256[] memory prices)
    {
        prices = abi.decode(
            _viewAt(oracle, abi.encodeCall(IAaveV4Oracle.getReservesPrices, (reserveIds)), fork), (uint256[])
        );
    }

    function _sourceSlot(uint256 reserveId) internal pure returns (bytes32) {
        return keccak256(abi.encode(reserveId, AAVE_ORACLE_SOURCES_MAPPING_SLOT));
    }

    function _successfulStaticCalls(address target, bytes4 selector, uint256 limit)
        internal
        view
        returns (PhEvm.TriggerCall[] memory)
    {
        PhEvm.CallFilter memory filter = PhEvm.CallFilter({
            callType: 2, minDepth: 0, maxDepth: type(uint32).max, topLevelOnly: false, successOnly: true
        });
        return ph.matchingCalls(target, selector, filter, limit);
    }

    function _successfulSourceReads(address source, uint256 limit) internal view returns (PhEvm.TriggerCall[] memory) {
        return _successfulStaticCalls(source, IAaveV4PriceFeed.latestAnswer.selector, limit);
    }

    function _hasMandatoryPriceOperation(
        address spoke,
        uint256 maxTraceCalls,
        PhEvm.ForkId memory preTx,
        PhEvm.ForkId memory postTx
    ) internal view returns (bool) {
        return _matchingCalls(spoke, IAaveV4Spoke.borrow.selector, 1).length != 0
            || _hasCollateralWithdraw(spoke, maxTraceCalls, preTx, postTx)
            || _matchingCalls(spoke, IAaveV4Spoke.liquidationCall.selector, 1).length != 0
            || _hasCollateralDisable(spoke, maxTraceCalls)
            || _matchingCalls(spoke, IAaveV4Spoke.updateUserRiskPremium.selector, 1).length != 0
            || _matchingCalls(spoke, IAaveV4Spoke.updateUserDynamicConfig.selector, 1).length != 0;
    }

    /// @dev Aave v4 refreshes account data on withdrawal only when the withdrawn reserve is
    ///      collateral. Check both transaction boundaries so collateral toggles in a multicall
    ///      cannot turn a risk-sensitive withdrawal into an unrecognized non-price path.
    function _hasCollateralWithdraw(
        address spoke,
        uint256 maxTraceCalls,
        PhEvm.ForkId memory preTx,
        PhEvm.ForkId memory postTx
    ) private view returns (bool) {
        PhEvm.TriggerCall[] memory calls = _matchingCalls(spoke, IAaveV4Spoke.withdraw.selector, maxTraceCalls + 1);
        require(calls.length <= maxTraceCalls, "AaveV4Oracle: trace limit exceeded");
        for (uint256 i; i < calls.length; ++i) {
            require(calls[i].input.length == 32 * 3, "AaveV4Oracle: malformed withdraw input");
            (uint256 reserveId,, address onBehalfOf) = abi.decode(calls[i].input, (uint256, uint256, address));
            (bool preCollateral,) = _spokeUserReserveStatusAt(spoke, reserveId, onBehalfOf, preTx);
            (bool postCollateral,) = _spokeUserReserveStatusAt(spoke, reserveId, onBehalfOf, postTx);
            if (preCollateral || postCollateral) {
                return true;
            }
        }
        return false;
    }

    function _hasCollateralDisable(address spoke, uint256 maxTraceCalls) private view returns (bool) {
        PhEvm.TriggerCall[] memory calls =
            _matchingCalls(spoke, IAaveV4Spoke.setUsingAsCollateral.selector, maxTraceCalls + 1);
        require(calls.length <= maxTraceCalls, "AaveV4Oracle: trace limit exceeded");
        for (uint256 i; i < calls.length; ++i) {
            require(calls[i].input.length == 32 * 3, "AaveV4Oracle: malformed collateral input");
            (, bool usingAsCollateral,) = abi.decode(calls[i].input, (uint256, bool, address));
            if (!usingAsCollateral) {
                return true;
            }
        }
        return false;
    }
}
