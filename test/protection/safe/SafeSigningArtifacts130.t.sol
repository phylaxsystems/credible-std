// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 <0.8.0;

// The 1.3.0 handler's public calldata override requires the upstream 0.7 compiler.
import {SignMessageLib} from "../../../lib/safe-smart-account-1.3.0/contracts/examples/libraries/SignMessage.sol";
import {
    CompatibilityFallbackHandler
} from "../../../lib/safe-smart-account-1.3.0/contracts/handler/CompatibilityFallbackHandler.sol";

contract SafeSigningArtifacts130Test {
    function testSigningArtifactsDeploy() public {
        require(address(new SignMessageLib()) != address(0));
        require(address(new CompatibilityFallbackHandler()) != address(0));
    }
}
