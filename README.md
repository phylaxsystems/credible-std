<div align="center">

<img src="https://phylax.systems/apple-touch-icon.png" alt="Phylax" width="76" height="76" />

<h1>credible-std</h1>

<p><b>Solidity standard library for writing Credible Layer assertions.</b></p>

<p><sub>THE POLICY ENGINE FOR PROGRAMMABLE CAPITAL</sub></p>

<p>
  <img src="https://img.shields.io/badge/Credible_Layer-stdlib-0092FF?style=for-the-badge&labelColor=160F0C" alt="Credible Layer stdlib" />
  <img src="https://img.shields.io/github/v/release/phylaxsystems/credible-std?style=for-the-badge&label=release&labelColor=160F0C&color=0092FF" alt="Latest release" />
  <img src="https://img.shields.io/badge/Solidity-%5E0.8.13-160F0C?style=for-the-badge&logo=solidity&logoColor=white" alt="Solidity ^0.8.13" />
  <img src="https://img.shields.io/badge/license-MIT-160F0C?style=for-the-badge" alt="License: MIT" />
</p>

<p>
  <a href="https://docs.phylax.systems/credible/credible-introduction"><b>Docs</b></a> &nbsp;·&nbsp;
  <a href="https://phylaxsystems.github.io/credible-std"><b>API Reference</b></a> &nbsp;·&nbsp;
  <a href="https://phylax.systems"><b>Website</b></a> &nbsp;·&nbsp;
  <a href="https://x.com/phylaxsystems"><b>X</b></a>
</p>

</div>

---

Standard library for implementing assertions in the Phylax Credible Layer (PCL). Provides the core contracts and interfaces needed to create, test, and validate assertions for smart contract security monitoring.

## Documentation

Full API documentation is available at: https://phylaxsystems.github.io/credible-std

To build the API site locally, use Foundry v1.8.3 and Node.js 24:

```bash
forge doc
npm ci --prefix docs
npm run build --prefix docs
```

Vocs writes the static site to `docs/dist/public`. Run `npm run preview --prefix docs`
to preview it at `/credible-std/`. Generated pages and the sidebar are ignored by Git;
the Vocs configuration and locked dependencies are committed in `docs/`. Keep fenced
NatSpec examples contiguous: Foundry treats empty `///` lines as separate descriptions.

## Examples

See the [example guide](examples/) for runnable demos, small assertion patterns,
protocol adapters, setup instructions, and coverage/quarantine status.

## Installation

### Using npm

Install the package:

```bash
npm install @phylax-systems/credible-std
```

Add these remappings to your `remappings.txt`:

```
credible-std/=node_modules/@phylax-systems/credible-std/src/
forge-std/=node_modules/@phylax-systems/credible-std/lib/forge-std/src/
@openzeppelin/=node_modules/@phylax-systems/credible-std/lib/openzeppelin-contracts/
```

### ABI artifacts

The npm package includes generated ABI arrays for every ABI-bearing contract and
interface defined under `src/`. Import them directly from `artifacts/`:

```ts
import phEvmAbi from "@phylax-systems/credible-std/artifacts/PhEvm.json";
import triggerRecorderAbi from "@phylax-systems/credible-std/artifacts/TriggerRecorder.json";
import safeTxShapeAssertionAbi from "@phylax-systems/credible-std/artifacts/protection/safe/SafeTxShapeAssertion.json";
```

An artifact whose contract name matches its Solidity filename mirrors the source
path without the `.sol` suffix. Additional contracts or interfaces declared in
the same source use `<Source>.<Contract>.json`, for example:
`artifacts/protection/lending/examples/AaveV3Interfaces.IAaveV3PoolLike.json`.

Each JSON file contains the raw ABI array, matching the artifact format published
by `@phylax-systems/credible-layer-contracts`.

### Using Foundry (Recommended)

Install the latest stable release:

```bash
forge install phylaxsystems/credible-std@0.8.1
```

Or install from master (latest development version):

```bash
forge install phylaxsystems/credible-std@master
```

Add the remapping to your `remappings.txt`:

```
credible-std/=lib/credible-std/src/
```

## Overview

The Phylax Credible Layer (PCL) is a security framework that enables real-time monitoring and validation of smart contract behavior through assertions. credible-std provides the foundational contracts and utilities needed to implement these assertions.

### Key Components

