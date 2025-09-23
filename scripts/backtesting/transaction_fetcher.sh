#!/bin/bash

# Transaction Fetcher - Bash Implementation
# Fetches blockchain transactions for backtesting
# Replaces the Rust implementation to reduce dependencies

set -eo pipefail

# Default values
OUTPUT_FORMAT="simple"
BATCH_SIZE=10
MAX_CONCURRENT=5
TEMP_DIR=""
START_TIME=""

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

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Fetches blockchain transactions for backtesting

OPTIONS:
    --rpc-url URL              RPC endpoint URL (required)
    --target-contract ADDRESS  Contract address to filter transactions for (required)
    --start-block NUMBER       Starting block number (required)
    --end-block NUMBER         Ending block number (required)
    --output-format FORMAT     Output format: simple or json (default: simple)
    --batch-size SIZE          Batch size for processing (default: 10)
    --max-concurrent COUNT     Maximum concurrent requests (default: 5)
    -h, --help                 Show this help message

EOF
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

# Fetch transactions from a single block
fetch_block_transactions() {
    local rpc_url="$1"
    local block_number="$2"
    local target_contract="$3"
    local output_file="$4"
    
    # Convert block number to hex
    local block_hex=$(printf "0x%x" "$block_number")
    
    # Prepare RPC request
    local rpc_request=$(jq -n \
        --arg method "eth_getBlockByNumber" \
        --arg block_hex "$block_hex" \
        '{
            "jsonrpc": "2.0",
            "method": $method,
            "params": [$block_hex, true],
            "id": 1
        }')
    
    # Make the request
    local response
    if ! response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "$rpc_request" \
        --max-time 30 \
        "$rpc_url"); then
        echo "Error: Failed to fetch block $block_number" >&2
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
    local block_num_decimal=$(hex_to_decimal "$block_num_hex")
    
    # Filter transactions that interact with the target contract
    local target_contract_lower=$(echo "$target_contract" | tr '[:upper:]' '[:lower:]')
    
    # Process each transaction
    while IFS= read -r tx; do
        [[ -z "$tx" ]] && continue
        
        # Check if transaction is sent to the target contract
        local tx_to=$(echo "$tx" | jq -r '.to // empty')
        if [[ -n "$tx_to" ]]; then
            local tx_to_lower=$(echo "$tx_to" | tr '[:upper:]' '[:lower:]')
            if [[ "$tx_to_lower" == "$target_contract_lower" ]]; then
                # Extract transaction data
                local tx_hash=$(echo "$tx" | jq -r '.hash')
                local tx_from=$(echo "$tx" | jq -r '.from')
                local tx_value=$(echo "$tx" | jq -r '.value')
                local tx_input=$(echo "$tx" | jq -r '.input')
                local tx_index_hex=$(echo "$tx" | jq -r '.transactionIndex')
                local tx_gas_price=$(echo "$tx" | jq -r '.gasPrice')
                
                # Convert transaction index to decimal
                local tx_index_decimal=$(hex_to_decimal "$tx_index_hex")
                
                # Output transaction in the format: hash|from|to|value|data|blockNumber|txIndex|gasPrice
                echo "$tx_hash|$tx_from|$tx_to|$tx_value|$tx_input|$block_num_decimal|$tx_index_decimal|$tx_gas_price" >> "$output_file"
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
            fetch_block_transactions "$rpc_url" "$block_num" "$target_contract" "$batch_output" &
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
    
    local tx_count=$(wc -l < "$all_transactions_file" | tr -d ' ')
    
    case "$output_format" in
        "json")
            # Convert to JSON format
            echo "["
            local first=true
            while IFS='|' read -r hash from to value data block_number tx_index gas_price; do
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
                    '{
                        hash: $hash,
                        from: $from,
                        to: $to,
                        value: $value,
                        data: $data,
                        block_number: $block_number,
                        transaction_index: $tx_index,
                        gas_price: $gas_price
                    }' | tr -d '\n'
            done < "$all_transactions_file"
            echo
            echo "]"
            ;;
        *)
            # Simple format: count|hash|from|to|value|data|blockNumber|txIndex|gasPrice|...
            echo -n "$tx_count"
            while IFS='|' read -r hash from to value data block_number tx_index gas_price; do
                echo -n "|$hash|$from|$to|$value|$data|$block_number|$tx_index|$gas_price"
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
    
    echo "Starting optimized fetch: blocks $start_block to $end_block (batch size: $BATCH_SIZE, max concurrent: $MAX_CONCURRENT)"
    
    # Process blocks in batches
    local all_transactions_file="$TEMP_DIR/all_transactions.txt"
    touch "$all_transactions_file"
    
    local total_blocks_processed=0
    local total_transactions_found=0
    local batch_id=0
    
    for ((batch_start=start_block; batch_start<=end_block; batch_start+=BATCH_SIZE)); do
        local batch_end=$((batch_start + BATCH_SIZE - 1))
        if [[ $batch_end -gt $end_block ]]; then
            batch_end=$end_block
        fi
        
        local tx_count=$(process_batch "$rpc_url" "$batch_start" "$batch_end" "$target_contract" "$batch_id" "$MAX_CONCURRENT")
        
        # Ensure tx_count is a valid number
        tx_count=${tx_count:-0}
        
        # Collect results from this batch
        local batch_file="$TEMP_DIR/batch_$batch_id.txt"
        if [[ -f "$batch_file" && -s "$batch_file" ]]; then
            cat "$batch_file" >> "$all_transactions_file"
            total_transactions_found=$((total_transactions_found + tx_count))
        fi
        
        total_blocks_processed=$((total_blocks_processed + batch_end - batch_start + 1))
        ((batch_id++))
    done
    
    # Calculate timing
    local end_time=$(date +%s)
    local duration=$((end_time - START_TIME))
    
    echo "Optimized fetch completed in ${duration}s"
    echo "Processed $total_blocks_processed blocks, found $total_transactions_found transactions"
    
    if [[ $duration -gt 0 ]]; then
        local blocks_per_sec=$((total_blocks_processed / duration))
        local tx_per_sec=$((total_transactions_found / duration))
        echo "Average: $blocks_per_sec blocks/sec, $tx_per_sec transactions/sec"
    fi
    
    # Output results
    echo "TRANSACTION_DATA:START"
    echo -n "TRANSACTION_DATA:"
    format_transactions "$OUTPUT_FORMAT" "$all_transactions_file"
    echo -n "TRANSACTION_DATA:END"
}

# Run main function
main "$@"
