#!/bin/bash

show_help() {
    cat << EOF
Transaction Fetcher - Fetches blockchain transactions for backtesting

Usage: $0 --rpc-url <URL> --target-contract <ADDRESS> --start-block <NUMBER> --end-block <NUMBER> [OPTIONS]

Required arguments:
    --rpc-url <URL>              RPC endpoint URL
    --target-contract <ADDRESS>  Contract address to filter transactions for
    --start-block <NUMBER>       Starting block number
    --end-block <NUMBER>         Ending block number

Optional arguments:
    --output-format <FORMAT>     Output format (simple, json) [default: simple]
    --batch-size <SIZE>          Batch size for parallel processing [default: 10]
    --max-concurrent <COUNT>     Maximum concurrent requests [default: 5]
    --help                       Show this help message

Examples:
    $0 --rpc-url http://localhost:8545 --target-contract 0x123... --start-block 1000 --end-block 2000
    $0 --rpc-url http://localhost:8545 --target-contract 0x123... --start-block 1000 --end-block 2000 --output-format json --batch-size 20 --max-concurrent 10
EOF
}

RPC_URL=""
TARGET_CONTRACT=""
START_BLOCK=""
END_BLOCK=""
OUTPUT_FORMAT="simple"
BATCH_SIZE=10
MAX_CONCURRENT=5

while [[ $# -gt 0 ]]; do
    case $1 in
        --rpc-url)
            RPC_URL="$2"
            shift 2
            ;;
        --target-contract)
            TARGET_CONTRACT="$2"
            shift 2
            ;;
        --start-block)
            START_BLOCK="$2"
            shift 2
            ;;
        --end-block)
            END_BLOCK="$2"
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
        --help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            show_help
            exit 1
            ;;
    esac
done

if [[ -z "$RPC_URL" || -z "$TARGET_CONTRACT" || -z "$START_BLOCK" || -z "$END_BLOCK" ]]; then
    echo "Error: Missing required arguments" >&2
    show_help
    exit 1
fi

if ! [[ "$START_BLOCK" =~ ^[0-9]+$ ]] || ! [[ "$END_BLOCK" =~ ^[0-9]+$ ]]; then
    echo "Error: Block numbers must be numeric" >&2
    exit 1
fi

if ! [[ "$BATCH_SIZE" =~ ^[0-9]+$ ]] || ! [[ "$MAX_CONCURRENT" =~ ^[0-9]+$ ]]; then
    echo "Error: Batch size and max concurrent must be numeric" >&2
    exit 1
fi

TARGET_CONTRACT_LOWER=$(echo "$TARGET_CONTRACT" | tr '[:upper:]' '[:lower:]')

TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

