// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "credible-std/PhEvm.sol";

import {
    AaveV4ExternalCollateralHelpers,
    IExternalFrozenAccount,
    IExternalPausable
} from "./AaveV4ExternalCollateralHelpers.sol";
import {IAaveV4Spoke} from "./AaveV4Interfaces.sol";

/// @title AaveV4PTUSDGRedemptionAssertion
/// @author Phylax Systems
/// @notice Makes PT-USDG-backed Aave positions reduce-only when PT's USDG exit is disabled.
/// @dev Protects the failure where PT remains transferable and Aave's PT oracle remains valid,
///      but Pendle's SY is paused, USDG is globally paused, or Paxos freezes the SY account.
///      Aave borrow does not redeem PT, so native Pendle/USDG reverts otherwise arrive only when
///      collateral value must be realized. Maturity is intentionally not treated as a failure.
contract AaveV4PTUSDGRedemptionAssertion is AaveV4ExternalCollateralHelpers {
    address internal immutable SPOKE;
    uint256 internal immutable PT_RESERVE_ID;
    address internal immutable PT_USDG;
    address internal immutable HUB;
    address internal immutable SY_USDG;
    address internal immutable USDG;

    /// @param spoke_ The Aave v4 USDG Pendle Spoke adopting the assertion.
    /// @param ptReserveId_ The Spoke reserve id for PT-USDG-24SEP2026.
    /// @param ptUsdg_ The canonical PT token.
    /// @param hub_ The Hub holding supplied PT on behalf of Aave users.
    /// @param syUsdg_ The Pendle standardized-yield contract through which PT resolves to USDG.
    /// @param usdg_ The Paxos USDG token returned by the SY redemption path.
    constructor(address spoke_, uint256 ptReserveId_, address ptUsdg_, address hub_, address syUsdg_, address usdg_) {
        require(spoke_ != address(0), "AaveV4PTUSDG: Spoke zero");
        require(ptUsdg_ != address(0), "AaveV4PTUSDG: PT zero");
        require(hub_ != address(0), "AaveV4PTUSDG: Hub zero");
        require(syUsdg_ != address(0), "AaveV4PTUSDG: SY zero");
        require(usdg_ != address(0), "AaveV4PTUSDG: USDG zero");

        SPOKE = spoke_;
        PT_RESERVE_ID = ptReserveId_;
        PT_USDG = ptUsdg_;
        HUB = hub_;
        SY_USDG = syUsdg_;
        USDG = usdg_;
    }

    /// @notice Registers only debt growth and effective-collateral removal paths.
    /// @dev Per-call context is necessary to identify the user and allow a complete PT exit while
    ///      blocking a withdrawal of other good collateral that leaves debt relying on stranded PT.
    function triggers() external view override {
        registerFnCallTrigger(this.assertPtUsdgRedemptionAvailable.selector, IAaveV4Spoke.borrow.selector);
        registerFnCallTrigger(this.assertPtUsdgRedemptionAvailable.selector, IAaveV4Spoke.withdraw.selector);
        registerFnCallTrigger(this.assertPtUsdgRedemptionAvailable.selector, IAaveV4Spoke.setUsingAsCollateral.selector);
    }

    /// @notice Requires the canonical PT -> SY -> USDG exit to remain administratively available.
    /// @dev The check runs only if the affected user still relies on positive PT collateral after
    ///      a risk-increasing call. A failure means Aave could accept more debt or less good
    ///      collateral even though SY/USDG state independently prevents PT value realization.
    ///      PreCall plus PostTx reads reject same-transaction pause/freeze wrapping.
    function assertPtUsdgRedemptionAvailable() external view {
        _requireAdopter(SPOKE, "AaveV4PTUSDG: configured Spoke is not adopter");

        PhEvm.TriggerContext memory ctx = ph.context();
        (address user, bool riskIncreasing) = _riskIncreasingUser(SPOKE, ctx);
        if (!riskIncreasing) {
            return;
        }

        PhEvm.ForkId memory postCall = _postCall(ctx.callEnd);
        if (!_isActiveCollateralAt(SPOKE, PT_RESERVE_ID, user, postCall)) {
            return;
        }

        IAaveV4Spoke.Reserve memory reserve = _spokeReserveAt(SPOKE, PT_RESERVE_ID, postCall);
        require(reserve.underlying == PT_USDG, "AaveV4PTUSDG: reserve PT changed");
        require(reserve.hub == HUB, "AaveV4PTUSDG: reserve Hub changed");

        _requireRedemptionAvailableAt(_preCall(ctx.callStart), "AaveV4PTUSDG: redemption disabled before risk increase");
        _requireRedemptionAvailableAt(_postTx(), "AaveV4PTUSDG: redemption disabled at transaction end");
    }

    /// @notice Returns the immutable deployment wiring for operational review.
    function configuration()
        external
        view
        returns (address spoke, uint256 ptReserveId, address ptUsdg, address hub, address syUsdg, address usdg)
    {
        return (SPOKE, PT_RESERVE_ID, PT_USDG, HUB, SY_USDG, USDG);
    }

    function _requireRedemptionAvailableAt(PhEvm.ForkId memory fork, string memory message) internal view {
        bool syPaused = _readBoolAt(SY_USDG, abi.encodeCall(IExternalPausable.paused, ()), fork);
        bool usdgPaused = _readBoolAt(USDG, abi.encodeCall(IExternalPausable.paused, ()), fork);
        bool syFrozen = _readBoolAt(USDG, abi.encodeCall(IExternalFrozenAccount.isFrozen, (SY_USDG)), fork);
        require(!syPaused && !usdgPaused && !syFrozen, message);
    }
}

/// @title AaveV4EthereumPTUSDGRedemptionAssertion
/// @notice Production-configured PT-USDG redemption gate for Aave v4 Ethereum.
/// @dev Constants were verified at Ethereum block 25,653,183. Revalidate the Spoke reserve,
///      PT/SY/USDG path, Hub, proxy implementations, and status ABIs before adoption after upgrades.
contract AaveV4EthereumPTUSDGRedemptionAssertion is AaveV4PTUSDGRedemptionAssertion {
    address public constant USDG_PENDLE_SPOKE = 0x956d8e0A89cfa3744428C4641b5a53B56167a7f9;
    address public constant PT_USDG_24SEP2026 = 0xc1906aeCf868749a2DeE203F59b904c0cf212140;
    address public constant PAXOS_HUB = 0x62d63197660c080236193CA60b70E49A08E90368;
    address public constant PENDLE_SY_USDG = 0xc1799CaB1F201946f7CFaFBaF1BCC089b2F08927;
    address public constant PAXOS_USDG = 0xe343167631d89B6Ffc58B88d6b7fB0228795491D;

    constructor()
        AaveV4PTUSDGRedemptionAssertion(USDG_PENDLE_SPOKE, 0, PT_USDG_24SEP2026, PAXOS_HUB, PENDLE_SY_USDG, PAXOS_USDG)
    {}
}
