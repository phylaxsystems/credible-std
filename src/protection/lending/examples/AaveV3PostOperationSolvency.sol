// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {AaveV3LikeOperationSafetyAssertionBase, AaveV3LikeProtectionSuite} from "./AaveV3LikeOperationSafety.sol";
import {IAaveV3LikePool} from "./AaveV3LikeInterfaces.sol";

/// @title AaveV3HorizonProtectionSuite
/// @author Phylax Systems
/// @notice Example `ILendingProtectionSuite` targeting a local Aave v3 Horizon deployment.
/// @dev The underlying logic now lives in `AaveV3LikeProtectionSuite` and is shared with SparkLend.
contract AaveV3HorizonProtectionSuite is AaveV3LikeProtectionSuite {
    constructor(address pool_, address addressesProvider_)
        AaveV3LikeProtectionSuite(pool_, addressesProvider_)
    {}

    /// @notice Only `withdraw` and `liquidationCall` carry bounded-consumption checks.
    /// @dev `getConsumptionChecks` returns checks solely for the `WithdrawCollateral` and `Liquidation`
    ///      kinds, so the generic assertion registers the per-call consumption trigger only for those
    ///      two selectors. The remaining monitored selectors (borrow, collateral toggle, aToken
    ///      transfer, e-mode) are covered by the transaction-end solvency check, which spans every
    ///      monitored selector. This override lives on the concrete Horizon suite rather than the shared
    ///      `AaveV3LikeProtectionSuite` so forks that add selectors with their own consumption checks
    ///      keep the safe default of one trigger per monitored selector.
    function getConsumptionSelectors() external pure override returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = IAaveV3LikePool.withdraw.selector;
        selectors[1] = IAaveV3LikePool.liquidationCall.selector;
    }
}

/// @title AaveV3HorizonOperationSafetyAssertion
/// @author Phylax Systems
/// @notice Example single-entry assertion bundle for Aave v3 Horizon.
/// @dev Usage:
///      `cl.assertion({ adopter: aaveV3HorizonPool, createData: abi.encodePacked(type(AaveV3HorizonOperationSafetyAssertion).creationCode, abi.encode(aaveV3HorizonPool, addressesProvider)), fnSelector: AaveV3HorizonOperationSafetyAssertion.assertOperationSafety.selector })`
contract AaveV3HorizonOperationSafetyAssertion is AaveV3LikeOperationSafetyAssertionBase {
    constructor(address pool_, address addressesProvider_)
        AaveV3LikeOperationSafetyAssertionBase(address(new AaveV3HorizonProtectionSuite(pool_, addressesProvider_)))
    {}
}

/// @title AaveV3ProtectionSuite
/// @author Phylax Systems
/// @notice Compatibility alias preserving the old generic Aave v3 suite name.
contract AaveV3ProtectionSuite is AaveV3HorizonProtectionSuite {
    constructor(address pool_, address addressesProvider_)
        AaveV3HorizonProtectionSuite(pool_, addressesProvider_)
    {}
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
