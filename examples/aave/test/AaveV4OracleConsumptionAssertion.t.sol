// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {CredibleTest} from "credible-std/CredibleTest.sol";
import {
    AaveV4EthereumMainSpokeOracleAssertion,
    AaveV4OracleConsumptionAssertion
} from "../src/AaveV4OracleConsumptionAssertion.sol";
import {IAaveV4Spoke} from "../src/AaveV4Interfaces.sol";

contract MockV4PriceFeed {
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

    function decimals() external pure returns (uint8) {
        return 8;
    }
}

contract MockV4AdapterFeed {
    MockV4PriceFeed public innerSource;

    constructor(MockV4PriceFeed innerSource_) {
        innerSource = innerSource_;
    }

    function setInnerSource(MockV4PriceFeed innerSource_) external {
        innerSource = innerSource_;
    }

    function latestAnswer() external view returns (int256) {
        return innerSource.latestAnswer();
    }

    function decimals() external pure returns (uint8) {
        return 8;
    }
}

/// @dev Storage deliberately matches Aave v4.0.0 v0.5.11 AaveOracle:
///      `spoke` is slot 0 and `_sources` is the uint256-keyed mapping at slot 1.
contract MockV4Oracle {
    address public spoke;
    mapping(uint256 reserveId => address source) internal sources;

    constructor(address spoke_) {
        spoke = spoke_;
    }

    function setSpoke(address spoke_) external {
        spoke = spoke_;
    }

    function decimals() external pure returns (uint8) {
        return 8;
    }

    function setReserveSource(uint256 reserveId, address source) external {
        require(MockV4PriceFeed(source).decimals() == 8, "bad source decimals");
        require(MockV4PriceFeed(source).latestAnswer() > 0, "bad source answer");
        sources[reserveId] = source;
    }

    function getReserveSource(uint256 reserveId) external view returns (address) {
        return sources[reserveId];
    }

    function getReservePrice(uint256 reserveId) public view returns (uint256) {
        address source = sources[reserveId];
        require(source != address(0), "source not set");
        int256 price = MockV4PriceFeed(source).latestAnswer();
        require(price > 0, "invalid price");
        return uint256(price);
    }

    function getReservesPrices(uint256[] calldata reserveIds) external view returns (uint256[] memory prices) {
        prices = new uint256[](reserveIds.length);
        for (uint256 i; i < reserveIds.length; ++i) {
            prices[i] = getReservePrice(reserveIds[i]);
        }
    }
}

contract MockV4Spoke {
    address public immutable ORACLE;
    IAaveV4Spoke.Reserve[] internal reserves;
    bool internal readUnknownReserve;
    bool internal consumePrices = true;

    constructor(address oracle_) {
        ORACLE = oracle_;
    }

    function addReserve(address asset) external {
        reserves.push(
            IAaveV4Spoke.Reserve({
                underlying: asset,
                hub: address(0xBEEF),
                assetId: uint16(reserves.length),
                decimals: 18,
                collateralRisk: 0,
                flags: 0,
                dynamicConfigKey: 0
            })
        );
    }

    function setReadUnknownReserve(bool enabled) external {
        readUnknownReserve = enabled;
    }

    function setConsumePrices(bool enabled) external {
        consumePrices = enabled;
    }

    function getReserveCount() external view returns (uint256) {
        return reserves.length;
    }

    function getReserve(uint256 reserveId) external view returns (IAaveV4Spoke.Reserve memory) {
        return reserves[reserveId];
    }

    function supply(uint256, uint256, address) external pure returns (uint256, uint256) {
        return (0, 0);
    }

    function repay(uint256, uint256, address) external pure returns (uint256, uint256) {
        return (0, 0);
    }

    function withdraw(uint256, uint256 amount, address) external view returns (uint256, uint256) {
        _consumePrices();
        return (amount, 0);
    }

    function borrow(uint256, uint256 amount, address) external view returns (uint256, uint256) {
        _consumePrices();
        require(amount != type(uint256).max, "forced post-price revert");
        return (amount, 0);
    }

    function liquidationCall(uint256, uint256, address, uint256, bool) external view {
        _consumePrices();
    }

    function setUsingAsCollateral(uint256, bool usingAsCollateral, address) external view {
        if (!usingAsCollateral) {
            _consumePrices();
        }
    }

    function updateUserRiskPremium(address) external view {
        _consumePrices();
    }

    function updateUserDynamicConfig(address) external view {
        _consumePrices();
    }

    function multicall(bytes[] calldata calls) external returns (bytes[] memory results) {
        results = new bytes[](calls.length);
        for (uint256 i; i < calls.length; ++i) {
            (bool success, bytes memory result) = address(this).delegatecall(calls[i]);
            require(success, "multicall leg failed");
            results[i] = result;
        }
    }

    function _consumePrices() internal view {
        if (!consumePrices) {
            return;
        }
        MockV4Oracle oracle = MockV4Oracle(ORACLE);
        for (uint256 i; i < reserves.length; ++i) {
            oracle.getReservePrice(i);
        }
        if (readUnknownReserve) {
            oracle.getReservePrice(reserves.length);
        }
    }
}

