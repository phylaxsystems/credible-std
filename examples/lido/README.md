# Lido examples

Build with:

```sh
FOUNDRY_PROFILE=lido forge build
FOUNDRY_PROFILE=lido pcl test
```

The generic vault assertions in this directory are retained as adapter prototypes. They register
no production triggers. Mellow flexible vaults, Veda BoringVaults, and Lido V3 stVaults have
different custody, supply, liability, rate, and asynchronous-withdrawal models; changing addresses
does not make one NAV, peg, exit-buffer, or Aave-position assertion valid for all three.

`LidoEasyTrackFlashLoanAssertion` remains active and is intentionally limited to
`objectToMotion(uint256)`. It reads the motion's real `snapshotBlock` and applies the same-transaction
balance check only when the snapshot is the current block. Historical motions use MiniMe's fixed
historical balance and are not affected by current token transfers. `createMotion` is not
balance-weighted and is not a supported selector.

Production vault coverage needs a dedicated adapter for each vault family, including its native
asset handling, pending shares, withdrawal liabilities, report lifecycle, supported rate ABI, and
recovery paths. Do not deploy the quarantined generic contracts until such an adapter is added and
tested against the pinned upstream implementation.
