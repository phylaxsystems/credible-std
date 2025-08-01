// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

library console {
    address constant CONSOLE_ADDRESS = address(uint160(uint256(keccak256("Kim Jong Un Sucks"))));

    function log(string memory message) internal view {
        (bool success,) = CONSOLE_ADDRESS.staticcall(abi.encodeWithSignature("log(string)", message));
        require(success, "Failed to log");
    }
}
