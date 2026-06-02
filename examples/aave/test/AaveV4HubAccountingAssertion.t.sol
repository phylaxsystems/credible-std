// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {AaveV4HubAccountingAssertion} from "../src/AaveV4HubAccountingAssertion.sol";
import {IAaveV4Hub} from "../src/AaveV4Interfaces.sol";

contract MockAaveV4Hub {
    IAaveV4Hub.Asset internal asset;
    bool internal breakSpokeSum;

    constructor() {
        asset.drawnIndex = 1;
    }

    function setBreakSpokeSum(bool enabled) external {
        breakSpokeSum = enabled;
    }

    function add(uint256, uint256) external returns (uint256) {
        if (breakSpokeSum) {
            asset.addedShares = 1;
        }
        return 0;
    }

    function remove(uint256, uint256, address) external pure returns (uint256) {
        return 0;
    }

    function draw(uint256, uint256, address) external pure returns (uint256) {
        return 0;
    }

    function restore(uint256, uint256, IAaveV4Hub.PremiumDelta calldata) external pure returns (uint256) {
        return 0;
    }

    function reportDeficit(uint256, uint256, IAaveV4Hub.PremiumDelta calldata)
        external
        pure
        returns (uint256, uint256)
    {
        return (0, 0);
    }

    function refreshPremium(uint256, IAaveV4Hub.PremiumDelta calldata) external pure {}

    function payFeeShares(uint256, uint256) external pure {}

    function transferShares(uint256, uint256, address) external pure {}

    function mintFeeShares(uint256) external pure returns (uint256) {
        return 0;
    }

    function eliminateDeficit(uint256, uint256, address) external pure returns (uint256, uint256) {
        return (0, 0);
    }

    function sweep(uint256, uint256) external pure {}

    function reclaim(uint256, uint256) external pure {}

    function updateAssetConfig(uint256, IAaveV4Hub.AssetConfig calldata, bytes calldata) external pure {}

    function addSpoke(uint256, address, IAaveV4Hub.SpokeConfig calldata) external pure {}

    function updateSpokeConfig(uint256, address, IAaveV4Hub.SpokeConfig calldata) external pure {}

    function setInterestRateData(uint256, bytes calldata) external pure {}

    function getAsset(uint256) external view returns (IAaveV4Hub.Asset memory) {
        return asset;
    }

    function getSpokeCount(uint256) external pure returns (uint256) {
        return 0;
    }

    function getAddedAssets(uint256) external pure returns (uint256) {
        return 0;
    }
}

contract AaveV4HubAccountingAssertionTest is Test, CredibleTest {
    MockAaveV4Hub internal hub;

    function setUp() public {
        hub = new MockAaveV4Hub();
    }

    function _arm() internal {
        bytes memory createData =
            abi.encodePacked(type(AaveV4HubAccountingAssertion).creationCode, abi.encode(address(hub), 1, 4, 0));
        cl.assertion(address(hub), createData, AaveV4HubAccountingAssertion.assertHubAssetAccounting.selector);
    }

    function testHubAccountingPassesWhenSpokeSumsMatch() public {
        _arm();
        hub.add(1, 0);
    }

    function testHubAccountingTripsOnAggregateSpokeMismatch() public {
        hub.setBreakSpokeSum(true);

        _arm();
        vm.expectRevert(bytes("AaveV4Hub: added shares mismatch"));
        hub.add(1, 0);
    }
}