| Contract | Description |
|----------|-------------|
| `Assertion.sol` | Base contract for creating assertions with trigger registration |
| `Credible.sol` | Provides access to the PhEvm precompile for transaction state inspection |
| `PhEvm.sol` | Interface for the PhEvm precompile (state forking, logs, call inputs) |
| `StateChanges.sol` | Type-safe utilities for tracking contract state changes |
| `TriggerRecorder.sol` | Interface for registering assertion triggers |
| `CredibleTest.sol` | Base contract for testing assertions with `pcl test` |
| `CredibleTestWithBacktesting.sol` | Extended test contract with historical transaction backtesting |

## Features

- **Trigger System**: Register triggers for function calls, storage changes, and balance changes
- **State Inspection**: Fork to pre/post transaction state, inspect logs, call inputs, and storage
- **Type-Safe State Changes**: Built-in converters for uint256, address, bool, and bytes32 state changes
- **Testing Framework**: Test assertions locally with PCL before deployment
- **Backtesting**: Validate assertions against historical blockchain transactions
- **Internal Call Detection**: Automatically detect transactions that call your contract internally (not just direct calls)

## Quick Start

Install [Foundry](https://getfoundry.sh/) and
[PCL 1.6.0](https://github.com/phylaxsystems/pcl/releases/tag/1.6.0), the version
used by this repository's CI. In a Foundry project with `forge-std` and the
`credible-std/` remapping above, create the following three files.

This teaching policy rejects **every net ETH withdrawal**, including legitimate
ones. It demonstrates snapshot reads and assertion testing; it is not a general
vault-solvency policy.

### 1. Create the demo target

Save as `src/MyContract.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MyContract {
    function deposit() external payable {}

    function balance() external view returns (uint256) {
        return address(this).balance;
    }

    function withdraw(uint256 amount) external {
        (bool ok,) = msg.sender.call{value: amount}("");
        require(ok, "ETH transfer failed");
    }
}
```

The target intentionally has no access control or depositor accounting.

### 2. Create an assertion

Save as `src/MyAssertion.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Assertion} from "credible-std/Assertion.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";
import {MyContract} from "./MyContract.sol";

contract MyAssertion is Assertion {
    constructor() {
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    function triggers() external view override {
        registerTxEndTrigger(this.checkInvariant.selector);
    }

    function checkInvariant() external view {
        address target = ph.getAssertionAdopter();
        bytes memory query = abi.encodeCall(MyContract.balance, ());
        uint256 balanceBefore = _readUintAt(target, query, _preTx());
        uint256 balanceAfter = _readUintAt(target, query, _postTx());
        require(balanceAfter >= balanceBefore, "Balance decreased unexpectedly");
    }
}
```

### 3. Test the assertion

Save as `test/MyAssertion.t.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {CredibleTest} from "credible-std/CredibleTest.sol";
import {Test} from "forge-std/Test.sol";
import {MyAssertion} from "../src/MyAssertion.sol";
import {MyContract} from "../src/MyContract.sol";

contract TestMyAssertion is CredibleTest, Test {
    MyContract target;

    function setUp() public {
        target = new MyContract();
        vm.deal(address(this), 2 ether);
        vm.deal(address(target), 1 ether);
    }

    receive() external payable {}

    function test_assertionPasses() public {
        cl.assertion({
            adopter: address(target),
            createData: type(MyAssertion).creationCode,
            fnSelector: MyAssertion.checkInvariant.selector
        });
        target.deposit{value: 1 ether}();
        assertEq(address(target).balance, 2 ether);
    }

    function test_assertionFails() public {
        cl.assertion({
            adopter: address(target),
            createData: type(MyAssertion).creationCode,
            fnSelector: MyAssertion.checkInvariant.selector
        });
        vm.expectRevert("Balance decreased unexpectedly");
        target.withdraw(1 ether);
        assertEq(address(target).balance, 1 ether);
    }
}
```

Run with `pcl test -vv`. `cl.assertion` arms the next external transaction; stock
`forge test` does not implement this cheatcode. The failing-policy test also
checks that the blocked withdrawal leaves the target's balance unchanged.

## Developing this repository

Run from the repository root after installing Foundry, PCL 1.6.0, and `jq`:

```bash
git submodule update --init --recursive
forge test --no-match-path 'test/{backtesting,protection}/**'
RUST_MIN_STACK=16777216 FOUNDRY_PROFILE=ci pcl test --match-path 'test/protection/**'
./scripts/check_examples.sh
```

The [example guide](examples/README.md) explains each profile's coverage and
quarantines. Backtests require FFI and a suitable RPC endpoint; see
[Backtesting](#backtesting). For assertion gas reports, see the
[gas collection guide](scripts/GAS_USAGE_README.md).

## PhEvm Cheatcodes

Access these via the `ph` instance inherited from `Credible`. Prefer explicit
`ForkId` snapshots for new assertions: [`Assertion`](src/Assertion.sol) defines
`_preTx()`, `_postTx()`, `_preCall(id)`, and `_postCall(id)` directly and inherits
typed `_read*At` helpers from [`ForkUtils`](src/utils/ForkUtils.sol).

| Current API | Description |
|-------------|-------------|
| `staticcallAt(target, data, gasLimit, fork)` | Read a contract at an explicit snapshot |
| `loadStateAt(target, slot, fork)` | Read storage at an explicit snapshot |
| `context()` | Read the matched function call's selector and call boundaries |
| `getLogsQuery(query, fork)` | Filter logs within a snapshot scope |
| `getErc20Transfers(token, fork)` | Inspect ERC-20 transfers within a snapshot scope |

The following APIs remain available; `forkPreTx`, `forkPostTx`, `forkPreCall`,
`forkPostCall`, and `load` are deprecated in favor of explicit snapshots:

| Function | Description |
|----------|-------------|
| `forkPreTx()` | Fork to state before the transaction |
| `forkPostTx()` | Fork to state after the transaction |
| `forkPreCall(uint256 id)` | Fork to state before a specific call |
| `forkPostCall(uint256 id)` | Fork to state after a specific call |
| `load(address, bytes32)` | Load a storage slot value |
| `getLogs()` | Get all logs emitted in the transaction |
| `getCallInputs(address, bytes4)` | Get CALL inputs for target/selector |
| `getStaticCallInputs(address, bytes4)` | Get STATICCALL inputs |
| `getDelegateCallInputs(address, bytes4)` | Get DELEGATECALL inputs |
| `getAllCallInputs(address, bytes4)` | Get all call types |
| `callinputAt(uint256)` | Get full recorded calldata for one call id |
| `callOutputAt(uint256)` | Get full recorded return or revert bytes for one call id |
| `getStateChanges(address, bytes32)` | Get state changes for a slot |
| `getAssertionAdopter()` | Get the adopter contract address |

## Trigger Types

For Reshiram assertions (as in the quick start), use `registerTxEndTrigger` for
transaction-wide checks or `registerFnCallTrigger(assertionSelector, targetSelector)`
for per-call checks. The latter supplies `ph.context()` for call-scoped snapshots.
ERC-20 changes and cumulative-flow policies have dedicated triggers; see
[`Assertion.sol`](src/Assertion.sol).

The legacy trigger API remains available in `triggers()`:

```solidity
function triggers() external view override {
    // Trigger on any call to the adopter
    registerCallTrigger(this.myAssertion.selector);

    // Trigger on specific function call
    registerCallTrigger(this.myAssertion.selector, ITarget.transfer.selector);

    // Trigger on any storage change
    registerStorageChangeTrigger(this.myAssertion.selector);

    // Trigger on specific storage slot change
    registerStorageChangeTrigger(this.myAssertion.selector, bytes32(uint256(0)));

    // Trigger on balance change
    registerBalanceChangeTrigger(this.myAssertion.selector);
}
```

## Backtesting

Test your assertions against historical blockchain transactions to validate correctness before deployment. The backtesting framework automatically detects both direct calls AND internal/nested calls to your target contract.

### Setup

Add to your `foundry.toml`:

```toml
[profile.backtesting]
src = "src"
test = "test"
ffi = true
gas_limit = 100000000
```

### Block Range Backtesting

The following templates need a real target, transaction/block range, assertion,
and archive-capable RPC URL. Discovery selects transactions touching the target;
it may fall back to direct calls only when tracing is unavailable.

```solidity
import {CredibleTestWithBacktesting} from "credible-std/CredibleTestWithBacktesting.sol";
import {BacktestingTypes} from "credible-std/utils/BacktestingTypes.sol";

contract MyBacktest is CredibleTestWithBacktesting {
    function testHistoricalTransactions() public {
        BacktestingTypes.BacktestingResults memory results = executeBacktest(
            BacktestingTypes.BacktestingConfig({
                targetContract: 0x1234...,           // Contract to monitor
                endBlock: 1000000,                   // End block
                blockRange: 100,                     // Number of blocks to test
                assertionCreationCode: type(MyAssertion).creationCode,
                assertionSelector: MyAssertion.checkInvariant.selector,
                rpcUrl: "https://eth.llamarpc.com",
                detailedBlocks: false,               // Verbose block output
                forkByTxHash: true                   // Fork by tx hash for accurate state
            })
        );

        // A zero-failure result alone can mean nothing was exercised.
        assertGt(results.successfulValidations, 0, "No successful validations");
        assertEq(results.assertionFailures, 0, "Assertions failed on historical data");
        assertEq(results.replayFailures, 0, "Replay failures");
        assertEq(results.unknownErrors, 0, "Unknown errors");
    }
}
```

### Single Transaction Backtesting

Test a specific transaction by hash:

```solidity
contract MyBacktest is CredibleTestWithBacktesting {
    function testSpecificTransaction() public {
        bytes32 txHash = 0xabc123...;

        BacktestingTypes.BacktestingResults memory results = executeBacktestForTransaction(
            txHash,
            0x1234...,                              // Target contract
            type(MyAssertion).creationCode,
            MyAssertion.checkInvariant.selector,
            "https://eth.llamarpc.com"
        );

        assertEq(results.successfulValidations, 1);
        assertEq(results.assertionFailures, 0);
        assertEq(results.replayFailures, 0);
        assertEq(results.unknownErrors, 0);
    }
}
```

### Running Backtests

```bash
# Run with verbose output
pcl test --ffi -vvvv --match-test testHistoricalTransactions

# Or with the backtesting profile
FOUNDRY_PROFILE=backtesting pcl test -vvvv
```

### Internal Call Detection

The backtesting framework automatically detects transactions that call your target contract internally (e.g., through a router or aggregator). It tries multiple trace APIs with automatic fallback:

1. **trace_filter** - Fastest, requires Erigon or archive node with trace API
2. **debug_traceBlockByNumber** - Slower but widely supported
3. **debug_traceTransaction** - Slowest, per-transaction tracing
4. **Direct calls only** - Fallback when no trace APIs available

Example output:
```
=== TRANSACTION DISCOVERY ===
Target: 0x1234...
Blocks: 1000000 to 1000100

[INFO] Detecting both direct calls AND internal/nested calls to target
[INFO] Trying trace APIs with automatic fallback...

[TRACE] Using trace_filter API (fastest method for internal call detection)
[TRACE] trace_filter not supported by this RPC endpoint
[TRACE] Falling back to debug_traceBlockByNumber (slower but widely supported)

=== DISCOVERY COMPLETE ===
[INFO] Detection method: debug_traceBlockByNumber
[INFO] Internal calls: ENABLED
```

### Understanding Results

The backtesting framework provides detailed categorization:

| Result | Description |
|--------|-------------|
| **Success** | Transaction passed assertion validation |
| **Skipped** | Transaction didn't trigger the assertion (selector mismatch) |
| **Assertion Failed** | Assertion policy rejected the transaction; investigate whether the policy models legitimate behavior correctly |
| **Replay Failure** | Transaction reverted before assertion could run |
| **Unknown Error** | Unexpected failure |

When an assertion fails, the framework automatically replays the transaction with full Foundry tracing enabled, showing the complete execution path for debugging.

## State Change Helpers

The `StateChanges` contract provides type-safe helpers for inspecting storage changes:

```solidity
// Get state changes as specific types
uint256[] memory uintChanges = getStateChangesUint(target, slot);
address[] memory addrChanges = getStateChangesAddress(target, slot);
bool[] memory boolChanges = getStateChangesBool(target, slot);
bytes32[] memory rawChanges = getStateChangesBytes32(target, slot);

// With mapping key support
uint256[] memory balanceChanges = getStateChangesUint(target, balancesSlot, userKey);

// With slot offset for struct fields
uint256[] memory fieldChanges = getStateChangesUint(target, structSlot, key, fieldOffset);
```

## Resources

- [Credible Layer Documentation](https://docs.phylax.systems/credible/credible-introduction)
- [Writing Assertions Guide](https://docs.phylax.systems/credible/write-first-assertion)
- [Testing Assertions Guide](https://docs.phylax.systems/credible/testing-assertions)
- [API Documentation](https://phylaxsystems.github.io/credible-std)

## License

MIT

---

<div align="center">
<sub><b>Phylax Systems</b> &nbsp;·&nbsp; <a href="https://docs.phylax.systems">Credible Layer docs</a> &nbsp;·&nbsp; <a href="https://phylax.systems">phylax.systems</a></sub>
</div>
