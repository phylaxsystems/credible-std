// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";

import {CredibleTest} from "credible-std/CredibleTest.sol";

import {
    AaveV4EthereumEtherFiSpokeWeETHTransferabilityAssertion,
    AaveV4EthereumMainSpokeWeETHTransferabilityAssertion,
    AaveV4ExternalCollateralTransferabilityAssertion as Transferability
} from "../src/AaveV4ExternalCollateralTransferabilityAssertion.sol";
import {
    AaveV4EthereumPTUSDGRedemptionAssertion,
    AaveV4PTUSDGRedemptionAssertion
} from "../src/AaveV4PTUSDGRedemptionAssertion.sol";
import {IAaveV4Spoke} from "../src/AaveV4Interfaces.sol";

contract MockAaveV4ExternalStatus {
    bool internal pausedState;
    bool internal revertPausedRead;
    uint256 public pausedUntil;
    mapping(address account => uint256 until) public blacklistedUntil;
    mapping(address account => bool blocked) internal blacklisted;
    mapping(address account => bool blocked) internal blackListed;
    mapping(address account => bool blocked) internal blocked;
    mapping(address account => bool frozen) internal frozen;
    mapping(bytes32 role => mapping(address account => bool granted)) internal roles;

    function paused() external view returns (bool) {
        require(!revertPausedRead, "status read unavailable");
        return pausedState;
    }

    function isBlacklisted(address account) external view returns (bool) {
        return blacklisted[account];
    }

    function isBlackListed(address account) external view returns (bool) {
        return blackListed[account];
    }

    function isBlocked(address account) external view returns (bool) {
        return blocked[account];
    }

    function isFrozen(address account) external view returns (bool) {
        return frozen[account];
    }

    function hasRole(bytes32 role, address account) external view returns (bool) {
        return roles[role][account];
    }

    function setPaused(bool value) external {
        pausedState = value;
    }

    function setRevertPausedRead(bool value) external {
        revertPausedRead = value;
    }

    function setPausedUntil(uint256 value) external {
        pausedUntil = value;
    }

    function setBlacklistedUntil(address account, uint256 value) external {
        blacklistedUntil[account] = value;
    }

    function setBlacklisted(address account, bool value) external {
        blacklisted[account] = value;
    }

    function setBlackListed(address account, bool value) external {
        blackListed[account] = value;
    }

    function setBlocked(address account, bool value) external {
        blocked[account] = value;
    }

    function setFrozen(address account, bool value) external {
        frozen[account] = value;
    }

    function setRole(bytes32 role, address account, bool value) external {
        roles[role][account] = value;
    }
}

