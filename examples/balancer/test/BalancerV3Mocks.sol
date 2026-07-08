// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Rounding, SwapKind, TokenInfo, TokenType, VaultSwapParams} from "../src/BalancerV3VaultInterfaces.sol";

interface IMockERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

/// @notice Rate provider mock with a settable rate for drift tests.
contract MockRateProvider {
    uint256 public rate = 1e18;

    function setRate(uint256 rate_) external {
        rate = rate_;
    }

    function getRate() external view returns (uint256) {
        return rate;
    }
}

/// @notice Pool math mock: the invariant is the sum of live balances, so directional value
///         movement maps one-to-one onto invariant movement and each test can steer it exactly.
contract MockBalancerV3Pool {
    function computeInvariant(uint256[] memory balancesLiveScaled18, Rounding) external pure returns (uint256) {
        uint256 invariant;
        for (uint256 i; i < balancesLiveScaled18.length; ++i) {
            invariant += balancesLiveScaled18[i];
        }
        return invariant;
    }
}

/// @notice Balancer V3 Vault mock: two-token pool, reserve/fee ledgers matching the real Vault's
///         getter surface, and one failure knob per invariant so each test trips exactly one check.
contract MockBalancerV3Vault {
    enum Mode {
        Honest,
        InvariantLoss, // pays out more tokenOut than the curve allows
        SupplyDrift, // mints BPT during a swap
        BalanceSwapEnds, // recorded balances move against the swap direction, invariant preserved
        ReserveSkim, // real tokens leave the Vault without the reserve ledger noticing
        PhantomBalance, // inflates the pool's recorded balance with no reserve backing
        RateShift // moves the rate provider mid-swap
    }

    uint256 internal constant FEE_DIVISOR = 100; // 1% mock swap fee

    address public immutable pool;
    MockRateProvider public immutable rateProvider0;

    address[] internal _tokens;
    uint256[] internal _balancesRaw;
    mapping(address token => uint256) public reservesOf;
    mapping(address token => uint256) internal _aggregateSwapFees;
    uint256 internal _bptSupply = 100e18;
    Mode public mode;
    address public skimReceiver;

    constructor(address pool_, address token0_, address token1_, MockRateProvider rateProvider0_) {
        pool = pool_;
        rateProvider0 = rateProvider0_;
        _tokens.push(token0_);
        _tokens.push(token1_);
        _balancesRaw.push(0);
        _balancesRaw.push(0);
    }

    // --- test knobs ---------------------------------------------------------

    function setMode(Mode mode_) external {
        mode = mode_;
    }

    function setSkimReceiver(address receiver) external {
        skimReceiver = receiver;
    }

    function seedPoolBalance(uint256 index, uint256 amount) external {
        _balancesRaw[index] = amount;
    }

    function seedReserves(address token, uint256 amount) external {
        reservesOf[token] = amount;
    }

    function seedAggregateSwapFee(address token, uint256 amount) external {
        _aggregateSwapFees[token] = amount;
    }

    // --- swap ----------------------------------------------------------------

    function swap(VaultSwapParams calldata params)
        external
        returns (uint256 amountCalculated, uint256 amountIn, uint256 amountOut)
    {
        if (params.pool != pool) {
            return (0, 0, 0);
        }

        uint256 indexIn = _indexOf(params.tokenIn);
        uint256 indexOut = _indexOf(params.tokenOut);
        amountIn = params.amountGivenRaw;
        uint256 fee = amountIn / FEE_DIVISOR;
        amountOut = mode == Mode.InvariantLoss ? amountIn * 2 : amountIn - 2 * fee;
        amountCalculated = amountOut;

        if (mode == Mode.BalanceSwapEnds) {
            // Recorded balances flow against the swap direction while the sum invariant holds.
            _balancesRaw[indexIn] -= amountIn;
            _balancesRaw[indexOut] += amountIn;
            return (amountCalculated, amountIn, amountOut);
        }

        IMockERC20(params.tokenIn).transferFrom(msg.sender, address(this), amountIn);
        IMockERC20(params.tokenOut).transfer(msg.sender, amountOut);

        reservesOf[params.tokenIn] += amountIn;
        reservesOf[params.tokenOut] -= amountOut;
        _balancesRaw[indexIn] += amountIn - fee;
        _aggregateSwapFees[params.tokenIn] += fee;
        _balancesRaw[indexOut] -= amountOut;

        if (mode == Mode.SupplyDrift) {
            _bptSupply += 1e18;
        } else if (mode == Mode.ReserveSkim) {
            IMockERC20(params.tokenOut).transfer(skimReceiver, 10e18);
        } else if (mode == Mode.PhantomBalance) {
            _balancesRaw[indexOut] += 600e18;
        } else if (mode == Mode.RateShift) {
            rateProvider0.setRate(rateProvider0.rate() * 2);
        }
    }

    // --- IBalancerV3VaultLike getter surface ----------------------------------

    function getPoolTokens(address) external view returns (address[] memory) {
        return _tokens;
    }

    function getPoolTokenInfo(address)
        external
        view
        returns (
            address[] memory tokens,
            TokenInfo[] memory tokenInfo,
            uint256[] memory balancesRaw,
            uint256[] memory lastBalancesLiveScaled18
        )
    {
        tokens = _tokens;
        tokenInfo = new TokenInfo[](2);
        tokenInfo[0] =
            TokenInfo({tokenType: TokenType.WITH_RATE, rateProvider: address(rateProvider0), paysYieldFees: false});
        tokenInfo[1] = TokenInfo({tokenType: TokenType.STANDARD, rateProvider: address(0), paysYieldFees: false});
        balancesRaw = _balancesRaw;
        lastBalancesLiveScaled18 = _balancesRaw;
    }

    function getCurrentLiveBalances(address) external view returns (uint256[] memory) {
        return _balancesRaw;
    }

    function getAggregateSwapFeeAmount(address, address token) external view returns (uint256) {
        return _aggregateSwapFees[token];
    }

    function getAggregateYieldFeeAmount(address, address) external pure returns (uint256) {
        return 0;
    }

    function getReservesOf(address token) external view returns (uint256) {
        return reservesOf[token];
    }

    function totalSupply(address) external view returns (uint256) {
        return _bptSupply;
    }

    function isPoolInitialized(address) external pure returns (bool) {
        return true;
    }

    function _indexOf(address token) internal view returns (uint256) {
        for (uint256 i; i < _tokens.length; ++i) {
            if (_tokens[i] == token) {
                return i;
            }
        }
        revert("MockVault: unknown token");
    }
}
