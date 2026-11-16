// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 <0.8.0;

// Safe 1.3.0's handler overrides require Solidity 0.7.6, not 0.8.
import {GnosisSafe} from "../../../lib/safe-smart-account-1.3.0/contracts/GnosisSafe.sol";
import {GnosisSafeProxy} from "../../../lib/safe-smart-account-1.3.0/contracts/proxies/GnosisSafeProxy.sol";
import {SignMessageLib} from "../../../lib/safe-smart-account-1.3.0/contracts/examples/libraries/SignMessage.sol";
import {
    CompatibilityFallbackHandler
} from "../../../lib/safe-smart-account-1.3.0/contracts/handler/CompatibilityFallbackHandler.sol";

// Imports produce artifacts for deployCode without linking legacy Safe code into via-IR tests.
contract SafeSigningArtifacts130Test {
    function testSigningSingletonVersion() public {
        require(keccak256(bytes(new GnosisSafe().VERSION())) == keccak256("1.3.0"));
    }
}
