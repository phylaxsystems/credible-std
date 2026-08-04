#!/usr/bin/env bash
set -euo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/script/test-credible-upgrades.sh"
PASS=0

expect_ok() {
    local expected="$1"; shift
    local output
    output=$("$SCRIPT" --validate-only "$@")
    [[ "$output" == *"$expected"* ]] || {
        echo "FAIL: expected '$expected', got '$output'" >&2; exit 1;
    }
    PASS=$((PASS + 1))
}

expect_fail() {
    local expected="$1"; shift
    local output
    if output=$("$SCRIPT" --validate-only "$@" 2>&1); then
        echo "FAIL: command unexpectedly succeeded: $*" >&2; exit 1
    fi
    [[ "$output" == *"$expected"* ]] || {
        echo "FAIL: expected '$expected', got '$output'" >&2; exit 1;
    }
    PASS=$((PASS + 1))
}

expect_ok "mode=fixture"
expect_ok "mode=target" \
    --target-address 0x1111111111111111111111111111111111111111 \
    --registry-address 0x2222222222222222222222222222222222222222 \
    --guarded-call "bump()" --state-read-call "count()(uint256)" \
    --state-before 0 --state-after 1 --expected-threshold 75
expect_ok "mode=target" \
    --target-address 0x1111111111111111111111111111111111111111 \
    --registry-address 0x2222222222222222222222222222222222222222 \
    --guarded-call "setName(string)" --guarded-call-arg "hello world" \
    --state-read-call "name()(string)" \
    --state-before '"old value"' --state-after '"hello world"'
expect_fail "unknown argument: --wat" --wat
expect_fail "target mode requires --guarded-call" \
    --target-address 0x1111111111111111111111111111111111111111 \
    --registry-address 0x2222222222222222222222222222222222222222
expect_fail "provide only one of --target-address and --target-deploy-command" \
    --target-address 0x1111111111111111111111111111111111111111 \
    --target-deploy-command "echo 0x1111111111111111111111111111111111111111"
expect_fail "--expected-threshold must be a positive integer" --expected-threshold 0
expect_fail "target-specific options require" --guarded-call "bump()"

echo "$PASS argument parsing/failure-message tests passed"
