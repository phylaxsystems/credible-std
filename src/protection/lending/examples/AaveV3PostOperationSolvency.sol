// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ILendingProtectionSuite} from "../ILendingProtectionSuite.sol";
import {AaveV3LikeProtectionSuite} from "./AaveV3LikeHelpers.sol";
import {AaveV3LikeOperationSafetyAssertionBase} from "./AaveV3LikeOperationSafety.sol";

/// @title AaveV3HorizonProtectionSuite
/// @author Phylax Systems
/// @notice Example `ILendingProtectionSuite` targeting a local Aave v3 Horizon deployment.
/// @dev The underlying logic lives in `AaveV3LikeProtectionSuite` so Base Aave, local Horizon
///      deployments, and close forks can reuse the same operation-safety model. The deployment
///      wrapper exists to keep the public example small: pass the pool and addresses provider, then
///      the shared suite supplies health-factor and bounded-consumption checks.
contract AaveV3HorizonProtectionSuite is AaveV3LikeProtectionSuite {
    constructor(address pool_, address addressesProvider_) AaveV3LikeProtectionSuite(pool_, addressesProvider_) {}
}

/// @title AaveV3HorizonOperationSafetyAssertion
/// @author Phylax Systems
/// @notice Example single-entry assertion bundle for Aave v3 Horizon.
/// @dev Usage:
///      `cl.assertion({ adopter: aaveV3HorizonPool, createData: abi.encodePacked(type(AaveV3HorizonOperationSafetyAssertion).creationCode, abi.encode(aaveV3HorizonPool, addressesProvider)), fnSelector: AaveV3HorizonOperationSafetyAssertion.assertOperationSafety.selector })`
///
///      The assertion is registered against the pool because the pool is the entry point for borrow,
///      withdraw, liquidation, collateral-flag, aToken transfer-finalization, and e-mode changes.
///      A revert from this bundle means a risk-increasing pool call either made a healthy user
///      liquidatable or consumed more user debt/collateral claim than the pre-call state allowed.
contract AaveV3HorizonOperationSafetyAssertion is AaveV3LikeOperationSafetyAssertionBase {
    constructor(address pool_, address addressesProvider_)
        AaveV3LikeOperationSafetyAssertionBase(ILendingProtectionSuite(
                address(new AaveV3HorizonProtectionSuite(pool_, addressesProvider_))
            ))
    {}
}

/// @title AaveV3ProtectionSuite
/// @author Phylax Systems
/// @notice Compatibility alias preserving the old generic Aave v3 suite name.
contract AaveV3ProtectionSuite is AaveV3HorizonProtectionSuite {
    constructor(address pool_, address addressesProvider_) AaveV3HorizonProtectionSuite(pool_, addressesProvider_) {}
}

/// @title AaveV3OperationSafetyAssertion
/// @author Phylax Systems
/// @notice Compatibility alias preserving the old generic Aave v3 assertion name.
contract AaveV3OperationSafetyAssertion is AaveV3HorizonOperationSafetyAssertion {
    constructor(address pool_, address addressesProvider_)
        AaveV3HorizonOperationSafetyAssertion(pool_, addressesProvider_)
    {}
}

/// @title AaveV3PostOperationSolvencyAssertion
/// @author Phylax Systems
/// @notice Deprecated compatibility alias for the pre-operation-safety contract name.
contract AaveV3PostOperationSolvencyAssertion is AaveV3HorizonOperationSafetyAssertion {
    constructor(address pool_, address addressesProvider_)
        AaveV3HorizonOperationSafetyAssertion(pool_, addressesProvider_)
    {}
}
