#!/usr/bin/env bash
#
# Integration test for the Credible Layer block guard against a live anvil node.
#
# Unlike the forge unit tests (which fake block state with vm.roll/vm.prank), this drives a real
# node so we can exercise the one thing that only matters on a real chain: whether a builder's
# "credible block marker" tx and a guarded tx land in the SAME block (a bundle).
#
# It seeds anvil with:
#   - a CredibleRegistry (examples/credible-block/src/CredibleRegistry.sol) whose admin is an EOA we
#     control, so we can whitelist a builder instantly (production gates this behind a timelock),
#   - a whitelisted "builder" account we control,
#   - a GuardedCounter (a concrete CredibleBlockGuard) standing in for an upgraded credible contract.
#
# Then it verifies three cases:
#   1. Credible block  — bundle [marker tx, guarded tx] into one block; both must succeed.
#   2. Non-credible    — send only the guarded tx (no marker); it must revert (NonCredibleBlock).
#   3. Fail-open       — after the builder stops marking for > failOpenBlockThreshold blocks, the
#                        guarded tx must start passing again (and must still revert at the boundary).
#
# Usage:  ./examples/credible-block/script/test-credible-upgrades.sh   (run from the repo root)
# Requires: anvil, cast, forge, jq on PATH.

set -euo pipefail

# --------------------------------------------------------------------------------------------------
# Config
# --------------------------------------------------------------------------------------------------
RPC_PORT="${RPC_PORT:-8545}"
RPC_URL="http://127.0.0.1:${RPC_PORT}"
FAIL_OPEN_THRESHOLD="${FAIL_OPEN_THRESHOLD:-10}" # kept small so the fail-open case runs quickly

export FOUNDRY_PROFILE=credible-block

# Deterministic anvil dev accounts (default mnemonic).
ADMIN_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80   # account 0 (deployer/admin)
BUILDER_KEY=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d # account 1 (credible builder)
USER_KEY=0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a   # account 2 (unprivileged caller)
BUILDER_ADDR=$(cast wallet address "$BUILDER_KEY")
USER_ADDR=$(cast wallet address "$USER_KEY")

GAS_LIMIT=2000000 # explicit so `cast send` skips eth_estimateGas (which would fail on reverting txs)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; BLUE=$'\033[0;34m'; BOLD=$'\033[1m'; NC=$'\033[0m'
PASS_COUNT=0; FAIL_COUNT=0
ANVIL_PID=""

cleanup() { [[ -n "$ANVIL_PID" ]] && kill "$ANVIL_PID" 2>/dev/null || true; }
trap cleanup EXIT

info()    { echo "${BLUE}==>${NC} $*"; }
section() { echo; echo "${BOLD}$*${NC}"; }

