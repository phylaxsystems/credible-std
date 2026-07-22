// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC20Mock} from "../../../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {BoringVaultAssertion} from "../src/BoringVaultAssertion.sol";

contract MockBoringAccountant {
    uint256 internal rate = 1e18;

    function setRate(uint256 rate_) external {
        rate = rate_;
    }

    function getRateInQuote(address) external view returns (uint256) {
        return rate;
    }
}

contract MockBoringVault is ERC20 {
    constructor() ERC20("Mock Boring Vault", "MBV") {}

    function enter(address from, address asset, uint256 assetAmount, address to, uint256 shareAmount) external {
        if (assetAmount != 0) ERC20Mock(asset).transferFrom(from, address(this), assetAmount);
        _mint(to, shareAmount);
    }

    function exit(address to, address asset, uint256 assetAmount, address from, uint256 shareAmount) external {
        _burn(from, shareAmount);
        if (assetAmount != 0) ERC20Mock(asset).transfer(to, assetAmount);
    }
}

contract BoringVaultAssertionTest is Test, CredibleTest {
    ERC20Mock internal asset;
    MockBoringAccountant internal accountant;
    MockBoringVault internal vault;
    address internal alice = makeAddr("alice");

    function setUp() public {
        asset = new ERC20Mock();
        accountant = new MockBoringAccountant();
        vault = new MockBoringVault();

        asset.mint(alice, 1_000 ether);
        vm.prank(alice);
        asset.approve(address(vault), type(uint256).max);
    }

    function _arm(bytes4 fnSelector) internal {
        address[] memory shareOnlyCallers = new address[](1);
        shareOnlyCallers[0] = address(this);
        bytes memory createData = abi.encodePacked(
            type(BoringVaultAssertion).creationCode,
            abi.encode(address(vault), address(accountant), uint8(18), shareOnlyCallers, 0, 0)
        );
        cl.assertion(address(vault), createData, fnSelector);
    }

    function testEnterAccountingPassesWhenSharesMatchAccountantRate() public {
        _arm(BoringVaultAssertion.assertEnterAccounting.selector);

        vm.prank(alice);
        vault.enter(alice, address(asset), 100 ether, alice, 100 ether);
    }

    function testEnterAccountingTripsWhenSharesAreOverMinted() public {
        _arm(BoringVaultAssertion.assertEnterAccounting.selector);

        vm.prank(alice);
        vm.expectRevert(bytes("BoringVault: enter over-minted shares"));
        vault.enter(alice, address(asset), 100 ether, alice, 101 ether);
    }

    function testAuthorizedShareOnlyEnterPasses() public {
        _arm(BoringVaultAssertion.assertEnterAccounting.selector);
        vault.enter(address(0), address(0), 0, alice, 100 ether);
    }

    function testUnauthorizedShareOnlyEnterTrips() public {
        _arm(BoringVaultAssertion.assertEnterAccounting.selector);
        vm.prank(alice);
        vm.expectRevert(bytes("BoringVault: unauthorized share-only caller"));
        vault.enter(address(0), address(0), 0, alice, 100 ether);
    }

    function testNonzeroAssetZeroAmountExitPasses() public {
        vault.enter(address(0), address(0), 0, alice, 100 ether);
        _arm(BoringVaultAssertion.assertExitAccounting.selector);

        vault.exit(alice, address(asset), 0, alice, 50 ether);
    }

    function testAuthorizedShareOnlyExitPasses() public {
        vault.enter(address(0), address(0), 0, address(this), 100 ether);
        _arm(BoringVaultAssertion.assertExitAccounting.selector);

        vault.exit(address(0), address(0), 0, address(this), 50 ether);
    }

    function testUnauthorizedShareOnlyExitTrips() public {
        vault.enter(address(0), address(0), 0, alice, 100 ether);
        _arm(BoringVaultAssertion.assertExitAccounting.selector);

        vm.prank(alice);
        vm.expectRevert(bytes("BoringVault: unauthorized share-only caller"));
        vault.exit(address(0), address(0), 0, alice, 50 ether);
    }
}