interface INestedV4Callback {
    function execute() external;
}

contract NestedV4CallbackReceiver is INestedV4Callback {
    MockV4PriceFeed internal immutable source;
    MockV4Spoke internal immutable spoke;
    int256 internal immutable temporaryPrice;
    int256 internal immutable restoredPrice;

    constructor(MockV4PriceFeed source_, MockV4Spoke spoke_, int256 temporaryPrice_, int256 restoredPrice_) {
        source = source_;
        spoke = spoke_;
        temporaryPrice = temporaryPrice_;
        restoredPrice = restoredPrice_;
    }

    function execute() external {
        source.setAnswer(temporaryPrice);
        spoke.borrow(0, 1, address(this));
        source.setAnswer(restoredPrice);
    }
}

contract V4OracleScenarioDriver {
    function priceBorrowRestore(MockV4PriceFeed source, int256 temporaryPrice, int256 restoredPrice, MockV4Spoke spoke)
        external
    {
        source.setAnswer(temporaryPrice);
        spoke.borrow(0, 1, address(this));
        source.setAnswer(restoredPrice);
    }

    function sourceBorrowRestore(
        MockV4Oracle oracle,
        uint256 reserveId,
        address temporarySource,
        address restoredSource,
        MockV4Spoke spoke
    ) external {
        oracle.setReserveSource(reserveId, temporarySource);
        spoke.borrow(0, 1, address(this));
        oracle.setReserveSource(reserveId, restoredSource);
    }

    function adapterBorrowRestore(
        MockV4AdapterFeed adapter,
        MockV4PriceFeed temporaryInnerSource,
        MockV4PriceFeed restoredInnerSource,
        MockV4Spoke spoke
    ) external {
        adapter.setInnerSource(temporaryInnerSource);
        spoke.borrow(0, 1, address(this));
        adapter.setInnerSource(restoredInnerSource);
    }

    function twoBorrows(MockV4Spoke spoke) external {
        spoke.borrow(0, 1, address(this));
        spoke.borrow(1, 1, address(this));
    }

    function manipulatedMulticall(
        MockV4PriceFeed source,
        int256 temporaryPrice,
        int256 restoredPrice,
        MockV4Spoke spoke
    ) external {
        source.setAnswer(temporaryPrice);
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeCall(MockV4Spoke.borrow, (0, 1, address(this)));
        calls[1] = abi.encodeCall(MockV4Spoke.updateUserRiskPremium, (address(this)));
        spoke.multicall(calls);
        source.setAnswer(restoredPrice);
    }

    function successfulThenCaughtRevertedBorrow(
        MockV4Spoke spoke,
        MockV4PriceFeed source,
        int256 temporaryPrice,
        int256 restoredPrice
    ) external {
        spoke.borrow(0, 1, address(this));
        source.setAnswer(temporaryPrice);
        (bool success,) = address(spoke).call(abi.encodeCall(MockV4Spoke.borrow, (0, type(uint256).max, address(this))));
        require(!success, "forced borrow unexpectedly succeeded");
        source.setAnswer(restoredPrice);
    }

    function invokeCallback(INestedV4Callback receiver) external {
        receiver.execute();
    }
}

