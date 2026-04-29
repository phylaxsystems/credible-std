// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {AaveV3LikeOperationSafetyAssertionBase, AaveV3LikeProtectionSuite} from "./AaveV3LikeOperationSafety.sol";

/// @title SparkLendV1ProtectionSuite
/// @author Phylax Systems
/// @notice `ILendingProtectionSuite` implementation for SparkLend v1.
/// @dev SparkLend v1 preserves the Aave v3 pool interface and health-factor accounting closely
///      enough to reuse the shared Aave v3-like lending adapter directly.
contract SparkLendV1ProtectionSuite is AaveV3LikeProtectionSuite {
    constructor(address pool_) AaveV3LikeProtectionSuite(pool_) {}
}

/// @title SparkLendV1OperationSafetyAssertion
/// @author Phylax Systems
/// @notice Single-entry assertion bundle for SparkLend v1 pools.
/// @dev Usage:
///      `cl.assertion({ adopter: sparkPool, createData: abi.encodePacked(type(SparkLendV1OperationSafetyAssertion).creationCode, abi.encode(sparkPool)), fnSelector: SparkLendV1OperationSafetyAssertion.assertOperationSafety.selector })`
contract SparkLendV1OperationSafetyAssertion is AaveV3LikeOperationSafetyAssertionBase {
    constructor(address pool_) AaveV3LikeOperationSafetyAssertionBase(address(new SparkLendV1ProtectionSuite(pool_))) {}
}

/// @title SparkLendV1PostOperationSolvencyAssertion
/// @author Phylax Systems
/// @notice Deprecated compatibility alias for the pre-operation-safety contract name.
contract SparkLendV1PostOperationSolvencyAssertion is SparkLendV1OperationSafetyAssertion {
    constructor(address pool_) SparkLendV1OperationSafetyAssertion(pool_) {}
}
