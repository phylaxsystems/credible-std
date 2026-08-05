// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "credible-std/PhEvm.sol";

import {AaveV4OracleConsumptionHelpers} from "./AaveV4OracleConsumptionHelpers.sol";
import {IAaveV4Oracle, IAaveV4Spoke} from "./AaveV4Interfaces.sol";

/// @title AaveV4OracleConsumptionAssertion
/// @author Phylax Systems
/// @notice Prevents an Aave v4 Spoke from consuming a same-transaction manipulated oracle price.
/// @dev The assertion:
///      - Executes once at transaction end and scans all committed nested price reads.
///      - Compares exact `AaveOracle.getReservePrice` returns with PreTx batch baselines.
///      - Maps every return through its direct configured `IPriceFeed.latestAnswer()` child.
///      - Rejects source, Spoke implementation, source proxy, and configured adapter-slot writes,
///        including writes restored before transaction end.
///      - Fails closed on incomplete reserve policy, malformed traces, unknown reserve IDs, or
///        trace limits.
///      It does not prove that a PreTx price is economically correct. Manipulation completed
///      before the protected transaction is outside this same-transaction invariant.
contract AaveV4OracleConsumptionAssertion is AaveV4OracleConsumptionHelpers {
    struct ReservePolicy {
        uint256 reserveId;
        address asset;
        address source;
        uint256 deviationBps;
    }

    struct ConfigSlotGuard {
        address target;
        bytes32 slot;
    }

    uint256 internal constant MAX_POLICY_COUNT = 64;
    uint256 internal constant MAX_CONFIG_GUARD_COUNT = 128;
    uint256 internal constant MAX_ALLOWED_TRACE_CALLS = 512;

    address internal immutable SPOKE;
    address internal immutable ORACLE;
    address internal immutable EXPECTED_SPOKE_IMPLEMENTATION;
    uint256 internal immutable MAX_TRACE_CALLS;

    ReservePolicy[] internal reservePolicies;
    ConfigSlotGuard[] internal configSlotGuards;

    /// @param spoke_ The exact Aave v4 Spoke proxy adopting the assertion.
    /// @param oracle_ The immutable AaveOracle selected by the pinned Spoke implementation.
    /// @param expectedSpokeImplementation_ The ERC-1967 implementation expected at PreTx.
    ///        Use zero only for a verified non-proxy Spoke test/deployment.
    /// @param maxTraceCalls_ Maximum matching oracle calls; exceeding it fails closed.
    /// @param reservePolicies_ Complete contiguous reserve-ID policy set for the Spoke.
    /// @param configSlotGuards_ Extra mutable adapter/router slots whose writes can affect prices.
    constructor(
        address spoke_,
        address oracle_,
        address expectedSpokeImplementation_,
        uint256 maxTraceCalls_,
        ReservePolicy[] memory reservePolicies_,
        ConfigSlotGuard[] memory configSlotGuards_
    ) {
        require(spoke_ != address(0), "AaveV4Oracle: spoke zero");
        require(oracle_ != address(0), "AaveV4Oracle: oracle zero");
        require(maxTraceCalls_ != 0 && maxTraceCalls_ <= MAX_ALLOWED_TRACE_CALLS, "AaveV4Oracle: bad trace limit");
        require(
            reservePolicies_.length != 0 && reservePolicies_.length <= MAX_POLICY_COUNT,
            "AaveV4Oracle: bad policy count"
        );
        require(configSlotGuards_.length <= MAX_CONFIG_GUARD_COUNT, "AaveV4Oracle: too many config guards");

        SPOKE = spoke_;
        ORACLE = oracle_;
        EXPECTED_SPOKE_IMPLEMENTATION = expectedSpokeImplementation_;
        MAX_TRACE_CALLS = maxTraceCalls_;

        for (uint256 i; i < reservePolicies_.length; ++i) {
            ReservePolicy memory policy = reservePolicies_[i];
            require(policy.reserveId == i, "AaveV4Oracle: policies not contiguous");
            require(policy.asset != address(0), "AaveV4Oracle: policy asset zero");
            require(policy.source != address(0), "AaveV4Oracle: policy source zero");
            require(policy.deviationBps < BPS, "AaveV4Oracle: bad tolerance");
            for (uint256 j; j < i; ++j) {
                require(reservePolicies_[j].source != policy.source, "AaveV4Oracle: source must map one reserve");
            }
            reservePolicies.push(policy);
        }

        for (uint256 i; i < configSlotGuards_.length; ++i) {
            ConfigSlotGuard memory guard = configSlotGuards_[i];
            require(guard.target != address(0), "AaveV4Oracle: guard target zero");
            for (uint256 j; j < i; ++j) {
                ConfigSlotGuard memory previous = configSlotGuards_[j];
                require(
                    previous.target != guard.target || previous.slot != guard.slot,
                    "AaveV4Oracle: duplicate config guard"
                );
            }
            configSlotGuards.push(guard);
        }
    }

    /// @notice Registers one transaction-end check for all committed V4 price consumption.
    /// @dev A transaction-end trigger preserves intermediate nested call nodes and outputs while
    ///      avoiding one full reserve-policy scan for every multicall leg. Nested oracle calldata
    ///      is not assumed to be available; see `_mapPriceCallToSource`.
    function triggers() external view override {
        registerTxEndTrigger(this.assertConsumedOraclePricesSafe.selector);
    }

    /// @notice Checks exact prices returned to successful risk-sensitive Spoke operations.
    /// @dev Only committed `withdraw`, `borrow`, `liquidationCall`, collateral-disable,
    ///      risk-premium refresh, and dynamic-config refresh calls select the check. Price reads in
    ///      caught reverted calls are excluded by the successful-call trace. A failure means the
    ///      Spoke consumed an unconfigured, malformed, or out-of-policy intermediate price, or a
    ///      price-routing/configuration surface was written during the transaction.
    function assertConsumedOraclePricesSafe() external view {
        _requireAdopter(SPOKE, "AaveV4Oracle: configured spoke is not adopter");

        PhEvm.TriggerCall[] memory priceCalls =
            _successfulStaticCalls(ORACLE, IAaveV4Oracle.getReservePrice.selector, MAX_TRACE_CALLS + 1);
        require(priceCalls.length <= MAX_TRACE_CALLS, "AaveV4Oracle: trace limit exceeded");

        uint256 spokePriceCallCount;
        for (uint256 i; i < priceCalls.length; ++i) {
            if (priceCalls[i].caller == SPOKE) {
                ++spokePriceCallCount;
            }
        }

        bool mandatoryPriceOperation;
        if (spokePriceCallCount == 0) {
            mandatoryPriceOperation = _hasMandatoryPriceOperation(SPOKE, MAX_TRACE_CALLS);
        }
        if (spokePriceCallCount == 0 && !mandatoryPriceOperation) {
            return;
        }

        PhEvm.ForkId memory preTx = _preTx();
        PhEvm.ForkId memory postTx = _postTx();
        _assertSpokeAndOracleIdentity(preTx, postTx);
        _assertRoutingConfigurationUnchanged();
        require(spokePriceCallCount != 0, "AaveV4Oracle: unrecognized price path");

        uint256[] memory baselinePrices = _loadAndValidatePreTxPolicy(preTx);
        _assertConsumedPrices(priceCalls, baselinePrices);
    }

    function reservePolicyCount() external view returns (uint256) {
        return reservePolicies.length;
    }

    function reservePolicy(uint256 index) external view returns (ReservePolicy memory) {
        return reservePolicies[index];
    }

    function configSlotGuardCount() external view returns (uint256) {
        return configSlotGuards.length;
    }

    function configSlotGuard(uint256 index) external view returns (ConfigSlotGuard memory) {
        return configSlotGuards[index];
    }

    function _assertSpokeAndOracleIdentity(PhEvm.ForkId memory preTx, PhEvm.ForkId memory postTx) internal view {
        require(_spokeOracleAt(SPOKE, preTx) == ORACLE, "AaveV4Oracle: unexpected PreTx oracle");
        require(_spokeOracleAt(SPOKE, postTx) == ORACLE, "AaveV4Oracle: Spoke oracle changed");
        require(_oracleSpokeAt(ORACLE, preTx) == SPOKE, "AaveV4Oracle: oracle-Spoke mismatch");
        require(_oracleDecimalsAt(ORACLE, preTx) == ORACLE_DECIMALS, "AaveV4Oracle: wrong oracle decimals");

        bytes32 preImplementation = ph.loadStateAt(SPOKE, ERC1967_IMPLEMENTATION_SLOT, preTx);
        bytes32 postImplementation = ph.loadStateAt(SPOKE, ERC1967_IMPLEMENTATION_SLOT, postTx);
        address expected = EXPECTED_SPOKE_IMPLEMENTATION;
        require(address(uint160(uint256(preImplementation))) == expected, "AaveV4Oracle: unexpected implementation");
        require(address(uint160(uint256(postImplementation))) == expected, "AaveV4Oracle: implementation changed");
        require(
            ph.getStateChanges(SPOKE, ERC1967_IMPLEMENTATION_SLOT).length == 0, "AaveV4Oracle: implementation written"
        );
        require(ph.getStateChanges(SPOKE, ERC1967_BEACON_SLOT).length == 0, "AaveV4Oracle: beacon written");
    }

    function _loadAndValidatePreTxPolicy(PhEvm.ForkId memory preTx)
        internal
        view
        returns (uint256[] memory baselinePrices)
    {
        uint256 policyCount = reservePolicies.length;
        require(_reserveCountAt(SPOKE, preTx) == policyCount, "AaveV4Oracle: incomplete reserve policy");

        uint256[] memory reserveIds = new uint256[](policyCount);
        for (uint256 i; i < policyCount; ++i) {
            ReservePolicy memory policy = reservePolicies[i];
            IAaveV4Spoke.Reserve memory reserve = _spokeReserveAt(SPOKE, policy.reserveId, preTx);
            require(reserve.underlying == policy.asset, "AaveV4Oracle: reserve asset mismatch");
            require(
                _reserveSourceAt(ORACLE, policy.reserveId, preTx) == policy.source,
                "AaveV4Oracle: unexpected PreTx source"
            );
            reserveIds[i] = policy.reserveId;
        }

        baselinePrices = _reservePricesAt(ORACLE, reserveIds, preTx);
        require(baselinePrices.length == policyCount, "AaveV4Oracle: malformed baseline prices");
        for (uint256 i; i < policyCount; ++i) {
            require(baselinePrices[i] != 0, "AaveV4Oracle: invalid PreTx price");
        }
    }

    function _assertRoutingConfigurationUnchanged() internal view {
        for (uint256 i; i < reservePolicies.length; ++i) {
            ReservePolicy memory policy = reservePolicies[i];
            require(
                ph.getStateChanges(ORACLE, _sourceSlot(policy.reserveId)).length == 0,
                "AaveV4Oracle: reserve source written"
            );
        }

        for (uint256 i; i < configSlotGuards.length; ++i) {
            ConfigSlotGuard memory guard = configSlotGuards[i];
            require(ph.getStateChanges(guard.target, guard.slot).length == 0, "AaveV4Oracle: guarded config written");
        }
    }

    function _assertConsumedPrices(PhEvm.TriggerCall[] memory priceCalls, uint256[] memory baselinePrices)
        internal
        view
    {
        PhEvm.TriggerCall[][] memory sourceCalls = new PhEvm.TriggerCall[][](reservePolicies.length);
        uint256 scannedSourceCalls;
        for (uint256 reserveId; reserveId < reservePolicies.length; ++reserveId) {
            sourceCalls[reserveId] = _successfulSourceReads(reservePolicies[reserveId].source, MAX_TRACE_CALLS + 1);
            require(sourceCalls[reserveId].length <= MAX_TRACE_CALLS, "AaveV4Oracle: source trace limit exceeded");
            scannedSourceCalls += sourceCalls[reserveId].length;
            require(scannedSourceCalls <= MAX_TRACE_CALLS, "AaveV4Oracle: source trace limit exceeded");
        }

        for (uint256 i; i < priceCalls.length; ++i) {
            PhEvm.TriggerCall memory priceCall = priceCalls[i];
            if (priceCall.caller != SPOKE) {
                continue;
            }

            (uint256 reserveId, int256 sourceAnswer) = _mapPriceCallToSource(priceCall, sourceCalls);
            bytes memory priceOutput = ph.callOutputAt(priceCall.callId);
            require(priceOutput.length == 32, "AaveV4Oracle: malformed oracle output");
            uint256 consumedPrice = abi.decode(priceOutput, (uint256));
            require(sourceAnswer > 0, "AaveV4Oracle: invalid source answer");
            require(uint256(sourceAnswer) == consumedPrice, "AaveV4Oracle: source/output mismatch");

            ReservePolicy memory policy = reservePolicies[reserveId];
            _requireWithinDeviation(baselinePrices[reserveId], consumedPrice, policy.deviationBps);
        }
    }

    /// @dev PCL v2 currently exposes an empty `TriggerCall.input` for the nested STATICCALL
    ///      generated by this compiler path. AaveOracle itself always performs exactly one direct
    ///      external `latestAnswer()` call to the selected source. Unique configured sources,
    ///      direct parent-call IDs, and equality between child and parent outputs therefore provide
    ///      an exact, trace-proven reserve mapping without relying on unavailable nested calldata.
    function _mapPriceCallToSource(PhEvm.TriggerCall memory priceCall, PhEvm.TriggerCall[][] memory sourceCalls)
        internal
        view
        returns (uint256 mappedReserveId, int256 sourceAnswer)
    {
        uint256 matches;
        for (uint256 reserveId; reserveId < sourceCalls.length; ++reserveId) {
            for (uint256 j; j < sourceCalls[reserveId].length; ++j) {
                PhEvm.TriggerCall memory sourceCall = sourceCalls[reserveId][j];
                if (sourceCall.caller != ORACLE || sourceCall.parentCallId != priceCall.callId) {
                    continue;
                }

                ++matches;
                mappedReserveId = reserveId;
                bytes memory sourceOutput = ph.callOutputAt(sourceCall.callId);
                require(sourceOutput.length == 32, "AaveV4Oracle: malformed source output");
                sourceAnswer = abi.decode(sourceOutput, (int256));
            }
        }
        require(matches == 1, "AaveV4Oracle: unconfigured price path");
    }

    function _requireWithinDeviation(uint256 baselinePrice, uint256 consumedPrice, uint256 deviationBps) internal view {
        require(consumedPrice != 0, "AaveV4Oracle: invalid consumed price");
        if (deviationBps == 0) {
            require(consumedPrice == baselinePrice, "AaveV4Oracle: consumed price deviated");
            return;
        }

        uint256 lowerBound = ph.mulDivDown(baselinePrice, BPS - deviationBps, BPS);
        uint256 upperBound = ph.mulDivUp(baselinePrice, BPS + deviationBps, BPS);
        require(consumedPrice >= lowerBound && consumedPrice <= upperBound, "AaveV4Oracle: consumed price deviated");
    }
}