fetch_block_transactions() {
    local block_num=$1
    local block_hex=$(printf "0x%x" "$block_num")
    local output_file="$TEMP_DIR/block_${block_num}.json"
    local debug_file="$TEMP_DIR/debug_${block_num}.json"
    
    local rpc_request=$(cat <<EOF
{
    "jsonrpc": "2.0",
    "method": "eth_getBlockByNumber",
    "params": ["$block_hex", true],
    "id": 1
}
EOF
    )
    
    local response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "$rpc_request" \
        --max-time 30 \
        "$RPC_URL" 2>/dev/null)
    
    if [[ -z "$response" ]]; then
        echo "Error fetching block $block_num: empty response" >&2
        return 1
    fi
    
    # Check if response is valid JSON
    if ! echo "$response" | jq -e . >/dev/null 2>&1; then
        echo "Error: Invalid JSON response for block $block_num" >&2
        echo "Response: $response" > "$debug_file"
        return 1
    fi
    
    # Check for error in response
    local error_msg=$(echo "$response" | jq -r '.error.message // empty')
    if [[ -n "$error_msg" ]]; then
        echo "Error fetching block $block_num: $error_msg" >&2
        return 1
    fi
    
    local block_data=$(echo "$response" | jq -r '.result // empty')
    if [[ -z "$block_data" ]] || [[ "$block_data" == "null" ]]; then
        echo "Error: No result for block $block_num" >&2
        return 1
    fi
    
    local block_number_hex=$(echo "$block_data" | jq -r '.number // empty')
    local block_number_dec=$((16#${block_number_hex#0x}))
    
    # Extract and filter transactions, output as JSON lines
    echo "$block_data" | jq -c --arg target "$TARGET_CONTRACT_LOWER" --arg blocknum "$block_number_dec" '
        .transactions[]? |
        select(.to != null) |
        select((.to | ascii_downcase) == $target) |
        {
            hash: .hash,
            from: .from,
            to: .to,
            value: .value,
            data: .input,
            block_number: $blocknum,
            transaction_index: (if .transactionIndex | startswith("0x") then
                (.transactionIndex[2:] | (explode | map(if . >= 97 then . - 87 elif . >= 65 then . - 55 else . - 48 end) | reduce .[] as $x (0; . * 16 + $x)))
            else
                .transactionIndex | tonumber
            end | tostring),
            gas_price: .gasPrice
        }' 2>/dev/null > "$output_file"
    
    local tx_count=$(wc -l < "$output_file" | tr -d ' ')
    if [[ "$tx_count" -gt 0 ]]; then
        echo "  Block $block_num: found $tx_count transactions" >&2
    fi
    
    return 0
}

START_TIME=$(date +%s)
echo "Starting optimized fetch: blocks $START_BLOCK to $END_BLOCK (batch size: $BATCH_SIZE, max concurrent: $MAX_CONCURRENT)" >&2

TOTAL_BLOCKS_PROCESSED=0
TOTAL_TRANSACTIONS_FOUND=0

ALL_TRANSACTIONS_FILE="$TEMP_DIR/all_transactions.json"
echo -n "" > "$ALL_TRANSACTIONS_FILE"

for (( batch_start = START_BLOCK; batch_start <= END_BLOCK; batch_start += BATCH_SIZE )); do
    batch_end=$((batch_start + BATCH_SIZE - 1))
    if [[ $batch_end -gt $END_BLOCK ]]; then
        batch_end=$END_BLOCK
    fi
    
    echo "Processing batch: blocks $batch_start to $batch_end" >&2
    
    pids=()
    for (( block_num = batch_start; block_num <= batch_end; block_num++ )); do
        while [[ ${#pids[@]} -ge $MAX_CONCURRENT ]]; do
            for i in "${!pids[@]}"; do
                if ! kill -0 "${pids[$i]}" 2>/dev/null; then
                    unset 'pids[$i]'
                fi
            done
            pids=("${pids[@]}") # Reindex array
            if [[ ${#pids[@]} -ge $MAX_CONCURRENT ]]; then
                sleep 0.1
            fi
        done
        
        fetch_block_transactions "$block_num" &
        pids+=("$!")
        TOTAL_BLOCKS_PROCESSED=$((TOTAL_BLOCKS_PROCESSED + 1))
    done
    
    wait
    
    for (( block_num = batch_start; block_num <= batch_end; block_num++ )); do
        block_file="$TEMP_DIR/block_${block_num}.json"
        if [[ -f "$block_file" && -s "$block_file" ]]; then
            cat "$block_file" >> "$ALL_TRANSACTIONS_FILE"
            tx_count=$(wc -l < "$block_file" | tr -d ' ')
            TOTAL_TRANSACTIONS_FOUND=$((TOTAL_TRANSACTIONS_FOUND + tx_count))
        fi
    done
done

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo "Optimized fetch completed in ${DURATION}s" >&2
echo "Processed $TOTAL_BLOCKS_PROCESSED blocks, found $TOTAL_TRANSACTIONS_FOUND transactions" >&2

if [[ $DURATION -gt 0 ]]; then
    BLOCKS_PER_SEC=$(echo "scale=2; $TOTAL_BLOCKS_PROCESSED / $DURATION" | bc)
    TX_PER_SEC=$(echo "scale=2; $TOTAL_TRANSACTIONS_FOUND / $DURATION" | bc)
    echo "Average: $BLOCKS_PER_SEC blocks/sec, $TX_PER_SEC transactions/sec" >&2
fi

echo "TRANSACTION_DATA:START"

if [[ "$OUTPUT_FORMAT" == "json" ]]; then
    if [[ -s "$ALL_TRANSACTIONS_FILE" ]]; then
        echo -n "TRANSACTION_DATA:["
        first=true
        while IFS= read -r line; do
            if [[ -n "$line" ]] && echo "$line" | jq -e . >/dev/null 2>&1; then
                if [[ "$first" == "true" ]]; then
                    echo -n "$line"
                    first=false
                else
                    echo -n ",$line"
                fi
            fi
        done < "$ALL_TRANSACTIONS_FILE"
        echo -n "]"
    else
        echo -n "TRANSACTION_DATA:[]"
    fi
else
    if [[ -s "$ALL_TRANSACTIONS_FILE" ]]; then
        echo -n "TRANSACTION_DATA:$TOTAL_TRANSACTIONS_FOUND"
        while IFS= read -r line; do
            if [[ -n "$line" ]] && echo "$line" | jq -e . >/dev/null 2>&1; then
                tx_hash=$(echo "$line" | jq -r '.hash // ""')
                tx_from=$(echo "$line" | jq -r '.from // ""')
                tx_to=$(echo "$line" | jq -r '.to // ""')
                tx_value=$(echo "$line" | jq -r '.value // ""')
                tx_data=$(echo "$line" | jq -r '.data // ""')
                tx_block=$(echo "$line" | jq -r '.block_number // ""')
                tx_index=$(echo "$line" | jq -r '.transaction_index // ""')
                tx_gas_price=$(echo "$line" | jq -r '.gas_price // ""')
                
                if [[ -n "$tx_hash" ]]; then
                    echo -n "|$tx_hash|$tx_from|$tx_to|$tx_value|$tx_data|$tx_block|$tx_index|$tx_gas_price"
                fi
            fi
        done < "$ALL_TRANSACTIONS_FILE"
    else
        echo -n "TRANSACTION_DATA:0"
    fi
fi

echo -n "TRANSACTION_DATA:END"