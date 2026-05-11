// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "../../Assertion.sol";
import {PhEvm} from "../../PhEvm.sol";

contract MockErc20 {
    event Transfer(address indexed from, address indexed to, uint256 value);

    function transferFromTo(address from, address to, uint256 value) external {
        emit Transfer(from, to, value);
    }
}

MockErc20 constant TOKEN_A = MockErc20(0xdCCf1eEB153eF28fdc3CF97d33f60576cF092e9c);
MockErc20 constant TOKEN_B = MockErc20(0x40f7EBE92dD6bdbEECADFFF3F9d7A1B33Cf8d7c0);

address constant ALICE = address(0xA11CE);
address constant BOB = address(0xB0B);
address constant CAROL = address(0xCA801);

contract TestErc20Transfers is Assertion {
    constructor() payable {}

    function _postTxFork() internal pure returns (PhEvm.ForkId memory) {
        return _postTx();
    }

    function getErc20TransfersReturnsAllTransfersForToken() external view {
        PhEvm.Erc20TransferData[] memory transfers = ph.getErc20Transfers(address(TOKEN_A), _postTxFork());
        require(transfers.length == 3, "expected 3 transfers on TOKEN_A");

        require(transfers[0].token_addr == address(TOKEN_A), "transfer[0] token mismatch");
        require(transfers[0].from == ALICE && transfers[0].to == BOB, "transfer[0] from/to");
        require(transfers[0].value == 100, "transfer[0] value != 100");

        require(transfers[1].from == ALICE && transfers[1].to == BOB, "transfer[1] from/to");
        require(transfers[1].value == 200, "transfer[1] value != 200");

        require(transfers[2].from == BOB && transfers[2].to == CAROL, "transfer[2] from/to");
        require(transfers[2].value == 50, "transfer[2] value != 50");
    }

    function getErc20TransfersForTokensMergesAcrossTokens() external view {
        address[] memory tokens = new address[](2);
        tokens[0] = address(TOKEN_A);
        tokens[1] = address(TOKEN_B);

        PhEvm.Erc20TransferData[] memory transfers = ph.getErc20TransfersForTokens(tokens, _postTxFork());
        require(transfers.length == 4, "expected 3 + 1 = 4 combined transfers");
    }

    function changedErc20BalanceDeltasReturnsRawTransfers() external view {
        PhEvm.Erc20TransferData[] memory deltas = ph.changedErc20BalanceDeltas(address(TOKEN_A), _postTxFork());
        require(deltas.length == 3, "changedErc20BalanceDeltas should mirror getErc20Transfers");
    }

    function reduceErc20BalanceDeltasAggregatesByPair() external view {
        PhEvm.Erc20TransferData[] memory deltas = ph.reduceErc20BalanceDeltas(address(TOKEN_A), _postTxFork());

        // Pairs: (ALICE -> BOB) collapses to one row of 300, (BOB -> CAROL) stays at 50.
        require(deltas.length == 2, "expected 2 reduced pairs");

        require(deltas[0].from == ALICE && deltas[0].to == BOB, "pair[0] should be ALICE->BOB");
        require(deltas[0].value == 300, "ALICE->BOB net != 300");

        require(deltas[1].from == BOB && deltas[1].to == CAROL, "pair[1] should be BOB->CAROL");
        require(deltas[1].value == 50, "BOB->CAROL net != 50");
    }

    function unknownTokenReturnsEmpty() external view {
        PhEvm.Erc20TransferData[] memory transfers =
            ph.getErc20Transfers(address(0x000000000000000000000000000000000000dEaD), _postTxFork());
        require(transfers.length == 0, "non-token address should yield no transfers");
    }

    function triggers() external view override {
        registerCallTrigger(this.getErc20TransfersReturnsAllTransfersForToken.selector);
        registerCallTrigger(this.getErc20TransfersForTokensMergesAcrossTokens.selector);
        registerCallTrigger(this.changedErc20BalanceDeltasReturnsRawTransfers.selector);
        registerCallTrigger(this.reduceErc20BalanceDeltasAggregatesByPair.selector);
        registerCallTrigger(this.unknownTokenReturnsEmpty.selector);
    }
}

contract TriggeringTx {
    constructor() payable {
        TOKEN_A.transferFromTo(ALICE, BOB, 100);
        TOKEN_A.transferFromTo(ALICE, BOB, 200);
        TOKEN_A.transferFromTo(BOB, CAROL, 50);
        TOKEN_B.transferFromTo(ALICE, CAROL, 1);
    }
}
