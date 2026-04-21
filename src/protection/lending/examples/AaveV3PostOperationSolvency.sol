// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {AaveV3LikeOperationSafetyAssertionBase, AaveV3LikeProtectionSuite} from "./AaveV3LikeOperationSafety.sol";

/// @title AaveV3HorizonProtectionSuite
/// @author Phylax Systems
/// @notice Example `ILendingProtectionSuite` targeting a local Aave v3 Horizon deployment.
/// @dev The underlying logic now lives in `AaveV3LikeProtectionSuite` and is shared with SparkLend.
contract AaveV3HorizonProtectionSuite is AaveV3LikeProtectionSuite {
    constructor(address pool_) AaveV3LikeProtectionSuite(pool_) {}
}

/// @title AaveV3HorizonOperationSafetyAssertion
/// @author Phylax Systems
/// @notice Example single-entry assertion bundle for Aave v3 Horizon.
/// @dev Usage:
///      `cl.assertion({ adopter: aaveV3HorizonPool, createData: abi.encodePacked(type(AaveV3HorizonOperationSafetyAssertion).creationCode, abi.encode(aaveV3HorizonPool)), fnSelector: AaveV3HorizonOperationSafetyAssertion.assertOperationSafety.selector })`
contract AaveV3HorizonOperationSafetyAssertion is AaveV3LikeOperationSafetyAssertionBase {
    constructor(address pool_)
        AaveV3LikeOperationSafetyAssertionBase(address(new AaveV3HorizonProtectionSuite(pool_)))
    {}
}

/// @title AaveV3ProtectionSuite
/// @author Phylax Systems
/// @notice Compatibility alias preserving the old generic Aave v3 suite name.
contract AaveV3ProtectionSuite is AaveV3HorizonProtectionSuite {
    constructor(address pool_) AaveV3HorizonProtectionSuite(pool_) {}
}

/// @title AaveV3OperationSafetyAssertion
/// @author Phylax Systems
/// @notice Compatibility alias preserving the old generic Aave v3 assertion name.
contract AaveV3OperationSafetyAssertion is AaveV3HorizonOperationSafetyAssertion {
    constructor(address pool_) AaveV3HorizonOperationSafetyAssertion(pool_) {}
}

/// @title AaveV3PostOperationSolvencyAssertion
/// @author Phylax Systems
/// @notice Deprecated compatibility alias for the pre-operation-safety contract name.
contract AaveV3PostOperationSolvencyAssertion is AaveV3HorizonOperationSafetyAssertion {
    constructor(address pool_) AaveV3HorizonOperationSafetyAssertion(pool_) {}
}
