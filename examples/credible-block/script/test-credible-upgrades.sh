#!/usr/bin/env bash
#
# Live-Anvil integration test for CredibleBlockGuard.
#
# With no target arguments this deploys the GuardedCounter example fixture. For a real upgrade,
# provide --target-address or --target-deploy-command plus the target-specific call/read inputs.

set -euo pipefail

RPC_PORT="${RPC_PORT:-8545}"
FAIL_OPEN_THRESHOLD="${FAIL_OPEN_THRESHOLD:-10}"
ADMIN_KEY="${ADMIN_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"
MARKER_KEY="${MARKER_KEY:-0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d}"
GUARDED_KEY="${GUARDED_KEY:-0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a}"
GAS_LIMIT="${GAS_LIMIT:-2000000}"

TARGET_ADDRESS=""
TARGET_DEPLOY_COMMAND=""
REGISTRY_ADDRESS=""
REGISTRY_DEPLOY_COMMAND=""
GUARDED_CALL=""
GUARDED_CALL_ARGS=()
MARKER_CALL="markCurrentBlockCredible()"
MARKER_CALL_ARGS=()
STATE_READ_CALL=""
STATE_READ_CALL_ARGS=()
STATE_BEFORE=""
STATE_AFTER=""
REGISTRY_READ_CALL="credibleRegistry()(address)"
THRESHOLD_READ_CALL="failOpenBlockThreshold()(uint256)"
CONFIG_ASSERT_COMMAND=""
GUARD_ERROR="NonCredibleBlock()"
VALIDATE_ONLY=false

usage() {
    cat <<'EOF'
Usage:
  test-credible-upgrades.sh                         # GuardedCounter fixture
  test-credible-upgrades.sh [target options]

Target options:
  --target-address ADDRESS                         Existing target on the fresh Anvil chain
  --target-deploy-command COMMAND                  Deploy/upgrade; final stdout line is its address
  --guarded-call SIGNATURE                         e.g. 'setName(string)'
  --guarded-call-arg ARGUMENT                      Repeat for each argument, e.g. 'hello world'
  --state-read-call SIGNATURE                      e.g. 'totalAssets()(uint256)'
  --state-read-call-arg ARGUMENT                   Repeat for each state-read argument
  --state-before VALUE                             Expected state before/after rejected calls
  --state-after VALUE                              Expected state after successful guarded call

Registry/configuration options:
  --registry-address ADDRESS                       Existing registry on the fresh Anvil chain
  --registry-deploy-command COMMAND                Deploy/configure; final stdout line is its address
  --marker-call SIGNATURE                          Default: markCurrentBlockCredible()
  --marker-call-arg ARGUMENT                       Repeat for each marker-call argument
  --expected-threshold BLOCKS                      Default in fixture mode: 10
  --registry-read-call SIGNATURE                   Default: credibleRegistry()(address)
  --threshold-read-call SIGNATURE                  Default: failOpenBlockThreshold()(uint256)
  --config-assert-command COMMAND                  Adapter for targets without public getters
                                                    (replaces both getter checks)
  --guard-error SIGNATURE                          Default: NonCredibleBlock()

Accounts/runtime:
  --marker-private-key KEY                         Marker transaction account
  --guarded-private-key KEY                        Guarded call account
  --admin-private-key KEY                          Fixture/deployment account
  --rpc-port PORT                                  Default: 8545
  --gas-limit GAS                                  Default: 2000000
  --validate-only                                  Parse and validate without starting Anvil
  -h, --help

Commands run via `bash -c` with RPC_URL, REPO_ROOT, ADMIN_KEY, MARKER_KEY, GUARDED_KEY,
MARKER_ADDRESS, GUARDED_ADDRESS, REGISTRY_ADDRESS, TARGET_ADDRESS and EXPECTED_THRESHOLD exported.
Deployment commands must print the deployed address as their final stdout line. A config assertion
command must exit zero only when TARGET_ADDRESS uses REGISTRY_ADDRESS and EXPECTED_THRESHOLD.
EOF
}

