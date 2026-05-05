# Nado Assertions

Nado is an offchain-orderbook perpetual and spot margin system with EVM settlement contracts. The Endpoint is the user and sequencer entry point. It accepts deposits, slow-mode transactions, signed withdrawals, order matches, oracle price updates, NLP mint/burn requests, and administrative assertions, then forwards state-changing work into the Clearinghouse and engines.

The Clearinghouse is the custody and risk hub. It owns the quote token, maps product IDs to product engines, updates spot collateral on deposits and withdrawals, enforces health checks, routes withdrawals through the WithdrawPool, settles PnL, handles insurance, and delegates liquidation logic to the liquidation module.

The SpotEngine stores collateral balances and borrow/deposit state per product and subaccount. Product token amounts are converted into the protocol's x18 accounting units based on ERC20 decimals. The PerpEngine stores perpetual positions, virtual quote balances, open interest, funding accumulators, and settlement state.

This assertion bundle is intentionally narrow. It protects the Clearinghouse boundary where token custody and SpotEngine ledger balances must agree, then adds quote-asset circuit breakers that supersede normal protocol limits during abnormal flow windows.
