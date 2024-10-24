// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {PhEvm} from "./PhEvm.sol";

contract Credible {
    //Precompile address - 0x15FDfe40Eee261663f48262DA81bf13232C63741
    PhEvm ph = PhEvm(address(uint160(uint256(keccak256("PhEvm")))));
}
