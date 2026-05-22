// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface INadoEndpointLike {
    function depositCollateral(bytes12 subaccountName, uint32 productId, uint128 amount) external;

    function depositCollateralWithReferral(
        bytes32 subaccount,
        uint32 productId,
        uint128 amount,
        string calldata referralCode
    ) external;

    function submitSlowModeTransaction(bytes calldata transaction) external;
}

interface INadoClearinghouseLike {
    struct DepositCollateral {
        bytes32 sender;
        uint32 productId;
        uint128 amount;
    }

    struct RebalanceXWithdraw {
        uint32 productId;
        uint128 amount;
        address sendTo;
    }

    function depositCollateral(DepositCollateral calldata txn) external;

    function withdrawCollateral(bytes32 sender, uint32 productId, uint128 amount, address sendTo, uint64 idx) external;

    function withdrawInsurance(bytes calldata transaction, uint64 idx) external;

    function rebalanceXWithdraw(bytes calldata transaction, uint64 nSubmissions) external;

    function depositInsurance(bytes calldata transaction) external;

    function getEngineByType(uint8 engineType) external view returns (address);

    function getQuote() external view returns (address);

    function getWithdrawPool() external view returns (address);
}

interface INadoSpotEngineLike {
    struct Config {
        address token;
        int128 interestInflectionUtilX18;
        int128 interestFloorX18;
        int128 interestSmallCapX18;
        int128 interestLargeCapX18;
        int128 withdrawFeeX18;
        int128 minDepositRateX18;
    }

    struct State {
        int128 cumulativeDepositsMultiplierX18;
        int128 cumulativeBorrowsMultiplierX18;
        int128 totalDepositsNormalized;
        int128 totalBorrowsNormalized;
    }

    struct Balance {
        int128 amount;
    }

    function getConfig(uint32 productId) external view returns (Config memory);

    function getBalance(uint32 productId, bytes32 subaccount) external view returns (Balance memory);
}

interface INadoErc20MetadataLike {
    function decimals() external view returns (uint8);
}
