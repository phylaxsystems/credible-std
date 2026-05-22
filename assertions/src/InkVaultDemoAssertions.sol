// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../examples/vault_demo/src/VaultDemoAssertions.sol";

address constant INK_VAULT_DEMO_ASSET = 0xD7d73B2338714Fe7086a3f707Dd61A6434718Fc9;
address constant INK_VAULT_DEMO_PROTECTED_VAULT = 0xf5E13aD91AF5F0A9d88115367F412959272254cc;
address constant INK_VAULT_DEMO_CURATOR_VAULT = 0x7AE85CaDF98Fc9AC5741F05E11A3ad659d4435Cb;

// Bump to mint a new bytecode (and therefore a new assertion ID) for every
// contract in this file. Re-registering the same assertion on StateOracle
// requires fresh bytecode.
bytes32 constant INK_VAULT_DEMO_ASSERTIONS_VERSION = "v1";

contract InkVaultAssetsMatchSharePriceAssertion is VaultAssetsMatchSharePriceAssertion {
    bytes32 public constant VERSION = INK_VAULT_DEMO_ASSERTIONS_VERSION;

    constructor() VaultAssetsMatchSharePriceAssertion(INK_VAULT_DEMO_PROTECTED_VAULT, 0) {}
}

contract InkVaultConvertToAssetsOracleSanityAssertion is VaultConvertToAssetsOracleSanityAssertion {
    bytes32 public constant VERSION = INK_VAULT_DEMO_ASSERTIONS_VERSION;

    constructor() VaultConvertToAssetsOracleSanityAssertion(INK_VAULT_DEMO_PROTECTED_VAULT, 1 ether, 100) {}
}

contract InkVaultCircuitBreakerAssertion is VaultCircuitBreakerAssertion {
    bytes32 public constant VERSION = INK_VAULT_DEMO_ASSERTIONS_VERSION;

    constructor() VaultCircuitBreakerAssertion(INK_VAULT_DEMO_PROTECTED_VAULT, INK_VAULT_DEMO_ASSET) {}
}

contract InkCuratorMarketHealthAssertion is CuratorMarketHealthAssertion {
    bytes32 public constant VERSION = INK_VAULT_DEMO_ASSERTIONS_VERSION;

    constructor() CuratorMarketHealthAssertion(INK_VAULT_DEMO_CURATOR_VAULT, 9_900, 100) {}
}