contract MockAaveV4ExternalSpoke {
    IAaveV4Spoke.Reserve[] internal reserves;
    mapping(uint256 reserveId => IAaveV4Spoke.DynamicReserveConfig config) internal dynamicConfigs;
    mapping(address user => mapping(uint256 reserveId => IAaveV4Spoke.UserPosition position)) internal positions;
    mapping(address user => mapping(uint256 reserveId => bool collateral)) internal collateralStatus;
    mapping(address user => mapping(uint256 reserveId => bool borrowing)) internal borrowingStatus;
    mapping(address user => uint256 debtValueRay) internal debts;

    function addReserve(address token, address hub, uint16 collateralFactor) external returns (uint256 reserveId) {
        reserveId = reserves.length;
        reserves.push(
            IAaveV4Spoke.Reserve({
                underlying: token,
                hub: hub,
                assetId: uint16(reserveId),
                decimals: 18,
                collateralRisk: 0,
                flags: 0,
                dynamicConfigKey: 0
            })
        );
        dynamicConfigs[reserveId] = IAaveV4Spoke.DynamicReserveConfig({
            collateralFactor: collateralFactor, maxLiquidationBonus: 10_500, liquidationFee: 1_000
        });
    }

    function setPosition(address user, uint256 reserveId, uint120 suppliedShares, bool usingAsCollateral) external {
        positions[user][reserveId].suppliedShares = suppliedShares;
        positions[user][reserveId].dynamicConfigKey = 0;
        collateralStatus[user][reserveId] = usingAsCollateral;
    }

    function setDebt(address user, uint256 debtValueRay) external {
        debts[user] = debtValueRay;
    }

    function setCollateralFactor(uint256 reserveId, uint16 collateralFactor) external {
        dynamicConfigs[reserveId].collateralFactor = collateralFactor;
    }

    function setReserveToken(uint256 reserveId, address token) external {
        reserves[reserveId].underlying = token;
    }

    function setReserveHub(uint256 reserveId, address hub) external {
        reserves[reserveId].hub = hub;
    }

    function supply(uint256 reserveId, uint256 amount, address onBehalfOf) external returns (uint256, uint256) {
        positions[onBehalfOf][reserveId].suppliedShares += uint120(amount);
        return (amount, amount);
    }

    function withdraw(uint256 reserveId, uint256 amount, address onBehalfOf) external returns (uint256, uint256) {
        uint120 shares = positions[onBehalfOf][reserveId].suppliedShares;
        uint120 removed = amount >= shares ? shares : uint120(amount);
        positions[onBehalfOf][reserveId].suppliedShares = shares - removed;
        return (removed, removed);
    }

    function borrow(uint256 reserveId, uint256 amount, address onBehalfOf) external returns (uint256, uint256) {
        debts[onBehalfOf] += amount * 1e27;
        borrowingStatus[onBehalfOf][reserveId] = true;
        return (amount, amount);
    }

    function repay(uint256 reserveId, uint256 amount, address onBehalfOf) external returns (uint256, uint256) {
        reserveId;
        amount;
        debts[onBehalfOf] = 0;
        return (amount, amount);
    }

    function liquidationCall(uint256, uint256, address user, uint256, bool) external {
        debts[user] = 0;
    }

    function setUsingAsCollateral(uint256 reserveId, bool usingAsCollateral, address onBehalfOf) external {
        collateralStatus[onBehalfOf][reserveId] = usingAsCollateral;
    }

    function getReserve(uint256 reserveId) external view returns (IAaveV4Spoke.Reserve memory) {
        return reserves[reserveId];
    }

    function getDynamicReserveConfig(uint256 reserveId, uint32)
        external
        view
        returns (IAaveV4Spoke.DynamicReserveConfig memory)
    {
        return dynamicConfigs[reserveId];
    }

    function getUserReserveStatus(uint256 reserveId, address user) external view returns (bool, bool) {
        return (collateralStatus[user][reserveId], borrowingStatus[user][reserveId]);
    }

    function getUserPosition(uint256 reserveId, address user) external view returns (IAaveV4Spoke.UserPosition memory) {
        return positions[user][reserveId];
    }

    function getUserAccountData(address user) external view returns (IAaveV4Spoke.UserAccountData memory data) {
        data.totalDebtValueRay = debts[user];
    }
}

contract AaveV4ExternalScenarioDriver {
    function borrowThenPause(MockAaveV4ExternalSpoke spoke, MockAaveV4ExternalStatus status, address user) external {
        spoke.borrow(1, 1, user);
        status.setPaused(true);
    }

    function pauseBorrowUnpause(MockAaveV4ExternalSpoke spoke, MockAaveV4ExternalStatus status, address user) external {
        status.setPaused(true);
        spoke.borrow(1, 1, user);
        status.setPaused(false);
    }
}

