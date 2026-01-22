#!/bin/bash

# Transaction Fetcher - Bash Implementation
# Fetches blockchain transactions for backtesting
# Uses trace APIs (trace_filter or debug_trace*) to detect internal calls

set -eo pipefail

# Default values
OUTPUT_FORMAT="simple"
BATCH_SIZE=10
MAX_CONCURRENT=5
DETAILED_BLOCKS=false
USE_TRACE_FILTER=false
TRACE_FILTER_BATCH_SIZE=100
TRACE_METHOD=""
TEMP_DIR=""
START_TIME=""

# RPC call counter files (for aggregating across subprocesses)
RPC_COUNTER_DIR=""

# Cleanup function
cleanup() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
}

# Set up cleanup on exit
trap cleanup EXIT

# Create temporary directory for parallel processing
TEMP_DIR=$(mktemp -d)
RPC_COUNTER_DIR="$TEMP_DIR/rpc_counters"
mkdir -p "$RPC_COUNTER_DIR"

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Fetches blockchain transactions for backtesting.

OPTIONS:
    --rpc-url URL                  RPC endpoint URL (required)
    --target-contract ADDRESS      Contract address to filter transactions for (required)
    --start-block NUMBER           Starting block number (required)
    --end-block NUMBER             Ending block number (required)
    --output-format FORMAT         Output format: simple or json (default: simple)
    --batch-size SIZE              Batch size for processing (default: 10)
    --max-concurrent COUNT         Maximum concurrent requests (default: 5)
    --use-trace-filter             Use traces for internal call detection (trace_filter w/ debug_trace* fallback)
    --trace-filter-batch-size SIZE Batch size for trace_filter (default: 100)
    --detailed-blocks              Enable detailed per-block summaries (default: false)
    -h, --help                     Show this help message

EXAMPLES:
    # Basic usage - fetch direct calls only
    $0 --rpc-url https://eth.llamarpc.com \\
       --target-contract 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D \\
       --start-block 10000000 \\
       --end-block 10000100

    # Use trace-based detection (trace_filter or debug_trace* fallback)
    $0 --rpc-url \$MAINNET_RPC_URL \\
       --target-contract 0xBA12222222228d8Ba445958a75a0704d566BF2C8 \\
       --start-block 23717632 \\
       --end-block 23717632 \\
       --use-trace-filter

PERFORMANCE:
    --batch-size: Blocks to process in parallel (default: 10, try 10-50)
    --max-concurrent: Concurrent RPC requests (default: 5, try 5-20)
    --trace-filter-batch-size: Blocks per trace_filter call (default: 100)

    Balance these based on your RPC provider's rate limits.

OUTPUT:
    simple: count|hash|from|to|value|data|blockNumber|txIndex|gasPrice|gasLimit|maxFeePerGas|maxPriorityFeePerGas|...
    json:   Array of transaction objects with labeled fields

EOF
}

# Exponential backoff retry function
# Usage: retry_with_backoff <max_retries> <curl_command...>
retry_with_backoff() {
    local max_retries="$1"
    shift
    local attempt=0
    local response=""

    while [[ $attempt -lt $max_retries ]]; do
        # Execute the curl command
        response=$("$@" 2>/dev/null || echo "")

        # Check if response is empty
        if [[ -z "$response" ]]; then
            attempt=$((attempt + 1))
            if [[ $attempt -lt $max_retries ]]; then
                local wait_time
                local jitter
                local total_wait
                local max_wait
                local wait_seconds
                wait_time=$((2 ** attempt))
                jitter=$((RANDOM % 1000))
                total_wait=$((wait_time * 1000 + jitter))
                max_wait=64000
                if [[ $total_wait -gt $max_wait ]]; then
                    total_wait=$max_wait
                fi
                wait_seconds=$(awk "BEGIN {print $total_wait/1000}")
                sleep "$wait_seconds"
                continue
            fi
        fi

        # Check for 429 error
        local error_code
        error_code=$(echo "$response" | jq -r '.error.code // empty' 2>/dev/null)
        if [[ "$error_code" == "429" ]]; then
            attempt=$((attempt + 1))
            if [[ $attempt -lt $max_retries ]]; then
                # Exponential backoff: 2^n seconds + random jitter (0-1000ms)
                local wait_time
                local jitter
                local total_wait
                local max_wait
                local wait_seconds
                wait_time=$((2 ** attempt))
                jitter=$((RANDOM % 1000))
                total_wait=$((wait_time * 1000 + jitter))

                # Cap at maximum backoff of 64 seconds
                max_wait=64000
                if [[ $total_wait -gt $max_wait ]]; then
                    total_wait=$max_wait
                fi

                wait_seconds=$(awk "BEGIN {print $total_wait/1000}")
                echo "Rate limit hit (429), retrying after ${wait_seconds}s (attempt $attempt/$max_retries)" >&2
                sleep "$wait_seconds"
                continue
            else
                echo "Max retries reached for rate-limited request" >&2
            fi
        fi

        # Success or non-retryable error
        echo "$response"
        return 0
    done

    # All retries exhausted
    echo "$response"
    return 1
}

