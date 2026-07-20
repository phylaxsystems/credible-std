// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "../../../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {
    SymbioticVaultFlowAssertion,
    SymbioticVaultProtection
} from "../src/SymbioticVaultFlowAssertion.sol";

contract MockSymbioticV1Vault {
    ERC20Mock public immutable collateral;
    address public burner;
    address public slasher;
    uint256 public currentEpoch = 2;
    uint256 public activeStake;
    uint256 public activeShares;
    bool public underpayClaim;
    bool public corruptSlashBuckets;

    mapping(uint256 => uint256) public withdrawals;
    mapping(uint256 => uint256) public withdrawalShares;
    mapping(uint256 => mapping(address => uint256)) public withdrawalSharesOf;
    mapping(uint256 => mapping(address => bool)) public isWithdrawalsClaimed;

    constructor(ERC20Mock collateral_, address burner_, address slasher_) {
        collateral = collateral_;
        burner = burner_;
        slasher = slasher_;
    }

    function seedClaim(uint256 epoch, address claimant, uint256 assets, uint256 shares) external {
        withdrawals[epoch] = assets;
        withdrawalShares[epoch] = shares;
        withdrawalSharesOf[epoch][claimant] = shares;
    }

    function seedSlash(uint256 active, uint256 currentQueued, uint256 nextQueued) external {
        activeStake = active;
        withdrawals[currentEpoch] = currentQueued;
        withdrawals[currentEpoch + 1] = nextQueued;
    }

    function setUnderpayClaim(bool enabled) external {
        underpayClaim = enabled;
    }

    function setCorruptSlashBuckets(bool enabled) external {
        corruptSlashBuckets = enabled;
    }

    function claim(address recipient, uint256 epoch) external returns (uint256 amount) {
        require(!isWithdrawalsClaimed[epoch][msg.sender], "already claimed");
        amount = withdrawals[epoch] * withdrawalSharesOf[epoch][msg.sender] / withdrawalShares[epoch];
        if (underpayClaim) amount /= 2;
        isWithdrawalsClaimed[epoch][msg.sender] = true;
        collateral.transfer(recipient, amount);
    }

    function onSlash(uint256 amount, uint48 captureTimestamp) external returns (uint256 slashedAmount) {
        require(msg.sender == slasher, "not slasher");
        require(epochAt(captureTimestamp) == currentEpoch, "test supports current capture");
        uint256 slashable = activeStake + withdrawals[currentEpoch + 1];
        slashedAmount = amount < slashable ? amount : slashable;

        if (corruptSlashBuckets) {
            activeStake -= slashedAmount;
        } else {
            uint256 activeSlashed = slashedAmount * activeStake / slashable;
            activeStake -= activeSlashed;
            withdrawals[currentEpoch + 1] -= slashedAmount - activeSlashed;
        }
        collateral.transfer(burner, slashedAmount);
    }

    function epochAt(uint48 timestamp) public pure returns (uint256) {
        return uint256(timestamp) / 100;
    }
}

contract SymbioticVaultFlowAssertionTest is Test, CredibleTest {
    ERC20Mock internal asset;
    MockSymbioticV1Vault internal vault;
    address internal burner = makeAddr("burner");
    address internal slasher = makeAddr("slasher");
    address internal recipient = makeAddr("recipient");

    function setUp() public {
        asset = new ERC20Mock();
        vault = new MockSymbioticV1Vault(asset, burner, slasher);
        asset.mint(address(vault), 1_000 ether);
    }

    function _arm(bytes4 selector) internal {
        bytes memory createData = abi.encodePacked(
            type(SymbioticVaultProtection).creationCode, abi.encode(address(vault), address(asset))
        );
        cl.assertion(address(vault), createData, selector);
    }

    function testClaimPaysFullEntitlement() public {
        vault.seedClaim(1, address(this), 100 ether, 100 ether);
        _arm(SymbioticVaultFlowAssertion.assertClaimFlow.selector);
        vault.claim(recipient, 1);
    }

    function testUnderpaidClaimCannotConsumeEpoch() public {
        vault.seedClaim(1, address(this), 100 ether, 100 ether);
        vault.setUnderpayClaim(true);
        _arm(SymbioticVaultFlowAssertion.assertClaimFlow.selector);
        vm.expectRevert(bytes("SymbioticVault: claim amount below entitlement"));
        vault.claim(recipient, 1);
    }

    function testCurrentEpochSlashConservesBucketsAndPaysBurner() public {
        vault.seedSlash(100 ether, 30 ether, 20 ether);
        _arm(SymbioticVaultFlowAssertion.assertSlashAccounting.selector);
        vm.prank(slasher);
        vault.onSlash(60 ether, 250);
    }

    function testCorruptSlashBucketAccountingTrips() public {
        vault.seedSlash(100 ether, 30 ether, 20 ether);
        vault.setCorruptSlashBuckets(true);
        _arm(SymbioticVaultFlowAssertion.assertSlashAccounting.selector);
        vm.expectRevert(bytes("SymbioticVault: slashed active stake mismatch"));
        vm.prank(slasher);
        vault.onSlash(60 ether, 250);
    }
}
