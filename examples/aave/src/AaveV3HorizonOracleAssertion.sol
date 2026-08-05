// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "credible-std/PhEvm.sol";

import {
    IAaveV3LikeAddressesProvider,
    IAaveV3LikePool
} from "credible-std/protection/lending/examples/AaveV3LikeInterfaces.sol";
import {AaveV3HorizonHelpers} from "./AaveV3HorizonHelpers.sol";
import {IAaveV3HorizonOracle, IAaveV3HorizonSource} from "./AaveV3HorizonInterfaces.sol";

/// @title AaveV3HorizonOracleAssertion
/// @author Phylax Systems
/// @notice Prevents Horizon risk operations from consuming a same-transaction manipulated price.
/// @dev The assertion:
///      - Fires once after a transaction containing successful risk-sensitive Pool operations.
///      - Inspects exact AaveOracle returns consumed by the Pool, including intermediate values
///        that were restored before PostTx.
///      - Compares each consumed return with its configured asset's PreTx oracle value.
///      - Rejects writes to the pinned AaveOracle source/fallback slots, including write-restore.
///      - Inspects the Pool's actual provider return so temporary provider swaps cannot hide.
///      This is a same-transaction consumption guard. It does not prove that the PreTx price was
///      independently correct or detect manipulation completed in an earlier transaction.
contract AaveV3HorizonOracleAssertion is AaveV3HorizonHelpers {
    uint256 internal constant ASSET_SOURCES_MAPPING_SLOT = 0;
    bytes32 internal constant FALLBACK_ORACLE_SLOT = bytes32(uint256(1));

    struct AssetPolicy {
        address asset;
        uint256 deviationBps;
    }

    address internal immutable POOL;
    address internal immutable ADDRESSES_PROVIDER;
    uint256 internal immutable MAX_TRACE_CALLS;

    AssetPolicy[] internal assetPolicies;

    /// @param pool_ Horizon Pool that adopts the assertion.
    /// @param addressesProvider_ PoolAddressesProvider used by that Pool.
    /// @param maxTraceCalls_ Fail-closed bound for matching provider/oracle/source calls.
    /// @param assetPolicies_ Complete active-reserve list with per-asset deviation tolerances.
    constructor(
        address pool_,
        address addressesProvider_,
        uint256 maxTraceCalls_,
        AssetPolicy[] memory assetPolicies_
    ) {
        require(pool_ != address(0), "AaveV3Horizon: pool zero");
        require(addressesProvider_ != address(0), "AaveV3Horizon: provider zero");
        require(maxTraceCalls_ != 0, "AaveV3Horizon: max trace calls zero");
        require(maxTraceCalls_ < type(uint256).max, "AaveV3Horizon: max trace calls too large");
        require(assetPolicies_.length != 0, "AaveV3Horizon: empty asset policies");

        POOL = pool_;
        ADDRESSES_PROVIDER = addressesProvider_;
        MAX_TRACE_CALLS = maxTraceCalls_;

        for (uint256 i; i < assetPolicies_.length; ++i) {
            AssetPolicy memory policy = assetPolicies_[i];
            require(policy.asset != address(0), "AaveV3Horizon: policy asset zero");
            require(policy.deviationBps < BPS, "AaveV3Horizon: bad asset tolerance");

            for (uint256 j; j < i; ++j) {
                require(assetPolicies_[j].asset != policy.asset, "AaveV3Horizon: duplicate asset policy");
            }

            assetPolicies.push(policy);
        }
    }

    /// @notice Registers one transaction-end trace check for Pool-consumed prices.
    /// @dev The assertion executes once for multicalls but examines intermediate call inputs and
    ///      outputs, so a manipulated price restored before PostTx remains observable.
    function triggers() external view override {
        registerTxEndTrigger(this.assertConsumedOraclePricesSafe.selector);
    }

    /// @notice Verifies exact oracle values consumed during successful risk-sensitive Pool calls.
    /// @dev Resolves configured assets and their sources at PreTx, rejects any source/fallback
    ///      storage writes in the transaction, and maps each source `latestAnswer` call to its
    ///      parent AaveOracle call. The parent call's actual return is compared with the PreTx price.
    ///      Every Pool-originated AaveOracle call must map to a configured source; unknown or
    ///      fallback-only price paths fail closed.
    function assertConsumedOraclePricesSafe() external view {
        _requireAdopter(POOL, "AaveV3Horizon: configured pool is not adopter");
        if (!_hasRiskOperation()) {
            return;
        }

        PhEvm.ForkId memory preTx = _preTx();
        PhEvm.ForkId memory postTx = _postTx();

        address oracle = _oracleAt(ADDRESSES_PROVIDER, preTx);
        require(oracle != address(0), "AaveV3Horizon: oracle zero");
        require(
            _oracleAt(ADDRESSES_PROVIDER, postTx) == oracle, "AaveV3Horizon: provider oracle changed during transaction"
        );

        _assertAssetPoliciesComplete(preTx);
        _assertAssetPoliciesComplete(postTx);

        uint256 policyCount = assetPolicies.length;
        address[] memory sources = new address[](policyCount);
        uint256[] memory baselinePrices = new uint256[](policyCount);

        for (uint256 i; i < policyCount; ++i) {
            AssetPolicy memory policy = assetPolicies[i];
            address source = _sourceOfAssetAt(oracle, policy.asset, preTx);
            require(source != address(0), "AaveV3Horizon: fallback-only asset unsupported");

            uint256 baselinePrice = _assetPriceAt(oracle, policy.asset, preTx);
            require(baselinePrice != 0, "AaveV3Horizon: baseline oracle price invalid");

            sources[i] = source;
            baselinePrices[i] = baselinePrice;
        }

        _assertOracleConfigurationUnchanged(oracle);
        _assertPoolProviderReturns(oracle);
        _assertConsumedPrices(oracle, sources, baselinePrices);
    }

    function assetPolicyCount() external view returns (uint256) {
        return assetPolicies.length;
    }

    function assetPolicy(uint256 index) external view returns (AssetPolicy memory) {
        return assetPolicies[index];
    }

    function _assertAssetPoliciesComplete(PhEvm.ForkId memory fork) internal view {
        address[] memory reserves = _reservesListAt(POOL, fork);
        require(reserves.length == assetPolicies.length, "AaveV3Horizon: unrecognized Pool oracle price path");

        for (uint256 i; i < reserves.length; ++i) {
            bool configured;
            for (uint256 j; j < assetPolicies.length; ++j) {
                if (reserves[i] == assetPolicies[j].asset) {
                    configured = true;
                    break;
                }
            }
            require(configured, "AaveV3Horizon: unrecognized Pool oracle price path");
        }
    }

    function _assertOracleConfigurationUnchanged(address oracle) internal view {
        require(
            ph.getStateChanges(oracle, FALLBACK_ORACLE_SLOT).length == 0,
            "AaveV3Horizon: fallback oracle changed during transaction"
        );

        for (uint256 i; i < assetPolicies.length; ++i) {
            bytes32 sourceSlot = keccak256(abi.encode(assetPolicies[i].asset, ASSET_SOURCES_MAPPING_SLOT));
            require(
                ph.getStateChanges(oracle, sourceSlot).length == 0,
                "AaveV3Horizon: reserve oracle source changed during transaction"
            );
        }
    }

    function _assertPoolProviderReturns(address expectedOracle) internal view {
        PhEvm.CallInputs[] memory providerCalls =
            ph.getStaticCallInputs(ADDRESSES_PROVIDER, IAaveV3LikeAddressesProvider.getPriceOracle.selector);
        require(providerCalls.length <= MAX_TRACE_CALLS, "AaveV3Horizon: too many provider calls");

        bool poolProviderCallSeen;
        for (uint256 i; i < providerCalls.length; ++i) {
            if (providerCalls[i].caller != POOL) {
                continue;
            }

            poolProviderCallSeen = true;
            bytes memory output = ph.callOutputAt(providerCalls[i].id);
            require(output.length == 32, "AaveV3Horizon: malformed provider output");
            require(abi.decode(output, (address)) == expectedOracle, "AaveV3Horizon: Pool consumed a different oracle");
        }
        require(poolProviderCallSeen, "AaveV3Horizon: Pool skipped oracle provider");
    }

    function _assertConsumedPrices(address oracle, address[] memory sources, uint256[] memory baselinePrices)
        internal
        view
    {
        PhEvm.CallInputs[] memory priceCalls =
            ph.getStaticCallInputs(oracle, IAaveV3HorizonOracle.getAssetPrice.selector);
        require(priceCalls.length <= MAX_TRACE_CALLS, "AaveV3Horizon: too many oracle calls");

        bool[] memory mappedPriceCalls = new bool[](priceCalls.length);
        PhEvm.CallFilter memory filter = PhEvm.CallFilter({
            callType: 2, minDepth: 0, maxDepth: type(uint32).max, topLevelOnly: false, successOnly: true
        });

        for (uint256 i; i < assetPolicies.length; ++i) {
            PhEvm.TriggerCall[] memory sourceCalls =
                ph.matchingCalls(sources[i], IAaveV3HorizonSource.latestAnswer.selector, filter, MAX_TRACE_CALLS + 1);
            require(sourceCalls.length <= MAX_TRACE_CALLS, "AaveV3Horizon: too many source calls");

            for (uint256 j; j < sourceCalls.length; ++j) {
                if (sourceCalls[j].caller != oracle) {
                    continue;
                }

                for (uint256 k; k < priceCalls.length; ++k) {
                    if (priceCalls[k].caller != POOL || priceCalls[k].id != sourceCalls[j].parentCallId) {
                        continue;
                    }
                    (bool assetAvailable, address priceCallAsset) = _priceCallAsset(priceCalls[k].input);
                    if (assetAvailable && priceCallAsset != assetPolicies[i].asset) {
                        continue;
                    }

                    bytes memory output = ph.callOutputAt(priceCalls[k].id);
                    require(output.length == 32, "AaveV3Horizon: malformed oracle output");
                    uint256 consumedPrice = abi.decode(output, (uint256));

                    _requirePriceWithinPolicy(baselinePrices[i], consumedPrice, assetPolicies[i].deviationBps);
                    mappedPriceCalls[k] = true;
                }
            }
        }

        bool poolPriceCallSeen;
        for (uint256 i; i < priceCalls.length; ++i) {
            if (priceCalls[i].caller == POOL) {
                poolPriceCallSeen = true;
                require(mappedPriceCalls[i], "AaveV3Horizon: unrecognized Pool oracle price path");
            }
        }
        require(poolPriceCallSeen, "AaveV3Horizon: Pool skipped oracle prices");
    }

    function _priceCallAsset(bytes memory priceCallInput) internal pure returns (bool available, address asset) {
        if (priceCallInput.length != 0) {
            require(priceCallInput.length == 32, "AaveV3Horizon: malformed oracle input");
            return (true, abi.decode(priceCallInput, (address)));
        }

        // PCL 1.6 omits nested STATICCALL input. Reserve-policy completeness above keeps
        // source-only matching fail closed until that runtime exposes the documented calldata.
        return (false, address(0));
    }

    function _requirePriceWithinPolicy(uint256 baselinePrice, uint256 consumedPrice, uint256 deviationBps)
        internal
        view
    {
        require(consumedPrice != 0, "AaveV3Horizon: consumed oracle price invalid");

        if (deviationBps == 0) {
            require(consumedPrice == baselinePrice, "AaveV3Horizon: consumed oracle price deviated");
            return;
        }

        uint256 lowerBound = ph.mulDivDown(baselinePrice, BPS - deviationBps, BPS);
        uint256 upperBound = ph.mulDivUp(baselinePrice, BPS + deviationBps, BPS);
        require(
            consumedPrice >= lowerBound && consumedPrice <= upperBound, "AaveV3Horizon: consumed oracle price deviated"
        );
    }

    function _hasRiskOperation() internal view returns (bool) {
        return _matchingCalls(POOL, IAaveV3LikePool.borrow.selector, 1).length != 0
            || _matchingCalls(POOL, IAaveV3LikePool.withdraw.selector, 1).length != 0
            || _matchingCalls(POOL, IAaveV3LikePool.setUserUseReserveAsCollateral.selector, 1).length != 0
            || _matchingCalls(POOL, IAaveV3LikePool.finalizeTransfer.selector, 1).length != 0
            || _matchingCalls(POOL, IAaveV3LikePool.setUserEMode.selector, 1).length != 0
            || _matchingCalls(POOL, IAaveV3LikePool.liquidationCall.selector, 1).length != 0
            || _matchingCalls(POOL, IAaveV3LikePool.flashLoan.selector, 1).length != 0;
    }
}