# Check if required tools are available
check_dependencies() {
    local missing_tools=()

    if ! command -v curl &> /dev/null; then
        missing_tools+=("curl")
    fi

    if ! command -v jq &> /dev/null; then
        missing_tools+=("jq")
    fi

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        echo "Error: Missing required tools: ${missing_tools[*]}" >&2
        echo "Please install the missing tools and try again." >&2
        exit 1
    fi
}

# Convert hex to decimal
hex_to_decimal() {
    local hex_value="$1"
    if [[ "$hex_value" =~ ^0x[0-9a-fA-F]+$ ]]; then
        printf "%d" "$hex_value"
    else
        echo "$hex_value"
    fi
}

# Count RPC calls from counter file
count_rpc_calls() {
    local counter_name="$1"
    local file="$RPC_COUNTER_DIR/${counter_name}.count"
    if [[ -f "$file" ]]; then
        wc -l < "$file" | tr -d ' '
    else
        echo "0"
    fi
}

# Check if RPC error indicates unsupported method
is_method_unsupported() {
    local response="$1"
    local error_code
    local error_msg
    error_code=$(echo "$response" | jq -r '.error.code // empty' 2>/dev/null)
    error_msg=$(echo "$response" | jq -r '.error.message // empty' 2>/dev/null | tr '[:upper:]' '[:lower:]')

    if [[ "$error_code" == "-32601" ]]; then
        return 0
    fi
    if [[ -n "$error_msg" ]]; then
        if [[ "$error_msg" == *"method not found"* ]] ||
           [[ "$error_msg" == *"does not exist"* ]] ||
           [[ "$error_msg" == *"not available"* ]] ||
           [[ "$error_msg" == *"unknown method"* ]] ||
           [[ "$error_msg" == *"not supported"* ]]; then
            return 0
        fi
    fi
    return 1
}

# Fetch transaction details and receipts for a list of tx hashes
emit_transactions_from_hashes() {
    local rpc_url="$1"
    local tx_hashes="$2"
    local output_file="$3"

    local tx_count=0
    local tx_processed=0

    if [[ -n "$tx_hashes" ]]; then
        while IFS= read -r tx_hash; do
            [[ -z "$tx_hash" ]] && continue

            # Add small delay every 5 transactions to avoid rate limiting
            if [[ $((tx_processed % 5)) -eq 0 && $tx_processed -gt 0 ]]; then
                sleep 0.1
            fi
            ((tx_processed++))

            # Fetch actual transaction data using eth_getTransactionByHash
            local tx_request
            tx_request=$(jq -n \
                --arg tx_hash "$tx_hash" \
                '{
                    "jsonrpc": "2.0",
                    "method": "eth_getTransactionByHash",
                    "params": [$tx_hash],
                    "id": 1
                }')

            echo "1" >> "$RPC_COUNTER_DIR/tx_fetch.count"
            local tx_response
            tx_response=$(retry_with_backoff 5 curl -s -X POST \
                -H "Content-Type: application/json" \
                -d "$tx_request" \
                --max-time 30 \
                "$rpc_url")

            local tx_data
            tx_data=$(echo "$tx_response" | jq -r '.result')

            if [[ -n "$tx_data" && "$tx_data" != "null" ]]; then
                local tx_from
                local tx_to
                local tx_value
                local tx_input
                local tx_gas_price
                local tx_gas_limit
                local tx_max_fee_per_gas
                local tx_max_priority_fee_per_gas
                local tx_block_num_hex
                local tx_index_hex

                tx_from=$(echo "$tx_data" | jq -r '.from')
                tx_to=$(echo "$tx_data" | jq -r '.to // empty')
                tx_value=$(echo "$tx_data" | jq -r '.value')
                tx_input=$(echo "$tx_data" | jq -r '.input')
                tx_gas_price=$(echo "$tx_data" | jq -r '.gasPrice // "0x0"')
                tx_gas_limit=$(echo "$tx_data" | jq -r '.gas // "0x0"')
                tx_max_fee_per_gas=$(echo "$tx_data" | jq -r '.maxFeePerGas // "0x0"')
                tx_max_priority_fee_per_gas=$(echo "$tx_data" | jq -r '.maxPriorityFeePerGas // "0x0"')
                tx_block_num_hex=$(echo "$tx_data" | jq -r '.blockNumber // empty')
                tx_index_hex=$(echo "$tx_data" | jq -r '.transactionIndex // empty')

                local block_num
                local tx_index
                block_num=$(hex_to_decimal "$tx_block_num_hex")
                tx_index=$(hex_to_decimal "$tx_index_hex")

                # Check if transaction succeeded on-chain
                local receipt_request
                receipt_request=$(jq -n \
                    --arg tx_hash "$tx_hash" \
                    '{
                        "jsonrpc": "2.0",
                        "method": "eth_getTransactionReceipt",
                        "params": [$tx_hash],
                        "id": 1
                    }')

                echo "1" >> "$RPC_COUNTER_DIR/receipt_fetch.count"
                local receipt_response
                receipt_response=$(retry_with_backoff 5 curl -s -X POST \
                    -H "Content-Type: application/json" \
                    -d "$receipt_request" \
                    --max-time 30 \
                    "$rpc_url")

                local tx_status
                tx_status=$(echo "$receipt_response" | jq -r '.result.status // empty')

                # Only output transaction if it succeeded (status == "0x1")
                if [[ "$tx_status" == "0x1" ]]; then
                    echo "$tx_hash|$tx_from|$tx_to|$tx_value|$tx_input|$block_num|$tx_index|$tx_gas_price|$tx_gas_limit|$tx_max_fee_per_gas|$tx_max_priority_fee_per_gas" >> "$output_file"
                    ((tx_count++))
                fi
            fi
        done <<< "$tx_hashes"
    fi

    echo "$tx_count"
}

