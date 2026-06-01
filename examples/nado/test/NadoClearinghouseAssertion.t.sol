// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "../../../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {NadoClearinghouseAssertion} from "../src/NadoClearinghouseAssertion.sol";
import {INadoClearinghouseLike, INadoSpotEngineLike} from "../src/NadoInterfaces.sol";

contract MockNadoSpotEngine {
    address public productToken;
    bool public shortCredit;
    mapping(uint32 => mapping(bytes32 => int128)) internal balances;

    constructor(address productToken_) {
        productToken = productToken_;
    }

    function setShortCredit(bool enabled) external {
        shortCredit = enabled;
    }

    function credit(uint32 productId, bytes32 subaccount, uint128 amount) external {
        uint128 credited = shortCredit ? amount - 1 : amount;
        balances[productId][subaccount] += int128(credited);
    }

    function getConfig(uint32) external view returns (INadoSpotEngineLike.Config memory config) {
        config.token = productToken;
    }

    function getBalance(uint32 productId, bytes32 subaccount)
        external
        view
        returns (INadoSpotEngineLike.Balance memory balance)
    {
        balance.amount = balances[productId][subaccount];
    }
}

contract MockNadoClearinghouse {
    MockNadoSpotEngine public immutable spotEngine;

    constructor(MockNadoSpotEngine spotEngine_) {
        spotEngine = spotEngine_;
    }

    function depositCollateral(INadoClearinghouseLike.DepositCollateral calldata txn) external {
        spotEngine.credit(txn.productId, txn.sender, txn.amount);
    }
}

contract NadoClearinghouseAssertionTest is Test, CredibleTest {
    uint32 internal constant PRODUCT_ID = 1;
    bytes32 internal constant SUBACCOUNT = bytes32(uint256(0xA11CE));

    ERC20Mock internal quoteAsset;
    MockNadoSpotEngine internal spotEngine;
    MockNadoClearinghouse internal clearinghouse;

    function setUp() public {
        quoteAsset = new ERC20Mock();
        spotEngine = new MockNadoSpotEngine(address(quoteAsset));
        clearinghouse = new MockNadoClearinghouse(spotEngine);
    }

    function _arm() internal {
        bytes memory createData = abi.encodePacked(
            type(NadoClearinghouseAssertion).creationCode,
            abi.encode(
                address(0),
                address(clearinghouse),
                address(spotEngine),
                address(quoteAsset),
                address(0),
                0,
                2_500,
                1_000,
                3_000,
                1 days
            )
        );
        cl.assertion(address(clearinghouse), createData, NadoClearinghouseAssertion.assertDepositCreditsSpotBalance.selector);
    }

    function _deposit(uint128 amount) internal {
        clearinghouse.depositCollateral(
            INadoClearinghouseLike.DepositCollateral({sender: SUBACCOUNT, productId: PRODUCT_ID, amount: amount})
        );
    }

    function testDepositCreditsSpotBalance() public {
        _arm();
        _deposit(100 ether);
    }

    function testDepositTripsWhenSpotCreditIsShort() public {
        spotEngine.setShortCredit(true);

        _arm();
        vm.expectRevert(bytes("Nado: deposit spot credit mismatch"));
        _deposit(100 ether);
    }
}
