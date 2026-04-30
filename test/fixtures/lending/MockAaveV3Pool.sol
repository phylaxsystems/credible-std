// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title MockAaveV3Pool
/// @notice Minimal Aave v3-like pool mock for credible-std assertion regression tests.
/// @dev Only implements the surface that `AaveV3LikeProtectionSuite.getAccountSnapshot` reads on
///      the borrow path: `ADDRESSES_PROVIDER()` and `getUserAccountData(account)`. The mock keeps
///      a per-account "next health factor" knob that the test pre-configures; calling `borrow`
///      latches it as the current health factor so pre- and post-call snapshots differ.
contract MockAaveV3Pool {
    address public immutable ADDRESSES_PROVIDER;

    struct AccountData {
        uint256 totalCollateralBase;
        uint256 totalDebtBase;
        uint256 availableBorrowsBase;
        uint256 currentLiquidationThreshold;
        uint256 ltv;
        uint256 healthFactor;
    }

    mapping(address => AccountData) public account;
    mapping(address => uint256) public nextHealthFactor;

    constructor(address provider_) {
        ADDRESSES_PROVIDER = provider_;
    }

    function setAccount(
        address user,
        uint256 totalCollateralBase,
        uint256 totalDebtBase,
        uint256 availableBorrowsBase,
        uint256 currentLiquidationThreshold,
        uint256 ltv,
        uint256 healthFactor
    ) external {
        account[user] = AccountData({
            totalCollateralBase: totalCollateralBase,
            totalDebtBase: totalDebtBase,
            availableBorrowsBase: availableBorrowsBase,
            currentLiquidationThreshold: currentLiquidationThreshold,
            ltv: ltv,
            healthFactor: healthFactor
        });
    }

    function setNextHealthFactor(address user, uint256 hf) external {
        nextHealthFactor[user] = hf;
    }

    function getUserAccountData(address user)
        external
        view
        returns (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        )
    {
        AccountData memory a = account[user];
        return (
            a.totalCollateralBase,
            a.totalDebtBase,
            a.availableBorrowsBase,
            a.currentLiquidationThreshold,
            a.ltv,
            a.healthFactor
        );
    }

    /// @notice Aave v3 `borrow(asset, amount, interestRateMode, referralCode, onBehalfOf)`.
    /// @dev Latches `nextHealthFactor[onBehalfOf]` as the current `healthFactor` so the assertion
    ///      sees a different post-call snapshot than the pre-call snapshot.
    function borrow(
        address, /* asset */
        uint256 amount,
        uint256, /* interestRateMode */
        uint16, /* referralCode */
        address onBehalfOf
    ) external {
        // Bump the user's debt to mirror Aave's effect on `totalDebtBase`. Tests do not assert on
        // the raw debt value — only the health factor — so we use `amount` 1:1 for clarity.
        account[onBehalfOf].totalDebtBase += amount;
        if (nextHealthFactor[onBehalfOf] != 0) {
            account[onBehalfOf].healthFactor = nextHealthFactor[onBehalfOf];
        }
    }
}
