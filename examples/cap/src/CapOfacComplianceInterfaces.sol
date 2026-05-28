// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// @notice Hypothetical OFAC compliance precompile.
/// @dev Returns true when `account` appears on the sanctions list.
interface IOfacCompliancePrecompile {
    function isListed(address account) external view returns (bool listed);
}

interface ICapAccessControlLike {
    function grantAccess(bytes4 selector, address target, address account) external;
    function revokeAccess(bytes4 selector, address target, address account) external;
}

interface ICapERC20Like {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);

    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external;
}

interface ICapERC4626Like {
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function mint(uint256 shares, address receiver) external returns (uint256 assets);
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
}

interface ICapLenderLike {
    function borrow(address asset, uint256 amount, address receiver) external returns (uint256 borrowed);
    function repay(address asset, uint256 amount, address agent) external returns (uint256 repaid);
    function realizeRestakerInterest(address agent, address asset) external returns (uint256 actualRealized);
    function openLiquidation(address agent) external;
    function closeLiquidation(address agent) external;
    function liquidate(address agent, address asset, uint256 amount, uint256 minLiquidatedValue)
        external
        returns (uint256 liquidatedValue);
    function setInterestReceiver(address asset, address interestReceiver) external;
}

interface ICapStabledropLike {
    function approveOperator(address operator, bool approved) external;
    function approveOperatorFor(address claimant, address operator, bool approved) external;
    function claim(address claimant, address recipient, uint256 amount, bytes32[] calldata proofs) external;
    function recoverERC20(address token, address to, uint256 amount) external;
}

interface ICapVaultLike {
    function mint(address asset, uint256 amountIn, uint256 minAmountOut, address receiver, uint256 deadline)
        external
        returns (uint256 amountOut);
    function burn(address asset, uint256 amountIn, uint256 minAmountOut, address receiver, uint256 deadline)
        external
        returns (uint256 amountOut);
    function redeem(uint256 amountIn, uint256[] calldata minAmountsOut, address receiver, uint256 deadline)
        external
        returns (uint256[] memory amountsOut);
    function borrow(address asset, uint256 amount, address receiver) external;
    function repay(address asset, uint256 amount) external;
    function setInsuranceFund(address insuranceFund) external;
    function rescueERC20(address asset, address receiver) external;
}
