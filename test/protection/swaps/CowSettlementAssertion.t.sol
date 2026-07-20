// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {ERC20Mock} from "../../../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {CowSettlementAssertion} from "../../../src/protection/swaps/examples/CowSettlementAssertion.sol";
import {IGPv2SettlementLike} from "../../../src/protection/swaps/examples/CowSettlementInterfaces.sol";

/// @notice Faithful, knob-driven stand-in for GPv2Settlement. It exposes the exact `settle`/`swap`
///         selectors and reproduces the real on-chain footprint of a settlement (pull the sell token
///         from the user, pay the buy token to the receiver, retain fees as buffer) plus the two
///         malicious footprints the assertions target:
///         - paying batch surplus to the solver (caller), and
///         - moving the accumulated buffer out to an unauthorized recipient.
contract MockGPv2Settlement {
    event Trade(
        address indexed owner,
        address sellToken,
        address buyToken,
        uint256 sellAmount,
        uint256 buyAmount,
        uint256 feeAmount,
        bytes orderUid
    );

    enum Mode {
        Honest,
        SolverSiphon
    }

    address public immutable USER;
    address public immutable RECEIVER;
    ERC20Mock public immutable SELL_TOKEN;
    ERC20Mock public immutable BUY_TOKEN;

    uint256 public sellAmount;
    uint256 public buyAmount;
    uint256 public surplus;
    Mode public mode;

    constructor(address user_, address receiver_, ERC20Mock sellToken_, ERC20Mock buyToken_) {
        USER = user_;
        RECEIVER = receiver_;
        SELL_TOKEN = sellToken_;
        BUY_TOKEN = buyToken_;
    }

    function configureTrade(uint256 sellAmount_, uint256 buyAmount_, uint256 surplus_, Mode mode_) external {
        sellAmount = sellAmount_;
        buyAmount = buyAmount_;
        surplus = surplus_;
        mode = mode_;
    }

    /// @dev Selector 0x13d79a0b — identical to mainnet GPv2Settlement.settle. Args are accepted to
    ///      match the real calldata shape but the scenario is driven by `configureTrade`.
    function settle(
        address[] calldata,
        uint256[] calldata,
        IGPv2SettlementLike.TradeData[] calldata,
        IGPv2SettlementLike.InteractionData[][3] calldata
    ) external {
        _executeConfiguredTrade();
    }

    /// @dev Selector 0x845a101f — identical to mainnet GPv2Settlement.swap.
    function swap(
        IGPv2SettlementLike.BatchSwapStep[] calldata,
        address[] calldata,
        IGPv2SettlementLike.TradeData calldata
    ) external {
        _executeConfiguredTrade();
    }

    /// @notice Authorized DAO sweep of accumulated buffer to the reward Safe.
    function sweep(address token, address sweepRecipient, uint256 amount) external {
        ERC20Mock(token).transfer(sweepRecipient, amount);
    }

    /// @notice Unauthorized buffer outflow (the drain footprint of the 2023-style incident).
    function drainTo(address token, address to, uint256 amount) external {
        ERC20Mock(token).transfer(to, amount);
    }

    function _executeConfiguredTrade() internal {
        // Pull the user's signed sell amount into the settlement contract.
        SELL_TOKEN.transferFrom(USER, address(this), sellAmount);
        // Pay the user (receiver) their bought tokens.
        BUY_TOKEN.transfer(RECEIVER, buyAmount);
        emit Trade(USER, address(SELL_TOKEN), address(BUY_TOKEN), sellAmount, buyAmount, 0, "");
        // Malicious: route batch surplus to the solver (the caller) instead of the user / buffer.
        if (mode == Mode.SolverSiphon) {
            BUY_TOKEN.transfer(msg.sender, surplus);
        }
    }
}

contract MockSolverForwarder {
    function settle(MockGPv2Settlement settlement) external {
        address[] memory tokens = new address[](0);
        uint256[] memory prices = new uint256[](0);
        IGPv2SettlementLike.TradeData[] memory trades = new IGPv2SettlementLike.TradeData[](0);
        IGPv2SettlementLike.InteractionData[][3] memory interactions;
        settlement.settle(tokens, prices, trades, interactions);
    }
}