# check <description> <actual> <expected>
check() {
    local desc="$1" actual="$2" expected="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "  ${GREEN}PASS${NC} $desc"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  ${RED}FAIL${NC} $desc (expected '$expected', got '$actual')"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

rpc()            { cast rpc --rpc-url "$RPC_URL" "$@" >/dev/null; }
mine_blocks()    { rpc anvil_mine "$(cast to-hex "$1")"; }              # mine N blocks instantly
receipt_status() { cast receipt --rpc-url "$RPC_URL" --async "$1" --json 2>/dev/null | jq -r '.status'; }
receipt_block()  { cast to-dec "$(cast receipt --rpc-url "$RPC_URL" --async "$1" --json | jq -r '.blockNumber')"; }
counter()        { cast call --rpc-url "$RPC_URL" "$GUARD" "count()(uint256)"; }

# Submit a tx WITHOUT waiting for it to be mined; echoes the tx hash.
send_async() {
    local key="$1"; shift
    cast send --rpc-url "$RPC_URL" --private-key "$key" --gas-limit "$GAS_LIMIT" --async "$@"
}

# Reset chain state to the post-deployment snapshot and re-arm the snapshot for the next case.
reset_state() {
    rpc evm_revert "$SNAPSHOT"
    SNAPSHOT=$(cast rpc --rpc-url "$RPC_URL" evm_snapshot | tr -d '"')
    rpc evm_setAutomine false # manual mining for deterministic block composition
}

# --------------------------------------------------------------------------------------------------
# Boot anvil + deploy
# --------------------------------------------------------------------------------------------------
section "Booting anvil (fifo mempool ordering) and deploying contracts"

# fifo ordering guarantees the marker tx (submitted first) is included before the guarded tx when
# both share a block, so the guarded call sees the block already marked credible.
anvil --port "$RPC_PORT" --order fifo --silent &
ANVIL_PID=$!

for _ in $(seq 1 50); do
    cast block-number --rpc-url "$RPC_URL" >/dev/null 2>&1 && break
    sleep 0.1
done

pushd "$REPO_ROOT" >/dev/null

# Deploy the registry with the builder account we control baked in as its sole marker.
REGISTRY=$(forge create examples/credible-block/src/CredibleRegistry.sol:CredibleRegistry \
    --rpc-url "$RPC_URL" --private-key "$ADMIN_KEY" --broadcast --json \
    --constructor-args "$BUILDER_ADDR" | jq -r '.deployedTo')
info "CredibleRegistry:  $REGISTRY (builder=$BUILDER_ADDR)"

GUARD=$(forge create examples/credible-block/src/GuardedCounter.sol:GuardedCounter \
    --rpc-url "$RPC_URL" --private-key "$ADMIN_KEY" --broadcast --json \
    --constructor-args "$REGISTRY" "$FAIL_OPEN_THRESHOLD" | jq -r '.deployedTo')
info "GuardedCounter:    $GUARD (failOpenBlockThreshold=$FAIL_OPEN_THRESHOLD)"

popd >/dev/null

check "registry builder is the account we control" \
    "$(cast call --rpc-url "$RPC_URL" "$REGISTRY" "builder()(address)")" \
    "$BUILDER_ADDR"

SNAPSHOT=$(cast rpc --rpc-url "$RPC_URL" evm_snapshot | tr -d '"')

# --------------------------------------------------------------------------------------------------
# Case 1: credible block — bundle [marker, guarded] into one block; both succeed.
# --------------------------------------------------------------------------------------------------
section "Case 1: credible block (marker + guarded tx bundled in one block)"
reset_state

# The marker must be submitted first (fifo) so it executes before the guarded call in the block.
MARKER_TX=$(send_async "$BUILDER_KEY" "$REGISTRY" "markCurrentBlockCredible()")
GUARDED_TX=$(send_async "$USER_KEY" "$GUARD" "bump()")
rpc evm_mine # seal ONE block containing both queued txs

info "marker tx:  $MARKER_TX"
info "guarded tx: $GUARDED_TX"
check "marker tx succeeded"          "$(receipt_status "$MARKER_TX")"  "0x1"
check "guarded tx succeeded"         "$(receipt_status "$GUARDED_TX")" "0x1"
check "both txs in the same block"   "$(receipt_block "$MARKER_TX")"   "$(receipt_block "$GUARDED_TX")"
check "counter incremented to 1"     "$(counter)"                      "1"

# --------------------------------------------------------------------------------------------------
# Case 2: non-credible block — guarded tx alone must revert.
# --------------------------------------------------------------------------------------------------
section "Case 2: non-credible block (guarded tx with no marker reverts)"
reset_state

# No marker this block. Static call surfaces the revert reason; the on-chain tx confirms status 0.
# cast can't decode the custom error without the ABI, so we match its 4-byte selector directly.
NON_CREDIBLE_SIG=$(cast sig "NonCredibleBlock()") # 0x95ad9b59
CALL_OUT=$(cast call --rpc-url "$RPC_URL" --from "$USER_ADDR" "$GUARD" "bump()" 2>&1 || true)
if echo "$CALL_OUT" | grep -qi "$NON_CREDIBLE_SIG"; then
    echo "  ${GREEN}PASS${NC} static call reverts with NonCredibleBlock()"; PASS_COUNT=$((PASS_COUNT + 1))
else
    echo "  ${RED}FAIL${NC} static call did not revert with NonCredibleBlock() (got: $CALL_OUT)"; FAIL_COUNT=$((FAIL_COUNT + 1))
fi

GUARDED_TX=$(send_async "$USER_KEY" "$GUARD" "bump()")
rpc evm_mine
check "guarded tx reverted on-chain" "$(receipt_status "$GUARDED_TX")" "0x0"
check "counter still 0"              "$(counter)"                      "0"

# --------------------------------------------------------------------------------------------------
# Case 3: fail-open — after the builder stops marking for > threshold blocks, guarded tx passes.
# --------------------------------------------------------------------------------------------------
section "Case 3: fail-open once no credible block for > failOpenBlockThreshold blocks"
reset_state

THRESHOLD=$(cast call --rpc-url "$RPC_URL" "$GUARD" "failOpenBlockThreshold()(uint256)")
info "failOpenBlockThreshold = $THRESHOLD"

# Mark one block credible so lastCredibleBlock is set to a concrete block M.
MARKER_TX=$(send_async "$BUILDER_KEY" "$REGISTRY" "markCurrentBlockCredible()")
rpc evm_mine
M=$(receipt_block "$MARKER_TX")
info "last credible block M = $M"

# Advance so the NEXT sealed block is M+THRESHOLD (gap == threshold, NOT > threshold => still guarded).
mine_blocks $(( THRESHOLD - 1 ))
BOUNDARY_TX=$(send_async "$USER_KEY" "$GUARD" "bump()")
rpc evm_mine
check "at gap == threshold (block $(receipt_block "$BOUNDARY_TX")), guarded tx still reverts" \
    "$(receipt_status "$BOUNDARY_TX")" "0x0"

# One more block: gap == threshold+1 (> threshold) => fail-open active, guarded tx passes.
OPEN_TX=$(send_async "$USER_KEY" "$GUARD" "bump()")
rpc evm_mine
check "at gap > threshold (block $(receipt_block "$OPEN_TX")), fail-open lets guarded tx pass" \
    "$(receipt_status "$OPEN_TX")" "0x1"
check "counter incremented to 1 via fail-open" "$(counter)" "1"

# --------------------------------------------------------------------------------------------------
# Summary
# --------------------------------------------------------------------------------------------------
section "Summary: ${GREEN}${PASS_COUNT} passed${NC}, ${RED}${FAIL_COUNT} failed${NC}"
[[ "$FAIL_COUNT" -eq 0 ]]
