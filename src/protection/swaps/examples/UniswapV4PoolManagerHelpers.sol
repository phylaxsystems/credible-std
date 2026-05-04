// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "../../../Assertion.sol";
import {PhEvm} from "../../../PhEvm.sol";
import {AssertionSpec} from "../../../SpecRecorder.sol";

import {IUniswapV4PoolManagerLike} from "./UniswapV4PoolManagerInterfaces.sol";

/// @title UniswapV4PoolManagerHelpers
/// @author Phylax Systems
/// @notice Fork-aware Uniswap v4 PoolManager state helpers used by the example assertions.
/// @dev V4 stores every pool's state inside the singleton PoolManager at slot 6
///      (`mapping(PoolId => Pool.State) _pools`). For each watched pool we compute the per-pool
///      base storage slot once at construction and then read the packed `Slot0`, `liquidity`, and
///      fee growth via the manager's `extsload(bytes32)` precompile. Protocol-fee accruals are
///      tracked globally per currency on the manager, not per pool.
abstract contract UniswapV4PoolManagerHelpers is Assertion {
    uint160 internal constant MIN_SQRT_PRICE = 4_295_128_739;
    uint160 internal constant MAX_SQRT_PRICE = 1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_342;

    /// @dev Storage slot of `mapping(PoolId => Pool.State) _pools` on the PoolManager. Mirrors
    ///      `StateLibrary.POOLS_SLOT` from v4-core.
    uint256 internal constant POOLS_SLOT = 6;

    /// @dev Per-pool offsets inside `Pool.State`. Mirror `StateLibrary` constants in v4-core.
    uint256 internal constant FEE_GROWTH_GLOBAL0_OFFSET = 1;
    uint256 internal constant FEE_GROWTH_GLOBAL1_OFFSET = 2;
    uint256 internal constant LIQUIDITY_OFFSET = 3;

    address internal immutable MANAGER;
    address internal immutable CURRENCY0;
    address internal immutable CURRENCY1;
    bytes32 internal immutable POOL_ID;
    bytes32 internal immutable POOL_STATE_BASE_SLOT;

    struct Slot0Snapshot {
        uint160 sqrtPriceX96;
        int24 tick;
        uint24 protocolFee;
        uint24 lpFee;
    }

    struct PoolSnapshot {
        Slot0Snapshot slot0;
        uint128 liquidity;
        uint256 feeGrowthGlobal0X128;
        uint256 feeGrowthGlobal1X128;
        uint256 protocolFeesAccrued0;
        uint256 protocolFeesAccrued1;
        uint256 managerBalance0;
        uint256 managerBalance1;
    }

    /// @dev Accepts the manager and the full PoolKey explicitly so the constructor never reads
    ///      from the adopter. The Credible Layer assertion-deploy runtime is isolated from the
    ///      calling state, so a `manager.extsload(...)` call in the constructor would revert with
    ///      EXTCODESIZE = 0.
    constructor(address manager_, IUniswapV4PoolManagerLike.PoolKey memory poolKey_) {
        require(manager_ != address(0), "UniswapV4Pool: manager zero");
        require(poolKey_.currency0 < poolKey_.currency1, "UniswapV4Pool: currencies misordered");
        MANAGER = manager_;
        CURRENCY0 = poolKey_.currency0;
        CURRENCY1 = poolKey_.currency1;
        POOL_ID = keccak256(abi.encode(poolKey_));
        POOL_STATE_BASE_SLOT = keccak256(abi.encode(POOL_ID, POOLS_SLOT));
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    function _snapshotAt(PhEvm.ForkId memory fork) internal view returns (PoolSnapshot memory snapshot) {
        snapshot.slot0 = _slot0At(fork);
        snapshot.liquidity = _liquidityAt(fork);
        (snapshot.feeGrowthGlobal0X128, snapshot.feeGrowthGlobal1X128) = _feeGrowthGlobalsAt(fork);
        snapshot.protocolFeesAccrued0 = _protocolFeesAccruedAt(CURRENCY0, fork);
        snapshot.protocolFeesAccrued1 = _protocolFeesAccruedAt(CURRENCY1, fork);
        snapshot.managerBalance0 = _readBalanceAt(CURRENCY0, MANAGER, fork);
        snapshot.managerBalance1 = _readBalanceAt(CURRENCY1, MANAGER, fork);
    }

    function _slot0At(PhEvm.ForkId memory fork) internal view returns (Slot0Snapshot memory slot0) {
        bytes32 packed = _extsloadAt(POOL_STATE_BASE_SLOT, fork);
        slot0.sqrtPriceX96 = uint160(uint256(packed));
        slot0.tick = int24(int256(uint256(packed) >> 160));
        slot0.protocolFee = uint24(uint256(packed) >> 184);
        slot0.lpFee = uint24(uint256(packed) >> 208);
    }

    function _liquidityAt(PhEvm.ForkId memory fork) internal view returns (uint128 liquidity) {
        bytes32 raw = _extsloadAt(_offsetSlot(LIQUIDITY_OFFSET), fork);
        liquidity = uint128(uint256(raw));
    }

    function _feeGrowthGlobalsAt(PhEvm.ForkId memory fork) internal view returns (uint256 g0, uint256 g1) {
        g0 = uint256(_extsloadAt(_offsetSlot(FEE_GROWTH_GLOBAL0_OFFSET), fork));
        g1 = uint256(_extsloadAt(_offsetSlot(FEE_GROWTH_GLOBAL1_OFFSET), fork));
    }

    function _protocolFeesAccruedAt(address currency, PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(MANAGER, abi.encodeCall(IUniswapV4PoolManagerLike.protocolFeesAccrued, (currency)), fork);
    }

    function _extsloadAt(bytes32 slot, PhEvm.ForkId memory fork) internal view returns (bytes32) {
        // `extsload(bytes32)` selector — disambiguated from the array overload.
        bytes memory raw = _viewAt(MANAGER, abi.encodeWithSelector(bytes4(0x1e2eaeaf), slot), fork);
        return abi.decode(raw, (bytes32));
    }

    function _offsetSlot(uint256 offset) internal view returns (bytes32) {
        return bytes32(uint256(POOL_STATE_BASE_SLOT) + offset);
    }

    function _swapArgs(bytes memory input)
        internal
        pure
        returns (
            IUniswapV4PoolManagerLike.PoolKey memory key,
            IUniswapV4PoolManagerLike.SwapParams memory params,
            bytes memory hookData
        )
    {
        return abi.decode(
            _args(input),
            (IUniswapV4PoolManagerLike.PoolKey, IUniswapV4PoolManagerLike.SwapParams, bytes)
        );
    }

    function _modifyLiquidityArgs(bytes memory input)
        internal
        pure
        returns (
            IUniswapV4PoolManagerLike.PoolKey memory key,
            IUniswapV4PoolManagerLike.ModifyLiquidityParams memory params,
            bytes memory hookData
        )
    {
        return abi.decode(
            _args(input),
            (IUniswapV4PoolManagerLike.PoolKey, IUniswapV4PoolManagerLike.ModifyLiquidityParams, bytes)
        );
    }

    function _collectProtocolFeesArgs(bytes memory input)
        internal
        pure
        returns (address recipient, address currency, uint256 amount)
    {
        return abi.decode(_args(input), (address, address, uint256));
    }

    function _inRange(int24 currentTick, int24 tickLower, int24 tickUpper) internal pure returns (bool) {
        return tickLower <= currentTick && currentTick < tickUpper;
    }

    function _matchesConfiguredPool(IUniswapV4PoolManagerLike.PoolKey memory key) internal view returns (bool) {
        return keccak256(abi.encode(key)) == POOL_ID;
    }

    function _requireConfiguredManagerIsAdopter() internal view {
        require(ph.getAssertionAdopter() == MANAGER, "UniswapV4Pool: configured manager is not adopter");
    }

    function _args(bytes memory input) internal pure returns (bytes memory args) {
        require(input.length >= 4, "UniswapV4Pool: short calldata");

        args = new bytes(input.length - 4);
        for (uint256 i; i < args.length; ++i) {
            args[i] = input[i + 4];
        }
    }
}
