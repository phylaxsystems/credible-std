# Gas Usage Collection

Collects assertion gas costs from `pcl test` output and stores them in a CSV.

## Quick Start

```bash
cd your-project  # the directory containing foundry.toml

# Initialize (creates assertions/gas_usage/ folder with config + CSV)
bash /path/to/gas_usage.sh init

# Edit assertions/gas_usage/gas_usage_config.sh to customize test→assertion mappings

# Run tests and collect gas data
bash /path/to/gas_usage.sh collect

# Or re-parse existing test output without running tests
bash /path/to/gas_usage.sh collect --dry
```

## Output

All files are created in `assertions/gas_usage/` by default (relative to the working directory):

- `gas_usage_config.sh` - Test→assertion mappings (edit this)
- `assertion_gas_usage.csv` - Gas costs
- `test_output.txt` - Cached test output

## Config

The `map_test_to_assertion()` function maps test names to assertions:

```bash
map_test_to_assertion() {
    case "$1" in
        testBatch_10*)       echo "assertionBatch:EVC" ;;
        testCall_*)          echo "assertionCall:EVC" ;;
        *)                   echo "" ;;  # No match
    esac
}
```

Pattern order matters - more specific patterns first.

## Foundry Profile

The script runs tests using the `unit-assertions` profile by default:

```bash
FOUNDRY_PROFILE=unit-assertions pcl test -vvv
```

This profile must be defined in your project's `foundry.toml`. See [Foundry Profile Configuration](https://docs.phylax.systems/credible/ci-cd-integration#foundry-profile-configuration) for setup instructions.

Override with: `FOUNDRY_PROFILE=other-profile bash ./gas_usage.sh collect`

## Source scanning and overrides

Run with Bash 4+ (the script uses associative arrays) and PCL on `PATH`.
Initialization scans only `SRC_DIR/*.sol` for functions named `assertion*`;
`SRC_DIR` defaults to `src/`. Many examples use `assert*` instead, so review and
complete the generated CSV and mappings rather than assuming discovery is complete.

This repository has no `unit-assertions` profile. Select one of its actual profiles,
for example `micro-patterns`, and set output/source paths explicitly if desired:

```bash
OUTPUT_DIR=gas_usage SRC_DIR=examples/micro-patterns/src bash ./scripts/gas_usage.sh init
# Complete gas_usage/gas_usage_config.sh and the CSV before collecting.
OUTPUT_DIR=gas_usage FOUNDRY_PROFILE=micro-patterns bash ./scripts/gas_usage.sh collect
```

Treat the CSV as a report, not a test gate: the collector pipes PCL output through
`tee` without `pipefail`. Run the [shared example checks](../examples/README.md#setup-and-checks)
separately to establish that tests passed.
