// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Compile upstream Safe bytecode with its supported legacy pipeline. Tests deploy
// these artifacts via deployCode so assertion tests can still use via-IR.
import {GnosisSafe} from "../../../lib/safe-smart-account-1.3.0/contracts/GnosisSafe.sol";
import {GnosisSafeProxy} from "../../../lib/safe-smart-account-1.3.0/contracts/proxies/GnosisSafeProxy.sol";
import {Safe as Safe140} from "../../../lib/safe-smart-account-1.4.0/contracts/Safe.sol";
import {SafeProxy as Proxy140} from "../../../lib/safe-smart-account-1.4.0/contracts/proxies/SafeProxy.sol";
import {Safe as Safe141} from "../../../lib/safe-smart-account/contracts/Safe.sol";
import {SafeProxy as Proxy141} from "../../../lib/safe-smart-account/contracts/proxies/SafeProxy.sol";
import {Safe as Safe150} from "../../../lib/safe-smart-account-1.5.0/contracts/Safe.sol";
import {SafeProxy as Proxy150} from "../../../lib/safe-smart-account-1.5.0/contracts/proxies/SafeProxy.sol";
import {SignMessageLib as Sign140} from "../../../lib/safe-smart-account-1.4.0/contracts/libraries/SignMessageLib.sol";
import {
    CompatibilityFallbackHandler as Handler140
} from "../../../lib/safe-smart-account-1.4.0/contracts/handler/CompatibilityFallbackHandler.sol";

contract SafeArtifactsTest {
    function testSupportedSingletonVersions() public {
        require(keccak256(bytes(new GnosisSafe().VERSION())) == keccak256("1.3.0"));
        require(keccak256(bytes(new Safe140().VERSION())) == keccak256("1.4.0"));
        require(keccak256(bytes(new Safe141().VERSION())) == keccak256("1.4.1"));
        require(keccak256(bytes(new Safe150().VERSION())) == keccak256("1.5.0"));
    }
}