die() { echo "ERROR: $*" >&2; exit 2; }
need_value() { [[ $# -ge 2 && -n "$2" ]] || die "$1 requires a value"; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target-address)          need_value "$@"; TARGET_ADDRESS="$2"; shift 2 ;;
        --target-deploy-command)   need_value "$@"; TARGET_DEPLOY_COMMAND="$2"; shift 2 ;;
        --registry-address)        need_value "$@"; REGISTRY_ADDRESS="$2"; shift 2 ;;
        --registry-deploy-command) need_value "$@"; REGISTRY_DEPLOY_COMMAND="$2"; shift 2 ;;
        --guarded-call)            need_value "$@"; GUARDED_CALL="$2"; shift 2 ;;
        --guarded-call-arg)        need_value "$@"; GUARDED_CALL_ARGS+=("$2"); shift 2 ;;
        --marker-call)             need_value "$@"; MARKER_CALL="$2"; shift 2 ;;
        --marker-call-arg)         need_value "$@"; MARKER_CALL_ARGS+=("$2"); shift 2 ;;
        --state-read-call)         need_value "$@"; STATE_READ_CALL="$2"; shift 2 ;;
        --state-read-call-arg)     need_value "$@"; STATE_READ_CALL_ARGS+=("$2"); shift 2 ;;
        --state-before)            need_value "$@"; STATE_BEFORE="$2"; shift 2 ;;
        --state-after)             need_value "$@"; STATE_AFTER="$2"; shift 2 ;;
        --registry-read-call)      need_value "$@"; REGISTRY_READ_CALL="$2"; shift 2 ;;
        --threshold-read-call)     need_value "$@"; THRESHOLD_READ_CALL="$2"; shift 2 ;;
        --config-assert-command)   need_value "$@"; CONFIG_ASSERT_COMMAND="$2"; shift 2 ;;
        --guard-error)             need_value "$@"; GUARD_ERROR="$2"; shift 2 ;;
        --expected-threshold)      need_value "$@"; FAIL_OPEN_THRESHOLD="$2"; shift 2 ;;
        --marker-private-key)      need_value "$@"; MARKER_KEY="$2"; shift 2 ;;
        --guarded-private-key)     need_value "$@"; GUARDED_KEY="$2"; shift 2 ;;
        --admin-private-key)       need_value "$@"; ADMIN_KEY="$2"; shift 2 ;;
        --rpc-port)                need_value "$@"; RPC_PORT="$2"; shift 2 ;;
        --gas-limit)               need_value "$@"; GAS_LIMIT="$2"; shift 2 ;;
        --validate-only)           VALIDATE_ONLY=true; shift ;;
        -h|--help)                 usage; exit 0 ;;
        *)                         die "unknown argument: $1 (use --help)" ;;
    esac
done

[[ "$FAIL_OPEN_THRESHOLD" =~ ^[1-9][0-9]*$ ]] ||
    die "--expected-threshold must be a positive integer"
[[ "$RPC_PORT" =~ ^[0-9]+$ ]] || die "--rpc-port must be an integer"
[[ -z "$TARGET_ADDRESS" || -z "$TARGET_DEPLOY_COMMAND" ]] ||
    die "provide only one of --target-address and --target-deploy-command"
[[ -z "$REGISTRY_ADDRESS" || -z "$REGISTRY_DEPLOY_COMMAND" ]] ||
    die "provide only one of --registry-address and --registry-deploy-command"

CUSTOM_MODE=false
if [[ -n "$TARGET_ADDRESS" || -n "$TARGET_DEPLOY_COMMAND" ]]; then
    CUSTOM_MODE=true
    [[ -n "$GUARDED_CALL" ]] || die "target mode requires --guarded-call"
    [[ -n "$STATE_READ_CALL" ]] || die "target mode requires --state-read-call"
    [[ -n "$STATE_BEFORE" ]] || die "target mode requires --state-before"
    [[ -n "$STATE_AFTER" ]] || die "target mode requires --state-after"
    [[ -n "$REGISTRY_ADDRESS" || -n "$REGISTRY_DEPLOY_COMMAND" ]] ||
        die "target mode requires --registry-address or --registry-deploy-command"
