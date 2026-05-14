// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "../../../PhEvm.sol";

import {AaveV3LikeTypes, IAaveV3LikePool} from "./AaveV3LikeInterfaces.sol";
import {AaveV3HorizonHelpers} from "./AaveV3HorizonHelpers.sol";

/// @title AaveV3HorizonOracleAssertion
/// @author Phylax Systems
/// @notice Protects Horizon's oracle-backed lending risk state.
/// @dev This assertion targets properties that are not local `require` checks:
///      - Risk-changing Pool operations must not share a transaction envelope with material
///        PreTx/PostTx oracle drift for active collateral, debt reserves, or touched assets.
///      - The active oracle source for those reserves must not be swapped earlier or later in the
///        same transaction while the Pool consumes the resulting risk state.
///      - The checks span Pool reserve/user bitmaps, the AddressesProvider, AaveOracle, and
///        Chainlink-compatible source contracts across the whole transaction, not one call frame.
contract AaveV3HorizonOracleAssertion is AaveV3HorizonHelpers {
    address internal immutable POOL;
    address internal immutable ADDRESSES_PROVIDER;
    uint256 internal immutable MAX_RESERVES_TO_SCAN;
    uint256 internal immutable ORACLE_DEVIATION_BPS;

    constructor(address pool_, address addressesProvider_, uint256 maxReservesToScan_, uint256 oracleDeviationBps_) {
        require(pool_ != address(0), "AaveV3Horizon: pool zero");
        require(addressesProvider_ != address(0), "AaveV3Horizon: provider zero");
        require(maxReservesToScan_ != 0, "AaveV3Horizon: max reserves zero");
        require(oracleDeviationBps_ <= BPS, "AaveV3Horizon: bad oracle tolerance");

        POOL = pool_;
        ADDRESSES_PROVIDER = addressesProvider_;
        MAX_RESERVES_TO_SCAN = maxReservesToScan_;
        ORACLE_DEVIATION_BPS = oracleDeviationBps_;
    }

    /// @notice Registers one transaction-end check for Horizon oracle/risk coupling.
    /// @dev This intentionally runs after the whole transaction, so it catches bundled oracle
    ///      changes that happened before or after a Pool risk operation. The Pool function itself
    ///      cannot reproduce the PreTx oracle/source baseline with a local require.
    function triggers() external view override {
        registerTxEndTrigger(this.assertRiskOperationOracleEnvelope.selector);
    }

    /// @notice Bounds oracle/source movement across any transaction that includes Pool risk operations.
    /// @dev Scans successful Horizon Pool calls in the transaction, resolves affected users/assets,
    ///      and compares oracle prices and source addresses between PreTx and PostTx. A failure
    ///      means the transaction consumed lending risk state while also changing the oracle basis
    ///      used to value that risk.
    function assertRiskOperationOracleEnvelope() external view {
        _requireAdopter(POOL, "AaveV3Horizon: configured pool is not adopter");

        PhEvm.ForkId memory pre = _preTx();
        PhEvm.ForkId memory post = _postTx();
        address oracle = _oracleAt(ADDRESSES_PROVIDER, post);

        _assertCallGroupOracleEnvelope(oracle, IAaveV3LikePool.borrow.selector, pre, post);
        _assertCallGroupOracleEnvelope(oracle, IAaveV3LikePool.withdraw.selector, pre, post);
        _assertCallGroupOracleEnvelope(oracle, IAaveV3LikePool.setUserUseReserveAsCollateral.selector, pre, post);
        _assertCallGroupOracleEnvelope(oracle, IAaveV3LikePool.finalizeTransfer.selector, pre, post);
        _assertCallGroupOracleEnvelope(oracle, IAaveV3LikePool.setUserEMode.selector, pre, post);
        _assertCallGroupOracleEnvelope(oracle, IAaveV3LikePool.liquidationCall.selector, pre, post);
    }

    function _assertCallGroupOracleEnvelope(
        address oracle,
        bytes4 selector,
        PhEvm.ForkId memory pre,
        PhEvm.ForkId memory post
    ) internal view {
        PhEvm.CallInputs[] memory calls = ph.getAllCallInputs(POOL, selector);

        for (uint256 i; i < calls.length; ++i) {
            address account = _operationAccount(selector, calls[i].input, calls[i].caller);
            if (account != address(0)) {
                _assertAccountReservePricesBounded(account, oracle, pre, post);
            }

            _assertTouchedAssetPricesBounded(selector, calls[i].input, oracle, pre, post);
        }
    }

    function _assertAccountReservePricesBounded(
        address account,
        address oracle,
        PhEvm.ForkId memory pre,
        PhEvm.ForkId memory post
    ) internal view {
        address[] memory reserves = _reservesListAt(POOL, post);
        require(reserves.length <= MAX_RESERVES_TO_SCAN, "AaveV3Horizon: too many reserves");

        uint256 preConfig = _userConfigDataAt(POOL, account, pre);
        uint256 postConfig = _userConfigDataAt(POOL, account, post);

        for (uint256 i; i < reserves.length; ++i) {
            AaveV3LikeTypes.ReserveData memory reserveData = _reserveDataAt(POOL, reserves[i], post);
            bool activeBefore =
                _isBorrowing(preConfig, reserveData.id) || _isUsingAsCollateral(preConfig, reserveData.id);
            bool activeAfter =
                _isBorrowing(postConfig, reserveData.id) || _isUsingAsCollateral(postConfig, reserveData.id);

            if (!activeBefore && !activeAfter) {
                continue;
            }

            _assertSourceStable(oracle, reserves[i], pre, post);
            _assertPriceBounded(oracle, reserves[i], pre, post, ORACLE_DEVIATION_BPS);
        }
    }

    function _assertTouchedAssetPricesBounded(
        bytes4 selector,
        bytes memory input,
        address oracle,
        PhEvm.ForkId memory pre,
        PhEvm.ForkId memory post
    ) internal view {
        if (selector == IAaveV3LikePool.borrow.selector) {
            (address asset,,,,) = abi.decode(input, (address, uint256, uint256, uint16, address));
            _assertSourceStable(oracle, asset, pre, post);
            _assertPriceBounded(oracle, asset, pre, post, ORACLE_DEVIATION_BPS);
            return;
        }

        if (selector == IAaveV3LikePool.withdraw.selector) {
            (address asset,,) = abi.decode(input, (address, uint256, address));
            _assertSourceStable(oracle, asset, pre, post);
            _assertPriceBounded(oracle, asset, pre, post, ORACLE_DEVIATION_BPS);
            return;
        }

        if (selector == IAaveV3LikePool.setUserUseReserveAsCollateral.selector) {
            (address asset,) = abi.decode(input, (address, bool));
            _assertSourceStable(oracle, asset, pre, post);
            _assertPriceBounded(oracle, asset, pre, post, ORACLE_DEVIATION_BPS);
            return;
        }

        if (selector == IAaveV3LikePool.finalizeTransfer.selector) {
            (address asset,,,,,) = abi.decode(input, (address, address, address, uint256, uint256, uint256));
            _assertSourceStable(oracle, asset, pre, post);
            _assertPriceBounded(oracle, asset, pre, post, ORACLE_DEVIATION_BPS);
            return;
        }

        if (selector == IAaveV3LikePool.liquidationCall.selector) {
            (address collateralAsset, address debtAsset,,,) =
                abi.decode(input, (address, address, address, uint256, bool));
            _assertSourceStable(oracle, collateralAsset, pre, post);
            _assertSourceStable(oracle, debtAsset, pre, post);
            _assertPriceBounded(oracle, collateralAsset, pre, post, ORACLE_DEVIATION_BPS);
            _assertPriceBounded(oracle, debtAsset, pre, post, ORACLE_DEVIATION_BPS);
        }
    }

    function _assertSourceStable(address oracle, address asset, PhEvm.ForkId memory pre, PhEvm.ForkId memory post)
        internal
        view
    {
        address preSource = _sourceOfAssetAt(oracle, asset, pre);
        address postSource = _sourceOfAssetAt(oracle, asset, post);
        require(preSource == postSource, "AaveV3Horizon: reserve oracle source changed");
    }

    function _operationAccount(bytes4 selector, bytes memory input, address caller) internal pure returns (address) {
        if (selector == IAaveV3LikePool.borrow.selector) {
            (,,,, address onBehalfOf) = abi.decode(input, (address, uint256, uint256, uint16, address));
            return onBehalfOf;
        }

        if (
            selector == IAaveV3LikePool.withdraw.selector
                || selector == IAaveV3LikePool.setUserUseReserveAsCollateral.selector
                || selector == IAaveV3LikePool.setUserEMode.selector
        ) {
            return caller;
        }

        if (selector == IAaveV3LikePool.finalizeTransfer.selector) {
            (, address from,,,,) = abi.decode(input, (address, address, address, uint256, uint256, uint256));
            return from;
        }

        if (selector == IAaveV3LikePool.liquidationCall.selector) {
            (,, address user,,) = abi.decode(input, (address, address, address, uint256, bool));
            return user;
        }

        return address(0);
    }
}
