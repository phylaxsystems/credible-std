// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface ISymbioticVaultLike {
    function collateral() external view returns (address);
    function delegator() external view returns (address);
    function currentEpoch() external view returns (uint256);
    function depositWhitelist() external view returns (bool);
    function isDepositorWhitelisted(address account) external view returns (bool);
    function isDepositLimit() external view returns (bool);
    function depositLimit() external view returns (uint256);
    function activeStake() external view returns (uint256);
    function activeShares() external view returns (uint256);
    function activeSharesOf(address account) external view returns (uint256);
    function withdrawals(uint256 epoch) external view returns (uint256);
    function withdrawalShares(uint256 epoch) external view returns (uint256);
    function withdrawalSharesOf(uint256 epoch, address account) external view returns (uint256);
    function isWithdrawalsClaimed(uint256 epoch, address account) external view returns (bool);
    function totalStake() external view returns (uint256);

    function deposit(address onBehalfOf, uint256 amount)
        external
        returns (uint256 depositedAmount, uint256 mintedShares);
    function withdraw(address claimer, uint256 amount) external returns (uint256 burnedShares, uint256 mintedShares);
    function redeem(address claimer, uint256 shares) external returns (uint256 withdrawnAssets, uint256 mintedShares);
    function claim(address recipient, uint256 epoch) external returns (uint256 amount);
    function claimBatch(address recipient, uint256[] calldata epochs) external returns (uint256 amount);
}

interface ISymbioticDelegatorLike {
    function stake(bytes32 subnetwork, address operator) external view returns (uint256);
    function maxNetworkLimit(bytes32 subnetwork) external view returns (uint256);
}

interface ISymbioticOperatorNetworkSpecificDelegatorLike is ISymbioticDelegatorLike {
    function network() external view returns (address);
    function operator() external view returns (address);
}

interface ISymbioticVotingPowerProviderLike {
    struct VaultValue {
        address vault;
        uint256 value;
    }

    function isTokenRegistered(address token) external view returns (bool);
    function getOperators() external view returns (address[] memory);
    function isOperatorVaultRegistered(address operator, address vault) external view returns (bool);
    function getOperatorVaults(address operator) external view returns (address[] memory);
    function getOperatorStakes(address operator) external view returns (VaultValue[] memory);
    function getOperatorVotingPowers(address operator, bytes memory extraData)
        external
        view
        returns (VaultValue[] memory);
}

interface ISymbioticOpNetVaultAutoDeployLike is ISymbioticVotingPowerProviderLike {
    function getAutoDeployedVault(address operator) external view returns (address);
    function isSetMaxNetworkLimitHookEnabled() external view returns (bool);
}
