// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {CredibleTest} from "credible-std/CredibleTest.sol";
import {AaveV3HorizonOracleAssertion} from "../src/AaveV3HorizonOracleAssertion.sol";

contract OracleGuardSource {
    int256 internal answer;

    constructor(int256 answer_) {
        answer = answer_;
    }

    function setAnswer(int256 answer_) external {
        answer = answer_;
    }

    function latestAnswer() external view returns (int256) {
        return answer;
    }
}

contract OracleGuardFallback {
    mapping(address => uint256) internal prices;

    function setPrice(address asset, uint256 price) external {
        prices[asset] = price;
    }

    function getAssetPrice(address asset) external view returns (uint256) {
        return prices[asset];
    }
}

/// @dev Storage order intentionally matches the pinned AaveOracle layout:
///      assetsSources mapping at slot 0 and fallback oracle at slot 1.
contract OracleGuardOracle {
    mapping(address => address) internal assetsSources;
    address internal fallbackOracle;

    constructor(address fallbackOracle_) {
        fallbackOracle = fallbackOracle_;
    }

    function setSource(address asset, address source) external {
        assetsSources[asset] = source;
    }

    function setFallbackOracle(address fallbackOracle_) external {
        fallbackOracle = fallbackOracle_;
    }

    function getSourceOfAsset(address asset) external view returns (address) {
        return assetsSources[asset];
    }

    function getFallbackOracle() external view returns (address) {
        return fallbackOracle;
    }

    function getAssetPrice(address asset) external view returns (uint256) {
        address source = assetsSources[asset];
        if (source == address(0)) {
            return OracleGuardFallback(fallbackOracle).getAssetPrice(asset);
        }

        int256 answer = OracleGuardSource(source).latestAnswer();
        if (answer <= 0) {
            return OracleGuardFallback(fallbackOracle).getAssetPrice(asset);
        }
        return uint256(answer);
    }
}

contract OracleGuardProvider {
    address internal oracle;

    constructor(address oracle_) {
        oracle = oracle_;
    }

    function setPriceOracle(address oracle_) external {
        oracle = oracle_;
    }

    function getPriceOracle() external view returns (address) {
        return oracle;
    }
}

interface IOracleGuardFlashReceiver {
    function executeOperation() external;
}

contract OracleGuardPool {
    OracleGuardProvider internal immutable provider;
    address[] internal assets;
    bool internal consumePrices = true;

    constructor(OracleGuardProvider provider_, address[] memory assets_) {
        provider = provider_;
        assets = assets_;
    }

    function addAsset(address asset) external {
        assets.push(asset);
    }

    function setConsumePrices(bool enabled) external {
        consumePrices = enabled;
    }

    function getReservesList() external view returns (address[] memory) {
        return assets;
    }

    function borrow(address, uint256 amount, uint256, uint16, address) external {
        require(amount != 0, "zero borrow");
        _consumePrices();
        require(amount != type(uint256).max, "forced post-price revert");
    }

    function withdraw(address, uint256 amount, address) external returns (uint256) {
        _consumePrices();
        return amount;
    }

    function liquidationCall(address, address, address, uint256, bool) external {
        _consumePrices();
    }

    function setUserUseReserveAsCollateral(address, bool) external {
        _consumePrices();
    }

    function setUserEMode(uint8) external {
        _consumePrices();
    }

    function finalizeTransfer(address, address, address, uint256, uint256, uint256) external {
        _consumePrices();
    }

    function flashLoan(
        address receiverAddress,
        address[] calldata,
        uint256[] calldata,
        uint256[] calldata,
        address,
        bytes calldata,
        uint16
    ) external {
        IOracleGuardFlashReceiver(receiverAddress).executeOperation();
        _consumePrices();
    }

    function _consumePrices() internal view {
        if (!consumePrices) {
            return;
        }
        OracleGuardOracle oracle = OracleGuardOracle(provider.getPriceOracle());
        for (uint256 i; i < assets.length; ++i) {
            oracle.getAssetPrice(assets[i]);
        }
    }
}

contract OracleGuardFlashReceiver is IOracleGuardFlashReceiver {
    OracleGuardSource internal immutable source;
    int256 internal immutable temporaryAnswer;

    constructor(OracleGuardSource source_, int256 temporaryAnswer_) {
        source = source_;
        temporaryAnswer = temporaryAnswer_;
    }

    function executeOperation() external {
        source.setAnswer(temporaryAnswer);
    }
}