contract CowSettlementAssertionTest is Test, CredibleTest {
    ERC20Mock internal sellToken;
    ERC20Mock internal buyToken;
    ERC20Mock internal dai; // accumulated fee buffer token

    MockGPv2Settlement internal settlement;

    address internal solver = makeAddr("solver");
    address internal user = makeAddr("cowUser");
    address internal sweepRecipient = makeAddr("daoSweep");
    address internal attacker = makeAddr("attacker");

    uint256 internal constant SELL = 1_000e18;
    uint256 internal constant BUY = 990e18;
    uint256 internal constant SURPLUS = 25e18;
    uint256 internal constant BUFFER = 500_000e18;

    function setUp() public {
        sellToken = new ERC20Mock();
        buyToken = new ERC20Mock();
        dai = new ERC20Mock();

        settlement = new MockGPv2Settlement(user, user, sellToken, buyToken);

        // User funds + approval, exactly as a CoW user approves the settlement/relayer to pull.
        sellToken.mint(user, SELL);
        vm.prank(user);
        sellToken.approve(address(settlement), type(uint256).max);

        // Settlement holds enough buy-token liquidity to pay the user and (in the malicious case)
        // the siphoned surplus, plus an accumulated DAI fee buffer.
        buyToken.mint(address(settlement), BUY + SURPLUS);
        dai.mint(address(settlement), BUFFER);
    }

    // ----------------------------------------------------------------
    //  Selector / configuration fidelity
    // ----------------------------------------------------------------

    function testSettlementSelectorsMatchMainnetGPv2() external pure {
        assertEq(
            IGPv2SettlementLike.settle.selector,
            bytes4(
                keccak256(
                    "settle(address[],uint256[],(uint256,uint256,address,uint256,uint256,uint32,bytes32,uint256,uint256,uint256,bytes)[],(address,uint256,bytes)[][3])"
                )
            ),
            "settle"
        );
        assertEq(IGPv2SettlementLike.settle.selector, bytes4(0x13d79a0b), "settle mainnet selector");
        assertEq(
            IGPv2SettlementLike.swap.selector,
            bytes4(
                keccak256(
                    "swap((bytes32,uint256,uint256,uint256,bytes)[],address[],(uint256,uint256,address,uint256,uint256,uint32,bytes32,uint256,uint256,uint256,bytes))"
                )
            ),
            "swap"
        );
        assertEq(IGPv2SettlementLike.swap.selector, bytes4(0x845a101f), "swap mainnet selector");
    }

    // ----------------------------------------------------------------
    //  Inventory protection — assertBufferConserved
    // ----------------------------------------------------------------

    function testAuthorizedBufferSweepPasses() public {
        _armBuffer();
        vm.prank(solver, solver);
        settlement.sweep(address(dai), sweepRecipient, 50_000e18);
    }

    function testBufferDrainToUnauthorizedRecipientTrips() public {
        _armBuffer();
        vm.expectRevert(bytes("CowSettlement: external buffer drain"));
        vm.prank(attacker, attacker);
        settlement.drainTo(address(dai), attacker, 200_000e18);
    }

    function testWatchedTokenCanBeUsedAsSettlementLiquidity() public {
        settlement.configureTrade(SELL, BUY, 0, MockGPv2Settlement.Mode.Honest);

        _armBufferFor(address(buyToken));
        vm.prank(solver, solver);
        _settle();
    }

    // ----------------------------------------------------------------
    //  Helpers
    // ----------------------------------------------------------------

    function _settle() internal {
        address[] memory tokens = new address[](0);
        uint256[] memory prices = new uint256[](0);
        IGPv2SettlementLike.TradeData[] memory trades = new IGPv2SettlementLike.TradeData[](0);
        IGPv2SettlementLike.InteractionData[][3] memory interactions;
        settlement.settle(tokens, prices, trades, interactions);
    }

    function _armBuffer() internal {
        _arm(CowSettlementAssertion.assertBufferConserved.selector);
    }

    function _armBufferFor(address bufferToken) internal {
        _arm(CowSettlementAssertion.assertBufferConserved.selector, bufferToken);
    }

    function _arm(bytes4 fnSelector) internal {
        _arm(fnSelector, address(dai));
    }

    function _arm(bytes4 fnSelector, address bufferToken) internal {
        address[] memory bufferTokens = new address[](1);
        bufferTokens[0] = bufferToken;

        bytes memory createData = abi.encodePacked(
            type(CowSettlementAssertion).creationCode,
            abi.encode(address(settlement), sweepRecipient, bufferTokens, uint256(0))
        );

        cl.assertion(address(settlement), createData, fnSelector);
    }
}
