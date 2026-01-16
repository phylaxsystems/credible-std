#!/bin/bash
#
# gas_usage.sh - Collect assertion gas usage from pcl tests
#
# Usage:
#   ./gas_usage.sh init              # Generate config template + CSV skeleton
#   ./gas_usage.sh collect           # Run pcl test and update CSV
#   ./gas_usage.sh collect --dry     # Parse existing test_output.txt (no test run)
#   ./gas_usage.sh clean             # Remove invalid gas values from CSV
#   ./gas_usage.sh help              # Show usage
#

set -e

# Determine working directory (where the script is run from)
# Defaults to current working directory
WORK_DIR="${WORK_DIR:-$(pwd)}"

# Output directory for generated files (created if doesn't exist)
# Defaults to assertions/gas_usage since pcl must run from repo root
OUTPUT_DIR="${OUTPUT_DIR:-${WORK_DIR}/assertions/gas_usage}"

# Default file locations (can be overridden via environment)
CONFIG_FILE="${CONFIG_FILE:-${OUTPUT_DIR}/gas_usage_config.sh}"
CSV_FILE="${CSV_FILE:-${OUTPUT_DIR}/assertion_gas_usage.csv}"
OUTPUT_FILE="${OUTPUT_FILE:-${OUTPUT_DIR}/test_output.txt}"
SRC_DIR="${SRC_DIR:-${WORK_DIR}/src}"
FOUNDRY_PROFILE="${FOUNDRY_PROFILE:-unit-assertions}"

# Default settings (overridden by config)
MAX_ASSERTION_GAS="${MAX_ASSERTION_GAS:-300000}"
BATCH_PATTERNS="${BATCH_PATTERNS:-10Deposits 10Withdrawals 10Operations Multiple Batch}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

#------------------------------------------------------------------------------
# Utility functions
#------------------------------------------------------------------------------

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

#------------------------------------------------------------------------------
# Config loading
#------------------------------------------------------------------------------

load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        # shellcheck source=/dev/null
        source "$CONFIG_FILE"
        log_info "Loaded config: $CONFIG_FILE"
    else
        log_warn "Config file not found: $CONFIG_FILE"
        log_warn "Using default settings. Run './gas_usage.sh init' to create config."
    fi
}

# Default mapping function (overridden by config)
map_test_to_assertion() {
    local test_name="$1"
    # Default: no mapping
    echo ""
}

#------------------------------------------------------------------------------
# Init command - generate config and CSV skeleton
#------------------------------------------------------------------------------