contract OracleGuardBundle {
    function priceBorrowRestore(
        OracleGuardSource source,
        int256 temporaryAnswer,
        int256 restoredAnswer,
        OracleGuardPool pool,
        address asset
    ) external {
        source.setAnswer(temporaryAnswer);
        pool.borrow(asset, 1, 2, 0, address(this));
        source.setAnswer(restoredAnswer);
    }

    function sourceBorrowRestore(
        OracleGuardOracle oracle,
        address asset,
        address temporarySource,
        address restoredSource,
        OracleGuardPool pool
    ) external {
        oracle.setSource(asset, temporarySource);
        pool.borrow(asset, 1, 2, 0, address(this));
        oracle.setSource(asset, restoredSource);
    }

    function fallbackBorrowRestore(
        OracleGuardOracle oracle,
        address temporaryFallback,
        address restoredFallback,
        OracleGuardPool pool,
        address asset
    ) external {
        oracle.setFallbackOracle(temporaryFallback);
        pool.borrow(asset, 1, 2, 0, address(this));
        oracle.setFallbackOracle(restoredFallback);
    }

    function providerBorrowRestore(
        OracleGuardProvider provider,
        address temporaryOracle,
        address restoredOracle,
        OracleGuardPool pool,
        address asset
    ) external {
        provider.setPriceOracle(temporaryOracle);
        pool.borrow(asset, 1, 2, 0, address(this));
        provider.setPriceOracle(restoredOracle);
    }

    function twoBorrows(OracleGuardPool pool, address asset) external {
        pool.borrow(asset, 1, 2, 0, address(this));
        pool.borrow(asset, 1, 2, 0, address(this));
    }

    function successfulThenCaughtManipulatedBorrow(
        OracleGuardPool pool,
        OracleGuardSource source,
        int256 temporaryAnswer,
        int256 restoredAnswer,
        address asset
    ) external {
        pool.borrow(asset, 1, 2, 0, address(this));
        source.setAnswer(temporaryAnswer);
        (bool ok,) =
            address(pool).call(abi.encodeCall(OracleGuardPool.borrow, (asset, type(uint256).max, 2, 0, address(this))));
        require(!ok, "forced borrow unexpectedly succeeded");
        source.setAnswer(restoredAnswer);
    }

    function flashManipulateRestore(
        OracleGuardPool pool,
        OracleGuardFlashReceiver receiver,
        OracleGuardSource source,
        int256 restoredAnswer,
        address asset
    ) external {
        address[] memory assets = new address[](1);
        assets[0] = asset;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1;
        uint256[] memory modes = new uint256[](1);
        modes[0] = 2;

        pool.flashLoan(address(receiver), assets, amounts, modes, address(this), "", 0);
        source.setAnswer(restoredAnswer);
    }
}

