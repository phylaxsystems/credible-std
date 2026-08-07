// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {CredibleTest} from "credible-std/CredibleTest.sol";
import {
    AaveV3HorizonOperationSafetyAssertion
} from "credible-std/protection/lending/examples/AaveV3PostOperationSolvency.sol";
import {LendingBaseAssertion} from "credible-std/protection/lending/LendingBaseAssertion.sol";
import {AaveV3LikeTypes, IAaveV3LikePool} from "credible-std/protection/lending/examples/AaveV3LikeInterfaces.sol";
import {AaveV3HorizonOracleAssertion} from "../src/AaveV3HorizonOracleAssertion.sol";
import {AaveV3HorizonReserveBackingAssertion} from "../src/AaveV3HorizonReserveBackingAssertion.sol";
import {AaveV3HorizonHelpers} from "../src/AaveV3HorizonHelpers.sol";
import {IAaveV3HorizonOracle} from "../src/AaveV3HorizonInterfaces.sol";

/// @notice Research-only mocks. They deliberately expose mutations that ordinary Aave entrypoints
///         do not expose so the assertions can be tested as independent failure detectors.
contract ResearchAccountingToken {
    uint8 public immutable decimals;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;

    event Transfer(address indexed from, address indexed to, uint256 amount);

    constructor(uint8 decimals_) {
        decimals = decimals_;
    }

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function seize(address from, address to, uint256 amount) external {
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
    }
}

