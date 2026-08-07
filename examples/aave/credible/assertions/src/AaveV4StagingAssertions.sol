// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {AaveV4HubAccountingAssertion} from "aave/AaveV4HubAccountingAssertion.sol";
import {
    AaveV4EthereumCoreHubFlowRateCircuitBreaker,
    AaveV4EthereumPrimeHubFlowRateCircuitBreaker
} from "aave/AaveV4HubFlowRateCircuitBreaker.sol";
import {
    AaveV4EthereumMainSpokeOracleAssertion,
    AaveV4OracleConsumptionAssertion
} from "aave/AaveV4OracleConsumptionAssertion.sol";
import {AaveV4SpokeRiskAssertion} from "aave/AaveV4SpokeRiskAssertion.sol";

// Staging deployment wrappers for the Aave v4 Credible Layer assertion suite
// (Notion: "Aave v4 Credible Layer assertion suite"). Constructor parameters
// are pinned here instead of credible.toml args so the exact deployed
// configuration is reviewable Solidity.
//
// Addresses sourced from the canonical aave-dao/aave-address-book
// AaveV4Ethereum registry (main commit 39aa509 on 2026-08-06), and previously
// verified on-chain at block 25,682,130:
//   Core Hub   0xCca852Bc40e560adC3b1Cc58CA5b55638ce826c9
//   Prime Hub  0x943827DCA022D0F354a8a8c332dA1e5Eb9f9F931
//   Main Spoke 0x94e7A5dCbE816e498b89aB752661904E2F56c485
//     impl 0xABd0E26FE17BDe4F1f1187Ed8aA80C274E03D8b5,
//     oracle 0x99B2B6CEa9C3D2fd8F4d90f86741C44B212a6127 (spoke() round-trips,
//     decimals 8), 14 reserves.
//
// Hub asset IDs read from getAsset(id).underlying at the same block:
//   Core: wstETH = 1, USDG = 8, WBTC = 11; Prime: WBTC = 1, wstETH = 3.
//
// STAGING_VERSION distinguishes assertion bytecode across staging releases:
// the StateOracle refuses to re-add a previously removed assertion id to the
// same adopter, so redeployments after a project teardown need fresh ids.

/// @dev Per-reserve oracle deviation tolerances are an open calibration
///      question in the suite doc. Staging placeholder policy pending
///      empirical per-asset calibration: 100 bps for volatile reserves,
///      50 bps for stables, in Main Spoke reserve-ID order
///      (WETH, wstETH, weETH, WBTC, cbBTC, AAVE, LINK,
///       USDC, USDT, EURC, RLUSD, USDG, frxUSD, GHO).
///      maxTraceCalls = 64 per the deployment guide.
contract AaveV4MainSpokeOracleAssertionStaging is AaveV4EthereumMainSpokeOracleAssertion {
    uint256 public constant STAGING_VERSION = 4;

    constructor()
        AaveV4EthereumMainSpokeOracleAssertion(
            64,
            [uint256(100), 100, 100, 100, 100, 100, 100, 50, 50, 50, 50, 50, 50, 50],
            new AaveV4OracleConsumptionAssertion.ConfigSlotGuard[](0)
        )
    {}
}

/// @dev maxReservesToScan = 16 (14 live reserves + headroom, still bounded
///      within the 3M assertion gas budget); oracle movement bound matches
///      the volatile-reserve envelope above.
contract AaveV4MainSpokeRiskAssertionStaging is AaveV4SpokeRiskAssertion {
    uint256 public constant STAGING_VERSION = 4;

    constructor() AaveV4SpokeRiskAssertion(0x94e7A5dCbE816e498b89aB752661904E2F56c485, 16, 100) {}
}

/// @dev One accounting instance per suite-covered Hub asset. maxSpokesToScan
///      = 16 (observed per-asset spoke counts are 3-6); share-price tolerance
///      1 bps: the platform backtest showed normal Core Hub traffic rounding
///      the added-share price down by sub-bps amounts (tx 0xd40f0a52... at
///      block 25,480,086 reverts with "added share price decreased" at 0 bps).
contract AaveV4CoreHubWstEthAccountingStaging is AaveV4HubAccountingAssertion {
    uint256 public constant STAGING_VERSION = 4;

    constructor() AaveV4HubAccountingAssertion(0xCca852Bc40e560adC3b1Cc58CA5b55638ce826c9, 1, 16, 1) {}
}

contract AaveV4CoreHubUsdgAccountingStaging is AaveV4HubAccountingAssertion {
    uint256 public constant STAGING_VERSION = 4;

    constructor() AaveV4HubAccountingAssertion(0xCca852Bc40e560adC3b1Cc58CA5b55638ce826c9, 8, 16, 1) {}
}

contract AaveV4CoreHubWbtcAccountingStaging is AaveV4HubAccountingAssertion {
    uint256 public constant STAGING_VERSION = 4;

    constructor() AaveV4HubAccountingAssertion(0xCca852Bc40e560adC3b1Cc58CA5b55638ce826c9, 11, 16, 1) {}
}

contract AaveV4PrimeHubWbtcAccountingStaging is AaveV4HubAccountingAssertion {
    uint256 public constant STAGING_VERSION = 4;

    constructor() AaveV4HubAccountingAssertion(0x943827DCA022D0F354a8a8c332dA1e5Eb9f9F931, 1, 16, 1) {}
}

contract AaveV4PrimeHubWstEthAccountingStaging is AaveV4HubAccountingAssertion {
    uint256 public constant STAGING_VERSION = 4;

    constructor() AaveV4HubAccountingAssertion(0x943827DCA022D0F354a8a8c332dA1e5Eb9f9F931, 3, 16, 1) {}
}

/// @dev Private-staging flow policy: 50% rolling 24-hour inflow/outflow and
///      75% peak flow-rate movement in either direction for every watched asset.
///      The parent remains experimental because cumulative dispatch is net-flow based.
contract AaveV4CoreHubFlowBreakerStaging is AaveV4EthereumCoreHubFlowRateCircuitBreaker {
    uint256 public constant STAGING_VERSION = 4;
}

contract AaveV4PrimeHubFlowBreakerStaging is AaveV4EthereumPrimeHubFlowRateCircuitBreaker {
    uint256 public constant STAGING_VERSION = 4;
}
