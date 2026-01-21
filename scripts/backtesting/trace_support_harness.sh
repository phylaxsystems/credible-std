#!/bin/bash

# Trace Support Harness
# Checks which trace APIs are supported by an RPC endpoint.

set -eo pipefail

RPC_URL=""
BLOCK_NUMBER=""
TARGET_CONTRACT=""

usage() {
    printf '%s\n' \
        "Usage: $0 --rpc-url URL --block NUMBER [--target-contract ADDRESS]" \
        "" \
        "Checks trace API support on a given RPC." \
        "" \
        "Options:" \
        "    --rpc-url URL                  RPC endpoint URL (required)" \
        "    --block NUMBER                 Block number to probe (required)" \
        "    --target-contract ADDRESS      Contract address for trace_filter test (optional)" \
        "    -h, --help                     Show this help message" \
        "" \
        "Example:" \
        "    $0 --rpc-url https://your.rpc --block 23717632 --target-contract 0xBA12222222228d8Ba445958a75a0704d566BF2C8"
}

check_dependencies() {
    local missing=()
    command -v curl >/dev/null 2>&1 || missing+=("curl")
    command -v jq >/dev/null 2>&1 || missing+=("jq")

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Error: Missing required tools: ${missing[*]}" >&2
        exit 1
    fi
}

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

# Parse args
while [[ $# -gt 0 ]]; do
    case $1 in
        --rpc-url)
            RPC_URL="$2"
            shift 2
            ;;
        --block)
            BLOCK_NUMBER="$2"
            shift 2
            ;;
        --target-contract)
            TARGET_CONTRACT="$2"
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

if [[ -z "$RPC_URL" || -z "$BLOCK_NUMBER" ]]; then
    echo "Error: --rpc-url and --block are required" >&2
    usage
    exit 1
fi

if ! [[ "$BLOCK_NUMBER" =~ ^[0-9]+$ ]]; then
    echo "Error: Block number must be a positive integer" >&2
    exit 1
fi

check_dependencies

BLOCK_HEX=$(printf "0x%x" "$BLOCK_NUMBER")

printf "Trace support check for block %s\n" "$BLOCK_NUMBER"

# trace_filter (requires target)
if [[ -n "$TARGET_CONTRACT" ]]; then
    TRACE_FILTER_REQ=$(jq -n \
        --arg block_hex "$BLOCK_HEX" \
        --arg target "$TARGET_CONTRACT" \
        '{"jsonrpc":"2.0","method":"trace_filter","params":[{"fromBlock":$block_hex,"toBlock":$block_hex,"toAddress":[$target]}],"id":1}')

    TRACE_FILTER_RESP=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "$TRACE_FILTER_REQ" \
        --max-time 30 \
        "$RPC_URL")

    if echo "$TRACE_FILTER_RESP" | jq -e '.error' >/dev/null 2>&1; then
        if is_method_unsupported "$TRACE_FILTER_RESP"; then
            echo "trace_filter: unsupported"
        else
            echo "trace_filter: error (see response for details)"
        fi
    else
        echo "trace_filter: supported"
    fi
else
    echo "trace_filter: skipped (no --target-contract provided)"
fi

# debug_traceBlockByNumber
TRACE_BLOCK_REQ=$(jq -n \
    --arg block_hex "$BLOCK_HEX" \
    '{"jsonrpc":"2.0","method":"debug_traceBlockByNumber","params":[$block_hex,{"tracer":"callTracer"}],"id":1}')

TRACE_BLOCK_RESP=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    -d "$TRACE_BLOCK_REQ" \
    --max-time 30 \
    "$RPC_URL")

if echo "$TRACE_BLOCK_RESP" | jq -e '.error' >/dev/null 2>&1; then
    if is_method_unsupported "$TRACE_BLOCK_RESP"; then
        echo "debug_traceBlockByNumber: unsupported"
    else
        echo "debug_traceBlockByNumber: error (see response for details)"
    fi
else
    echo "debug_traceBlockByNumber: supported"
fi

# debug_traceTransaction (needs a tx hash)
TX_HASH=""
for ((i=0; i<5; i++)); do
    local_block=$((BLOCK_NUMBER - i))
    if [[ $local_block -lt 0 ]]; then
        break
    fi
    local_block_hex=$(printf "0x%x" "$local_block")
    BLOCK_REQ=$(jq -n \
        --arg block_hex "$local_block_hex" \
        '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":[$block_hex,false],"id":1}')
    BLOCK_RESP=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "$BLOCK_REQ" \
        --max-time 30 \
        "$RPC_URL")
    TX_HASH=$(echo "$BLOCK_RESP" | jq -r '.result.transactions[0] // empty')
    if [[ -n "$TX_HASH" ]]; then
        break
    fi
    TX_HASH=""
done

if [[ -z "$TX_HASH" ]]; then
    echo "debug_traceTransaction: skipped (no tx hash found in recent blocks)"
    exit 0
fi

TRACE_TX_REQ=$(jq -n \
    --arg tx_hash "$TX_HASH" \
    '{"jsonrpc":"2.0","method":"debug_traceTransaction","params":[$tx_hash,{"tracer":"callTracer"}],"id":1}')

TRACE_TX_RESP=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    -d "$TRACE_TX_REQ" \
    --max-time 30 \
    "$RPC_URL")

if echo "$TRACE_TX_RESP" | jq -e '.error' >/dev/null 2>&1; then
    if is_method_unsupported "$TRACE_TX_RESP"; then
        echo "debug_traceTransaction: unsupported"
    else
        echo "debug_traceTransaction: error (see response for details)"
    fi
else
    echo "debug_traceTransaction: supported"
fi
