# Gas Usage Collection

Collects assertion gas costs from `pcl test` output and stores them in a CSV.

## Quick Start

```bash
cd your-project/assertions/

# Initialize (creates gas_usage/ folder with config + CSV)
/path/to/gas_usage.sh init

# Edit gas_usage/gas_usage_config.sh to customize test→assertion mappings

# Run tests and collect gas data
/path/to/gas_usage.sh collect

# Or re-parse existing test output without running tests
/path/to/gas_usage.sh collect --dry
```

## Output

All files are created in `gas_usage/` subfolder:

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

Override with: `FOUNDRY_PROFILE=other-profile ./gas_usage.sh collect`
