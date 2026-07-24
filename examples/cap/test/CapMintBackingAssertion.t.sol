// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "../../../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {CapMintBackingAssertion} from "../src/CapMintBackingAssertion.sol";

/// @notice Backing asset with configurable decimals (USDC-like, 6 decimals).
contract MockAsset is ERC20Mock {
    uint8 internal immutable DECIMALS;

    constructor(uint8 decimals_) {
        DECIMALS = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return DECIMALS;
    }
}

/// @notice Cap oracle stand-in. Prices are 8-decimal USD; 1e8 == $1.
contract MockOracle {
    mapping(address => uint256) internal price;

    function setPrice(address asset, uint256 price8) external {
        price[asset] = price8;
    }

    function getPrice(address asset) external view returns (uint256, uint256) {
        return (price[asset], block.timestamp);
    }
}

/// @notice Minimal CapToken/Vault stand-in: it is simultaneously the cUSD ERC20 and the vault
///         that tracks per-asset backing. One knob (`infiniteMint`) mints cUSD without recording
///         or pulling backing, so the solvency assertion can trip exactly that failure.
contract MockCapToken {
    uint8 public constant decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) public totalSupplies;
    mapping(address => uint256) public totalBorrows;
    mapping(address => uint256) public loaned;

    bool public infiniteMint;

    /// @dev Seed a healthy, fully-backed starting state (surplus == 0).
    function seed(address asset, uint256 backingUnits, uint256 capSupply) external {
        totalSupplies[asset] = backingUnits;
        totalSupply = capSupply;
        ERC20Mock(asset).mint(address(this), backingUnits);
    }

    function setInfiniteMint(bool on) external {
        infiniteMint = on;
    }

    /// @dev Honest mint at $1: pull `amountIn` (6dp) asset in, record it as backing, mint the
    ///      18dp face equivalent. Buggy mint skips both the pull and the booking.
    function mint(address asset, uint256 amountIn, uint256, address, uint256) external returns (uint256 amountOut) {
        amountOut = amountIn * 1e12; // 6 -> 18 decimals at $1
        if (!infiniteMint) {
            ERC20Mock(asset).transferFrom(msg.sender, address(this), amountIn);
            totalSupplies[asset] += amountIn;
        }
        totalSupply += amountOut;
    }

    function burn(address asset, uint256 amountIn, uint256, address receiver, uint256)
        external
        returns (uint256 amountOut)
    {
        amountOut = amountIn / 1e12; // 18 -> 6 decimals at $1
        totalSupply -= amountIn;
        totalSupplies[asset] -= amountOut;
        ERC20Mock(asset).transfer(receiver, amountOut);
    }
}

contract CapMintBackingAssertionTest is Test, CredibleTest {
    MockAsset internal usdc;
    MockOracle internal oracle;
    MockCapToken internal cap;

    address internal user = makeAddr("user");
    address internal donor = makeAddr("donor");

    function setUp() public {
        usdc = new MockAsset(6);
        oracle = new MockOracle();
        cap = new MockCapToken();

        oracle.setPrice(address(usdc), 1e8); // $1
        // 1000 USDC backing == 1000 cUSD supply: fully backed, surplus 0.
        cap.seed(address(usdc), 1_000e6, 1_000e18);

        usdc.mint(user, 1_000e6);
        vm.prank(user);
        usdc.approve(address(cap), type(uint256).max);
    }

    function _armSolvency() internal {
        bytes memory createData = abi.encodePacked(
            type(CapMintBackingAssertion).creationCode,
            abi.encode(address(oracle), address(usdc), address(0), address(0), address(0), address(0))
        );
        cl.assertion(address(cap), createData, CapMintBackingAssertion.assertBackingCoversSupply.selector);
    }

    function _armInflow() internal {
        bytes memory createData = abi.encodePacked(
            type(CapMintBackingAssertion).creationCode,
            abi.encode(address(oracle), address(usdc), address(0), address(0), address(0), address(0))
        );
        cl.assertion(address(cap), createData, CapMintBackingAssertion.assertReserveInflowAccounted.selector);
    }

    function policyPrototypeHonestMintStaysBacked() public {
        _armSolvency();
        vm.prank(user);
        cap.mint(address(usdc), 100e6, 0, user, block.timestamp);
    }

    function policyPrototypeInfiniteMintTrips() public {
        cap.setInfiniteMint(true);
        _armSolvency();
        // Mint 100 cUSD with no asset pulled and no backing recorded.
        vm.expectRevert(bytes("CapBacking: backing conservation violated"));
        cap.mint(address(usdc), 100e6, 0, user, block.timestamp);
    }

    function policyPrototypeUnbackedMintWithinBufferTrips() public {
        // Start over-collateralized: $1000 backing vs $900 cUSD (a +$100 surplus buffer).
        cap.seed(address(usdc), 1_000e6, 900e18);
        cap.setInfiniteMint(true);
        _armSolvency();
        // An unbacked 50 cUSD mint stays net-positive ($1000 backing vs $950 supply), so a
        // floor-only check would pass it — but it erodes the buffer, so conservation trips.
        vm.expectRevert(bytes("CapBacking: backing conservation violated"));
        cap.mint(address(usdc), 50e6, 0, user, block.timestamp);
    }

    function policyPrototypeHonestBurnStaysBacked() public {
        _armSolvency();
        vm.prank(user);
        cap.burn(address(usdc), 100e18, 0, user, block.timestamp);
    }

    function policyPrototypeAccountedInflowFromMintPasses() public {
        _armInflow();
        // A large but fully-booked mint: idle and accounted backing rise together.
        vm.prank(user);
        cap.mint(address(usdc), 300e6, 0, user, block.timestamp);
    }

    function policyPrototypeUnaccountedDonationTrips() public {
        usdc.mint(donor, 300e6);
        _armInflow();
        // Direct donation: idle custody jumps with no matching accounting.
        vm.expectRevert(bytes("CapBacking: unaccounted reserve inflow"));
        vm.prank(donor);
        usdc.transfer(address(cap), 300e6);
    }

    function testDeploys() public {
        CapMintBackingAssertion assertion =
            new CapMintBackingAssertion(address(oracle), address(usdc), address(0), address(0), address(0), address(0));
        assertTrue(address(assertion) != address(0));
    }
}
