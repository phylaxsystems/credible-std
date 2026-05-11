// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "../../Assertion.sol";
import {PhEvm} from "../../PhEvm.sol";

contract MockOracle {
    uint256 public price;

    function setPrice(uint256 newPrice) external {
        price = newPrice;
    }

    function latestPrice() external view returns (uint256) {
        return price;
    }
}

MockOracle constant ORACLE = MockOracle(0xdCCf1eEB153eF28fdc3CF97d33f60576cF092e9c);

contract TestOracleSanity is Assertion {
    constructor() payable {}

    function _query() internal pure returns (bytes memory) {
        return abi.encodeWithSelector(MockOracle.latestPrice.selector);
    }

    function _setPriceCalls() internal view returns (PhEvm.CallInputs[] memory) {
        return ph.getCallInputs(address(ORACLE), MockOracle.setPrice.selector);
    }

    function smallMoveWithinToleranceReturnsTrue() external {
        // Compare post-state of the two adjacent setPrice calls (1e18 -> 1.005e18 ≈ 0.5%).
        PhEvm.CallInputs[] memory calls = _setPriceCalls();
        require(calls.length == 2, "expected 2 setPrice calls");

        require(
            ph.oracleSanityAt(address(ORACLE), _query(), 1000, _postCall(calls[0].id), _postCall(calls[1].id)),
            "0.5% move should pass 10% tolerance"
        );
    }

    function largeMoveOutsideToleranceReturnsFalse() external {
        PhEvm.CallInputs[] memory calls = _setPriceCalls();
        require(calls.length == 2, "expected 2 setPrice calls");

        // 0.5% > 10 bps tolerance.
        require(
            !ph.oracleSanityAt(address(ORACLE), _query(), 10, _postCall(calls[0].id), _postCall(calls[1].id)),
            "0.5% move should fail 0.1% tolerance"
        );
    }

    function identicalForksAlwaysPass() external {
        require(ph.oracleSanityAt(address(ORACLE), _query(), 0, _postTx(), _postTx()), "same-fork compare must pass");
    }

    function triggers() external view override {
        registerCallTrigger(this.smallMoveWithinToleranceReturnsTrue.selector);
        registerCallTrigger(this.largeMoveOutsideToleranceReturnsFalse.selector);
        registerCallTrigger(this.identicalForksAlwaysPass.selector);
    }
}

contract TriggeringTx {
    constructor() payable {
        ORACLE.setPrice(1e18);
        ORACLE.setPrice(1.005e18);
    }
}