# Fetch transactions using trace_filter (much faster for internal calls)
fetch_transactions_trace_filter() {
    local rpc_url="$1"
    local start_block="$2"
    local end_block="$3"
    local target_contract="$4"
    local output_file="$5"

    # Convert block numbers to hex
    local start_hex
    local end_hex
    start_hex=$(printf "0x%x" "$start_block")
    end_hex=$(printf "0x%x" "$end_block")

    echo "[TRACE] Using trace_filter API (fastest method for internal call detection)" >&2
    echo "[TRACE] Fetching blocks $start_block to $end_block..." >&2

    # Prepare trace_filter request
    local trace_request
    trace_request=$(jq -n \
        --arg start_hex "$start_hex" \
        --arg end_hex "$end_hex" \
        --arg target "$target_contract" \
        '{
            "jsonrpc": "2.0",
            "method": "trace_filter",
            "params": [{
                "fromBlock": $start_hex,
                "toBlock": $end_hex,
                "toAddress": [$target]
            }],
            "id": 1
        }')

    # Make RPC call with retry logic
    echo "1" >> "$RPC_COUNTER_DIR/trace_filter.count"
    local trace_response
    trace_response=$(retry_with_backoff 5 curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "$trace_request" \
        --max-time 60 \
        "$rpc_url")

    # Check for errors
    if [[ -z "$trace_response" ]] || echo "$trace_response" | jq -e '.error' > /dev/null 2>&1; then
        local error_msg
        error_msg=$(echo "$trace_response" | jq -r '.error.message // "Unknown error"')
        echo "Error: trace_filter failed: $error_msg" >&2
        if is_method_unsupported "$trace_response"; then
            echo "[TRACE] trace_filter not supported by this RPC endpoint" >&2
            echo "0"
            return 2
        fi
        echo "0"
        return 1
    fi

    # Extract unique transaction hashes that involve the target contract
    local tx_hashes
    tx_hashes=$(echo "$trace_response" | jq -r '.result | map(.transactionHash) | unique | .[]?')
    tx_hashes=$(echo "$tx_hashes" | awk 'NF' | awk '!seen[$0]++')

    local tx_count
    tx_count=$(emit_transactions_from_hashes "$rpc_url" "$tx_hashes" "$output_file")

    echo "  Found $tx_count transactions in blocks $start_block-$end_block" >&2
    echo "$tx_count"
}

