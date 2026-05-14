// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "../../../PhEvm.sol";

import {AaveV4Helpers} from "./AaveV4Helpers.sol";
import {IAaveV4Hub} from "./AaveV4Interfaces.sol";

/// @title AaveV4HubAccountingAssertion
/// @author Phylax Systems
/// @notice Example assertion for one Aave v4 Hub asset.
/// @dev Protects cross-spoke accounting that is not expressed by a single Hub `require`:
///      - Hub aggregate shares, premium data, and deficits match the sum of listed Spokes.
///      - Hub added assets cover the sum of each Spoke's converted added assets.
///      - Drawn index and added-asset share price do not move backwards across Hub mutations.
contract AaveV4HubAccountingAssertion is AaveV4Helpers {
    address internal immutable HUB;
    uint256 internal immutable ASSET_ID;
    uint256 internal immutable MAX_SPOKES_TO_SCAN;
    uint256 internal immutable SHARE_PRICE_TOLERANCE_BPS;

    constructor(address hub_, uint256 assetId_, uint256 maxSpokesToScan_, uint256 sharePriceToleranceBps_) {
        require(hub_ != address(0), "AaveV4Hub: hub zero");
        require(maxSpokesToScan_ > 0, "AaveV4Hub: max spokes zero");
        require(sharePriceToleranceBps_ <= BPS, "AaveV4Hub: bad tolerance");

        HUB = hub_;
        ASSET_ID = assetId_;
        MAX_SPOKES_TO_SCAN = maxSpokesToScan_;
        SHARE_PRICE_TOLERANCE_BPS = sharePriceToleranceBps_;
    }

    /// @notice Registers Hub mutators that can change aggregate accounting, indices, or spoke sums.
    /// @dev The assertion is configured for one `assetId`; calls for other assets no-op after
    ///      decoding the first calldata argument.
    function triggers() external view override {
        registerFnCallTrigger(this.assertHubAssetAccounting.selector, IAaveV4Hub.add.selector);
        registerFnCallTrigger(this.assertHubAssetAccounting.selector, IAaveV4Hub.remove.selector);
        registerFnCallTrigger(this.assertHubAssetAccounting.selector, IAaveV4Hub.draw.selector);
        registerFnCallTrigger(this.assertHubAssetAccounting.selector, IAaveV4Hub.restore.selector);
        registerFnCallTrigger(this.assertHubAssetAccounting.selector, IAaveV4Hub.reportDeficit.selector);
        registerFnCallTrigger(this.assertHubAssetAccounting.selector, IAaveV4Hub.refreshPremium.selector);
        registerFnCallTrigger(this.assertHubAssetAccounting.selector, IAaveV4Hub.payFeeShares.selector);
        registerFnCallTrigger(this.assertHubAssetAccounting.selector, IAaveV4Hub.transferShares.selector);
        registerFnCallTrigger(this.assertHubAssetAccounting.selector, IAaveV4Hub.mintFeeShares.selector);
        registerFnCallTrigger(this.assertHubAssetAccounting.selector, IAaveV4Hub.eliminateDeficit.selector);
        registerFnCallTrigger(this.assertHubAssetAccounting.selector, IAaveV4Hub.sweep.selector);
        registerFnCallTrigger(this.assertHubAssetAccounting.selector, IAaveV4Hub.reclaim.selector);
        registerFnCallTrigger(this.assertHubAssetAccounting.selector, IAaveV4Hub.updateAssetConfig.selector);
        registerFnCallTrigger(this.assertHubAssetAccounting.selector, IAaveV4Hub.addSpoke.selector);
        registerFnCallTrigger(this.assertHubAssetAccounting.selector, IAaveV4Hub.updateSpokeConfig.selector);
        registerFnCallTrigger(this.assertHubAssetAccounting.selector, IAaveV4Hub.setInterestRateData.selector);
    }

    /// @notice Checks one Hub asset remains backed and internally coherent after a Hub mutation.
    /// @dev Reads the Hub's aggregate asset state and enumerates listed Spokes at the post-call
    ///      fork. A failure means cross-Spoke accounting no longer agrees with Hub totals,
    ///      Spoke-level added assets exceed Hub added assets, or a monotonic index moved backwards.
    function assertHubAssetAccounting() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        _requireAdopter(HUB, "AaveV4Hub: configured hub is not adopter");

        if (_firstUint256Arg(ph.callinputAt(ctx.callStart)) != ASSET_ID) {
            return;
        }

        PhEvm.ForkId memory pre = _preCall(ctx.callStart);
        PhEvm.ForkId memory post = _postCall(ctx.callEnd);
        IAaveV4Hub.Asset memory preAsset = _hubAssetAt(HUB, ASSET_ID, pre);
        IAaveV4Hub.Asset memory postAsset = _hubAssetAt(HUB, ASSET_ID, post);

        _assertSpokeSums(postAsset, post);
        _assertMonotonicAssetRatios(preAsset, postAsset, pre, post);
    }

    function _assertSpokeSums(IAaveV4Hub.Asset memory asset, PhEvm.ForkId memory fork) internal view {
        uint256 count = _readUintAt(HUB, abi.encodeCall(IAaveV4Hub.getSpokeCount, (ASSET_ID)), fork);
        require(count <= MAX_SPOKES_TO_SCAN, "AaveV4Hub: too many spokes");

        uint256 addedShares;
        uint256 drawnShares;
        uint256 premiumShares;
        int256 premiumOffsetRay;
        uint256 deficitRay;
        uint256 spokeAddedAssets;

        for (uint256 i; i < count; ++i) {
            address spoke = _readAddressAt(HUB, abi.encodeCall(IAaveV4Hub.getSpokeAddress, (ASSET_ID, i)), fork);
            IAaveV4Hub.SpokeData memory spokeData = _hubSpokeAt(HUB, ASSET_ID, spoke, fork);
            addedShares += spokeData.addedShares;
            drawnShares += spokeData.drawnShares;
            premiumShares += spokeData.premiumShares;
            premiumOffsetRay += spokeData.premiumOffsetRay;
            deficitRay += spokeData.deficitRay;
            spokeAddedAssets += _hubSpokeAddedAssetsAt(HUB, ASSET_ID, spoke, fork);
        }

        require(addedShares == asset.addedShares, "AaveV4Hub: added shares mismatch");
        require(drawnShares == asset.drawnShares, "AaveV4Hub: drawn shares mismatch");
        require(premiumShares == asset.premiumShares, "AaveV4Hub: premium shares mismatch");
        require(premiumOffsetRay == asset.premiumOffsetRay, "AaveV4Hub: premium offset mismatch");
        require(deficitRay == asset.deficitRay, "AaveV4Hub: deficit mismatch");
        require(
            _readUintAt(HUB, abi.encodeCall(IAaveV4Hub.getAddedAssets, (ASSET_ID)), fork) >= spokeAddedAssets,
            "AaveV4Hub: spoke assets exceed added assets"
        );
    }

    function _assertMonotonicAssetRatios(
        IAaveV4Hub.Asset memory preAsset,
        IAaveV4Hub.Asset memory postAsset,
        PhEvm.ForkId memory pre,
        PhEvm.ForkId memory post
    ) internal view {
        require(postAsset.drawnIndex >= preAsset.drawnIndex, "AaveV4Hub: drawn index decreased");

        uint256 preShares = preAsset.addedShares;
        uint256 postShares = postAsset.addedShares;
        if (preShares == 0 || postShares == 0) {
            return;
        }

        uint256 preAssets = _readUintAt(HUB, abi.encodeCall(IAaveV4Hub.getAddedAssets, (ASSET_ID)), pre);
        uint256 postAssets = _readUintAt(HUB, abi.encodeCall(IAaveV4Hub.getAddedAssets, (ASSET_ID)), post);

        require(
            ph.ratioGe(postAssets, postShares, preAssets, preShares, SHARE_PRICE_TOLERANCE_BPS),
            "AaveV4Hub: added share price decreased"
        );
    }
}
