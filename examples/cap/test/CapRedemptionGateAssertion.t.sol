// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "../../../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {CapRedemptionGateAssertion} from "../src/CapRedemptionGateAssertion.sol";

/// @notice Minimal Cap cUSD vault stand-in. Every gated path moves the watched asset out of the
///         vault so the built-in cumulative-outflow watcher fires and the tiered gate can react.
contract MockCapVault {
    mapping(address => uint256) public loaned;

    address internal immutable ASSET;
    address internal immutable STRATEGY;

    constructor(address asset_, address strategy_) {
        ASSET = asset_;
        STRATEGY = strategy_;
    }

    function borrow(address asset, uint256 amount, address receiver) external {
        ERC20Mock(asset).transfer(receiver, amount);
    }

    function burn(address asset, uint256 amountIn, uint256, address receiver, uint256)
        external
        returns (uint256 amountOut)
    {
        ERC20Mock(asset).transfer(receiver, amountIn);
        return amountIn;
    }

    function redeem(uint256 amountIn, uint256[] calldata, address receiver, uint256)
        external
        returns (uint256[] memory amountsOut)
    {
        ERC20Mock(ASSET).transfer(receiver, amountIn);
        amountsOut = new uint256[](1);
        amountsOut[0] = amountIn;
    }

    function investAll(address asset) external {
        ERC20Mock(asset).transfer(STRATEGY, 60 ether);
    }

    function setLoaned(address asset, uint256 amount) external {
        loaned[asset] = amount;
    }
}

contract CapRedemptionGateAssertionTest is Test, CredibleTest {
    ERC20Mock internal asset;
    MockCapVault internal vault;
    address internal receiver = makeAddr("receiver");
    address internal strategy = makeAddr("strategy");

    function setUp() public {
        asset = new ERC20Mock();
        vault = new MockCapVault(address(asset), strategy);
        // 100e18 idle TVL: outflow bps == ethers moved out (e.g. 20 ether out == 2000 bps).
        asset.mint(address(vault), 100 ether);
    }

    function _arm() internal {
        bytes memory createData = abi.encodePacked(
            type(CapRedemptionGateAssertion).creationCode,
            abi.encode(address(asset), address(0), address(0), address(0), address(0))
        );
        cl.assertion(address(vault), createData, CapRedemptionGateAssertion.assertCapRedemptionGate.selector);
    }

    function testSmallBorrowOutflowPassesBelowGateTier() public {
        _arm();
        // 1% outflow stays under the 15% tier-2 floor, so nothing is gated.
        vault.borrow(address(asset), 1 ether, receiver);
    }

    function testLargeBorrowTripsBorrowGate() public {
        _arm();
        // 20% outflow clears the 15% borrow tier.
        vm.expectRevert(bytes("CapGate: borrow disabled"));
        vault.borrow(address(asset), 20 ether, receiver);
    }

    function testRedeemBelowTier3StillAllowed() public {
        _arm();
        // 20% outflow trips the borrow tier but not the 30% redemption tier, so redeem passes.
        uint256[] memory minOut;
        vault.redeem(20 ether, minOut, receiver, block.timestamp);
    }

    function testRedeemTripsRedemptionGate() public {
        _arm();
        // 35% outflow clears the 30% redemption tier.
        uint256[] memory minOut;
        vm.expectRevert(bytes("CapGate: redemption capacity reached"));
        vault.redeem(35 ether, minOut, receiver, block.timestamp);
    }

    function testBurnTripsRedemptionGate() public {
        _arm();
        // burn is the second redemption path gated at the 30% tier.
        vm.expectRevert(bytes("CapGate: redemption capacity reached"));
        vault.burn(address(asset), 35 ether, 0, receiver, block.timestamp);
    }

    function testInvestAllTripsInvestGate() public {
        _arm();
        // investAll moves 60% of TVL into a strategy, clearing the 50% invest tier.
        vm.expectRevert(bytes("CapGate: invest disabled"));
        vault.investAll(address(asset));
    }

    function testAssertionDeploysWithWatchedAsset() public {
        CapRedemptionGateAssertion assertion =
            new CapRedemptionGateAssertion(address(asset), address(0), address(0), address(0), address(0));
        assertTrue(address(assertion) != address(0));
    }
}
