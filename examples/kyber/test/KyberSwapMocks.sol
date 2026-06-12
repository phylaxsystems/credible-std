// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {SwapDescriptionV2, SwapExecutionParams} from "../src/KyberMetaAggregationRouterInterfaces.sol";

/// @notice Standard 18-decimal token with a public mint, used as src/dst in faithful swaps.
contract MintableToken is ERC20 {
    constructor(string memory n, string memory s) ERC20(n, s) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @notice 18-decimal token with a public mint that also honors an EIP-2612 `permit`.
/// @dev Models a permit-capable srcToken. `permit` grants the allowance (emitting the standard
///      `Approval` event) without verifying the signature, i.e. it stands in for a valid signed
///      permit an attacker replays. Used to exercise the permit-then-drain vector: an allowance to
///      the router that is created *inside* the swap call and so is invisible to a pre-call read.
contract PermitMintableToken is ERC20 {
    constructor(string memory n, string memory s) ERC20(n, s) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function permit(address owner, address spender, uint256 value, uint256, uint8, bytes32, bytes32) external {
        _approve(owner, spender, value); // emits Approval(owner, spender, value)
    }
}

/// @notice Fee-on-transfer token: the recipient is credited `value - fee`, the fee goes to a sink.
/// @dev Models the realistic gap the min-return assertion closes: a transfer of `value` succeeds
///      (so a router measuring the gross output is satisfied) while the recipient is credited less.
contract FeeOnTransferToken is ERC20 {
    uint256 public immutable feeBps;
    address public immutable feeSink;

    constructor(uint256 feeBps_, address feeSink_) ERC20("FeeOnTransfer", "FOT") {
        feeBps = feeBps_;
        feeSink = feeSink_;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0) && feeBps != 0) {
            uint256 fee = (value * feeBps) / 10_000;
            super._update(from, to, value - fee);
            super._update(from, feeSink, fee);
        } else {
            super._update(from, to, value);
        }
    }
}

/// @notice Constant-product (Uniswap V2-style) pool used as a realistic liquidity source.
/// @dev Input tokens are transferred in by the router before the executor calls `swap`, matching
///      the on-chain "send-then-swap" pattern. Reserves can be skewed via `setReserves` to model a
///      sandwiched / drifted market that returns less output.
contract MockUniV2Pool {
    address public immutable token0;
    address public immutable token1;
    uint256 public reserve0;
    uint256 public reserve1;

    constructor(address token0_, address token1_) {
        token0 = token0_;
        token1 = token1_;
    }

    function sync() public {
        reserve0 = IERC20(token0).balanceOf(address(this));
        reserve1 = IERC20(token1).balanceOf(address(this));
    }

    function setReserves(uint256 r0, uint256 r1) external {
        reserve0 = r0;
        reserve1 = r1;
    }

    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        public
        pure
        returns (uint256 amountOut)
    {
        uint256 amountInWithFee = amountIn * 997;
        amountOut = (amountInWithFee * reserveOut) / (reserveIn * 1000 + amountInWithFee);
    }

    /// @notice Settles a swap whose input token was already transferred to the pool.
    /// @return amountOut The gross output amount transferred toward `to`.
    function swap(address tokenIn, address to) external returns (uint256 amountOut) {
        (uint256 reserveIn, uint256 reserveOut, address tokenOut) =
            tokenIn == token0 ? (reserve0, reserve1, token1) : (reserve1, reserve0, token0);

        uint256 amountIn = IERC20(tokenIn).balanceOf(address(this)) - reserveIn;
        amountOut = getAmountOut(amountIn, reserveIn, reserveOut);
        IERC20(tokenOut).transfer(to, amountOut);
        sync();
    }
}

/// @notice Honest IAggregationExecutor-style adapter: routes the router's call into a pool swap.
contract MockAggregationExecutor {
    /// @param data abi.encode(pool, tokenIn, recipient)
    /// @return amountOut The gross output the pool reported (what a router measures).
    function callBytes(bytes calldata data) external returns (uint256 amountOut) {
        (address pool, address tokenIn, address to) = abi.decode(data, (address, address, address));
        return MockUniV2Pool(pool).swap(tokenIn, to);
    }
}

/// @notice Helper that pays out its own inventory, with no standing allowance to the router.
/// @dev Used to prove a legitimate third-party-sourced transfer (not an exercised approval) does
///      not trip the approval assertion.
contract SelfFundedPayer {
    function payOut(address token, address to, uint256 amount) external returns (uint256) {
        IERC20(token).transfer(to, amount);
        return amount;
    }
}

