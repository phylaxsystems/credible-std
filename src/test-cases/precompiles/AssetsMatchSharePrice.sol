// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "../../Assertion.sol";
import {PhEvm} from "../../PhEvm.sol";

contract MockVault {
    uint256 public totalAssets;
    uint256 public totalSupply;

    function deposit(uint256 assets, uint256 shares) external {
        totalAssets += assets;
        totalSupply += shares;
    }

    function inflate(uint256 extraAssets) external {
        totalAssets += extraAssets;
    }
}

MockVault constant VAULT = MockVault(0xdCCf1eEB153eF28fdc3CF97d33f60576cF092e9c);

contract TestAssetsMatchSharePrice is Assertion {
    constructor() payable {}

    function _deposits() internal view returns (PhEvm.CallInputs[] memory) {
        return ph.getCallInputs(address(VAULT), MockVault.deposit.selector);
    }

    function proportionalDepositsKeepSharePriceConstant() external {
        // Pre vs post-deposit (1:1 ratio preserved at every step) within zero-tolerance: must pass.
        PhEvm.CallInputs[] memory calls = _deposits();
        require(calls.length == 2, "expected 2 deposit calls");

        require(
            ph.assetsMatchSharePriceAt(address(VAULT), 0, _postCall(calls[0].id), _postCall(calls[1].id)),
            "ratio-preserving deposits must keep share price stable"
        );
    }

    function tightTolerancePassesOnStableSharePrice() external {
        require(ph.assetsMatchSharePrice(address(VAULT), 0), "share price must be stable across all forks");
    }

    function identicalForksAlwaysPass() external {
        require(
            ph.assetsMatchSharePriceAt(address(VAULT), 0, _postTx(), _postTx()), "same-fork compare must pass"
        );
    }

    function triggers() external view override {
        registerCallTrigger(this.proportionalDepositsKeepSharePriceConstant.selector);
        registerCallTrigger(this.tightTolerancePassesOnStableSharePrice.selector);
        registerCallTrigger(this.identicalForksAlwaysPass.selector);
    }
}

contract TriggeringTx {
    constructor() payable {
        // Two proportional deposits — 1:1 asset-to-share ratio held throughout.
        VAULT.deposit(100, 100);
        VAULT.deposit(50, 50);
    }
}