else
    [[ -z "$GUARDED_CALL$STATE_READ_CALL$STATE_BEFORE$STATE_AFTER$REGISTRY_ADDRESS$REGISTRY_DEPLOY_COMMAND$CONFIG_ASSERT_COMMAND" &&
        ${#GUARDED_CALL_ARGS[@]} -eq 0 && ${#STATE_READ_CALL_ARGS[@]} -eq 0 ]] ||
        die "target-specific options require --target-address or --target-deploy-command"
    GUARDED_CALL="bump()"
    STATE_READ_CALL="count()(uint256)"
    STATE_BEFORE="0"
    STATE_AFTER="1"
fi

if $VALIDATE_ONLY; then
    echo "configuration valid (mode=$($CUSTOM_MODE && echo target || echo fixture), threshold=$FAIL_OPEN_THRESHOLD)"
    exit 0
fi

for command in anvil cast forge jq; do
    command -v "$command" >/dev/null || die "required command not found on PATH: $command"
done

RPC_URL="http://127.0.0.1:${RPC_PORT}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
MARKER_ADDRESS=$(cast wallet address "$MARKER_KEY")
GUARDED_ADDRESS=$(cast wallet address "$GUARDED_KEY")
export RPC_URL REPO_ROOT ADMIN_KEY MARKER_KEY GUARDED_KEY MARKER_ADDRESS GUARDED_ADDRESS
export EXPECTED_THRESHOLD="$FAIL_OPEN_THRESHOLD"

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; BLUE=$'\033[0;34m'; BOLD=$'\033[1m'; NC=$'\033[0m'
PASS_COUNT=0; FAIL_COUNT=0; ANVIL_PID=""
cleanup() { [[ -n "$ANVIL_PID" ]] && kill "$ANVIL_PID" 2>/dev/null || true; }
trap cleanup EXIT
info() { echo "${BLUE}==>${NC} $*"; }
section() { echo; echo "${BOLD}$*${NC}"; }
check() {
    local desc="$1" actual="$2" expected="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "  ${GREEN}PASS${NC} $desc"; PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  ${RED}FAIL${NC} $desc (expected '$expected', got '$actual')"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}
rpc() { cast rpc --rpc-url "$RPC_URL" "$@" >/dev/null; }
mine_blocks() { rpc anvil_mine "$(cast to-hex "$1")"; }
receipt_status() { cast receipt --rpc-url "$RPC_URL" --async "$1" --json 2>/dev/null | jq -r '.status'; }
receipt_block() { cast to-dec "$(cast receipt --rpc-url "$RPC_URL" --async "$1" --json | jq -r '.blockNumber')"; }
normalize_cast_value() {
    local value="$1"
    printf '%s' "${value%% \[*}"
}
read_state() {
    local value
    value=$(cast call --rpc-url "$RPC_URL" "$TARGET_ADDRESS" "$STATE_READ_CALL" "${STATE_READ_CALL_ARGS[@]}")
    normalize_cast_value "$value"
}
send_async() {
    local key="$1" address="$2" call="$3"; shift 3
    cast send --rpc-url "$RPC_URL" --private-key "$key" --gas-limit "$GAS_LIMIT" \
        --async "$address" "$call" "$@"
}
reset_state() {
    rpc evm_revert "$SNAPSHOT"
    SNAPSHOT=$(cast rpc --rpc-url "$RPC_URL" evm_snapshot | tr -d '"')
    rpc evm_setAutomine false
}
run_address_command() {
    local description="$1" command_text="$2" output address
    output=$(bash -c "$command_text") || die "$description command failed"
    address=$(printf '%s\n' "$output" | tail -n 1 | tr -d '[:space:]')
    [[ "$address" =~ ^0x[0-9a-fA-F]{40}$ ]] ||
        die "$description command must print a contract address as its final line (got '$address')"
    printf '%s' "$address"
}

section "Booting Anvil (FIFO mempool)"
if cast block-number --rpc-url "$RPC_URL" >/dev/null 2>&1; then
    die "something is already listening on $RPC_URL; set --rpc-port to a free port"
fi
anvil --port "$RPC_PORT" --order fifo --silent &
ANVIL_PID=$!
for _ in $(seq 1 50); do
    kill -0 "$ANVIL_PID" 2>/dev/null || die "Anvil exited before becoming ready"
    cast block-number --rpc-url "$RPC_URL" >/dev/null 2>&1 && break
    sleep 0.1
done
cast block-number --rpc-url "$RPC_URL" >/dev/null 2>&1 ||
    die "Anvil did not become ready on $RPC_URL"

if [[ -n "$REGISTRY_DEPLOY_COMMAND" ]]; then
    REGISTRY_ADDRESS=$(run_address_command "registry deployment/configuration" "$REGISTRY_DEPLOY_COMMAND")
elif [[ -z "$REGISTRY_ADDRESS" ]]; then
    REGISTRY_ADDRESS=$(cd "$REPO_ROOT" && FOUNDRY_PROFILE=credible-block forge create \
        examples/credible-block/src/CredibleRegistry.sol:CredibleRegistry \
        --rpc-url "$RPC_URL" --private-key "$ADMIN_KEY" --broadcast --json \
        --constructor-args "$MARKER_ADDRESS" | jq -r '.deployedTo')
fi
REGISTRY_ADDRESS=$(cast to-check-sum-address "$REGISTRY_ADDRESS" 2>/dev/null) ||
    die "registry address is not a valid address"
export REGISTRY_ADDRESS

if [[ -n "$TARGET_DEPLOY_COMMAND" ]]; then
    TARGET_ADDRESS=$(run_address_command "target deployment/upgrade" "$TARGET_DEPLOY_COMMAND")
elif [[ -z "$TARGET_ADDRESS" ]]; then
    TARGET_ADDRESS=$(cd "$REPO_ROOT" && FOUNDRY_PROFILE=credible-block forge create \
        examples/credible-block/src/GuardedCounter.sol:GuardedCounter \
        --rpc-url "$RPC_URL" --private-key "$ADMIN_KEY" --broadcast --json \
        --constructor-args "$REGISTRY_ADDRESS" "$FAIL_OPEN_THRESHOLD" | jq -r '.deployedTo')
fi
TARGET_ADDRESS=$(cast to-check-sum-address "$TARGET_ADDRESS" 2>/dev/null) ||
    die "target address is not a valid address"
export TARGET_ADDRESS
info "mode: $($CUSTOM_MODE && echo 'real target validation' || echo 'GuardedCounter fixture coverage')"
info "registry: $REGISTRY_ADDRESS; target: $TARGET_ADDRESS"

section "Verifying target configuration"
if [[ -n "$CONFIG_ASSERT_COMMAND" ]]; then
    if bash -c "$CONFIG_ASSERT_COMMAND"; then
        echo "  ${GREEN}PASS${NC} contract-specific configuration assertion"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        die "contract-specific configuration assertion failed"
    fi
else
    CONFIG_FAILURES=$FAIL_COUNT
    check "target uses expected registry" \
        "$(cast call --rpc-url "$RPC_URL" "$TARGET_ADDRESS" "$REGISTRY_READ_CALL")" "$REGISTRY_ADDRESS"
    check "target uses expected fail-open threshold" \
        "$(normalize_cast_value "$(cast call --rpc-url "$RPC_URL" "$TARGET_ADDRESS" "$THRESHOLD_READ_CALL")")" \
        "$FAIL_OPEN_THRESHOLD"
    [[ "$FAIL_COUNT" -eq "$CONFIG_FAILURES" ]] || die "target configuration verification failed"
fi
check "initial target state" "$(read_state)" "$STATE_BEFORE"

SNAPSHOT=$(cast rpc --rpc-url "$RPC_URL" evm_snapshot | tr -d '"')

section "Case 1: marker + guarded call in one manually mined block"
reset_state
MARKER_TX=$(send_async "$MARKER_KEY" "$REGISTRY_ADDRESS" "$MARKER_CALL" "${MARKER_CALL_ARGS[@]}")
GUARDED_TX=$(send_async "$GUARDED_KEY" "$TARGET_ADDRESS" "$GUARDED_CALL" "${GUARDED_CALL_ARGS[@]}")
rpc evm_mine
check "marker transaction succeeded" "$(receipt_status "$MARKER_TX")" "0x1"
check "guarded transaction succeeded" "$(receipt_status "$GUARDED_TX")" "0x1"
check "marker and guarded transaction share a block" \
    "$(receipt_block "$MARKER_TX")" "$(receipt_block "$GUARDED_TX")"
check "guarded action produced expected state" "$(read_state)" "$STATE_AFTER"

section "Case 2: unmarked call while builder window is live"
reset_state
SEED_TX=$(send_async "$MARKER_KEY" "$REGISTRY_ADDRESS" "$MARKER_CALL" "${MARKER_CALL_ARGS[@]}")
rpc evm_mine
GUARDED_TX=$(send_async "$GUARDED_KEY" "$TARGET_ADDRESS" "$GUARDED_CALL" "${GUARDED_CALL_ARGS[@]}")
rpc evm_mine
check "guarded transaction reverted" "$(receipt_status "$GUARDED_TX")" "0x0"
check "rejected call left target state unchanged" "$(read_state)" "$STATE_BEFORE"
ERROR_SELECTOR=$(cast sig "$GUARD_ERROR")
CALL_OUT=$(cast call --rpc-url "$RPC_URL" --from "$GUARDED_ADDRESS" \
    "$TARGET_ADDRESS" "$GUARDED_CALL" "${GUARDED_CALL_ARGS[@]}" 2>&1 || true)
if grep -qi "$ERROR_SELECTOR" <<<"$CALL_OUT"; then
    echo "  ${GREEN}PASS${NC} static call reverted with $GUARD_ERROR"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo "  ${RED}FAIL${NC} expected $GUARD_ERROR ($ERROR_SELECTOR), got: $CALL_OUT"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

section "Case 3: builder inactivity boundary and strict fail-open"
reset_state
MARKER_TX=$(send_async "$MARKER_KEY" "$REGISTRY_ADDRESS" "$MARKER_CALL" "${MARKER_CALL_ARGS[@]}")
rpc evm_mine
M=$(receipt_block "$MARKER_TX")
mine_blocks $((FAIL_OPEN_THRESHOLD - 1))
BOUNDARY_TX=$(send_async "$GUARDED_KEY" "$TARGET_ADDRESS" "$GUARDED_CALL" "${GUARDED_CALL_ARGS[@]}")
rpc evm_mine
check "gap == threshold still reverts" "$(receipt_status "$BOUNDARY_TX")" "0x0"
check "boundary rejection left target state unchanged" "$(read_state)" "$STATE_BEFORE"
OPEN_TX=$(send_async "$GUARDED_KEY" "$TARGET_ADDRESS" "$GUARDED_CALL" "${GUARDED_CALL_ARGS[@]}")
rpc evm_mine
check "gap > threshold succeeds" "$(receipt_status "$OPEN_TX")" "0x1"
check "fail-open call produced expected state" "$(read_state)" "$STATE_AFTER"
info "last credible block=$M, threshold=$FAIL_OPEN_THRESHOLD"

section "Summary: ${GREEN}${PASS_COUNT} passed${NC}, ${RED}${FAIL_COUNT} failed${NC}"
[[ "$FAIL_COUNT" -eq 0 ]]