# Fetch transactions using debug_traceBlockByNumber with callTracer
fetch_transactions_debug_trace_block() {
    local rpc_url="$1"
    local start_block="$2"
    local end_block="$3"
    local target_contract="$4"
    local output_file="$5"

    local target_contract_lower
    target_contract_lower=$(echo "$target_contract" | tr '[:upper:]' '[:lower:]')

    local tx_hashes=""

    for ((block=start_block; block<=end_block; block++)); do
        local block_hex
        block_hex=$(printf "0x%x" "$block")

        echo "[TRACE] Tracing block $block with debug_traceBlockByNumber..." >&2

        local trace_request
        trace_request=$(jq -n \
            --arg block_hex "$block_hex" \
            '{
                "jsonrpc": "2.0",
                "method": "debug_traceBlockByNumber",
                "params": [$block_hex, {"tracer":"callTracer"}],
                "id": 1
            }')

        echo "1" >> "$RPC_COUNTER_DIR/debug_trace_block.count"
        local trace_response
        trace_response=$(retry_with_backoff 5 curl -s -X POST \
            -H "Content-Type: application/json" \
            -d "$trace_request" \
            --max-time 60 \
            "$rpc_url")

        if [[ -z "$trace_response" ]] || echo "$trace_response" | jq -e '.error' > /dev/null 2>&1; then
            local error_msg
            error_msg=$(echo "$trace_response" | jq -r '.error.message // "Unknown error"')
            echo "Error: debug_traceBlockByNumber failed: $error_msg" >&2
            if is_method_unsupported "$trace_response"; then
                echo "[TRACE] debug_traceBlockByNumber not supported by this RPC endpoint" >&2
                echo "0"
                return 2
            fi
            echo "0"
            return 1
        fi

        local block_tx_hashes
        block_tx_hashes=$(echo "$trace_response" | jq -r --arg target "$target_contract_lower" '
            def hasTarget(node):
                if (node | type) == "object" then
                    ((node.to? // "" | ascii_downcase) == $target) or
                    ([node.calls[]? | hasTarget(.)] | any)
                else
                    false
                end;
            .result[]?
            | (.result? // .) as $r
            | select(hasTarget($r))
            | (.txHash // .transactionHash // .hash // empty)
        ')

        if [[ -n "$block_tx_hashes" ]]; then
            tx_hashes+="$block_tx_hashes"$'\n'
        fi
    done

    tx_hashes=$(echo "$tx_hashes" | awk 'NF' | awk '!seen[$0]++')
    local tx_count
    tx_count=$(emit_transactions_from_hashes "$rpc_url" "$tx_hashes" "$output_file")

    echo "  Found $tx_count transactions in blocks $start_block-$end_block" >&2
    echo "$tx_count"
}

# Fetch transactions using debug_traceTransaction with callTracer (slow fallback)
fetch_transactions_debug_trace_tx() {
    local rpc_url="$1"
    local start_block="$2"
    local end_block="$3"
    local target_contract="$4"
    local output_file="$5"

    local target_contract_lower
    target_contract_lower=$(echo "$target_contract" | tr '[:upper:]' '[:lower:]')

    local tx_hashes=""

    for ((block=start_block; block<=end_block; block++)); do
        local block_hex
        block_hex=$(printf "0x%x" "$block")

        local block_request
        block_request=$(jq -n \
            --arg block_hex "$block_hex" \
            '{
                "jsonrpc": "2.0",
                "method": "eth_getBlockByNumber",
                "params": [$block_hex, false],
                "id": 1
            }')

        echo "1" >> "$RPC_COUNTER_DIR/block_fetch.count"
        local block_response
        block_response=$(retry_with_backoff 5 curl -s -X POST \
            -H "Content-Type: application/json" \
            -d "$block_request" \
            --max-time 30 \
            "$rpc_url")

        if [[ -z "$block_response" ]] || echo "$block_response" | jq -e '.error' > /dev/null 2>&1; then
            local error_msg
            error_msg=$(echo "$block_response" | jq -r '.error.message // "Unknown error"')
            echo "Error: eth_getBlockByNumber failed: $error_msg" >&2
            echo "0"
            return 1
        fi

        local tx_list
        tx_list=$(echo "$block_response" | jq -r '.result.transactions[]? // empty')

        while IFS= read -r tx_hash; do
            [[ -z "$tx_hash" ]] && continue

            local trace_request
            trace_request=$(jq -n \
                --arg tx_hash "$tx_hash" \
                '{
                    "jsonrpc": "2.0",
                    "method": "debug_traceTransaction",
                    "params": [$tx_hash, {"tracer":"callTracer"}],
                    "id": 1
                }')

            echo "1" >> "$RPC_COUNTER_DIR/debug_trace_tx.count"
            local trace_response
            trace_response=$(retry_with_backoff 5 curl -s -X POST \
                -H "Content-Type: application/json" \
                -d "$trace_request" \
                --max-time 60 \
                "$rpc_url")

            if [[ -z "$trace_response" ]] || echo "$trace_response" | jq -e '.error' > /dev/null 2>&1; then
                local error_msg
                error_msg=$(echo "$trace_response" | jq -r '.error.message // "Unknown error"')
                echo "Error: debug_traceTransaction failed: $error_msg" >&2
                if is_method_unsupported "$trace_response"; then
                    echo "[TRACE] debug_traceTransaction not supported by this RPC endpoint" >&2
                    echo "0"
                    return 2
                fi
                continue
            fi

            if echo "$trace_response" | jq -e --arg target "$target_contract_lower" '
                def hasTarget(node):
                    if (node | type) == "object" then
                        ((node.to? // "" | ascii_downcase) == $target) or
                        ([node.calls[]? | hasTarget(.)] | any)
                    else
                        false
                    end;
                (.result? // empty) as $r
                | $r != null and hasTarget($r)
            ' > /dev/null; then
                tx_hashes+="$tx_hash"$'\n'
            fi
        done <<< "$tx_list"
    done

    tx_hashes=$(echo "$tx_hashes" | awk 'NF' | awk '!seen[$0]++')
    local tx_count
    tx_count=$(emit_transactions_from_hashes "$rpc_url" "$tx_hashes" "$output_file")

    echo "  Found $tx_count transactions in blocks $start_block-$end_block" >&2
    echo "$tx_count"
}

# Fetch transactions from a single block
fetch_block_transactions() {
    local rpc_url="$1"
    local block_number="$2"
    local target_contract="$3"
    local output_file="$4"
    local rpc_counter_dir="$5"

    # Convert block number to hex
    local block_hex
    block_hex=$(printf "0x%x" "$block_number")

    # Prepare RPC request
    local rpc_request
    rpc_request=$(jq -n \
        --arg method "eth_getBlockByNumber" \
        --arg block_hex "$block_hex" \
        '{
            "jsonrpc": "2.0",
            "method": $method,
            "params": [$block_hex, true],
            "id": 1
        }')

    # Make the request with retry logic (max 5 retries)
    local response
    echo "1" >> "$rpc_counter_dir/block_fetch.count"
    response=$(retry_with_backoff 5 curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "$rpc_request" \
        --max-time 30 \
        "$rpc_url")

    if [[ -z "$response" ]]; then
        echo "Error: Failed to fetch block $block_number after retries" >&2
        return 1
    fi

    # Check for RPC errors
    local error
    if ! error=$(echo "$response" | jq -r '.error // empty' 2>/dev/null); then
        echo "Error: Invalid JSON response for block $block_number" >&2
        return 1
    fi

    if [[ -n "$error" && "$error" != "null" ]]; then
        echo "Error: RPC error for block $block_number: $error" >&2
        return 1
    fi

    # Extract block data
    local block_data
    if ! block_data=$(echo "$response" | jq -r '.result // empty' 2>/dev/null); then
        echo "Error: Invalid JSON response for block $block_number" >&2
        return 1
    fi

    if [[ -z "$block_data" || "$block_data" == "null" || "$block_data" == "empty" ]]; then
        echo "Warning: No block data for block $block_number" >&2
        return 1
    fi

    # Get block number and transactions
    local block_num_hex
    if ! block_num_hex=$(echo "$block_data" | jq -r '.number' 2>/dev/null); then
        echo "Error: Failed to parse block number for block $block_number" >&2
        return 1
    fi

    local transactions
    if ! transactions=$(echo "$block_data" | jq -c '.transactions[]? // empty' 2>/dev/null); then
        echo "Error: Failed to parse transactions for block $block_number" >&2
        return 1
    fi

    # Convert block number to decimal
    local block_num_decimal
    block_num_decimal=$(hex_to_decimal "$block_num_hex")

    # Filter transactions that interact with the target contract
    local target_contract_lower
    target_contract_lower=$(echo "$target_contract" | tr '[:upper:]' '[:lower:]')

    # Process each transaction - only check direct calls (tx.to == target)
    while IFS= read -r tx; do
        [[ -z "$tx" ]] && continue

        local tx_hash
        local tx_to
        tx_hash=$(echo "$tx" | jq -r '.hash')
        tx_to=$(echo "$tx" | jq -r '.to // empty')

        # Check if this is a direct call to target contract
        if [[ -n "$tx_to" ]]; then
            local tx_to_lower
            tx_to_lower=$(echo "$tx_to" | tr '[:upper:]' '[:lower:]')
            if [[ "$tx_to_lower" == "$target_contract_lower" ]]; then
                # Direct call found - check if transaction succeeded on-chain
                local receipt_request
                receipt_request=$(jq -n \
                    --arg tx_hash "$tx_hash" \
                    '{
                        "jsonrpc": "2.0",
                        "method": "eth_getTransactionReceipt",
                        "params": [$tx_hash],
                        "id": 1
                    }')

                echo "1" >> "$rpc_counter_dir/receipt_fetch.count"
                local receipt_response
                receipt_response=$(retry_with_backoff 5 curl -s -X POST \
                    -H "Content-Type: application/json" \
                    -d "$receipt_request" \
                    --max-time 30 \
                    "$rpc_url")

                local tx_status
                tx_status=$(echo "$receipt_response" | jq -r '.result.status // empty')

                # Only output transaction if it succeeded (status == "0x1")
                if [[ "$tx_status" == "0x1" ]]; then
                    local tx_from
                    local tx_value
                    local tx_input
                    local tx_index_hex
                    local tx_gas_price
                    local tx_gas_limit
                    local tx_max_fee_per_gas
                    local tx_max_priority_fee_per_gas
                    tx_from=$(echo "$tx" | jq -r '.from')
                    tx_value=$(echo "$tx" | jq -r '.value')
                    tx_input=$(echo "$tx" | jq -r '.input')
                    tx_index_hex=$(echo "$tx" | jq -r '.transactionIndex')
                    tx_gas_price=$(echo "$tx" | jq -r '.gasPrice // "0x0"')
                    tx_gas_limit=$(echo "$tx" | jq -r '.gas // "0x0"')
                    tx_max_fee_per_gas=$(echo "$tx" | jq -r '.maxFeePerGas // "0x0"')
                    tx_max_priority_fee_per_gas=$(echo "$tx" | jq -r '.maxPriorityFeePerGas // "0x0"')

                    # Convert transaction index to decimal
                    local tx_index_decimal
                    tx_index_decimal=$(hex_to_decimal "$tx_index_hex")

                    # Output transaction in the format: hash|from|to|value|data|blockNumber|txIndex|gasPrice|gasLimit|maxFeePerGas|maxPriorityFeePerGas
                    echo "$tx_hash|$tx_from|$tx_to|$tx_value|$tx_input|$block_num_decimal|$tx_index_decimal|$tx_gas_price|$tx_gas_limit|$tx_max_fee_per_gas|$tx_max_priority_fee_per_gas" >> "$output_file"
                fi
            fi
        fi
    done <<< "$transactions"
}

# Process a batch of blocks
process_batch() {
    local rpc_url="$1"
    local start_block="$2"
    local end_block="$3"
    local target_contract="$4"
    local batch_id="$5"
    local max_concurrent="$6"

    local batch_output="$TEMP_DIR/batch_$batch_id.txt"
    touch "$batch_output"

    # Create array of block numbers in this batch
    local blocks=()
    for ((block=start_block; block<=end_block; block++)); do
        blocks+=("$block")
    done

    echo "Processing batch $batch_id: blocks $start_block to $end_block" >&2

    # Process blocks with concurrency limit
    local pids=()
    local block_index=0

    while [[ $block_index -lt ${#blocks[@]} ]]; do
        # Start new jobs up to the concurrency limit
        while [[ ${#pids[@]} -lt $max_concurrent && $block_index -lt ${#blocks[@]} ]]; do
            local block_num="${blocks[$block_index]}"
            fetch_block_transactions "$rpc_url" "$block_num" "$target_contract" "$batch_output" "$RPC_COUNTER_DIR" &
            pids+=($!)
            ((block_index++))
        done

        # Wait for at least one job to complete
        if [[ ${#pids[@]} -gt 0 ]]; then
            wait "${pids[0]}"
            pids=("${pids[@]:1}")  # Remove first element
        fi
    done

    # Wait for all remaining jobs
    if [[ ${#pids[@]} -gt 0 ]]; then
        wait "${pids[@]}"
    fi

    # Count transactions found in this batch
    local tx_count=0
    if [[ -f "$batch_output" ]]; then
        tx_count=$(wc -l < "$batch_output" 2>/dev/null || echo "0")
    fi

    if [[ $tx_count -gt 0 ]]; then
        echo "  Batch $batch_id: found $tx_count transactions" >&2
    fi

    # Always return a number (default to 0 if empty)
    echo "${tx_count:-0}"
}

# Format transactions for output
format_transactions() {
    local output_format="$1"
    local all_transactions_file="$2"

    if [[ ! -f "$all_transactions_file" ]] || [[ ! -s "$all_transactions_file" ]]; then
        echo "0"
        return
    fi

    # Count transactions (one per line)
    local tx_count
    tx_count=$(wc -l < "$all_transactions_file" | tr -d ' ')

    case "$output_format" in
        "json")
            # Convert to JSON format
            echo "["
            local first=true
            while IFS='|' read -r hash from to value data block_number tx_index gas_price gas_limit max_fee_per_gas max_priority_fee_per_gas; do
                if [[ "$first" == "true" ]]; then
                    first=false
                else
                    echo ","
                fi
                jq -n \
                    --arg hash "$hash" \
                    --arg from "$from" \
                    --arg to "$to" \
                    --arg value "$value" \
                    --arg data "$data" \
                    --arg block_number "$block_number" \
                    --arg tx_index "$tx_index" \
                    --arg gas_price "$gas_price" \
                    --arg gas_limit "$gas_limit" \
                    --arg max_fee_per_gas "$max_fee_per_gas" \
                    --arg max_priority_fee_per_gas "$max_priority_fee_per_gas" \
                    '{
                        hash: $hash,
                        from: $from,
                        to: $to,
                        value: $value,
                        data: $data,
                        block_number: $block_number,
                        transaction_index: $tx_index,
                        gas_price: $gas_price,
                        gas_limit: $gas_limit,
                        max_fee_per_gas: $max_fee_per_gas,
                        max_priority_fee_per_gas: $max_priority_fee_per_gas
                    }' | tr -d '\n'
            done < "$all_transactions_file"
            echo
            echo "]"
            ;;
        *)
            # Simple format: count|hash|from|to|value|data|blockNumber|txIndex|gasPrice|gasLimit|maxFeePerGas|maxPriorityFeePerGas|...
            echo -n "$tx_count"
            while IFS='|' read -r hash from to value data block_number tx_index gas_price gas_limit max_fee_per_gas max_priority_fee_per_gas; do
                echo -n "|$hash|$from|$to|$value|$data|$block_number|$tx_index|$gas_price|$gas_limit|$max_fee_per_gas|$max_priority_fee_per_gas"
            done < "$all_transactions_file"
            ;;
    esac
}

# Main function
main() {
    local rpc_url=""
    local target_contract=""
    local start_block=""
    local end_block=""

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --rpc-url)
                rpc_url="$2"
                shift 2
                ;;
            --target-contract)
                target_contract="$2"
                shift 2
                ;;
            --start-block)
                start_block="$2"
                shift 2
                ;;
            --end-block)
                end_block="$2"
                shift 2
                ;;
            --output-format)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            --batch-size)
                BATCH_SIZE="$2"
                shift 2
                ;;
            --max-concurrent)
                MAX_CONCURRENT="$2"
                shift 2
                ;;
            --detailed-blocks)
                DETAILED_BLOCKS=true
                shift
                ;;
            --use-trace-filter)
                USE_TRACE_FILTER=true
                shift
                ;;
            --trace-filter-batch-size)
                TRACE_FILTER_BATCH_SIZE="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                echo "Error: Unknown option $1" >&2
                usage
                exit 1
                ;;
        esac
    done

    # Validate required arguments
    if [[ -z "$rpc_url" || -z "$target_contract" || -z "$start_block" || -z "$end_block" ]]; then
        echo "Error: Missing required arguments" >&2
        usage
        exit 1
    fi

    # Validate numeric arguments
    if ! [[ "$start_block" =~ ^[0-9]+$ ]] || ! [[ "$end_block" =~ ^[0-9]+$ ]]; then
        echo "Error: Block numbers must be positive integers" >&2
        exit 1
    fi

    if [[ $start_block -gt $end_block ]]; then
        echo "Error: Start block must be less than or equal to end block" >&2
        exit 1
    fi

    # Check dependencies
    check_dependencies

    # Start timing
    START_TIME=$(date +%s)

    # Process blocks in batches
    local all_transactions_file="$TEMP_DIR/all_transactions.txt"
    touch "$all_transactions_file"

    local total_blocks_processed=0
    local total_transactions_found=0
    local batch_id=0

    # Choose processing method and batch size
    local batch_size
    if [[ "$USE_TRACE_FILTER" == "true" ]]; then
        TRACE_METHOD="trace_filter"
        echo "" >&2
        echo "=== TRANSACTION DISCOVERY ===" >&2
        echo "Target: $target_contract" >&2
        echo "Blocks: $start_block to $end_block" >&2
        echo "" >&2
        echo "[INFO] Detecting both direct calls AND internal/nested calls to target" >&2
        echo "[INFO] Trying trace APIs with automatic fallback..." >&2
        echo "" >&2
        batch_size=$TRACE_FILTER_BATCH_SIZE
    else
        echo "" >&2
        echo "=== TRANSACTION DISCOVERY ===" >&2
        echo "Target: $target_contract" >&2
        echo "Blocks: $start_block to $end_block" >&2
        echo "" >&2
        echo "[INFO] Direct calls only mode (no internal call detection)" >&2
        echo "" >&2
        batch_size=$BATCH_SIZE
    fi

    # Unified batch processing loop
    for ((batch_start=start_block; batch_start<=end_block; batch_start+=batch_size)); do
        local batch_end=$((batch_start + batch_size - 1))
        if [[ $batch_end -gt $end_block ]]; then
            batch_end=$end_block
        fi

        local batch_file="$TEMP_DIR/batch_$batch_id.txt"
        touch "$batch_file"

        # Call appropriate processing function
        # Note: We use "|| true" to prevent set -e from exiting on non-zero return codes
        # The return code is captured in status for fallback handling
        local tx_count
        if [[ "$USE_TRACE_FILTER" == "true" ]]; then
            local status=0
            while true; do
                if [[ "$TRACE_METHOD" == "trace_filter" ]]; then
                    tx_count=$(fetch_transactions_trace_filter "$rpc_url" "$batch_start" "$batch_end" "$target_contract" "$batch_file") || status=$?
                    if [[ $status -eq 2 ]]; then
                        TRACE_METHOD="debug_trace_block"
                        echo "[TRACE] Falling back to debug_traceBlockByNumber (slower but widely supported)" >&2
                        status=0
                        continue
                    fi
                elif [[ "$TRACE_METHOD" == "debug_trace_block" ]]; then
                    tx_count=$(fetch_transactions_debug_trace_block "$rpc_url" "$batch_start" "$batch_end" "$target_contract" "$batch_file") || status=$?
                    if [[ $status -eq 2 ]]; then
                        TRACE_METHOD="debug_trace_tx"
                        echo "[TRACE] Falling back to debug_traceTransaction (slowest, per-transaction tracing)" >&2
                        status=0
                        continue
                    fi
                else
                    tx_count=$(fetch_transactions_debug_trace_tx "$rpc_url" "$batch_start" "$batch_end" "$target_contract" "$batch_file") || status=$?
                    if [[ $status -eq 2 ]]; then
                        echo "[WARN] No trace APIs supported by this RPC - falling back to direct calls only" >&2
                        echo "[WARN] Internal/nested calls to target contract will NOT be detected" >&2
                        echo "[WARN] Consider using an RPC with debug/trace API support for complete coverage" >&2
                        TRACE_METHOD=""
                        tx_count=$(process_batch "$rpc_url" "$batch_start" "$batch_end" "$target_contract" "$batch_id" "$MAX_CONCURRENT")
                    fi
                fi
                break
            done
        else
            tx_count=$(process_batch "$rpc_url" "$batch_start" "$batch_end" "$target_contract" "$batch_id" "$MAX_CONCURRENT")
        fi
        tx_count=${tx_count:-0}

        # Collect results from this batch
        if [[ -f "$batch_file" && -s "$batch_file" ]]; then
            cat "$batch_file" >> "$all_transactions_file"
            total_transactions_found=$((total_transactions_found + tx_count))
        fi

        total_blocks_processed=$((total_blocks_processed + batch_end - batch_start + 1))
        batch_id=$((batch_id + 1))
    done

    # Calculate timing
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - START_TIME))

    echo "" >&2
    echo "=== DISCOVERY COMPLETE ===" >&2

    # Report which trace method was used
    if [[ "$USE_TRACE_FILTER" == "true" ]]; then
        if [[ -n "$TRACE_METHOD" ]]; then
            case "$TRACE_METHOD" in
                "trace_filter")
                    echo "[INFO] Detection method: trace_filter (fastest)" >&2
                    ;;
                "debug_trace_block")
                    echo "[INFO] Detection method: debug_traceBlockByNumber" >&2
                    ;;
                "debug_trace_tx")
                    echo "[INFO] Detection method: debug_traceTransaction (slowest)" >&2
                    ;;
            esac
            echo "[INFO] Internal calls: ENABLED" >&2
        else
            echo "[WARN] Detection method: direct calls only (no trace API available)" >&2
            echo "[WARN] Internal calls: DISABLED" >&2
        fi
    else
        echo "[INFO] Detection method: direct calls only" >&2
    fi

    echo "" >&2
    echo "Completed in ${duration}s" >&2
    echo "Processed $total_blocks_processed blocks, found $total_transactions_found transactions" >&2

    if [[ $duration -gt 0 ]]; then
        local blocks_per_sec=$((total_blocks_processed / duration))
        local tx_per_sec=$((total_transactions_found / duration))
        echo "Average: $blocks_per_sec blocks/sec, $tx_per_sec transactions/sec" >&2
    fi

    # Display RPC call statistics
    local block_fetch_count
    local detailed_block_count
    local trace_filter_count
    local debug_trace_block_count
    local debug_trace_tx_count
    local tx_fetch_count
    local receipt_fetch_count
    block_fetch_count=$(count_rpc_calls "block_fetch")
    detailed_block_count=$(count_rpc_calls "detailed_block")
    trace_filter_count=$(count_rpc_calls "trace_filter")
    debug_trace_block_count=$(count_rpc_calls "debug_trace_block")
    debug_trace_tx_count=$(count_rpc_calls "debug_trace_tx")
    tx_fetch_count=$(count_rpc_calls "tx_fetch")
    receipt_fetch_count=$(count_rpc_calls "receipt_fetch")

    local total_rpc_calls=$((block_fetch_count + detailed_block_count + trace_filter_count + debug_trace_block_count + debug_trace_tx_count + tx_fetch_count + receipt_fetch_count))

    echo "" >&2
    echo "=== RPC CALL STATISTICS ===" >&2
    echo "Total RPC calls: $total_rpc_calls" >&2
    echo "  - Block fetches: $block_fetch_count" >&2
    if [[ $trace_filter_count -gt 0 ]]; then
        echo "  - trace_filter calls: $trace_filter_count" >&2
    fi
    if [[ $debug_trace_block_count -gt 0 ]]; then
        echo "  - debug_traceBlockByNumber calls: $debug_trace_block_count" >&2
    fi
    if [[ $debug_trace_tx_count -gt 0 ]]; then
        echo "  - debug_traceTransaction calls: $debug_trace_tx_count" >&2
    fi
    if [[ $tx_fetch_count -gt 0 ]]; then
        echo "  - Transaction fetches (eth_getTransactionByHash): $tx_fetch_count" >&2
    fi
    if [[ $receipt_fetch_count -gt 0 ]]; then
        echo "  - Receipt fetches (status checks): $receipt_fetch_count" >&2
    fi
    if [[ $detailed_block_count -gt 0 ]]; then
        echo "  - Detailed block fetches: $detailed_block_count" >&2
    fi
    if [[ $duration -gt 0 && $total_rpc_calls -gt 0 ]]; then
        local rpc_per_sec=$((total_rpc_calls / duration))
        echo "Average: $rpc_per_sec RPC calls/sec" >&2
    fi
    echo "===========================" >&2

    # Output results
    echo "TRANSACTION_DATA:START"
    echo -n "TRANSACTION_DATA:"
    format_transactions "$OUTPUT_FORMAT" "$all_transactions_file"
    echo -n "TRANSACTION_DATA:END"

    # Output formatted block summaries if detailed blocks is enabled
    if [[ "$DETAILED_BLOCKS" = true ]]; then
        echo "BLOCK_SUMMARY_FORMATTED:START"

        # Count triggered transactions per block by parsing the transactions file
        declare -A triggered_per_block

        if [[ -f "$all_transactions_file" && -s "$all_transactions_file" ]]; then
            while IFS='|' read -r hash from to value data block_num rest; do
                # Extract block number from transaction line (format: hash|from|to|value|data|block_number|...)
                if [[ -n "$block_num" ]]; then
                    triggered_per_block[$block_num]=$((${triggered_per_block[$block_num]:-0} + 1))
                fi
            done < "$all_transactions_file"
        fi

        # Get total tx count for each block and format output
        for ((block = start_block; block <= end_block; block++)); do
            local block_hex
            block_hex=$(printf "0x%x" "$block")
            echo "1" >> "$RPC_COUNTER_DIR/detailed_block.count"
            local total_tx_count
            total_tx_count=$(curl -s -X POST "$rpc_url" \
                -H "Content-Type: application/json" \
                -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"$block_hex\", false],\"id\":1}" \
                | jq -r '.result.transactions | length')

            if [[ -z "$total_tx_count" || "$total_tx_count" == "null" ]]; then
                total_tx_count=0
            fi

            local triggered_count=${triggered_per_block[$block]:-0}
            local not_triggered=$((total_tx_count - triggered_count))

            # Format output line
            if [[ $triggered_count -gt 0 ]]; then
                echo "=== BLOCK $block SUMMARY | Triggered: $triggered_count | Not Triggered: $not_triggered | Total: $total_tx_count ==="
            else
                echo "=== BLOCK $block | Total TXs: $total_tx_count ==="
            fi
        done

        echo "BLOCK_SUMMARY_FORMATTED:END"
    fi
}

# Run main function
main "$@"