contract ResearchPriceSource {
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

contract ResearchFallbackOracle {
    mapping(address => uint256) public prices;

    function setPrice(address asset, uint256 price) external {
        prices[asset] = price;
    }

    function getAssetPrice(address asset) external view returns (uint256) {
        return prices[asset];
    }
}

contract ResearchOracle is IAaveV3HorizonOracle {
    mapping(address => address) internal sources;
    address internal fallbackOracle;

    constructor(address fallbackOracle_) {
        fallbackOracle = fallbackOracle_;
    }

    function setAssetSources(address[] calldata assets, address[] calldata newSources) external {
        require(assets.length == newSources.length, "length");
        for (uint256 i; i < assets.length; ++i) {
            sources[assets[i]] = newSources[i];
        }
    }

    function setFallbackOracle(address fallbackOracle_) external {
        fallbackOracle = fallbackOracle_;
    }

    function getAssetPrice(address asset) external view returns (uint256) {
        address source = sources[asset];
        if (source == address(0)) {
            return ResearchFallbackOracle(fallbackOracle).getAssetPrice(asset);
        }

        int256 answer = ResearchPriceSource(source).latestAnswer();
        if (answer <= 0) {
            return ResearchFallbackOracle(fallbackOracle).getAssetPrice(asset);
        }
        return uint256(answer);
    }

    function getSourceOfAsset(address asset) external view returns (address) {
        return sources[asset];
    }

    function getFallbackOracle() external view returns (address) {
        return fallbackOracle;
    }
}

contract ResearchAddressesProvider {
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

contract ResearchPool is IAaveV3LikePool {
    address public immutable override ADDRESSES_PROVIDER;

    struct AccountData {
        uint256 totalCollateralBase;
        uint256 totalDebtBase;
        uint256 availableBorrowsBase;
        uint256 currentLiquidationThreshold;
        uint256 ltv;
        uint256 healthFactor;
    }

    address[] internal reserves;
    mapping(address => bool) internal listed;
    mapping(address => AaveV3LikeTypes.ReserveData) internal reserveData;
    mapping(address => AaveV3LikeTypes.UserConfigurationMap) internal userConfig;
    mapping(address => AccountData) internal accounts;
    mapping(address => uint256) internal deficits;
    mapping(address => uint256) internal normalizedIncome;

    constructor(address provider_) {
        ADDRESSES_PROVIDER = provider_;
    }

    function setReserve(address asset, uint16 id, address aToken, address variableDebtToken) external {
        if (!listed[asset]) {
            listed[asset] = true;
            reserves.push(asset);
        }
        reserveData[asset] = AaveV3LikeTypes.ReserveData({
            configurationData: 0,
            liquidityIndex: 1e27,
            currentLiquidityRate: 0,
            variableBorrowIndex: 1e27,
            currentVariableBorrowRate: 0,
            currentStableBorrowRate: 0,
            lastUpdateTimestamp: 0,
            id: id,
            aTokenAddress: aToken,
            stableDebtTokenAddress: address(0),
            variableDebtTokenAddress: variableDebtToken,
            interestRateStrategyAddress: address(0),
            accruedToTreasury: 0,
            unbacked: 0,
            isolationModeTotalDebt: 0
        });
        normalizedIncome[asset] = 1e27;
    }

    function setAccruedToTreasury(address asset, uint128 scaledAmount) external {
        reserveData[asset].accruedToTreasury = scaledAmount;
    }

    function setUnbacked(address asset, uint128 amount) external {
        reserveData[asset].unbacked = amount;
    }

    function setReserveDeficit(address asset, uint256 amount) external {
        deficits[asset] = amount;
    }

    function getReserveDeficit(address asset) external view returns (uint256) {
        return deficits[asset];
    }

    function setReserveNormalizedIncome(address asset, uint256 index) external {
        normalizedIncome[asset] = index;
    }

    function getReserveNormalizedIncome(address asset) external view returns (uint256) {
        return normalizedIncome[asset];
    }

    function setUserConfig(address user, uint256 data) external {
        userConfig[user].data = data;
    }

    function setAccount(address user, uint256 collateral, uint256 debt, uint256 healthFactor) external {
        accounts[user] = AccountData({
            totalCollateralBase: collateral,
            totalDebtBase: debt,
            availableBorrowsBase: collateral > debt ? collateral - debt : 0,
            currentLiquidationThreshold: 8000,
            ltv: 7000,
            healthFactor: healthFactor
        });
    }

    function borrow(address, uint256 amount, uint256, uint16, address onBehalfOf) external override {
        require(amount != 0, "forced borrow failure");
        IAaveV3HorizonOracle activeOracle =
            IAaveV3HorizonOracle(ResearchAddressesProvider(ADDRESSES_PROVIDER).getPriceOracle());
        for (uint256 i; i < reserves.length; ++i) {
            activeOracle.getAssetPrice(reserves[i]);
        }
        accounts[onBehalfOf].totalDebtBase += amount;
    }

    function withdraw(address, uint256 amount, address) external pure override returns (uint256) {
        return amount;
    }

    function liquidationCall(address, address, address, uint256, bool) external pure override {}

    function flashLoan(
        address,
        address[] calldata,
        uint256[] calldata,
        uint256[] calldata,
        address,
        bytes calldata,
        uint16
    ) external pure override {}

    function setUserUseReserveAsCollateral(address asset, bool useAsCollateral) external override {
        uint256 bit = 1 << (reserveData[asset].id * 2 + 1);
        if (useAsCollateral) {
            userConfig[msg.sender].data |= bit;
        } else {
            userConfig[msg.sender].data &= ~bit;
        }
    }

    function setUserEMode(uint8) external pure override {}

    function finalizeTransfer(address, address, address, uint256, uint256, uint256) external pure override {}

    function getUserAccountData(address user)
        external
        view
        override
        returns (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        )
    {
        AccountData memory a = accounts[user];
        return (
            a.totalCollateralBase,
            a.totalDebtBase,
            a.availableBorrowsBase,
            a.currentLiquidationThreshold,
            a.ltv,
            a.healthFactor
        );
    }

    function getUserConfiguration(address user)
        external
        view
        override
        returns (AaveV3LikeTypes.UserConfigurationMap memory)
    {
        return userConfig[user];
    }

    function getReserveData(address asset) external view override returns (AaveV3LikeTypes.ReserveData memory) {
        return reserveData[asset];
    }

    function getReservesList() external view override returns (address[] memory) {
        return reserves;
    }
}

    contract ResearchBundle {
        function priceThenBorrow(
            ResearchPriceSource source,
            int256 answer,
            ResearchPool pool,
            address asset,
            address user
        ) external {
            source.setAnswer(answer);
            pool.borrow(asset, 1, 2, 0, user);
        }

        function priceBorrowRestore(
            ResearchPriceSource source,
            int256 temporaryAnswer,
            int256 restoredAnswer,
            ResearchPool pool,
            address asset,
            address user
        ) external {
            source.setAnswer(temporaryAnswer);
            pool.borrow(asset, 1, 2, 0, user);
            source.setAnswer(restoredAnswer);
        }

        function sourceBorrowRestore(
            ResearchOracle oracle,
            address oracleAsset,
            address temporarySource,
            address restoredSource,
            ResearchPool pool,
            address borrowAsset,
            address user
        ) external {
            _setSource(oracle, oracleAsset, temporarySource);
            pool.borrow(borrowAsset, 1, 2, 0, user);
            _setSource(oracle, oracleAsset, restoredSource);
        }

        function providerThenBorrow(
            ResearchAddressesProvider provider,
            address newOracle,
            ResearchPool pool,
            address borrowAsset,
            address user
        ) external {
            provider.setPriceOracle(newOracle);
            pool.borrow(borrowAsset, 1, 2, 0, user);
        }

        function providerBorrowRestore(
            ResearchAddressesProvider provider,
            address temporaryOracle,
            address restoredOracle,
            ResearchPool pool,
            address borrowAsset,
            address user
        ) external {
            provider.setPriceOracle(temporaryOracle);
            pool.borrow(borrowAsset, 1, 2, 0, user);
            provider.setPriceOracle(restoredOracle);
        }

        function seizeThenPoolCall(
            ResearchAccountingToken underlying,
            address aToken,
            address recipient,
            uint256 amount,
            ResearchPool pool,
            address borrowAsset,
            address user
        ) external {
            underlying.seize(aToken, recipient, amount);
            pool.borrow(borrowAsset, 1, 2, 0, user);
        }

        function seizePoolCallRestore(
            ResearchAccountingToken underlying,
            address aToken,
            address recipient,
            uint256 amount,
            ResearchPool pool,
            address borrowAsset,
            address user
        ) external {
            underlying.seize(aToken, recipient, amount);
            pool.borrow(borrowAsset, 1, 2, 0, user);
            underlying.seize(recipient, aToken, amount);
        }

        function twoBorrows(ResearchPool pool, address asset, address user) external {
            pool.borrow(asset, 1, 2, 0, user);
            pool.borrow(asset, 1, 2, 0, user);
        }

        function successfulThenFailedBorrow(ResearchPool pool, address asset, address user) external {
            pool.borrow(asset, 1, 2, 0, user);
            (bool ok,) = address(pool).call(abi.encodeCall(ResearchPool.borrow, (asset, 0, 2, 0, user)));
            require(!ok, "borrow unexpectedly succeeded");
        }

        function _setSource(ResearchOracle oracle, address asset, address source) internal {
            address[] memory assets = new address[](1);
            assets[0] = asset;
            address[] memory sources = new address[](1);
            sources[0] = source;
            oracle.setAssetSources(assets, sources);
        }
    }

    /// @notice Research-only trace probe. A successful Pool call selects TxEnd; the probe then checks
    ///         whether getAllCallInputs also returns a caught, reverted call with the same selector.
    contract SuccessfulCallTraceAssertion is AaveV3HorizonHelpers {
        address internal immutable POOL;

        constructor(address pool_) {
            POOL = pool_;
        }

        function triggers() external view override {
            registerTxEndTrigger(this.assertOnlySuccessfulBorrowSeen.selector);
        }

        function assertOnlySuccessfulBorrowSeen() external view {
            require(
                ph.getAllCallInputs(POOL, IAaveV3LikePool.borrow.selector).length == 1,
                "research: reverted call included"
            );
        }
    }

    /// @dev Test-only harness arms the quarantined backing logic so its accounting remains covered.
    contract ArmedReserveBackingAssertion is AaveV3HorizonReserveBackingAssertion {
        constructor(address pool_, address[] memory assets_, uint256 deficit_)
            AaveV3HorizonReserveBackingAssertion(pool_, assets_, deficit_)
        {}

        function triggers() external view override {
            registerTxEndTrigger(this.assertReserveBacking.selector);
        }
    }

    contract AaveV3AdversarialResearchTest is Test, CredibleTest {
        uint256 internal constant MAX_RESERVES = 8;
        uint256 internal constant ORACLE_TOLERANCE_BPS = 100;
        int256 internal constant PRICE = 100_00000000;

        address internal alice = makeAddr("alice");
        address internal recipient = makeAddr("recipient");

        ResearchAccountingToken internal debtAsset;
        ResearchAccountingToken internal collateralAsset;
        ResearchAccountingToken internal debtAToken;
        ResearchAccountingToken internal collateralAToken;
        ResearchAccountingToken internal variableDebtToken;
        ResearchFallbackOracle internal fallbackOracle;
        ResearchOracle internal oracle;
        ResearchOracle internal secondOracle;
        ResearchAddressesProvider internal provider;
        ResearchPriceSource internal debtSource;
        ResearchPriceSource internal collateralSource;
        ResearchPriceSource internal temporarySource;
        ResearchPool internal pool;
        ResearchBundle internal bundle;

        function setUp() public {
            debtAsset = new ResearchAccountingToken(18);
            collateralAsset = new ResearchAccountingToken(18);
            debtAToken = new ResearchAccountingToken(18);
            collateralAToken = new ResearchAccountingToken(18);
            variableDebtToken = new ResearchAccountingToken(18);
            fallbackOracle = new ResearchFallbackOracle();
            oracle = new ResearchOracle(address(fallbackOracle));
            secondOracle = new ResearchOracle(address(fallbackOracle));
            provider = new ResearchAddressesProvider(address(oracle));
            debtSource = new ResearchPriceSource(PRICE);
            collateralSource = new ResearchPriceSource(PRICE);
            temporarySource = new ResearchPriceSource(2 * PRICE);
            pool = new ResearchPool(address(provider));
            bundle = new ResearchBundle();

            _setSources(oracle, address(debtSource), address(collateralSource));
            _setSources(secondOracle, address(debtSource), address(collateralSource));
            pool.setReserve(address(debtAsset), 0, address(debtAToken), address(variableDebtToken));
            pool.setReserve(address(collateralAsset), 1, address(collateralAToken), address(0));
            pool.setUserConfig(alice, (1 << 0) | (1 << 3));
            pool.setAccount(alice, 200 ether, 100 ether, 2 ether);

            debtAToken.mint(alice, 1_000 ether);
            debtAsset.mint(address(debtAToken), 600 ether);
            variableDebtToken.mint(alice, 400 ether);
            collateralAToken.mint(alice, 1_000 ether);
            collateralAsset.mint(address(collateralAToken), 1_000 ether);
        }

        function testBackingHonestPoolTransactionPasses() public {
            _armBacking();
            pool.borrow(address(debtAsset), 1, 2, 0, alice);
        }

        function testBackingSameSeizureTripsWhenTransactionAlsoTouchesPool() public {
            _armBacking();
            vm.expectRevert(bytes("AaveV3Horizon: reserve backing deficit"));
            bundle.seizeThenPoolCall(
                collateralAsset, address(collateralAToken), recipient, 1 ether, pool, address(debtAsset), alice
            );
        }

        function testBackingIncludesAccruedTreasuryLiability() public {
            pool.setAccruedToTreasury(address(collateralAsset), uint128(10 ether));

            _armBacking();
            vm.expectRevert(bytes("AaveV3Horizon: reserve backing deficit"));
            pool.borrow(address(debtAsset), 1, 2, 0, alice);
        }

        function testBackingUsesCurrentNormalizedIncomeWhenStoredIndexIsStale() public {
            collateralAsset.mint(address(collateralAToken), 15 ether);
            pool.setAccruedToTreasury(address(collateralAsset), uint128(10 ether));
            pool.setReserveNormalizedIncome(address(collateralAsset), 2e27);

            _armBacking();
            vm.expectRevert(bytes("AaveV3Horizon: reserve backing deficit"));
            pool.borrow(address(debtAsset), 1, 2, 0, alice);
        }

        function testBackingDeficitHasCorrectPositiveSign() public {
            collateralAsset.seize(address(collateralAToken), recipient, 10 ether);
            pool.setReserveDeficit(address(collateralAsset), 10 ether);

            _armBacking();
            pool.borrow(address(debtAsset), 1, 2, 0, alice);
        }

        /// @dev PostTx-only backing accepts a temporary transaction-intermediate custody shortfall.
        function testBackingTemporarySeizureRestoredBeforeTxEndPasses() public {
            _armBacking();
            bundle.seizePoolCallRestore(
                collateralAsset, address(collateralAToken), recipient, 1 ether, pool, address(debtAsset), alice
            );
        }

        function testOracleStableBorrowPasses() public {
            _armOracle();
            pool.borrow(address(debtAsset), 1, 2, 0, alice);
        }

        function testOracleMultipleStableCallsPass() public {
            _armOracle();
            bundle.twoBorrows(pool, address(debtAsset), alice);
        }

        function testOraclePersistentPriceMutationTrips() public {
            _armOracle();
            vm.expectRevert(bytes("AaveV3Horizon: consumed oracle price deviated"));
            bundle.priceThenBorrow(collateralSource, 2 * PRICE, pool, address(debtAsset), alice);
        }

        function testOracleTemporaryPriceManipulationAndRestoreTrips() public {
            _armOracle();
            vm.expectRevert(bytes("AaveV3Horizon: consumed oracle price deviated"));
            bundle.priceBorrowRestore(collateralSource, 2 * PRICE, PRICE, pool, address(debtAsset), alice);
        }

        function testOracleTemporarySourceSwapAndRestoreTrips() public {
            _armOracle();
            vm.expectRevert(bytes("AaveV3Horizon: reserve oracle source changed during transaction"));
            bundle.sourceBorrowRestore(
                oracle,
                address(collateralAsset),
                address(temporarySource),
                address(collateralSource),
                pool,
                address(debtAsset),
                alice
            );
        }

        function testOraclePermanentProviderSwitchToExistingOracleTrips() public {
            _armOracle();
            vm.expectRevert(bytes("AaveV3Horizon: provider oracle changed during transaction"));
            bundle.providerThenBorrow(provider, address(secondOracle), pool, address(debtAsset), alice);
        }

        function testOracleTemporaryProviderSwitchAndRestoreTrips() public {
            _armOracle();
            vm.expectRevert(bytes("AaveV3Horizon: Pool consumed a different oracle"));
            bundle.providerBorrowRestore(
                provider, address(secondOracle), address(oracle), pool, address(debtAsset), alice
            );
        }

        /// @dev This models a normal feed update bundled by an automation/governance transaction.
        function testOracleLegitimateLargePriceUpdateBundledWithBorrowTrips() public {
            _armOracle();
            vm.expectRevert(bytes("AaveV3Horizon: consumed oracle price deviated"));
            bundle.priceThenBorrow(collateralSource, 102_00000000, pool, address(debtAsset), alice);
        }

        function testGetAllCallInputsExcludesCaughtRevertedBorrow() public {
            bytes memory createData =
                abi.encodePacked(type(SuccessfulCallTraceAssertion).creationCode, abi.encode(address(pool)));
            cl.assertion(
                address(pool), createData, SuccessfulCallTraceAssertion.assertOnlySuccessfulBorrowSeen.selector
            );

            bundle.successfulThenFailedBorrow(pool, address(debtAsset), alice);
        }

        /// @dev The production wrapper creates its suite in constructor initcode. The assertion runtime
        ///      currently cannot call that child contract when registering monitored selectors.
        function testProductionOperationSafetyBundleChildSuiteIsUnavailable() public {
            bytes memory createData = abi.encodePacked(
                type(AaveV3HorizonOperationSafetyAssertion).creationCode, abi.encode(address(pool), address(provider))
            );
            cl.assertion(address(pool), createData, LendingBaseAssertion.assertOperationSafety.selector);

            vm.expectRevert();
            pool.borrow(address(debtAsset), 1, 2, 0, alice);
        }

        function _armBacking() internal {
            bytes memory createData = abi.encodePacked(
                type(ArmedReserveBackingAssertion).creationCode, abi.encode(address(pool), _assets(), 0)
            );
            cl.assertion(address(pool), createData, AaveV3HorizonReserveBackingAssertion.assertReserveBacking.selector);
        }

        function _armOracle() internal {
            AaveV3HorizonOracleAssertion.AssetPolicy[] memory policies = new AaveV3HorizonOracleAssertion
                .AssetPolicy[](2);
            policies[0] =
                AaveV3HorizonOracleAssertion.AssetPolicy({
                asset: address(debtAsset), deviationBps: ORACLE_TOLERANCE_BPS
            });
            policies[1] = AaveV3HorizonOracleAssertion.AssetPolicy({
                asset: address(collateralAsset), deviationBps: ORACLE_TOLERANCE_BPS
            });
            bytes memory createData = abi.encodePacked(
                type(AaveV3HorizonOracleAssertion).creationCode,
                abi.encode(address(pool), address(provider), MAX_RESERVES, policies)
            );
            cl.assertion(
                address(pool), createData, AaveV3HorizonOracleAssertion.assertConsumedOraclePricesSafe.selector
            );
        }

        function _assets() internal view returns (address[] memory assets) {
            assets = new address[](2);
            assets[0] = address(debtAsset);
            assets[1] = address(collateralAsset);
        }

        function _setSources(ResearchOracle targetOracle, address debtSource_, address collateralSource_) internal {
            address[] memory assets = _assets();
            address[] memory sources = new address[](2);
            sources[0] = debtSource_;
            sources[1] = collateralSource_;
            targetOracle.setAssetSources(assets, sources);
        }
    }