abstract contract AaveV4ExternalCollateralTestBase is Test, CredibleTest {
    uint256 internal constant RESTRICTED_RESERVE = 0;
    uint256 internal constant GOOD_RESERVE = 1;
    uint256 internal constant INITIAL_DEBT_RAY = 100e27;
    bytes32 internal constant FULL_RESTRICTED_STAKER_ROLE = keccak256("FULL_RESTRICTED_STAKER_ROLE");

    address internal user = makeAddr("borrower");
    address internal hub = makeAddr("Aave Hub");
    address internal otherHub = makeAddr("other Hub");
    address internal goodToken = makeAddr("good collateral");

    MockAaveV4ExternalStatus internal token;
    MockAaveV4ExternalStatus internal blacklister;
    MockAaveV4ExternalSpoke internal spoke;
    AaveV4ExternalScenarioDriver internal driver;

    function setUp() public virtual {
        vm.warp(1_000_000);
        token = new MockAaveV4ExternalStatus();
        blacklister = new MockAaveV4ExternalStatus();
        spoke = new MockAaveV4ExternalSpoke();
        spoke.addReserve(address(token), hub, 8_000);
        spoke.addReserve(goodToken, hub, 8_000);
        spoke.setPosition(user, RESTRICTED_RESERVE, 100, true);
        spoke.setPosition(user, GOOD_RESERVE, 100, true);
        spoke.setDebt(user, INITIAL_DEBT_RAY);
        driver = new AaveV4ExternalScenarioDriver();
    }
}

