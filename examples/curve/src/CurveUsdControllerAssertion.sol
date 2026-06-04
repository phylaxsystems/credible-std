// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "credible-std/PhEvm.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";
import {CurveUsdControllerProtocolHelpers} from "./CurveUsdProtocol.sol";

/// @title CurveUsdControllerAssertion
/// @notice Example crvUSD controller checks for loan lists, debt totals, and post-action solvency.
contract CurveUsdControllerAssertion is CurveUsdControllerProtocolHelpers {
    constructor(address controller_, address amm_, uint256 maxLoansToScan_, uint256 debtTolerance_)
        CurveUsdControllerProtocolHelpers(controller_, amm_, maxLoansToScan_, debtTolerance_)
    {
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    /// @notice Registers checks over loan-list indexing, aggregate debt, and post-action health rules.
    function triggers() external view override {
        registerTxEndTrigger(this.assertLoanListIntegrity.selector);
        registerTxEndTrigger(this.assertDebtAccounting.selector);
        registerTxEndTrigger(this.assertPostRiskIncreasingOperationHealth.selector);
        registerTxEndTrigger(this.assertPostLiquidationHealthRule.selector);
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

    /// @notice Checks risk-increasing actions leave every touched loan with nonnegative health.
    /// @dev Transaction-end check: enumerates the accounts touched by risk-increasing calls this
    ///      transaction, and requires each surviving loan to be healthy at PostTx. Runs once per
    ///      transaction instead of once per matched call.
    function assertPostRiskIncreasingOperationHealth() external {
        (address[] memory users, uint256 count) = _curveUsdAffectedAccounts(_curveUsdRiskIncreasingSelectors());
        PhEvm.ForkId memory fork = _postTx();

        for (uint256 i; i < count; ++i) {
            if (!_controllerLoanExistsAt(users[i], fork)) {
                continue;
            }
            require(_controllerHealthAt(users[i], false, fork) >= 0, "CurveUSD: unhealthy post-operation");
        }
    }

    /// @notice Checks a liquidation that starts from healthy state does not leave a surviving loan unhealthy.
    /// @dev Transaction-end check: enumerates liquidated accounts; for each that was healthy at PreTx
    ///      and still has a loan at PostTx, requires nonnegative PostTx health. Runs once per tx.
    function assertPostLiquidationHealthRule() external {
        (address[] memory users, uint256 count) = _curveUsdAffectedAccounts(_curveUsdLiquidationSelectors());
        PhEvm.ForkId memory preFork = _preTx();
        PhEvm.ForkId memory postFork = _postTx();

        for (uint256 i; i < count; ++i) {
            address user = users[i];
            if (_controllerHealthAt(user, true, preFork) < 0) {
                continue;
            }
            if (!_controllerLoanExistsAt(user, postFork)) {
                continue;
            }
            require(_controllerHealthAt(user, false, postFork) >= 0, "CurveUSD: healthy liquidation left unhealthy");
        }
    }
}
