// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {
    IRoycoVaultTranche,
    RoycoAssetClaims,
    RoycoKernelStateView,
    RoycoSyncedAccountingState,
    RoycoTrancheType
} from "../src/RoycoHelpers.sol";
import {RoycoVaultTrancheAssertion} from "../src/RoycoVaultTrancheAssertion.sol";
import {RoycoVaultTrancheOperationAssertion} from "../src/RoycoVaultTrancheOperationAssertion.sol";

contract MockRoycoTrancheKernel {
    address public tranche;
    address public protocolFeeRecipient;
    uint256 public expectedFeeShares;

    constructor(address protocolFeeRecipient_) {
        protocolFeeRecipient = protocolFeeRecipient_;
    }

    function setTranche(address tranche_) external {
        tranche = tranche_;
    }

    function setExpectedFeeShares(uint256 expectedFeeShares_) external {
        expectedFeeShares = expectedFeeShares_;
    }

    function getState() external view returns (RoycoKernelStateView memory state) {
        state.protocolFeeRecipient = protocolFeeRecipient;
    }

    function previewSyncTrancheAccounting(RoycoTrancheType)
        external
        view
        returns (RoycoSyncedAccountingState memory state, RoycoAssetClaims memory claims, uint256 totalTrancheShares)
    {
        totalTrancheShares = IRoycoVaultTranche(tranche).totalSupply() + expectedFeeShares;
        return (state, claims, totalTrancheShares);
    }
}

contract MockRoycoVaultTranche is ERC20 {
    address public immutable KERNEL;
    RoycoTrancheType public immutable TRANCHE_TYPE;

    address public extraMintRecipient;
    uint256 public extraMintShares;

    constructor(address kernel_) ERC20("Mock Royco Tranche", "MRT") {
        KERNEL = kernel_;
        TRANCHE_TYPE = RoycoTrancheType.SENIOR;
    }

    function configureExtraMint(address recipient, uint256 shares) external {
        extraMintRecipient = recipient;
        extraMintShares = shares;
    }

    function seed(address account, uint256 shares) external {
        _mint(account, shares);
    }

    function previewDeposit(uint256 assets) external pure returns (uint256 shares) {
        return assets;
    }

    function previewRedeem(uint256 shares) public pure returns (RoycoAssetClaims memory claims) {
        claims = RoycoAssetClaims({stAssets: shares, jtAssets: 0, nav: shares});
    }

    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        MockRoycoTrancheKernel kernel = MockRoycoTrancheKernel(KERNEL);
        uint256 feeShares = kernel.expectedFeeShares();
        if (feeShares != 0) {
            _mint(kernel.protocolFeeRecipient(), feeShares);
        }

        shares = assets;
        _mint(receiver, shares);
        if (extraMintShares != 0) {
            _mint(extraMintRecipient, extraMintShares);
        }
    }

    function redeem(uint256 shares, address, address owner) external returns (RoycoAssetClaims memory claims) {
        MockRoycoTrancheKernel kernel = MockRoycoTrancheKernel(KERNEL);
        uint256 feeShares = kernel.expectedFeeShares();
        if (feeShares != 0) {
            _mint(kernel.protocolFeeRecipient(), feeShares);
        }

        _burn(owner, shares);
        return previewRedeem(shares);
    }
}

contract RoycoVaultTrancheAssertionTest is Test, CredibleTest {
    MockRoycoTrancheKernel internal kernel;
    MockRoycoVaultTranche internal tranche;

    address internal feeRecipient = makeAddr("feeRecipient");
    address internal user = makeAddr("user");
    address internal attacker = makeAddr("attacker");

    function setUp() public {
        kernel = new MockRoycoTrancheKernel(feeRecipient);
        tranche = new MockRoycoVaultTranche(address(kernel));
        kernel.setTranche(address(tranche));
    }

    function testDepositMintsExactUserAndProtocolFeeShares() public {
        kernel.setExpectedFeeShares(5 ether);
        _arm(RoycoVaultTrancheOperationAssertion.assertDepositPreviewConsistency.selector);

        tranche.deposit(100 ether, user);
    }

    function testDepositRejectsExtraThirdPartyMint() public {
        kernel.setExpectedFeeShares(5 ether);
        tranche.configureExtraMint(attacker, 1);
        _arm(RoycoVaultTrancheOperationAssertion.assertDepositPreviewConsistency.selector);

        vm.expectRevert(bytes("Royco: deposit supply delta mismatch"));
        tranche.deposit(100 ether, user);
    }

    function testDepositAccountsForFeeSharesWhenReceiverIsFeeRecipient() public {
        kernel.setExpectedFeeShares(7 ether);
        _arm(RoycoVaultTrancheOperationAssertion.assertDepositPreviewConsistency.selector);

        tranche.deposit(100 ether, feeRecipient);
    }

    function testRedeemAccountsForFeeSharesWhenOwnerIsFeeRecipient() public {
        tranche.seed(feeRecipient, 100 ether);
        kernel.setExpectedFeeShares(150 ether);
        _arm(RoycoVaultTrancheOperationAssertion.assertRedeemPreviewConsistency.selector);

        tranche.redeem(50 ether, user, feeRecipient);
    }

    function _arm(bytes4 fnSelector) internal {
        bytes memory createData = abi.encodePacked(
            type(RoycoVaultTrancheAssertion).creationCode,
            abi.encode(address(tranche), address(kernel), RoycoTrancheType.SENIOR)
        );
        cl.assertion(address(tranche), createData, fnSelector);
    }
}