contract AaveV4ExternalCollateralTransferabilityAssertionTest is AaveV4ExternalCollateralTestBase {
    function testHonestBorrowPasses() public {
        _arm(Transferability.AdapterKind.Paused, address(token));
        spoke.borrow(GOOD_RESERVE, 1, user);
    }

    function testGlobalPauseTrips() public {
        token.setPaused(true);
        _expectBorrowFailure(
            Transferability.AdapterKind.Paused,
            address(token),
            "AaveV4Transferability: collateral restricted before risk increase"
        );
    }

    function testCamelCaseBlacklistTrips() public {
        token.setBlacklisted(hub, true);
        _expectBorrowFailure(
            Transferability.AdapterKind.PausedAndBlacklisted,
            address(token),
            "AaveV4Transferability: collateral restricted before risk increase"
        );
    }

    function testTetherBlacklistTrips() public {
        token.setBlackListed(hub, true);
        _expectBorrowFailure(
            Transferability.AdapterKind.PausedAndBlackListed,
            address(token),
            "AaveV4Transferability: collateral restricted before risk increase"
        );
    }

    function testWeEthIndefinitePauseTrips() public {
        token.setPaused(true);
        _expectBorrowFailure(
            Transferability.AdapterKind.WeEth,
            address(blacklister),
            "AaveV4Transferability: collateral restricted before risk increase"
        );
    }

    function testWeEthTimedPauseTripsAtBoundary() public {
        token.setPausedUntil(block.timestamp);
        _expectBorrowFailure(
            Transferability.AdapterKind.WeEth,
            address(blacklister),
            "AaveV4Transferability: collateral restricted before risk increase"
        );
    }

    function testWeEthHubBlacklistTrips() public {
        blacklister.setBlacklistedUntil(hub, block.timestamp + 1 days);
        _expectBorrowFailure(
            Transferability.AdapterKind.WeEth,
            address(blacklister),
            "AaveV4Transferability: collateral restricted before risk increase"
        );
    }

    function testWeEthExpiredTimedPausePasses() public {
        token.setPausedUntil(block.timestamp - 1);
        _arm(Transferability.AdapterKind.WeEth, address(blacklister));
        spoke.borrow(GOOD_RESERVE, 1, user);
    }

    function testWeEthBlacklistEndingAtCurrentTimestampPasses() public {
        blacklister.setBlacklistedUntil(hub, block.timestamp);
        _arm(Transferability.AdapterKind.WeEth, address(blacklister));
        spoke.borrow(GOOD_RESERVE, 1, user);
    }

    function testBlockedHubTrips() public {
        token.setBlocked(hub, true);
        _expectBorrowFailure(
            Transferability.AdapterKind.Blocked,
            address(token),
            "AaveV4Transferability: collateral restricted before risk increase"
        );
    }

    function testFullRestrictedRoleTrips() public {
        token.setRole(FULL_RESTRICTED_STAKER_ROLE, hub, true);
        _expectBorrowFailure(
            Transferability.AdapterKind.FullRestrictedRole,
            address(token),
            "AaveV4Transferability: collateral restricted before risk increase"
        );
    }

    function testPauseAddedAfterBorrowTripsAtPostTx() public {
        _arm(Transferability.AdapterKind.Paused, address(token));
        vm.expectRevert(bytes("AaveV4Transferability: collateral restricted at transaction end"));
        driver.borrowThenPause(spoke, token, user);
    }

    function testTransientPauseWrappedAroundBorrowTripsAtPreCall() public {
        _arm(Transferability.AdapterKind.Paused, address(token));
        vm.expectRevert(bytes("AaveV4Transferability: collateral restricted before risk increase"));
        driver.pauseBorrowUnpause(spoke, token, user);
    }

    function testDebtFreeCollateralWithdrawalPassesWhilePaused() public {
        spoke.setDebt(user, 0);
        token.setPaused(true);
        _arm(Transferability.AdapterKind.Paused, address(token));
        spoke.withdraw(RESTRICTED_RESERVE, 10, user);
    }

    function testNonCollateralWithdrawalPassesWhileOtherCollateralPaused() public {
        spoke.setPosition(user, GOOD_RESERVE, 100, false);
        token.setPaused(true);
        _arm(Transferability.AdapterKind.Paused, address(token));
        spoke.withdraw(GOOD_RESERVE, 10, user);
    }

    function testZeroFactorWithdrawalPassesAsNonCollateral() public {
        spoke.setCollateralFactor(GOOD_RESERVE, 0);
        token.setPaused(true);
        _arm(Transferability.AdapterKind.Paused, address(token));
        spoke.withdraw(GOOD_RESERVE, 10, user);
    }

    function testFullImpairedCollateralExitPasses() public {
        token.setPaused(true);
        _arm(Transferability.AdapterKind.Paused, address(token));
        spoke.withdraw(RESTRICTED_RESERVE, type(uint256).max, user);
    }

    function testPartialImpairedCollateralExitTripsWhileDebtStillReliesOnIt() public {
        token.setPaused(true);
        _arm(Transferability.AdapterKind.Paused, address(token));
        vm.expectRevert(bytes("AaveV4Transferability: collateral restricted before risk increase"));
        spoke.withdraw(RESTRICTED_RESERVE, 10, user);
    }

    function testDisableImpairedCollateralPasses() public {
        token.setPaused(true);
        _arm(Transferability.AdapterKind.Paused, address(token));
        spoke.setUsingAsCollateral(RESTRICTED_RESERVE, false, user);
    }

    function testEnableImpairedCollateralWithDebtTrips() public {
        spoke.setPosition(user, RESTRICTED_RESERVE, 100, false);
        token.setPaused(true);
        _arm(Transferability.AdapterKind.Paused, address(token));
        vm.expectRevert(bytes("AaveV4Transferability: collateral restricted before risk increase"));
        spoke.setUsingAsCollateral(RESTRICTED_RESERVE, true, user);
    }

    function testEnableImpairedCollateralWithoutDebtPasses() public {
        spoke.setPosition(user, RESTRICTED_RESERVE, 100, false);
        spoke.setDebt(user, 0);
        token.setPaused(true);
        _arm(Transferability.AdapterKind.Paused, address(token));
        spoke.setUsingAsCollateral(RESTRICTED_RESERVE, true, user);
    }

    function testNoOpCollateralEnablePassesWhilePaused() public {
        token.setPaused(true);
        _arm(Transferability.AdapterKind.Paused, address(token));
        spoke.setUsingAsCollateral(RESTRICTED_RESERVE, true, user);
    }

    function testWithdrawGoodCollateralTripsWhenDebtReliesOnImpairedCollateral() public {
        token.setPaused(true);
        _arm(Transferability.AdapterKind.Paused, address(token));
        vm.expectRevert(bytes("AaveV4Transferability: collateral restricted before risk increase"));
        spoke.withdraw(GOOD_RESERVE, 10, user);
    }

    function testDisableGoodCollateralTripsWhenDebtReliesOnImpairedCollateral() public {
        token.setPaused(true);
        _arm(Transferability.AdapterKind.Paused, address(token));
        vm.expectRevert(bytes("AaveV4Transferability: collateral restricted before risk increase"));
        spoke.setUsingAsCollateral(GOOD_RESERVE, false, user);
    }

    function testPausedCollateralNotUsedByAffectedUserPasses() public {
        spoke.setPosition(user, RESTRICTED_RESERVE, 100, false);
        token.setPaused(true);
        _arm(Transferability.AdapterKind.Paused, address(token));
        spoke.borrow(GOOD_RESERVE, 1, user);
    }

    function testZeroSuppliedSharesDoNotCountAsReliance() public {
        spoke.setPosition(user, RESTRICTED_RESERVE, 0, true);
        token.setPaused(true);
        _arm(Transferability.AdapterKind.Paused, address(token));
        spoke.borrow(GOOD_RESERVE, 1, user);
    }

    function testZeroCollateralFactorDoesNotCountAsReliance() public {
        spoke.setCollateralFactor(RESTRICTED_RESERVE, 0);
        token.setPaused(true);
        _arm(Transferability.AdapterKind.Paused, address(token));
        spoke.borrow(GOOD_RESERVE, 1, user);
    }

    function testSupplyRemainsOpenWhilePaused() public {
        token.setPaused(true);
        _arm(Transferability.AdapterKind.Paused, address(token));
        // The local Credible harness requires the armed assertion to execute once. Expecting its
        // zero-execution diagnostic proves `supply` is deliberately absent from production triggers.
        vm.expectRevert(bytes("Expected 1 assertion to be executed, but 0 were executed."));
        spoke.supply(GOOD_RESERVE, 1, user);
    }

    function testRepayRemainsOpenWhilePaused() public {
        token.setPaused(true);
        _arm(Transferability.AdapterKind.Paused, address(token));
        vm.expectRevert(bytes("Expected 1 assertion to be executed, but 0 were executed."));
        spoke.repay(GOOD_RESERVE, 1, user);
    }

    function testLiquidationRemainsOpenWhilePaused() public {
        token.setPaused(true);
        _arm(Transferability.AdapterKind.Paused, address(token));
        vm.expectRevert(bytes("Expected 1 assertion to be executed, but 0 were executed."));
        spoke.liquidationCall(RESTRICTED_RESERVE, GOOD_RESERVE, user, 1, true);
    }

    function testMultiplePoliciesRejectedToPreserveAssertionGasBound() public {
        Transferability.CollateralPolicy[] memory policies = new Transferability.CollateralPolicy[](2);
        policies[0] = Transferability.CollateralPolicy({
            reserveId: RESTRICTED_RESERVE,
            token: address(token),
            hub: hub,
            statusSource: address(token),
            adapter: Transferability.AdapterKind.Paused
        });
        policies[1] = Transferability.CollateralPolicy({
            reserveId: GOOD_RESERVE,
            token: address(token),
            hub: hub,
            statusSource: address(token),
            adapter: Transferability.AdapterKind.Paused
        });
        vm.expectRevert(bytes("AaveV4Transferability: one policy required"));
        new Transferability(address(spoke), policies);
    }

    function testReserveTokenDriftFailsClosed() public {
        spoke.setReserveToken(RESTRICTED_RESERVE, goodToken);
        _arm(Transferability.AdapterKind.Paused, address(token));
        vm.expectRevert(bytes("AaveV4Transferability: reserve token changed"));
        spoke.borrow(GOOD_RESERVE, 1, user);
    }

    function testReserveHubDriftFailsClosed() public {
        spoke.setReserveHub(RESTRICTED_RESERVE, otherHub);
        _arm(Transferability.AdapterKind.Paused, address(token));
        vm.expectRevert(bytes("AaveV4Transferability: reserve Hub changed"));
        spoke.borrow(GOOD_RESERVE, 1, user);
    }

    function testExternalStatusGetterFailureFailsClosed() public {
        token.setRevertPausedRead(true);
        _arm(Transferability.AdapterKind.Paused, address(token));
        vm.expectRevert(bytes("AaveV4: fork view failed"));
        spoke.borrow(GOOD_RESERVE, 1, user);
    }

    function testWrongAdopterFailsClosed() public {
        MockAaveV4ExternalSpoke other = new MockAaveV4ExternalSpoke();
        other.addReserve(address(token), hub, 8_000);
        other.setPosition(user, 0, 100, true);
        other.setDebt(user, INITIAL_DEBT_RAY);

        Transferability.CollateralPolicy[] memory policies =
            _policies(Transferability.AdapterKind.Paused, address(token));
        bytes memory createData =
            abi.encodePacked(type(Transferability).creationCode, abi.encode(address(spoke), policies));
        cl.assertion(address(other), createData, Transferability.assertExternalCollateralTransferable.selector);

        vm.expectRevert(bytes("AaveV4Transferability: configured Spoke is not adopter"));
        other.borrow(0, 1, user);
    }

    function _expectBorrowFailure(Transferability.AdapterKind adapter, address statusSource, string memory reason)
        internal
    {
        _arm(adapter, statusSource);
        vm.expectRevert(bytes(reason));
        spoke.borrow(GOOD_RESERVE, 1, user);
    }

    function _arm(Transferability.AdapterKind adapter, address statusSource) internal {
        Transferability.CollateralPolicy[] memory policies = _policies(adapter, statusSource);
        _armPolicies(policies);
    }

    function _armPolicies(Transferability.CollateralPolicy[] memory policies) internal {
        bytes memory createData =
            abi.encodePacked(type(Transferability).creationCode, abi.encode(address(spoke), policies));
        cl.assertion(address(spoke), createData, Transferability.assertExternalCollateralTransferable.selector);
    }

    function _policies(Transferability.AdapterKind adapter, address statusSource)
        internal
        view
        returns (Transferability.CollateralPolicy[] memory policies)
    {
        policies = new Transferability.CollateralPolicy[](1);
        policies[0] = Transferability.CollateralPolicy({
            reserveId: RESTRICTED_RESERVE, token: address(token), hub: hub, statusSource: statusSource, adapter: adapter
        });
    }
}