contract MockV4SpokeImplementation {
    address public immutable ORACLE;
    address internal immutable ASSET;

    constructor(address oracle_, address asset_) {
        ORACLE = oracle_;
        ASSET = asset_;
    }

    function getReserveCount() external pure returns (uint256) {
        return 1;
    }

    function getReserve(uint256 reserveId) external view returns (IAaveV4Spoke.Reserve memory) {
        require(reserveId == 0, "unknown reserve");
        return IAaveV4Spoke.Reserve({
            underlying: ASSET,
            hub: address(0xBEEF),
            assetId: 0,
            decimals: 18,
            collateralRisk: 0,
            flags: 0,
            dynamicConfigKey: 0
        });
    }

    function borrow(uint256, uint256 amount, address) external view returns (uint256, uint256) {
        MockV4Oracle(ORACLE).getReservePrice(0);
        return (amount, 0);
    }
}

contract MinimalV4SpokeProxy {
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    constructor(address implementation_) {
        _setImplementation(implementation_);
    }

    function upgradeTo(address implementation_) external {
        _setImplementation(implementation_);
    }

    function _setImplementation(address implementation_) internal {
        bytes32 slot = IMPLEMENTATION_SLOT;
        assembly ("memory-safe") {
            sstore(slot, implementation_)
        }
    }

    fallback() external payable {
        bytes32 slot = IMPLEMENTATION_SLOT;
        assembly ("memory-safe") {
            let implementation := sload(slot)
            calldatacopy(0, 0, calldatasize())
            let success := delegatecall(gas(), implementation, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            if iszero(success) { revert(0, returndatasize()) }
            return(0, returndatasize())
        }
    }
}

contract V4UpgradeScenarioDriver {
    function upgradeBorrowRestore(
        MinimalV4SpokeProxy proxy,
        address temporaryImplementation,
        address restoredImplementation
    ) external {
        proxy.upgradeTo(temporaryImplementation);
        IAaveV4Spoke(address(proxy)).borrow(0, 1, address(this));
        proxy.upgradeTo(restoredImplementation);
    }
}

contract AaveV4OracleConsumptionAssertionTest is Test, CredibleTest {
    uint256 internal constant MAX_TRACE_CALLS = 32;
    uint256 internal constant DEVIATION_BPS = 100;
    int256 internal constant PRICE = 100_00000000;

    address internal asset0 = makeAddr("v4 asset 0");
    address internal asset1 = makeAddr("v4 asset 1");

    MockV4Oracle internal oracle;
    MockV4Spoke internal spoke;
    MockV4PriceFeed internal source0;
    MockV4PriceFeed internal source1;
    MockV4PriceFeed internal temporarySource;
    V4OracleScenarioDriver internal driver;

    function setUp() public {
        oracle = new MockV4Oracle(address(0));
        spoke = new MockV4Spoke(address(oracle));
        oracle.setSpoke(address(spoke));

        source0 = new MockV4PriceFeed(PRICE);
        source1 = new MockV4PriceFeed(PRICE);
        temporarySource = new MockV4PriceFeed(2 * PRICE);
        oracle.setReserveSource(0, address(source0));
        oracle.setReserveSource(1, address(source1));
        spoke.addReserve(asset0);
        spoke.addReserve(asset1);
        driver = new V4OracleScenarioDriver();
    }

    function testHonestStablePriceOperation() public {
        _arm(MAX_TRACE_CALLS, DEVIATION_BPS, 2);
        spoke.borrow(0, 1, address(this));
    }

    function testBorrowWithoutPriceReadFailsClosed() public {
        _expectMandatoryPathWithoutPriceFails(abi.encodeCall(MockV4Spoke.borrow, (0, 1, address(this))));
    }

    function testWithdrawWithoutPriceReadFailsClosed() public {
        _expectMandatoryPathWithoutPriceFails(abi.encodeCall(MockV4Spoke.withdraw, (0, 1, address(this))));
    }

    function testLiquidationWithoutPriceReadFailsClosed() public {
        _expectMandatoryPathWithoutPriceFails(
            abi.encodeCall(MockV4Spoke.liquidationCall, (0, 1, address(this), 1, false))
        );
    }

    function testCollateralDisableWithoutPriceReadFailsClosed() public {
        _expectMandatoryPathWithoutPriceFails(
            abi.encodeCall(MockV4Spoke.setUsingAsCollateral, (0, false, address(this)))
        );
    }

    function testRiskPremiumRefreshWithoutPriceReadFailsClosed() public {
        _expectMandatoryPathWithoutPriceFails(abi.encodeCall(MockV4Spoke.updateUserRiskPremium, (address(this))));
    }

    function testDynamicConfigRefreshWithoutPriceReadFailsClosed() public {
        _expectMandatoryPathWithoutPriceFails(abi.encodeCall(MockV4Spoke.updateUserDynamicConfig, (address(this))));
    }

    function testHonestWithdrawPricePath() public {
        _arm(MAX_TRACE_CALLS, DEVIATION_BPS, 2);
        spoke.withdraw(0, 1, address(this));
    }

    function testHonestLiquidationPricePath() public {
        _arm(MAX_TRACE_CALLS, DEVIATION_BPS, 2);
        spoke.liquidationCall(0, 1, address(this), 1, false);
    }

    function testHonestCollateralDisablePricePath() public {
        _arm(MAX_TRACE_CALLS, DEVIATION_BPS, 2);
        spoke.setUsingAsCollateral(0, false, address(this));
    }

    function testHonestRiskPremiumRefreshPricePath() public {
        _arm(MAX_TRACE_CALLS, DEVIATION_BPS, 2);
        spoke.updateUserRiskPremium(address(this));
    }

    function testHonestDynamicConfigRefreshPricePath() public {
        _arm(MAX_TRACE_CALLS, DEVIATION_BPS, 2);
        spoke.updateUserDynamicConfig(address(this));
    }

    function testNonPriceCollateralEnablePathReturnsCleanly() public {
        _arm(MAX_TRACE_CALLS, DEVIATION_BPS, 2);
        spoke.setUsingAsCollateral(0, true, address(this));
    }

    function testSupplyIsCorrectlyOmittedAsNonPriceOperation() public {
        _arm(MAX_TRACE_CALLS, DEVIATION_BPS, 2);
        spoke.supply(0, 1, address(this));
    }

    function testRepayIsCorrectlyOmittedAsNonPriceOperation() public {
        _arm(MAX_TRACE_CALLS, DEVIATION_BPS, 2);
        spoke.repay(0, 1, address(this));
    }

    function testEthereumWrapperPinsCompleteReserveAndConfigPolicy() public {
        uint256[14] memory tolerances;
        for (uint256 i; i < tolerances.length; ++i) {
            tolerances[i] = i;
        }
        AaveV4OracleConsumptionAssertion.ConfigSlotGuard[] memory extra =
            new AaveV4OracleConsumptionAssertion.ConfigSlotGuard[](0);
        AaveV4EthereumMainSpokeOracleAssertion production =
            new AaveV4EthereumMainSpokeOracleAssertion(64, tolerances, extra);

        assertEq(production.reservePolicyCount(), 14);
        assertEq(production.configSlotGuardCount(), 22);
        for (uint256 i; i < tolerances.length; ++i) {
            AaveV4OracleConsumptionAssertion.ReservePolicy memory policy = production.reservePolicy(i);
            assertEq(policy.reserveId, i);
            assertEq(policy.deviationBps, i);
            assertTrue(policy.asset != address(0));
            assertTrue(policy.source != address(0));
        }
    }

    function testTemporaryFeedValueManipulationAndRestorationTrips() public {
        _arm(MAX_TRACE_CALLS, DEVIATION_BPS, 2);
        vm.expectRevert(bytes("AaveV4Oracle: consumed price deviated"));
        driver.priceBorrowRestore(source1, 2 * PRICE, PRICE, spoke);
    }

    function testTemporarySourceReplacementAndRestorationTrips() public {
        _arm(MAX_TRACE_CALLS, DEVIATION_BPS, 2);
        vm.expectRevert(bytes("AaveV4Oracle: reserve source written"));
        driver.sourceBorrowRestore(oracle, 1, address(temporarySource), address(source1), spoke);
    }

    function testTemporaryAdapterConfigurationAndRestorationTrips() public {
        MockV4AdapterFeed adapter = new MockV4AdapterFeed(source1);
        oracle.setReserveSource(1, address(adapter));

        AaveV4OracleConsumptionAssertion.ReservePolicy[] memory policies = _twoPolicies(DEVIATION_BPS, address(adapter));
        AaveV4OracleConsumptionAssertion.ConfigSlotGuard[] memory configGuards =
            new AaveV4OracleConsumptionAssertion.ConfigSlotGuard[](1);
        configGuards[0] = AaveV4OracleConsumptionAssertion.ConfigSlotGuard({target: address(adapter), slot: bytes32(0)});

        _armCustom(address(spoke), address(oracle), address(0), MAX_TRACE_CALLS, policies, configGuards);
        vm.expectRevert(bytes("AaveV4Oracle: guarded config written"));
        driver.adapterBorrowRestore(adapter, temporarySource, source1, spoke);
    }

    function testTemporarySpokeImplementationAndOracleRestorationTrips() public {
        address proxyAsset = makeAddr("proxy asset");
        MockV4Oracle canonicalOracle = new MockV4Oracle(address(0));
        MockV4Oracle temporaryOracle = new MockV4Oracle(address(0));
        MockV4PriceFeed canonicalSource = new MockV4PriceFeed(PRICE);
        MockV4PriceFeed manipulatedSource = new MockV4PriceFeed(2 * PRICE);
        canonicalOracle.setReserveSource(0, address(canonicalSource));
        temporaryOracle.setReserveSource(0, address(manipulatedSource));

        MockV4SpokeImplementation canonicalImplementation =
            new MockV4SpokeImplementation(address(canonicalOracle), proxyAsset);
        MockV4SpokeImplementation temporaryImplementation =
            new MockV4SpokeImplementation(address(temporaryOracle), proxyAsset);
        MinimalV4SpokeProxy proxy = new MinimalV4SpokeProxy(address(canonicalImplementation));
        canonicalOracle.setSpoke(address(proxy));
        temporaryOracle.setSpoke(address(proxy));
        V4UpgradeScenarioDriver upgradeDriver = new V4UpgradeScenarioDriver();

        AaveV4OracleConsumptionAssertion.ReservePolicy[] memory policies =
            new AaveV4OracleConsumptionAssertion.ReservePolicy[](1);
        policies[0] = AaveV4OracleConsumptionAssertion.ReservePolicy({
            reserveId: 0, asset: proxyAsset, source: address(canonicalSource), deviationBps: DEVIATION_BPS
        });
        AaveV4OracleConsumptionAssertion.ConfigSlotGuard[] memory configGuards =
            new AaveV4OracleConsumptionAssertion.ConfigSlotGuard[](0);
        _armCustom(
            address(proxy),
            address(canonicalOracle),
            address(canonicalImplementation),
            MAX_TRACE_CALLS,
            policies,
            configGuards
        );

        vm.expectRevert(bytes("AaveV4Oracle: implementation written"));
        upgradeDriver.upgradeBorrowRestore(proxy, address(temporaryImplementation), address(canonicalImplementation));
    }

    function testNestedCallbackManipulationAndRestorationTrips() public {
        NestedV4CallbackReceiver receiver = new NestedV4CallbackReceiver(source1, spoke, 2 * PRICE, PRICE);

        _arm(MAX_TRACE_CALLS, DEVIATION_BPS, 2);
        vm.expectRevert(bytes("AaveV4Oracle: consumed price deviated"));
        driver.invokeCallback(receiver);
    }

    function testMulticallAndMultipleOperationsTripOnManipulatedPrice() public {
        _arm(MAX_TRACE_CALLS, DEVIATION_BPS, 2);
        vm.expectRevert(bytes("AaveV4Oracle: consumed price deviated"));
        driver.manipulatedMulticall(source1, 2 * PRICE, PRICE, spoke);
    }

    function testSingleReserveStableMulticallPasses() public {
        MockV4Oracle oneOracle = new MockV4Oracle(address(0));
        MockV4Spoke oneSpoke = new MockV4Spoke(address(oneOracle));
        MockV4PriceFeed oneSource = new MockV4PriceFeed(PRICE);
        address oneAsset = makeAddr("single reserve multicall asset");
        oneOracle.setSpoke(address(oneSpoke));
        oneOracle.setReserveSource(0, address(oneSource));
        oneSpoke.addReserve(oneAsset);

        AaveV4OracleConsumptionAssertion.ReservePolicy[] memory policies =
            new AaveV4OracleConsumptionAssertion.ReservePolicy[](1);
        policies[0] = AaveV4OracleConsumptionAssertion.ReservePolicy({
            reserveId: 0, asset: oneAsset, source: address(oneSource), deviationBps: DEVIATION_BPS
        });
        AaveV4OracleConsumptionAssertion.ConfigSlotGuard[] memory configGuards =
            new AaveV4OracleConsumptionAssertion.ConfigSlotGuard[](0);
        _armCustom(address(oneSpoke), address(oneOracle), address(0), MAX_TRACE_CALLS, policies, configGuards);
        driver.twoBorrows(oneSpoke);
    }

    /// @dev The installed PCL 1.6.0 runner uses a legacy 300k test ceiling. The assertion's
    ///      measured 330k execution is below the production 3m ceiling but is rejected locally.
    function testTwoReserveMultipleOperationsMeasuresAboveLegacyLocalCeiling() public {
        _arm(MAX_TRACE_CALLS, DEVIATION_BPS, 2);
        vm.expectRevert(bytes("Assertion exceeded gas limit"));
        driver.twoBorrows(spoke);
    }

    function testCaughtRevertedPriceConsumingSubcallIsExcluded() public {
        _arm(MAX_TRACE_CALLS, DEVIATION_BPS, 2);
        driver.successfulThenCaughtRevertedBorrow(spoke, source1, 2 * PRICE, PRICE);
    }

    function testIncompletePolicyConfigurationFailsClosed() public {
        _arm(MAX_TRACE_CALLS, DEVIATION_BPS, 1);
        vm.expectRevert(bytes("AaveV4Oracle: incomplete reserve policy"));
        spoke.borrow(0, 1, address(this));
    }

    function testUnknownPriceConsumptionPathFailsClosed() public {
        MockV4PriceFeed source2 = new MockV4PriceFeed(PRICE);
        oracle.setReserveSource(2, address(source2));
        spoke.setReadUnknownReserve(true);

        _arm(MAX_TRACE_CALLS, DEVIATION_BPS, 2);
        vm.expectRevert(bytes("AaveV4Oracle: unconfigured price path"));
        spoke.borrow(0, 1, address(this));
    }

    function testTraceBoundExhaustionFailsClosed() public {
        _arm(1, DEVIATION_BPS, 2);
        vm.expectRevert(bytes("AaveV4Oracle: trace limit exceeded"));
        spoke.borrow(0, 1, address(this));
    }

    function testMovementInsideConfiguredTolerancePasses() public {
        _arm(MAX_TRACE_CALLS, DEVIATION_BPS, 2);
        driver.priceBorrowRestore(source1, 100_50000000, PRICE, spoke);
    }

    function testMovementOutsideConfiguredToleranceTrips() public {
        _arm(MAX_TRACE_CALLS, DEVIATION_BPS, 2);
        vm.expectRevert(bytes("AaveV4Oracle: consumed price deviated"));
        driver.priceBorrowRestore(source1, 101_00000001, PRICE, spoke);
    }

    function testZeroToleranceRequiresExactStability() public {
        _arm(MAX_TRACE_CALLS, 0, 2);
        vm.expectRevert(bytes("AaveV4Oracle: consumed price deviated"));
        driver.priceBorrowRestore(source1, PRICE + 1, PRICE, spoke);
    }

    function testFullRangeToleranceIsRejected() public {
        AaveV4OracleConsumptionAssertion.ReservePolicy[] memory policies = _twoPolicies(10_000, address(source1));
        AaveV4OracleConsumptionAssertion.ConfigSlotGuard[] memory configGuards =
            new AaveV4OracleConsumptionAssertion.ConfigSlotGuard[](0);

        vm.expectRevert(bytes("AaveV4Oracle: bad tolerance"));
        new AaveV4OracleConsumptionAssertion(
            address(spoke), address(oracle), address(0), MAX_TRACE_CALLS, policies, configGuards
        );
    }

    /// @dev Same-transaction protection cannot identify a baseline corrupted before PreTx.
    function testPreExistingManipulationIsDocumentedFalseNegative() public {
        source1.setAnswer(2 * PRICE);

        _arm(MAX_TRACE_CALLS, DEVIATION_BPS, 2);
        spoke.borrow(0, 1, address(this));
    }

    /// @dev Expected local-ceiling rejection still executes and reports the complete assertion gas.
    function testRealisticFourteenReserveGasScaling() public {
        (
            MockV4Oracle largeOracle,
            MockV4Spoke largeSpoke,
            AaveV4OracleConsumptionAssertion.ReservePolicy[] memory policies
        ) = _largeFixture();
        AaveV4OracleConsumptionAssertion.ConfigSlotGuard[] memory configGuards = _realisticConfigGuards();

        _armCustom(address(largeSpoke), address(largeOracle), address(0), 64, policies, configGuards);
        vm.expectRevert(bytes("Assertion exceeded gas limit"));
        largeSpoke.borrow(0, 1, address(this));
    }

    /// @dev Two full 14-reserve price sweeps approximate a realistic V4 multicall.
    function testRealisticFourteenReserveMulticallGasScaling() public {
        (
            MockV4Oracle largeOracle,
            MockV4Spoke largeSpoke,
            AaveV4OracleConsumptionAssertion.ReservePolicy[] memory policies
        ) = _largeFixture();
        AaveV4OracleConsumptionAssertion.ConfigSlotGuard[] memory configGuards = _realisticConfigGuards();

        _armCustom(address(largeSpoke), address(largeOracle), address(0), 64, policies, configGuards);
        vm.expectRevert(bytes("Assertion exceeded gas limit"));
        driver.twoBorrows(largeSpoke);
    }

    function _largeFixture()
        internal
        returns (
            MockV4Oracle largeOracle,
            MockV4Spoke largeSpoke,
            AaveV4OracleConsumptionAssertion.ReservePolicy[] memory policies
        )
    {
        largeOracle = new MockV4Oracle(address(0));
        largeSpoke = new MockV4Spoke(address(largeOracle));
        largeOracle.setSpoke(address(largeSpoke));

        policies = new AaveV4OracleConsumptionAssertion.ReservePolicy[](14);
        for (uint256 i; i < 14; ++i) {
            address asset = address(uint160(0x1000 + i));
            MockV4PriceFeed source = new MockV4PriceFeed(PRICE + int256(i));
            largeOracle.setReserveSource(i, address(source));
            largeSpoke.addReserve(asset);
            policies[i] = AaveV4OracleConsumptionAssertion.ReservePolicy({
                reserveId: i, asset: asset, source: address(source), deviationBps: DEVIATION_BPS
            });
        }
    }

    function _realisticConfigGuards()
        internal
        pure
        returns (AaveV4OracleConsumptionAssertion.ConfigSlotGuard[] memory guards)
    {
        guards = new AaveV4OracleConsumptionAssertion.ConfigSlotGuard[](22);
        for (uint256 i; i < guards.length; ++i) {
            guards[i] = AaveV4OracleConsumptionAssertion.ConfigSlotGuard({
                target: address(uint160(0x2000 + i)), slot: bytes32(uint256(2))
            });
        }
    }

    function _arm(uint256 maxTraceCalls, uint256 deviationBps, uint256 policyCount) internal {
        AaveV4OracleConsumptionAssertion.ReservePolicy[] memory policies =
            new AaveV4OracleConsumptionAssertion.ReservePolicy[](policyCount);
        AaveV4OracleConsumptionAssertion.ReservePolicy[] memory fullPolicies =
            _twoPolicies(deviationBps, address(source1));
        for (uint256 i; i < policyCount; ++i) {
            policies[i] = fullPolicies[i];
        }
        AaveV4OracleConsumptionAssertion.ConfigSlotGuard[] memory configGuards =
            new AaveV4OracleConsumptionAssertion.ConfigSlotGuard[](0);
        _armCustom(address(spoke), address(oracle), address(0), maxTraceCalls, policies, configGuards);
    }

    function _expectMandatoryPathWithoutPriceFails(bytes memory callData) internal {
        spoke.setConsumePrices(false);
        _arm(MAX_TRACE_CALLS, DEVIATION_BPS, 2);
        vm.expectRevert(bytes("AaveV4Oracle: unrecognized price path"));
        (bool success, bytes memory result) = address(spoke).call(callData);
        if (!success) {
            assembly ("memory-safe") {
                revert(add(result, 32), mload(result))
            }
        }
    }

    function _twoPolicies(uint256 deviationBps, address secondSource)
        internal
        view
        returns (AaveV4OracleConsumptionAssertion.ReservePolicy[] memory policies)
    {
        policies = new AaveV4OracleConsumptionAssertion.ReservePolicy[](2);
        policies[0] = AaveV4OracleConsumptionAssertion.ReservePolicy({
            reserveId: 0, asset: asset0, source: address(source0), deviationBps: deviationBps
        });
        policies[1] = AaveV4OracleConsumptionAssertion.ReservePolicy({
            reserveId: 1, asset: asset1, source: secondSource, deviationBps: deviationBps
        });
    }

    function _armCustom(
        address spoke_,
        address oracle_,
        address expectedImplementation,
        uint256 maxTraceCalls,
        AaveV4OracleConsumptionAssertion.ReservePolicy[] memory policies,
        AaveV4OracleConsumptionAssertion.ConfigSlotGuard[] memory configGuards
    ) internal {
        bytes memory createData = abi.encodePacked(
            type(AaveV4OracleConsumptionAssertion).creationCode,
            abi.encode(spoke_, oracle_, expectedImplementation, maxTraceCalls, policies, configGuards)
        );
        cl.assertion(spoke_, createData, AaveV4OracleConsumptionAssertion.assertConsumedOraclePricesSafe.selector);
    }
}
