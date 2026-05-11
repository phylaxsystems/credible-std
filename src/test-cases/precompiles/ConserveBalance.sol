// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "../../Assertion.sol";
import {PhEvm} from "../../PhEvm.sol";

contract BalanceToken {
    mapping(address => uint256) internal _balanceOf;

    event Transfer(address indexed from, address indexed to, uint256 value);

    function balanceOf(address account) external view returns (uint256) {
        return _balanceOf[account];
    }

    function setBalance(address account, uint256 amount) external {
        _balanceOf[account] = amount;
    }

    function transfer(address from, address to, uint256 amount) external {
        _balanceOf[from] -= amount;
        _balanceOf[to] += amount;
        emit Transfer(from, to, amount);
    }
}

BalanceToken constant TOKEN = BalanceToken(0xdCCf1eEB153eF28fdc3CF97d33f60576cF092e9c);

address constant HOLDER = address(0xBEEF);
address constant MOVER = address(0xCAFE);

contract TestConserveBalance is Assertion {
    constructor() payable {}

    function conservedAccountReturnsTrue() external {
        // HOLDER is never touched in TriggeringTx; balance must match across forks.
        require(ph.conserveBalance(_preTx(), _postTx(), address(TOKEN), HOLDER), "HOLDER balance must be conserved");
    }

    function changedAccountReturnsFalse() external {
        // MOVER's balance shifts during the transaction; conservation must fail.
        require(!ph.conserveBalance(_preTx(), _postTx(), address(TOKEN), MOVER), "MOVER balance should differ");
    }

    function identicalForksAlwaysConserve() external {
        require(ph.conserveBalance(_postTx(), _postTx(), address(TOKEN), MOVER), "same-fork compare must hold");
    }

    function triggers() external view override {
        registerCallTrigger(this.conservedAccountReturnsTrue.selector);
        registerCallTrigger(this.changedAccountReturnsFalse.selector);
        registerCallTrigger(this.identicalForksAlwaysConserve.selector);
    }
}

contract TriggeringTx {
    constructor() payable {
        TOKEN.setBalance(MOVER, 100);
        TOKEN.transfer(MOVER, address(0xDEAD), 25);
    }
}
