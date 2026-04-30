// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {ERC20Mock} from "../../../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {AerodromePoolAssertion} from "../../../src/protection/swaps/examples/AerodromePoolAssertion.sol";

import {MockAerodromePool} from "../../fixtures/swaps/MockAerodromePool.sol";

/// @title AerodromePoolAssertionTest
/// @notice cl.assertion-armed regression tests for the example AerodromePoolAssertion.
/// @dev Exercises the swap-curve invariant (`assertSwapKNonDecreasing`) and the reserve-balance
///      invariant (`assertReservesMatchBalances`). The mock implements only the view surface and
///      a swap mutator with a configurable `Mode` flag.
contract AerodromePoolAssertionTest is Test, CredibleTest {
    address internal poolFees = makeAddr("poolFees");
    ERC20Mock internal token0;
    ERC20Mock internal token1;
    MockAerodromePool internal pool;

    uint256 internal constant SEED_RESERVE = 1_000 ether;

    function setUp() public {
        token0 = new ERC20Mock();
        token1 = new ERC20Mock();
        pool = new MockAerodromePool(address(token0), address(token1), poolFees, false /* volatile */ );

        // Seed the pool with matching reserves and balances so honest paths start at K = r0 * r1.
        token0.mint(address(pool), SEED_RESERVE);
        token1.mint(address(pool), SEED_RESERVE);
        pool.setReserves(SEED_RESERVE, SEED_RESERVE);
        pool.mintLP(address(this), 1 ether);
    }

    function _arm(bytes4 fnSelector) internal {
        bytes memory createData = abi.encodePacked(
            type(AerodromePoolAssertion).creationCode,
            abi.encode(address(pool), address(token0), address(token1), false, uint256(1e18), uint256(1e18))
        );
        cl.assertion(address(pool), createData, fnSelector);
    }

    /// @notice An honest swap that moves more input into the pool than output out keeps K growing.
    function testHonestSwapPassesKCheck() public {
        // Pre-fund the pool with the swap input so balance == reserves + input after we transfer.
        // 110 token0 in, 100 token1 out — k_post > k_pre.
        token0.mint(address(this), 110);
        token0.transfer(address(pool), 110);

        _arm(AerodromePoolAssertion.assertSwapKNonDecreasing.selector);
        pool.swap(0, 100, address(this), "");
    }

    /// @notice An honest swap leaves the pool's reserves equal to its real token balances.
    function testHonestSwapPassesReservesMatchCheck() public {
        token0.mint(address(this), 110);
        token0.transfer(address(pool), 110);

        _arm(AerodromePoolAssertion.assertReservesMatchBalances.selector);
        pool.swap(0, 100, address(this), "");
    }

    /// @notice A swap that artificially decreases reserves trips `K decreased`.
    function testKDecreasingSwapTrips() public {
        token0.mint(address(this), 110);
        token0.transfer(address(pool), 110);
        pool.setMode(MockAerodromePool.Mode.KDecreasing);

        _arm(AerodromePoolAssertion.assertSwapKNonDecreasing.selector);
        vm.expectRevert(bytes("AerodromePool: K decreased"));
        pool.swap(0, 100, address(this), "");
    }

    /// @notice A swap that desyncs reserves from balances trips `reserve0 != balance0`.
    function testReservesBalanceMismatchTrips() public {
        token0.mint(address(this), 110);
        token0.transfer(address(pool), 110);
        pool.setMode(MockAerodromePool.Mode.KDecreasing);

        _arm(AerodromePoolAssertion.assertReservesMatchBalances.selector);
        vm.expectRevert(bytes("AerodromePool: reserve0 != balance0"));
        pool.swap(0, 100, address(this), "");
    }
}
