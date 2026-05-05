// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "../../../../PhEvm.sol";
import {CurveUsdControllerProtocolHelpers} from "./CurveUsdProtocol.sol";

/// @title CurveUsdControllerAssertion
/// @notice Example crvUSD controller checks for loan lists, debt totals, and post-action solvency.
contract CurveUsdControllerAssertion is CurveUsdControllerProtocolHelpers {
    constructor(address controller_, uint256 maxLoansToScan_, uint256 debtTolerance_)
        CurveUsdControllerProtocolHelpers(controller_, maxLoansToScan_, debtTolerance_)
    {}

    /// @notice Registers checks over loan-list indexing, aggregate debt, and post-action health rules.
    function triggers() external view override {
        registerTxEndTrigger(this.assertLoanListIntegrity.selector);
        registerTxEndTrigger(this.assertDebtAccounting.selector);
        _registerCurveUsdRiskIncreasingTriggers(this.assertPostRiskIncreasingOperationHealth.selector);
        _registerCurveUsdLiquidationTriggers(this.assertPostLiquidationHealthRule.selector);
    }

    /// @notice Checks `loans(i)`, `loan_ix(user)`, `loan_exists(user)`, and AMM liquidity stay consistent.
    function assertLoanListIntegrity() external {
        PhEvm.ForkId memory fork = _postTx();
        uint256 loanCount = _controllerNLoansAt(fork);
        require(loanCount <= maxLoansToScan, "CurveUSD: too many loans to scan");

        for (uint256 i; i < loanCount; ++i) {
            address user = _controllerLoanAt(i, fork);

            require(user != address(0), "CurveUSD: empty active loan slot");
            require(_controllerLoanExistsAt(user, fork), "CurveUSD: listed loan does not exist");
            require(_controllerLoanIndexAt(user, fork) == i, "CurveUSD: bad loan_ix");
            require(_ammHasLiquidityAt(user, fork), "CurveUSD: loan without AMM liquidity");
        }
    }

    /// @notice Checks `total_debt()` stays within rounding distance of the summed user debts.
    function assertDebtAccounting() external {
        PhEvm.ForkId memory fork = _postTx();
        uint256 loanCount = _controllerNLoansAt(fork);
        require(loanCount <= maxLoansToScan, "CurveUSD: too many loans to scan");

        uint256 sumDebt;
        for (uint256 i; i < loanCount; ++i) {
            sumDebt += _controllerDebtAt(_controllerLoanAt(i, fork), fork);
        }

        uint256 totalDebt = _controllerTotalDebtAt(fork);
        require(sumDebt + debtTolerance >= totalDebt, "CurveUSD: sum debt below total debt");
        require(sumDebt <= totalDebt + loanCount + debtTolerance, "CurveUSD: sum debt too high");
    }

    /// @notice Checks risk-increasing actions leave an existing loan with nonnegative health.
    function assertPostRiskIncreasingOperationHealth() external {
        CurveUsdTriggeredCall memory triggered = _resolveCurveUsdTriggeredCall();
        address user = _curveUsdAccountFromCall(triggered);
        PhEvm.ForkId memory fork = _postCall(triggered.callEnd);

        if (!_controllerLoanExistsAt(user, fork)) {
            return;
        }

        require(_controllerHealthAt(user, false, fork) >= 0, "CurveUSD: unhealthy post-operation");
    }

    /// @notice Checks a liquidation that starts from healthy state does not leave a surviving loan unhealthy.
    function assertPostLiquidationHealthRule() external {
        CurveUsdTriggeredCall memory triggered = _resolveCurveUsdTriggeredCall();
        address user = _curveUsdAccountFromCall(triggered);

        if (_controllerHealthAt(user, true, _preCall(triggered.callStart)) < 0) {
            return;
        }

        PhEvm.ForkId memory fork = _postCall(triggered.callEnd);
        if (!_controllerLoanExistsAt(user, fork)) {
            return;
        }

        require(_controllerHealthAt(user, false, fork) >= 0, "CurveUSD: healthy liquidation left unhealthy");
    }
}