contract AaveV4PTUSDGRedemptionAssertionTest is AaveV4ExternalCollateralTestBase {
    MockAaveV4ExternalStatus internal sy;
    MockAaveV4ExternalStatus internal usdg;

    function setUp() public override {
        super.setUp();
        sy = new MockAaveV4ExternalStatus();
        usdg = new MockAaveV4ExternalStatus();
    }

    function testHonestPtBorrowPasses() public {
        _armPt();
        spoke.borrow(GOOD_RESERVE, 1, user);
    }

    function testSyPauseTrips() public {
        sy.setPaused(true);
        _expectPtBorrowFailure("AaveV4PTUSDG: redemption disabled before risk increase");
    }

    function testUsdgPauseTrips() public {
        usdg.setPaused(true);
        _expectPtBorrowFailure("AaveV4PTUSDG: redemption disabled before risk increase");
    }

    function testUsdgFreezeOfSyTrips() public {
        usdg.setFrozen(address(sy), true);
        _expectPtBorrowFailure("AaveV4PTUSDG: redemption disabled before risk increase");
    }

    function testSyPauseAddedAfterBorrowTripsAtPostTx() public {
        _armPt();
        vm.expectRevert(bytes("AaveV4PTUSDG: redemption disabled at transaction end"));
        driver.borrowThenPause(spoke, sy, user);
    }

    function testTransientSyPauseWrappedAroundBorrowTripsAtPreCall() public {
        _armPt();
        vm.expectRevert(bytes("AaveV4PTUSDG: redemption disabled before risk increase"));
        driver.pauseBorrowUnpause(spoke, sy, user);
    }

    function testPostMaturityWithAvailableRedemptionPasses() public {
        vm.warp(1_790_208_001);
        _armPt();
        spoke.borrow(GOOD_RESERVE, 1, user);
    }

    function testPtNotUsedAsCollateralPassesDuringSyPause() public {
        spoke.setPosition(user, RESTRICTED_RESERVE, 100, false);
        sy.setPaused(true);
        _armPt();
        spoke.borrow(GOOD_RESERVE, 1, user);
    }

    function testDebtFreePtWithdrawalPassesDuringSyPause() public {
        spoke.setDebt(user, 0);
        sy.setPaused(true);
        _armPt();
        spoke.withdraw(RESTRICTED_RESERVE, 10, user);
    }

    function testFullPtExitPassesDuringSyPause() public {
        sy.setPaused(true);
        _armPt();
        spoke.withdraw(RESTRICTED_RESERVE, type(uint256).max, user);
    }

    function testPartialPtExitTripsDuringSyPause() public {
        sy.setPaused(true);
        _armPt();
        vm.expectRevert(bytes("AaveV4PTUSDG: redemption disabled before risk increase"));
        spoke.withdraw(RESTRICTED_RESERVE, 10, user);
    }

    function testDisablePtCollateralPassesDuringSyPause() public {
        sy.setPaused(true);
        _armPt();
        spoke.setUsingAsCollateral(RESTRICTED_RESERVE, false, user);
    }

    function testEnablePtCollateralWithDebtTripsDuringSyPause() public {
        spoke.setPosition(user, RESTRICTED_RESERVE, 100, false);
        sy.setPaused(true);
        _armPt();
        vm.expectRevert(bytes("AaveV4PTUSDG: redemption disabled before risk increase"));
        spoke.setUsingAsCollateral(RESTRICTED_RESERVE, true, user);
    }

    function testWithdrawGoodCollateralTripsWhenDebtReliesOnStrandedPt() public {
        sy.setPaused(true);
        _armPt();
        vm.expectRevert(bytes("AaveV4PTUSDG: redemption disabled before risk increase"));
        spoke.withdraw(GOOD_RESERVE, 10, user);
    }

    function testDisableGoodCollateralTripsWhenDebtReliesOnStrandedPt() public {
        usdg.setFrozen(address(sy), true);
        _armPt();
        vm.expectRevert(bytes("AaveV4PTUSDG: redemption disabled before risk increase"));
        spoke.setUsingAsCollateral(GOOD_RESERVE, false, user);
    }

    function testSupplyRemainsOpenWhenPtRedemptionDisabled() public {
        sy.setPaused(true);
        _armPt();
        vm.expectRevert(bytes("Expected 1 assertion to be executed, but 0 were executed."));
        spoke.supply(GOOD_RESERVE, 1, user);
    }

    function testRepayRemainsOpenWhenPtRedemptionDisabled() public {
        usdg.setPaused(true);
        _armPt();
        vm.expectRevert(bytes("Expected 1 assertion to be executed, but 0 were executed."));
        spoke.repay(GOOD_RESERVE, 1, user);
    }

    function testLiquidationRemainsOpenWhenPtRedemptionDisabled() public {
        usdg.setFrozen(address(sy), true);
        _armPt();
        vm.expectRevert(bytes("Expected 1 assertion to be executed, but 0 were executed."));
        spoke.liquidationCall(RESTRICTED_RESERVE, GOOD_RESERVE, user, 1, true);
    }

    function testPtReserveTokenDriftFailsClosed() public {
        spoke.setReserveToken(RESTRICTED_RESERVE, goodToken);
        _armPt();
        vm.expectRevert(bytes("AaveV4PTUSDG: reserve PT changed"));
        spoke.borrow(GOOD_RESERVE, 1, user);
    }

    function testPtReserveHubDriftFailsClosed() public {
        spoke.setReserveHub(RESTRICTED_RESERVE, otherHub);
        _armPt();
        vm.expectRevert(bytes("AaveV4PTUSDG: reserve Hub changed"));
        spoke.borrow(GOOD_RESERVE, 1, user);
    }

    function testPtExternalGetterFailureFailsClosed() public {
        sy.setRevertPausedRead(true);
        _armPt();
        vm.expectRevert(bytes("AaveV4: fork view failed"));
        spoke.borrow(GOOD_RESERVE, 1, user);
    }

    function _expectPtBorrowFailure(string memory reason) internal {
        _armPt();
        vm.expectRevert(bytes(reason));
        spoke.borrow(GOOD_RESERVE, 1, user);
    }

    function _armPt() internal {
        bytes memory createData = abi.encodePacked(
            type(AaveV4PTUSDGRedemptionAssertion).creationCode,
            abi.encode(address(spoke), RESTRICTED_RESERVE, address(token), hub, address(sy), address(usdg))
        );
        cl.assertion(
            address(spoke), createData, AaveV4PTUSDGRedemptionAssertion.assertPtUsdgRedemptionAvailable.selector
        );
    }
}