cmd_init() {
    log_info "Initializing gas usage collection..."

    # Create output directory if it doesn't exist
    if [[ ! -d "$OUTPUT_DIR" ]]; then
        log_info "Creating output directory: $OUTPUT_DIR"
        mkdir -p "$OUTPUT_DIR"
    fi

    # Scan for assertion functions in Solidity files
    log_info "Scanning for assertion functions in $SRC_DIR..."

    if [[ ! -d "$SRC_DIR" ]]; then
        log_error "Source directory not found: $SRC_DIR"
        exit 1
    fi

    # Find all assertion functions and their contracts
    local assertions=()
    local contracts=()

    while IFS= read -r line; do
        # Extract function name
        local fn_name
        fn_name=$(echo "$line" | sed -E 's/.*function (assertion[A-Za-z0-9_]+).*/\1/')

        # Extract contract name from file
        local file_path
        file_path=$(echo "$line" | cut -d: -f1)
        local contract_name
        contract_name=$(basename "$file_path" .a.sol | sed 's/\.sol$//')

        assertions+=("$fn_name")
        contracts+=("$contract_name")
    done < <(grep -rh "function assertion" "$SRC_DIR"/*.sol 2>/dev/null || true)

    if [[ ${#assertions[@]} -eq 0 ]]; then
        log_warn "No assertion functions found in $SRC_DIR"
        log_warn "Make sure your assertion contracts have functions named 'assertion*'"
    else
        log_info "Found ${#assertions[@]} assertion function(s)"
    fi

    # Generate config file
    if [[ -f "$CONFIG_FILE" ]]; then
        log_warn "Config file already exists: $CONFIG_FILE"
        read -p "Overwrite? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Skipping config generation"
        else
            generate_config "${assertions[@]}" "${contracts[@]}"
        fi
    else
        generate_config "${assertions[@]}" "${contracts[@]}"
    fi

    # Generate CSV skeleton
    if [[ -f "$CSV_FILE" ]]; then
        log_warn "CSV file already exists: $CSV_FILE"
        read -p "Overwrite? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Skipping CSV generation"
        else
            generate_csv "${assertions[@]}" "${contracts[@]}"
        fi
    else
        generate_csv "${assertions[@]}" "${contracts[@]}"
    fi

    log_info "Initialization complete!"
    log_info ""
    log_info "Next steps:"
    log_info "  1. Edit $CONFIG_FILE to customize test→assertion mappings"
    log_info "  2. Run './gas_usage.sh collect' to collect gas data"
}

generate_config() {
    local assertions=("$@")
    local half=$((${#assertions[@]} / 2))
    local fns=("${assertions[@]:0:$half}")
    local contracts=("${assertions[@]:$half}")

    log_info "Generating config: $CONFIG_FILE"

    cat >"$CONFIG_FILE" <<'CONFIGHEADER'
#!/bin/bash
#
# Gas Usage Configuration
# Generated by gas_usage.sh init
#

# Project info
PROJECT_NAME="My Project"
PROTOCOL_NAME="My Protocol"

# Maximum gas for assertions (values above this are invalid)
MAX_ASSERTION_GAS=300000

# Batch test patterns (space-separated)
# Tests matching these patterns will have gas recorded in the batch column
BATCH_PATTERNS="10Deposits 10Withdrawals 10Operations 10Borrows 5Operations Multiple Batch"

# Map test function names to assertion function + adopter
# Returns "assertionFunction:Adopter" or empty string if no match
#
# Pattern matching uses bash glob patterns:
#   * = any characters
#   ? = single character
#
# Order matters! More specific patterns should come first.
map_test_to_assertion() {
    local test_name="$1"
    case "$test_name" in
CONFIGHEADER

    # Generate case statements for each assertion
    # Group by contract to create sensible patterns
    declare -A seen_contracts
    for i in "${!fns[@]}"; do
        local fn="${fns[$i]}"
        local contract="${contracts[$i]}"

        # Determine assertion type from function name
        local type=""
        if [[ "$fn" == *"Batch"* ]]; then
            type="Batch"
        elif [[ "$fn" == *"Call"* ]]; then
            type="Call"
        elif [[ "$fn" == *"ControlCollateral"* ]]; then
            type="ControlCollateral"
        fi

        # Generate pattern based on naming convention
        # Common patterns: testAssertionName_Type_*, testType_*
        if [[ -n "$type" ]]; then
            echo "        test${type}_*)"
            echo "            echo \"${fn}:EVC\" ;;"
        fi

        seen_contracts["$contract"]=1
    done >>"$CONFIG_FILE"

    # Add catch-all patterns for each unique assertion
    for i in "${!fns[@]}"; do
        local fn="${fns[$i]}"
        # Create a generic pattern from the function name
        local base_name
        base_name=$(echo "$fn" | sed 's/assertion//' | sed 's/Batch//' | sed 's/Call//' | sed 's/ControlCollateral//')
        if [[ -n "$base_name" ]]; then
            echo "        test*${base_name}*)"
            echo "            echo \"${fn}:EVC\" ;;"
        fi
    done >>"$CONFIG_FILE"

    cat >>"$CONFIG_FILE" <<'CONFIGFOOTER'
        # Default: no match
        *)
            echo "" ;;
    esac
}
CONFIGFOOTER

    chmod +x "$CONFIG_FILE"
    log_info "Config generated. Please review and customize the mappings!"
}

generate_csv() {
    local assertions=("$@")
    local half=$((${#assertions[@]} / 2))
    local fns=("${assertions[@]:0:$half}")
    local contracts=("${assertions[@]:$half}")

    log_info "Generating CSV: $CSV_FILE"

    # Write header
    echo "Assertion Function Name,Assertion Group Name,Assertion Adopter Address (Contract Name),Protocol It Belongs To,Gas Cost for 1 TX,Gas Cost for Batched 10 TXs,Unit Test Type,Notes" >"$CSV_FILE"

    # Write rows for each assertion
    for i in "${!fns[@]}"; do
        local fn="${fns[$i]}"
        local contract="${contracts[$i]}"
        echo "${fn},${contract},EVC,\${PROTOCOL_NAME},TBD,TBD,Real Contract (Valid test)," >>"$CSV_FILE"
    done

    log_info "CSV generated with ${#fns[@]} assertion(s)"
}

#------------------------------------------------------------------------------
# Collect command - run tests and parse gas costs
#------------------------------------------------------------------------------

cmd_collect() {
    local dry_run=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
        --dry)
            dry_run=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
        esac
    done

    load_config

    if [[ ! -f "$CSV_FILE" ]]; then
        log_error "CSV file not found: $CSV_FILE"
        log_error "Run './gas_usage.sh init' first to create the CSV skeleton."
        exit 1
    fi

    # Run tests unless --dry
    if [[ "$dry_run" == false ]]; then
        log_info "Running pcl tests (profile: $FOUNDRY_PROFILE)..."
        FOUNDRY_PROFILE="$FOUNDRY_PROFILE" pcl test -vvv 2>&1 | tee "$OUTPUT_FILE"
    else
        log_info "Dry run: using existing $OUTPUT_FILE"
        if [[ ! -f "$OUTPUT_FILE" ]]; then
            log_error "Test output file not found: $OUTPUT_FILE"
            exit 1
        fi
    fi

    log_info ""
    log_info "Parsing test output..."

    # Parse test output and update CSV
    parse_and_update_csv

    log_info ""
    log_info "Gas collection complete!"
    log_info "Review: $CSV_FILE"
}

parse_and_update_csv() {
    local current_test=""
    local test_count=0
    local update_count=0

    # Create temp file for updates
    local tmp_csv
    tmp_csv=$(mktemp)
    cp "$CSV_FILE" "$tmp_csv"

    # Track what we've already updated to implement proper priority:
    # - Single TX: keep first value
    # - Batch TX: 10x batch tests always win, others only set if empty
    declare -A updated_single
    declare -A updated_batch

    # Read test output line by line
    while IFS= read -r line; do
        # Check for test result line: [PASS] testName() or [FAIL] testName()
        # Use sed -E for extended regex (portable across BSD/GNU)
        if echo "$line" | grep -qE '\[(PASS|FAIL)\].*\(\)'; then
            current_test=$(echo "$line" | sed -E 's/.*\[(PASS|FAIL)\][[:space:]]+([a-zA-Z0-9_]+)\(\).*/\2/')
            # Verify we got a valid test name (not the whole line)
            if [[ "$current_test" != "$line" && -n "$current_test" ]]; then
                ((test_count++)) || true
            fi
        fi

        # Check for assertion gas cost (ignore transaction gas)
        # Skip lines with "Transaction" in them
        if echo "$line" | grep -qi "transaction"; then
            continue
        fi

        if echo "$line" | grep -qi "assertion.*gas.*cost"; then
            # Extract gas value using sed
            local gas
            gas=$(echo "$line" | sed -n 's/.*[Aa]ssertion[[:space:]]*gas[[:space:]]*cost:[[:space:]]*\([0-9]*\).*/\1/p')

            # Skip if no gas value extracted
            if [[ -z "$gas" ]]; then
                continue
            fi

            # Validate gas is within limits
            if [[ "$gas" -gt "$MAX_ASSERTION_GAS" ]]; then
                log_warn "Ignoring gas $gas for $current_test (exceeds $MAX_ASSERTION_GAS)"
                continue
            fi

            if [[ -z "$current_test" ]]; then
                continue
            fi

            # Get assertion mapping
            local mapping
            mapping=$(map_test_to_assertion "$current_test")

            if [[ -z "$mapping" ]]; then
                log_warn "No mapping for test: $current_test"
                continue
            fi

            local assertion_fn="${mapping%%:*}"
            local adopter="${mapping##*:}"
            local key="${assertion_fn}:${adopter}"

            # Determine if this is a batch test and if it's a 10x batch test
            local is_batch=false
            local is_10x_batch=false

            # Check for 10x batch patterns (highest priority)
            if [[ "$current_test" == *"10Transactions"* ]] ||
                [[ "$current_test" == *"10Operations"* ]] ||
                [[ "$current_test" == *"10Withdrawals"* ]] ||
                [[ "$current_test" == *"10Deposits"* ]] ||
                [[ "$current_test" == *"10Borrows"* ]] ||
                [[ "$current_test" == *"10PriceChanges"* ]]; then
                is_10x_batch=true
                is_batch=true
            else
                # Check other batch patterns
                for pattern in $BATCH_PATTERNS; do
                    if [[ "$current_test" == *"$pattern"* ]]; then
                        is_batch=true
                        break
                    fi
                done
            fi

            # Apply update priority logic
            local should_update=false
            local column=""

            if [[ "$is_batch" == true ]]; then
                column=6
                # 10x batch tests always update
                # Other batch tests only update if we haven't seen this assertion yet
                if [[ "$is_10x_batch" == true ]]; then
                    should_update=true
                    updated_batch["$key"]="10x"
                elif [[ -z "${updated_batch[$key]}" ]]; then
                    should_update=true
                    updated_batch["$key"]="other"
                fi
            else
                column=5
                # Single TX: only update if we haven't seen this assertion yet
                if [[ -z "${updated_single[$key]}" ]]; then
                    should_update=true
                    updated_single["$key"]=1
                fi
            fi

            if [[ "$should_update" == true ]]; then
                update_csv_cell "$tmp_csv" "$assertion_fn" "$adopter" "$column" "$gas"
                ((update_count++)) || true
                log_info "  $current_test → $assertion_fn ($adopter): $gas gas $([ "$is_batch" == true ] && echo "[batch$([ "$is_10x_batch" == true ] && echo " 10x")]" || echo "[single]")"
            fi
        fi
    done <"$OUTPUT_FILE"

    # Replace original CSV with updated version
    mv "$tmp_csv" "$CSV_FILE"

    log_info ""
    log_info "Processed $test_count test(s), updated $update_count gas value(s)"
}

update_csv_cell() {
    local csv_file="$1"
    local assertion_fn="$2"
    local adopter="$3"
    local column="$4"
    local value="$5"

    # Use awk to update the specific cell
    # Match row where column 1 = assertion_fn AND column 3 = adopter
    awk -F',' -v OFS=',' \
        -v fn="$assertion_fn" \
        -v adp="$adopter" \
        -v col="$column" \
        -v val="$value" \
        'NR==1 { print; next }
         $1==fn && $3==adp { $col=val }
         { print }' \
        "$csv_file" >"${csv_file}.tmp" && mv "${csv_file}.tmp" "$csv_file"
}

#------------------------------------------------------------------------------
# Clean command - remove invalid gas values
#------------------------------------------------------------------------------

cmd_clean() {
    load_config

    if [[ ! -f "$CSV_FILE" ]]; then
        log_error "CSV file not found: $CSV_FILE"
        exit 1
    fi

    log_info "Cleaning invalid gas values (> $MAX_ASSERTION_GAS) from $CSV_FILE..."

    local cleaned=0
    local tmp_csv
    tmp_csv=$(mktemp)

    # Process CSV: reset values > MAX_ASSERTION_GAS to TBD
    while IFS=',' read -r fn group adopter protocol single batch test_type notes; do
        # Check and clean single TX gas (column 5)
        if [[ "$single" =~ ^[0-9]+$ ]] && [[ "$single" -gt "$MAX_ASSERTION_GAS" ]]; then
            log_info "  Cleaning $fn: $single > $MAX_ASSERTION_GAS"
            single="TBD"
            ((cleaned++)) || true
        fi

        # Check and clean batch TX gas (column 6)
        if [[ "$batch" =~ ^[0-9]+$ ]] && [[ "$batch" -gt "$MAX_ASSERTION_GAS" ]]; then
            log_info "  Cleaning $fn (batch): $batch > $MAX_ASSERTION_GAS"
            batch="TBD"
            ((cleaned++)) || true
        fi

        echo "${fn},${group},${adopter},${protocol},${single},${batch},${test_type},${notes}"
    done <"$CSV_FILE" >"$tmp_csv"

    mv "$tmp_csv" "$CSV_FILE"

    log_info "Cleaned $cleaned invalid gas value(s)"
}

#------------------------------------------------------------------------------
# Help command
#------------------------------------------------------------------------------

cmd_help() {
    cat <<EOF
gas_usage.sh - Collect assertion gas usage from pcl tests

USAGE:
    ./gas_usage.sh <command> [options]

COMMANDS:
    init              Generate config template and CSV skeleton by scanning
                      Solidity files for assertion functions

    collect           Run pcl tests and update CSV with gas costs
    collect --dry     Parse existing test_output.txt without running tests

    clean             Remove invalid gas values (> MAX_ASSERTION_GAS) from CSV

    help              Show this help message

ENVIRONMENT VARIABLES:
    CONFIG_FILE       Path to config file (default: ../gas_usage_config.sh)
    CSV_FILE          Path to CSV file (default: ../assertion_gas_usage.csv)
    OUTPUT_FILE       Path to test output file (default: ../test_output.txt)
    SRC_DIR           Path to Solidity source directory (default: ../src)
    FOUNDRY_PROFILE   Foundry profile for tests (default: unit-assertions)

EXAMPLES:
    # First-time setup
    ./gas_usage.sh init

    # Edit gas_usage_config.sh to customize mappings, then:
    ./gas_usage.sh collect

    # Re-parse existing test output
    ./gas_usage.sh collect --dry

EOF
}

#------------------------------------------------------------------------------
# Main entry point
#------------------------------------------------------------------------------

main() {
    local cmd="${1:-help}"
    shift || true

    case "$cmd" in
    init)
        cmd_init "$@"
        ;;
    collect)
        cmd_collect "$@"
        ;;
    clean)
        cmd_clean "$@"
        ;;
    help | --help | -h)
        cmd_help
        ;;
    *)
        log_error "Unknown command: $cmd"
        cmd_help
        exit 1
        ;;
    esac
}

main "$@"