/// @title AaveV4EthereumMainSpokeOracleAssertion
/// @author Phylax Systems
/// @notice Ready-to-configure assertion pinned to Aave v4 Ethereum Main Spoke release v0.5.11.
/// @dev Addresses and reserve ordering are verified at Ethereum block 25,646,732. The wrapper
///      pins the deployed Spoke implementation, AaveOracle, all 14 reserve assets, and their
///      current oracle sources. Deploy a new assertion after a legitimate implementation,
///      reserve, or source migration.
contract AaveV4EthereumMainSpokeOracleAssertion is AaveV4OracleConsumptionAssertion {
    address public constant MAIN_SPOKE = 0x94e7A5dCbE816e498b89aB752661904E2F56c485;
    address public constant MAIN_SPOKE_ORACLE = 0x99B2B6CEa9C3D2fd8F4d90f86741C44B212a6127;
    address public constant MAIN_SPOKE_IMPLEMENTATION = 0xABd0E26FE17BDe4F1f1187Ed8aA80C274E03D8b5;

    /// @param maxTraceCalls_ Fail-closed transaction-wide oracle-call bound.
    /// @param deviationBps_ Per-reserve tolerances in Main Spoke reserve-ID order.
    /// @param configSlotGuards_ Additional mutable adapter configuration slots to protect.
    constructor(uint256 maxTraceCalls_, uint256[14] memory deviationBps_, ConfigSlotGuard[] memory configSlotGuards_)
        AaveV4OracleConsumptionAssertion(
            MAIN_SPOKE,
            MAIN_SPOKE_ORACLE,
            MAIN_SPOKE_IMPLEMENTATION,
            maxTraceCalls_,
            _mainSpokePolicies(deviationBps_),
            _mainSpokeConfigGuards(configSlotGuards_)
        )
    {}

    /// @dev Verified mutable routing/cap slots for the exact source graph at block 25,646,732.
    ///      Chainlink EACAggregatorProxy keeps its active phase/aggregator in slot 2.
    ///      PriceCapAdapterBase keeps its packed cap parameters in slots 1 and 2.
    ///      PriceCapAdapterStable and EURPriceCapAdapterStable keep the active cap in slot 2.
    function _mainSpokeConfigGuards(ConfigSlotGuard[] memory extra)
        private
        pure
        returns (ConfigSlotGuard[] memory guards)
    {
        guards = new ConfigSlotGuard[](22 + extra.length);
        uint256 i;

        // Direct or transitively consumed Chainlink EACAggregatorProxy active-phase slots.
        guards[i++] = ConfigSlotGuard(0x5424384B256154046E9667dDFaaa5e550145215e, bytes32(uint256(2))); // WETH/USD
        guards[i++] = ConfigSlotGuard(0xb41E773f507F7a7EA890b1afB7d2b660c30C8B0A, bytes32(uint256(2))); // cbBTC/USD
        guards[i++] = ConfigSlotGuard(0xF02C1e2A3B77c1cacC72f72B44f7d0a4c62e4a85, bytes32(uint256(2))); // AAVE/USD
        guards[i++] = ConfigSlotGuard(0xC7e9b623ed51F033b32AE7f1282b1AD62C28C183, bytes32(uint256(2))); // LINK/USD
        guards[i++] = ConfigSlotGuard(0xfdFD9C85aD200c506Cf9e21F1FD8dd01932FBB23, bytes32(uint256(2))); // WBTC/BTC
        guards[i++] = ConfigSlotGuard(0xEa674bBC33AE708Bc9EB4ba348b04E4eB55b496b, bytes32(uint256(2))); // USDC/USD
        guards[i++] = ConfigSlotGuard(0x3E7d1eAB13ad0104d2750B8863b489D65364e32D, bytes32(uint256(2))); // USDT/USD
        guards[i++] = ConfigSlotGuard(0x26C46B7aD0012cA71F2298ada567dC9Af14E7f2A, bytes32(uint256(2))); // RLUSD/USD
        guards[i++] = ConfigSlotGuard(0x14f0737d6b705259e521EA6E9E3506AC78dBd311, bytes32(uint256(2))); // USDG/USD
        guards[i++] = ConfigSlotGuard(0x9B4a96210bc8D9D55b1908B465D8B0de68B7fF83, bytes32(uint256(2))); // frxUSD/USD
        guards[i++] = ConfigSlotGuard(0x04F84020Fdf10d9ee64D1dcC2986EDF2F556DA11, bytes32(uint256(2))); // EURC/USD
        guards[i++] = ConfigSlotGuard(0xb49f677943BC038e9857d61E7d053CaA2C1734C1, bytes32(uint256(2))); // EUR/USD

        // Mutable CAPO parameter slots.
        guards[i++] = ConfigSlotGuard(0xe1D97bF61901B075E9626c8A2340a7De385861Ef, bytes32(uint256(1)));
        guards[i++] = ConfigSlotGuard(0xe1D97bF61901B075E9626c8A2340a7De385861Ef, bytes32(uint256(2)));
        guards[i++] = ConfigSlotGuard(0x87625393534d5C102cADB66D37201dF24cc26d4C, bytes32(uint256(1)));
        guards[i++] = ConfigSlotGuard(0x87625393534d5C102cADB66D37201dF24cc26d4C, bytes32(uint256(2)));
        guards[i++] = ConfigSlotGuard(0x3f73F03aa83B2A48ed27E964eD0fDb590332095B, bytes32(uint256(2)));
        guards[i++] = ConfigSlotGuard(0x260326c220E469358846b187eE53328303Efe19C, bytes32(uint256(2)));
        guards[i++] = ConfigSlotGuard(0xf0eaC18E908B34770FDEe46d069c846bDa866759, bytes32(uint256(2)));
        guards[i++] = ConfigSlotGuard(0x83D20dEEdcd4aC1313496c8CBcAad0fa298c0CE4, bytes32(uint256(2)));
        guards[i++] = ConfigSlotGuard(0x25DEd2f9aE6ae9416693AB63Abe3aB25493861FD, bytes32(uint256(2)));
        guards[i++] = ConfigSlotGuard(0xa6aB031A4d189B24628EC9Eb155F0a0f1A0E55a3, bytes32(uint256(2)));

        for (uint256 j; j < extra.length; ++j) {
            guards[i++] = extra[j];
        }
    }

    function _mainSpokePolicies(uint256[14] memory d) private pure returns (ReservePolicy[] memory policies) {
        policies = new ReservePolicy[](14);
        policies[0] = ReservePolicy(
            0, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, 0x5424384B256154046E9667dDFaaa5e550145215e, d[0]
        );
        policies[1] = ReservePolicy(
            1, 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0, 0xe1D97bF61901B075E9626c8A2340a7De385861Ef, d[1]
        );
        policies[2] = ReservePolicy(
            2, 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee, 0x87625393534d5C102cADB66D37201dF24cc26d4C, d[2]
        );
        policies[3] = ReservePolicy(
            3, 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599, 0xDaa4B74C6bAc4e25188e64ebc68DB5050b690cAc, d[3]
        );
        policies[4] = ReservePolicy(
            4, 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf, 0xb41E773f507F7a7EA890b1afB7d2b660c30C8B0A, d[4]
        );
        policies[5] = ReservePolicy(
            5, 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9, 0xF02C1e2A3B77c1cacC72f72B44f7d0a4c62e4a85, d[5]
        );
        policies[6] = ReservePolicy(
            6, 0x514910771AF9Ca656af840dff83E8264EcF986CA, 0xC7e9b623ed51F033b32AE7f1282b1AD62C28C183, d[6]
        );
        policies[7] = ReservePolicy(
            7, 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, 0x3f73F03aa83B2A48ed27E964eD0fDb590332095B, d[7]
        );
        policies[8] = ReservePolicy(
            8, 0xdAC17F958D2ee523a2206206994597C13D831ec7, 0x260326c220E469358846b187eE53328303Efe19C, d[8]
        );
        policies[9] = ReservePolicy(
            9, 0x1aBaEA1f7C830bD89Acc67eC4af516284b1bC33c, 0xa6aB031A4d189B24628EC9Eb155F0a0f1A0E55a3, d[9]
        );
        policies[10] = ReservePolicy(
            10, 0x8292Bb45bf1Ee4d140127049757C2E0fF06317eD, 0xf0eaC18E908B34770FDEe46d069c846bDa866759, d[10]
        );
        policies[11] = ReservePolicy(
            11, 0xe343167631d89B6Ffc58B88d6b7fB0228795491D, 0x83D20dEEdcd4aC1313496c8CBcAad0fa298c0CE4, d[11]
        );
        policies[12] = ReservePolicy(
            12, 0xCAcd6fd266aF91b8AeD52aCCc382b4e165586E29, 0x25DEd2f9aE6ae9416693AB63Abe3aB25493861FD, d[12]
        );
        policies[13] = ReservePolicy(
            13, 0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f, 0xD110cac5d8682A3b045D5524a9903E031d70FCCd, d[13]
        );
    }
}
