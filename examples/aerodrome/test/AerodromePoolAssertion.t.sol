// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "../../../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {AerodromePoolAssertion} from "../src/AerodromePoolAssertion.sol";

contract MockAerodromePoolFees {
    function pay(address token, address recipient, uint256 claimed, address extraRecipient, uint256 extra) external {
        if (claimed != 0) ERC20Mock(token).transfer(recipient, claimed);
        if (extra != 0) ERC20Mock(token).transfer(extraRecipient, extra);
    }
}

contract MockAerodromePool {
    enum Mode {
        Honest,
        KDecreasing,
        Underbacked
    }

    address public immutable token0;
    address public immutable token1;
    address public immutable poolFeesAddress;
    bool public immutable stable;

    uint256 public reserve0;
    uint256 public reserve1;
    uint256 public claimed0;
    uint256 public claimed1;
    uint256 public extra0;
    uint256 public extra1;
    address public extraRecipient;
    Mode public mode;

    constructor(address token0_, address token1_, address poolFees_, bool stable_) {
        token0 = token0_;
        token1 = token1_;
        poolFeesAddress = poolFees_;
        stable = stable_;
    }

    function setMode(Mode mode_) external {
        mode = mode_;
    }

    function setReserves(uint256 reserve0_, uint256 reserve1_) external {
        reserve0 = reserve0_;
        reserve1 = reserve1_;
    }

    function configureClaim(
        uint256 claimed0_,
        uint256 claimed1_,
        uint256 extra0_,
        uint256 extra1_,
        address extraRecipient_
    ) external {
        claimed0 = claimed0_;
        claimed1 = claimed1_;
        extra0 = extra0_;
        extra1 = extra1_;
        extraRecipient = extraRecipient_;
    }

    function poolFees() external view returns (address) {
        return poolFeesAddress;
    }

    function metadata()
        external
        view
        returns (uint256 dec0, uint256 dec1, uint256 r0, uint256 r1, bool st, address t0, address t1)
    {
        return (1e18, 1e18, reserve0, reserve1, stable, token0, token1);
    }

    function claimFees() external returns (uint256, uint256) {
        MockAerodromePoolFees fees = MockAerodromePoolFees(poolFeesAddress);
        fees.pay(token0, msg.sender, claimed0, extraRecipient, extra0);
        fees.pay(token1, msg.sender, claimed1, extraRecipient, extra1);
        return (claimed0, claimed1);
    }

    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata) external {
        if (amount0Out != 0) ERC20Mock(token0).transfer(to, amount0Out);
        if (amount1Out != 0) ERC20Mock(token1).transfer(to, amount1Out);

        uint256 nextReserve0 = ERC20Mock(token0).balanceOf(address(this));
        uint256 nextReserve1 = ERC20Mock(token1).balanceOf(address(this));

        if (mode == Mode.KDecreasing) {
            nextReserve0 = nextReserve0 / 2;
        } else if (mode == Mode.Underbacked) {
            nextReserve0 = nextReserve0 + 1;
        }

        reserve0 = nextReserve0;
        reserve1 = nextReserve1;
    }
}

contract AerodromePoolAssertionTest is Test, CredibleTest {
    uint256 internal constant SEED_RESERVE = 1_000 ether;

    ERC20Mock internal token0;
    ERC20Mock internal token1;
    MockAerodromePoolFees internal poolFees;
    MockAerodromePool internal pool;
    address internal attacker = makeAddr("attacker");

    function setUp() public {
        token0 = new ERC20Mock();
        token1 = new ERC20Mock();
        poolFees = new MockAerodromePoolFees();
        pool = new MockAerodromePool(address(token0), address(token1), address(poolFees), false);

        token0.mint(address(pool), SEED_RESERVE);
        token1.mint(address(pool), SEED_RESERVE);
        token0.mint(address(poolFees), 100 ether);
        token1.mint(address(poolFees), 100 ether);
        pool.setReserves(SEED_RESERVE, SEED_RESERVE);
    }

    function _arm(bytes4 fnSelector) internal {
        bytes memory createData = abi.encodePacked(type(AerodromePoolAssertion).creationCode, abi.encode(address(pool)));
        cl.assertion(address(pool), createData, fnSelector);
    }

    function testHonestSwapPassesKCheck() public {
        token0.mint(address(this), 120 ether);
        token0.transfer(address(pool), 120 ether);

        _arm(AerodromePoolAssertion.assertSwapKNonDecreasing.selector);
        pool.swap(0, 100 ether, address(this), "");
    }

    function testSwapThatLowersKTrips() public {
        token0.mint(address(this), 120 ether);
        token0.transfer(address(pool), 120 ether);
        pool.setMode(MockAerodromePool.Mode.KDecreasing);

        _arm(AerodromePoolAssertion.assertSwapKNonDecreasing.selector);
        vm.expectRevert(bytes("AerodromePool: swap decreased K"));
        pool.swap(0, 100 ether, address(this), "");
    }

    function testUnderbackedReserveTrips() public {
        token0.mint(address(this), 120 ether);
        token0.transfer(address(pool), 120 ether);
        pool.setMode(MockAerodromePool.Mode.Underbacked);

        _arm(AerodromePoolAssertion.assertReservesBackedByBalances.selector);
        vm.expectRevert(bytes("AerodromePool: token0 reserves underbacked"));
        pool.swap(0, 100 ether, address(this), "");
    }

    function testHonestClaimFeesMatchesSeparatedCustody() public {
        pool.configureClaim(10 ether, 20 ether, 0, 0, attacker);
        _arm(AerodromePoolAssertion.assertClaimFeesDebitsSeparatedCustody.selector);

        pool.claimFees();
    }

    function testClaimFeesRejectsExcessSeparatedCustodyDebit() public {
        pool.configureClaim(10 ether, 20 ether, 1 ether, 0, attacker);
        _arm(AerodromePoolAssertion.assertClaimFeesDebitsSeparatedCustody.selector);

        vm.expectRevert(bytes("AerodromePool: token0 claim/custody mismatch"));
        pool.claimFees();
    }
}
