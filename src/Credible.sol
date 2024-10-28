// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {PhEvm} from "./PhEvm.sol";

/// @notice The Credible contract
contract Credible {
    //Precompile address -
    PhEvm ph = PhEvm(address(uint160(uint256(keccak256("Kim Jong Un Sucks")))));
}