contract AaveV4ExternalCollateralProductionConfigTest is Test {
    function testEthereumMainSpokeWeEthWrapperPinsReviewedPolicy() public {
        AaveV4EthereumMainSpokeWeETHTransferabilityAssertion assertion =
            new AaveV4EthereumMainSpokeWeETHTransferabilityAssertion();

        assertEq(assertion.collateralPolicyCount(), 1);
        Transferability.CollateralPolicy memory policy = assertion.collateralPolicy(0);
        assertEq(policy.reserveId, 2);
        assertEq(policy.token, assertion.WEETH());
        assertEq(policy.hub, assertion.CORE_HUB());
        assertEq(policy.statusSource, assertion.WEETH_BLACKLISTER());
        assertEq(uint256(policy.adapter), uint256(Transferability.AdapterKind.WeEth));
        assertEq(assertion.MAIN_SPOKE(), 0x94e7A5dCbE816e498b89aB752661904E2F56c485);
    }

    function testEthereumEtherFiSpokeWeEthWrapperPinsReviewedPolicy() public {
        AaveV4EthereumEtherFiSpokeWeETHTransferabilityAssertion assertion =
            new AaveV4EthereumEtherFiSpokeWeETHTransferabilityAssertion();

        assertEq(assertion.collateralPolicyCount(), 1);
        Transferability.CollateralPolicy memory policy = assertion.collateralPolicy(0);
        assertEq(policy.reserveId, 0);
        assertEq(policy.token, assertion.WEETH());
        assertEq(policy.hub, assertion.CORE_HUB());
        assertEq(policy.statusSource, assertion.WEETH_BLACKLISTER());
        assertEq(uint256(policy.adapter), uint256(Transferability.AdapterKind.WeEth));
        assertEq(assertion.ETHERFI_ESPOKE(), 0xbF10BDfE177dE0336aFD7fcCF80A904E15386219);
    }

    function testEthereumPtUsdgWrapperPinsReviewedRedemptionPath() public {
        AaveV4EthereumPTUSDGRedemptionAssertion assertion = new AaveV4EthereumPTUSDGRedemptionAssertion();
        (address configuredSpoke, uint256 reserveId, address pt, address configuredHub, address sy, address usdg) =
            assertion.configuration();

        assertEq(configuredSpoke, assertion.USDG_PENDLE_SPOKE());
        assertEq(reserveId, 0);
        assertEq(pt, assertion.PT_USDG_24SEP2026());
        assertEq(configuredHub, assertion.PAXOS_HUB());
        assertEq(sy, assertion.PENDLE_SY_USDG());
        assertEq(usdg, assertion.PAXOS_USDG());
    }
}
