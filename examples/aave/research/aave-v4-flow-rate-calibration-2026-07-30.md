# Aave v4 flow-rate circuit-breaker calibration

Snapshot date: 2026-07-30<br>
Chain: Ethereum mainnet<br>
Historical block range: 25,430,974–25,646,159<br>
Lookback: 30 days

## Asset selection

The three assets were selected from DefiLlama's aggregate Aave v4 token TVL:

| Rank | Asset | Aggregate token TVL |
| --- | --- | ---: |
| 1 | WBTC | $52.35m |
| 2 | USDG | $30.84m |
| 3 | wstETH | $29.40m |

DefiLlama derives Aave v4 TVL from ERC20 balances held by the Core, Plus, and
Prime Hubs. WBTC and wstETH are split between Core and Prime, so both Hubs need
their own adopter-scoped watchers. USDG is held only by Core.

Sources:

- <https://defillama.com/protocol/aave-v4>
- <https://api.llama.fi/protocol/aave-v4>
- <https://github.com/DefiLlama/DefiLlama-Adapters/blob/main/projects/aave-v4/index.js>

## Methodology

For each Hub/token pair:

1. Query every ERC20 `Transfer` to and from the Hub during the 30-day range.
2. Reconstruct the Hub balance at the beginning of the range from the current
   balance and the net transfer flow.
3. Calculate the maximum rolling 24-hour net directional flow as basis points
   of the Hub balance immediately before the window's first transfer.
4. Bucket net flow into 10-second intervals and calculate the peak flow rate as
   basis points of the Hub balance per second.
5. Set each production limit to `ceil(observed maximum × 1.20)`.

This intentionally calibrates to the maximum observed window rather than the
30-day daily average. A breaker set from the average would have rejected
legitimate historical spikes.

The Phylax cumulative watcher measures net flow: inflows offset outflows and
vice versa. It does not cap gross volume. The peak-rate signal is experimental
and comes from the same 10-second buckets.

## Results

| Hub | Asset | Current balance | 30d gross in | 30d gross out | Max 24h net in | In limit | Max 24h net out | Out limit | Peak in rate | In-rate limit | Peak out rate | Out-rate limit |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Core | WBTC | 670.9402 | 129.0485 | 20.8481 | 986.44 bps | 1,184 bps | 91.41 bps | 110 bps | 39.32 bps/s | 48 bps/s | 7.22 bps/s | 9 bps/s |
| Core | USDG | 30.6733m | 68.6104m | 61.5900m | 4,329.38 bps | 5,196 bps | 4,472.00 bps | 5,367 bps | 438.64 bps/s | 527 bps/s | 128.27 bps/s | 154 bps/s |
| Core | wstETH | 8,490.4974 | 4,365.9474 | 1,416.9640 | 1,587.63 bps | 1,906 bps | 776.51 bps | 932 bps | 47.57 bps/s | 58 bps/s | 77.62 bps/s | 94 bps/s |
| Prime | WBTC | 136.7563 | 57.6882 | 47.4818 | 1,750.94 bps | 2,102 bps | 2,026.00 bps | 2,432 bps | 123.91 bps/s | 149 bps/s | 148.27 bps/s | 178 bps/s |
| Prime | wstETH | 3,840.5454 | 2,142.8947 | 1,233.7078 | 2,903.51 bps | 3,485 bps | 757.23 bps | 909 bps | 175.60 bps/s | 211 bps/s | 60.15 bps/s | 73 bps/s |

The observed maxima used for these constants are checked in as
`aave-v4-flow-rate-observed-maxima.csv`; `calculate-aave-v4-flow-limits.py`
recomputes every limit as `ceil(observed × 1.20)`. The table and chart were
reconciled to that artifact, notably for Core USDG and Prime WBTC outflow.

## Operational notes

- The assertion uses a 1 bps cumulative dispatch floor so the custom rate check
  executes well before any calibrated limit. The policy trips if either the
  cumulative limit or peak-rate limit is exceeded.
- The trigger is currently unarmed because net-flow dispatch can fail to select
  the directional rate assertion after opposite-direction flow in the same
  window. Keep this policy staged until absolute directional or rate-native
  dispatch is available.
- Apply the Core assertion to the Core Hub and the Prime companion assertion to
  the Prime Hub. Adopting either assertion on another address fails explicitly.
- Recalibrate before production rollout and after material cap, asset-mix, or
  flow-regime changes. Thirty days is a useful initial sample, not a permanent
  risk parameter.
- `inflowRate()` and `outflowRate()` require
  `AssertionSpec.Experimental`; the public Phylax docs describe Experimental as
  unrestricted and potentially untested. This draft should remain staged until
  the runtime support and production policy are confirmed.
