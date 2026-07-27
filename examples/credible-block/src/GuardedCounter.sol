// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {CredibleBlockGuard} from "credible-std/protection/credible_block/CredibleBlockGuard.sol";
import {ICredibleRegistry} from "credible-std/protection/credible_block/ICredibleRegistry.sol";

/// @notice A minimal contract that adopts the {CredibleBlockGuard} `onlyCredibleBlock` modifier,
///         standing in for a real credible-layer contract upgrade. Its guarded entrypoint (`bump`)
///         only executes inside a block a whitelisted builder marked credible, unless the guard is
///         failing open because the builder set has gone silent past `failOpenBlockThreshold`.
contract GuardedCounter is CredibleBlockGuard {
    uint256 public count;

    constructor(ICredibleRegistry credibleRegistry_, uint256 failOpenBlockThreshold_)
        CredibleBlockGuard(credibleRegistry_, failOpenBlockThreshold_)
    {}

    /// @notice Guarded state mutation: reverts with `NonCredibleBlock` outside a credible block.
    function bump() external onlyCredibleBlock {
        count++;
    }
}
