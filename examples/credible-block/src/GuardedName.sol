// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {CredibleBlockGuard} from "credible-std/protection/credible_block/CredibleBlockGuard.sol";
import {ICredibleRegistry} from "credible-std/protection/credible_block/ICredibleRegistry.sol";

/// @notice String-valued fixture for exercising target-mode argument and state handling.
contract GuardedName is CredibleBlockGuard {
    string public name;

    constructor(ICredibleRegistry credibleRegistry_, uint256 failOpenBlockThreshold_)
        CredibleBlockGuard(credibleRegistry_, failOpenBlockThreshold_)
    {}

    function setName(string calldata newName) external onlyCredibleBlock {
        name = newName;
    }
}