contract AaveV3HorizonOracleAssertionTest is Test, CredibleTest {
    uint256 internal constant MAX_TRACE_CALLS = 16;
    uint256 internal constant DEVIATION_BPS = 100;
    int256 internal constant PRICE = 100_00000000;

    address internal asset0 = makeAddr("asset0");
    address internal asset1 = makeAddr("asset1");

    OracleGuardSource internal source0;
    OracleGuardSource internal source1;
    OracleGuardSource internal temporarySource;
    OracleGuardFallback internal fallbackOracle;
    OracleGuardFallback internal secondFallbackOracle;
    OracleGuardOracle internal oracle;
    OracleGuardOracle internal secondOracle;
    OracleGuardProvider internal provider;
    OracleGuardPool internal pool;
    OracleGuardBundle internal bundle;

    function setUp() public {
        source0 = new OracleGuardSource(PRICE);
        source1 = new OracleGuardSource(PRICE);
        temporarySource = new OracleGuardSource(2 * PRICE);
        fallbackOracle = new OracleGuardFallback();
        secondFallbackOracle = new OracleGuardFallback();
        oracle = new OracleGuardOracle(address(fallbackOracle));
        secondOracle = new OracleGuardOracle(address(fallbackOracle));
        provider = new OracleGuardProvider(address(oracle));

        oracle.setSource(asset0, address(source0));
        oracle.setSource(asset1, address(source1));
        secondOracle.setSource(asset0, address(source0));
        secondOracle.setSource(asset1, address(source1));

        address[] memory assets = new address[](2);
        assets[0] = asset0;
        assets[1] = asset1;
        pool = new OracleGuardPool(provider, assets);
        bundle = new OracleGuardBundle();
    }

    function testStableBorrowPassesBelowThreeMillionGas() public {
        _arm(MAX_TRACE_CALLS);
        pool.borrow(asset0, 1, 2, 0, address(this));
    }

    function testBorrowWithoutProviderOrPriceReadFailsClosed() public {
        pool.setConsumePrices(false);
        _arm(MAX_TRACE_CALLS);
        vm.expectRevert(bytes("AaveV3Horizon: Pool skipped oracle provider"));
        pool.borrow(asset0, 1, 2, 0, address(this));
    }

    function testStableMulticallPassesBelowThreeMillionGas() public {
        _arm(MAX_TRACE_CALLS);
        bundle.twoBorrows(pool, asset0);
    }

    function testCaughtRevertedPriceConsumptionIsExcluded() public {
        _arm(MAX_TRACE_CALLS);
        bundle.successfulThenCaughtManipulatedBorrow(pool, source1, 2 * PRICE, PRICE, asset0);
    }

    function testTemporaryPriceManipulationAndRestoreTrips() public {
        _arm(MAX_TRACE_CALLS);
        vm.expectRevert(bytes("AaveV3Horizon: consumed oracle price deviated"));
        bundle.priceBorrowRestore(source1, 2 * PRICE, PRICE, pool, asset0);
    }

    function testPriceMovementInsideConfiguredTolerancePasses() public {
        _arm(MAX_TRACE_CALLS);
        bundle.priceBorrowRestore(source1, 100_50000000, PRICE, pool, asset0);
    }

    function testTemporarySourceSwapAndRestoreTrips() public {
        _arm(MAX_TRACE_CALLS);
        vm.expectRevert(bytes("AaveV3Horizon: reserve oracle source changed during transaction"));
        bundle.sourceBorrowRestore(oracle, asset1, address(temporarySource), address(source1), pool);
    }

    function testTemporaryFallbackSwapAndRestoreTrips() public {
        _arm(MAX_TRACE_CALLS);
        vm.expectRevert(bytes("AaveV3Horizon: fallback oracle changed during transaction"));
        bundle.fallbackBorrowRestore(oracle, address(secondFallbackOracle), address(fallbackOracle), pool, asset0);
    }

    function testTemporaryProviderSwapAndRestoreTrips() public {
        _arm(MAX_TRACE_CALLS);
        vm.expectRevert(bytes("AaveV3Horizon: Pool consumed a different oracle"));
        bundle.providerBorrowRestore(provider, address(secondOracle), address(oracle), pool, asset0);
    }

    function testFlashLoanCallbackManipulationAndRestoreTrips() public {
        OracleGuardFlashReceiver receiver = new OracleGuardFlashReceiver(source1, 2 * PRICE);

        _arm(MAX_TRACE_CALLS);
        vm.expectRevert(bytes("AaveV3Horizon: consumed oracle price deviated"));
        bundle.flashManipulateRestore(pool, receiver, source1, PRICE, asset0);
    }

    function testIncompleteAssetConfigurationFailsClosed() public {
        address asset2 = makeAddr("asset2");
        OracleGuardSource source2 = new OracleGuardSource(PRICE);
        oracle.setSource(asset2, address(source2));
        pool.addAsset(asset2);

        _arm(MAX_TRACE_CALLS);
        vm.expectRevert(bytes("AaveV3Horizon: unrecognized Pool oracle price path"));
        pool.borrow(asset0, 1, 2, 0, address(this));
    }

    function testIncompleteAssetConfigurationWithSharedSourceFailsClosed() public {
        address asset2 = makeAddr("asset2");
        oracle.setSource(asset2, address(source1));
        pool.addAsset(asset2);

        _arm(MAX_TRACE_CALLS);
        vm.expectRevert(bytes("AaveV3Horizon: unrecognized Pool oracle price path"));
        pool.borrow(asset0, 1, 2, 0, address(this));
    }

    function testTraceCallBoundFailsClosed() public {
        _arm(1);
        vm.expectRevert(bytes("AaveV3Horizon: too many oracle calls"));
        pool.borrow(asset0, 1, 2, 0, address(this));
    }

    /// @dev Same-transaction comparison cannot detect a baseline already corrupted before PreTx.
    function testPreExistingManipulationRemainsOutOfScope() public {
        source1.setAnswer(2 * PRICE);

        _arm(MAX_TRACE_CALLS);
        pool.borrow(asset0, 1, 2, 0, address(this));
    }

    function testFullRangeToleranceIsRejected() public {
        AaveV3HorizonOracleAssertion.AssetPolicy[] memory policies =
            new AaveV3HorizonOracleAssertion.AssetPolicy[](1);
        policies[0] = AaveV3HorizonOracleAssertion.AssetPolicy({asset: asset0, deviationBps: 10_000});

        vm.expectRevert(bytes("AaveV3Horizon: bad asset tolerance"));
        new AaveV3HorizonOracleAssertion(address(pool), address(provider), MAX_TRACE_CALLS, policies);
    }

    function _arm(uint256 maxTraceCalls) internal {
        AaveV3HorizonOracleAssertion.AssetPolicy[] memory policies = new AaveV3HorizonOracleAssertion.AssetPolicy[](2);
        policies[0] = AaveV3HorizonOracleAssertion.AssetPolicy({asset: asset0, deviationBps: DEVIATION_BPS});
        policies[1] = AaveV3HorizonOracleAssertion.AssetPolicy({asset: asset1, deviationBps: DEVIATION_BPS});

        bytes memory createData = abi.encodePacked(
            type(AaveV3HorizonOracleAssertion).creationCode,
            abi.encode(address(pool), address(provider), maxTraceCalls, policies)
        );
        cl.assertion(address(pool), createData, AaveV3HorizonOracleAssertion.assertConsumedOraclePricesSafe.selector);
    }
}