/// @notice Faithful MetaAggregationRouterV2 settlement model.
/// @dev Reproduces the observable on-chain behavior the assertions rely on:
///      - source funds and fees are pulled from `msg.sender` against standing allowances and routed
///        to `srcReceivers` / `feeReceivers`;
///      - settlement is delegated to a user-supplied target via a low-level `call` (the executor
///        dispatch — the same opcode an arbitrary-call drain abuses);
///      - min-return is enforced against the executor-reported output, not the recipient's true
///        credited balance, which is exactly why a fork-aware recipient check still adds value.
///      `enforceMinReturn` lets tests model a compromised/buggy router whose own guard is absent.
contract MockKyberRouterV2 {
    address internal constant ETH_SENTINEL = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint256 internal constant _PARTIAL_FILL = 0x01;

    bool public enforceMinReturn = true;

    function setEnforceMinReturn(bool enforce) external {
        enforceMinReturn = enforce;
    }

    /// @notice `swap` entry point. The real router forces the executor `callBytes` selector here;
    ///         the mock issues the raw executor call so a single helper drives every entry point.
    function swap(SwapExecutionParams calldata execution)
        external
        payable
        returns (uint256 returnAmount, uint256 gasUsed)
    {
        returnAmount = _settle(execution.desc, execution.callTarget, execution.targetData);
        return (returnAmount, gasUsed);
    }

    /// @notice `swapGeneric` entry point. On-chain it raw-calls a whitelisted `callTarget`; the
    ///         mock omits the whitelist so the same arbitrary-call drain vector can be exercised.
    function swapGeneric(SwapExecutionParams calldata execution)
        external
        payable
        returns (uint256 returnAmount, uint256 gasUsed)
    {
        returnAmount = _settle(execution.desc, execution.callTarget, execution.targetData);
        return (returnAmount, gasUsed);
    }

    function swapSimpleMode(
        address caller,
        SwapDescriptionV2 calldata desc,
        bytes calldata executorData,
        bytes calldata
    ) external returns (uint256 returnAmount, uint256 gasUsed) {
        returnAmount = _settle(desc, caller, executorData);
        return (returnAmount, gasUsed);
    }

    function _settle(SwapDescriptionV2 calldata desc, address callTarget, bytes calldata targetData)
        internal
        returns (uint256 returnAmount)
    {
        _runPermit(desc.srcToken, desc.permit);

        uint256 spentAmount = _collect(desc.srcToken, desc.srcReceivers, desc.srcAmounts);
        _collect(desc.srcToken, desc.feeReceivers, desc.feeAmounts);

        if (callTarget != address(0)) {
            (bool ok, bytes memory ret) = callTarget.call(targetData);
            require(ok, "MockKyberRouterV2: executor call failed");
            if (ret.length >= 32) {
                returnAmount = abi.decode(ret, (uint256));
            }
        }

        if (enforceMinReturn) {
            // Mirrors MetaAggregationRouterV2._checkReturnAmount: a partial-fill order is held to a
            // pro-rated minimum keyed to the amount actually spent, not the flat minReturnAmount.
            if (desc.flags & _PARTIAL_FILL != 0) {
                require(
                    returnAmount * desc.amount >= desc.minReturnAmount * spentAmount, "Return amount is not enough"
                );
            } else {
                require(returnAmount >= desc.minReturnAmount, "Return amount is not enough");
            }
        }
    }

    /// @notice Mirrors MetaAggregationRouterV2._permit: forwards a 224-byte (7-word) permit blob to
    ///         the srcToken before any funds move, so a swap can establish a router allowance mid-call.
    function _runPermit(address token, bytes calldata permit) internal {
        if (permit.length != 32 * 7) {
            return;
        }
        // permit(address,address,uint256,uint256,uint8,bytes32,bytes32) == 0xd505accf
        (bool ok,) = token.call(abi.encodePacked(bytes4(0xd505accf), permit));
        require(ok, "MockKyberRouterV2: permit failed");
    }

    function _collect(address token, address[] calldata receivers, uint256[] calldata amounts)
        internal
        returns (uint256 total)
    {
        if (token == ETH_SENTINEL) {
            return 0;
        }
        for (uint256 i; i < receivers.length; ++i) {
            if (amounts[i] == 0) {
                continue;
            }
            IERC20(token).transferFrom(msg.sender, receivers[i], amounts[i]);
            total += amounts[i];
        }
    }
}
