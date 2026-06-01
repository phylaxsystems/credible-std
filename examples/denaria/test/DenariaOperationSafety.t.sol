// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {Assertion} from "../../../src/Assertion.sol";
import {CredibleTest} from "../../../src/CredibleTest.sol";
import {PhEvm} from "../../../src/PhEvm.sol";
import {AssertionSpec} from "../../../src/SpecRecorder.sol";
import {DenariaProtectionSuite} from "../src/DenariaOperationSafety.sol";
import {IDenariaPerpPairLike, IDenariaVaultLike} from "../src/DenariaInterfaces.sol";

contract DenariaTradeExecutionAssertion is Assertion {
    uint256 internal constant ORACLE_DECIMALS = 1e8;

    constructor() {
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    function triggers() external view override {
        registerFnCallTrigger(this.assertTradeExecutionAtMark.selector, IDenariaPerpPairLike.trade.selector);
    }

    function assertTradeExecutionAtMark() external view {
        address pair = ph.getAssertionAdopter();
        PhEvm.TriggerContext memory ctx = ph.context();
        bytes memory input = ph.callinputAt(ctx.callStart);

        (bool direction, uint256 tradeSize,,,,,) =
            abi.decode(_stripSelector(input), (bool, uint256, uint256, uint256, address, uint8, bytes));
        uint256 tradeReturn = abi.decode(ph.callOutputAt(ctx.callStart), (uint256));
        uint256 markPrice = _readPrice(pair, PhEvm.ForkId({forkType: 3, callIndex: ctx.callEnd}));

        require(tradeSize == 0 || tradeReturn != 0, "Denaria: empty trade return");
        if (tradeSize == 0) return;

        uint256 executionPrice = direction
            ? tradeSize * ORACLE_DECIMALS / tradeReturn
            : tradeReturn * ORACLE_DECIMALS / tradeSize;
        if (direction) {
            require(executionPrice >= markPrice, "Denaria: long better than mark");
        } else {
            require(executionPrice <= markPrice, "Denaria: short better than mark");
        }
    }

    function _readPrice(address pair, PhEvm.ForkId memory fork) internal view returns (uint256) {
        PhEvm.StaticCallResult memory result =
            ph.staticcallAt(pair, abi.encodeCall(IDenariaPerpPairLike.getPrice, ()), 500_000, fork);
        require(result.ok, "Denaria: price read failed");
        return abi.decode(result.data, (uint256));
    }

    function _stripSelector(bytes memory input) internal pure returns (bytes memory args) {
        require(input.length >= 4, "Denaria: short call input");
        args = new bytes(input.length - 4);
        for (uint256 i; i < args.length; ++i) {
            args[i] = input[i + 4];
        }
    }
}

contract MockDenariaVault {
    mapping(address => uint256) public collateral;

    function setCollateral(address user, uint256 amount) external {
        collateral[user] = amount;
    }

    function userCollateral(address user) external view returns (uint256) {
        return collateral[user];
    }

    function removeCollateral(uint256 amount, bytes memory) external {
        collateral[msg.sender] -= amount;
    }

    function removeAllCollateral(bytes memory) external {
        collateral[msg.sender] = 0;
    }
}

contract MockDenariaPerpPair {
    event ExecutedTrade(
        address indexed user,
        bool direction,
        uint256 tradeSize,
        uint256 tradeReturn,
        uint256 currentPrice,
        uint256 leverage
    );

    uint256 public price;
    bool public returnTooMuchAsset;

    function setPrice(uint256 price_) external {
        price = price_;
    }

    function setReturnTooMuchAsset(bool enabled) external {
        returnTooMuchAsset = enabled;
    }

    function getPrice() external view returns (uint256) {
        return price;
    }

    function trade(bool direction, uint256 size, uint256, uint256, address, uint8 leverage, bytes memory)
        external
        returns (uint256 tradeReturn)
    {
        tradeReturn = direction ? size * 1e8 / price : size * price / 1e8;
        if (returnTooMuchAsset && direction) {
            tradeReturn *= 2;
        }
        emit ExecutedTrade(msg.sender, direction, size, tradeReturn, price, leverage);
    }

    function closeAndWithdraw(uint256, uint256, address, bytes memory) external {}

    function addLiquidity(uint256, uint256, uint256, bytes memory) external {}

    function removeLiquidity(uint256, uint256, uint256, bytes memory) external {}

    function realizePnL(bytes calldata) external pure returns (uint256, bool) {
        return (0, true);
    }

    function liquidate(address, uint256, bytes memory) external {}
}

contract DenariaOperationSafetyTest is Test, CredibleTest {
    uint256 internal constant ORACLE_DECIMALS = 1e8;
    uint256 internal constant TOKEN_UNIT = 1e18;

    MockDenariaPerpPair internal pair;
    MockDenariaVault internal vault;

    function setUp() public {
        pair = new MockDenariaPerpPair();
        vault = new MockDenariaVault();
        pair.setPrice(100 * ORACLE_DECIMALS);
    }

    function testSuiteExposesDenariaSelectors() public {
        DenariaProtectionSuite suite = new DenariaProtectionSuite(address(pair), address(vault));
        bytes4[] memory selectors = suite.getMonitoredSelectors();

        assertEq(selectors.length, 8);
        assertEq(selectors[0], IDenariaPerpPairLike.trade.selector);
        assertEq(selectors[6], IDenariaVaultLike.removeCollateral.selector);
    }

    function testHonestTradePassesExecutionCheck() public {
        bytes memory createData = abi.encodePacked(type(DenariaTradeExecutionAssertion).creationCode);
        cl.assertion(address(pair), createData, DenariaTradeExecutionAssertion.assertTradeExecutionAtMark.selector);

        pair.trade(true, 100 * TOKEN_UNIT, 0, 0, address(0), 1, "");
    }

    function testTradeBetterThanMarkTrips() public {
        pair.setReturnTooMuchAsset(true);

        bytes memory createData = abi.encodePacked(type(DenariaTradeExecutionAssertion).creationCode);
        cl.assertion(address(pair), createData, DenariaTradeExecutionAssertion.assertTradeExecutionAtMark.selector);

        vm.expectRevert(bytes("Denaria: long better than mark"));
        pair.trade(true, 100 * TOKEN_UNIT, 0, 0, address(0), 1, "");
    }
}
