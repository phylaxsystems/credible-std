#!/usr/bin/env bash
set -euo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/script/test-credible-upgrades.sh"

REGISTRY_DEPLOY_COMMAND='cd "$REPO_ROOT" && FOUNDRY_PROFILE=credible-block forge create examples/credible-block/src/CredibleRegistry.sol:CredibleRegistry --rpc-url "$RPC_URL" --private-key "$ADMIN_KEY" --broadcast --json --constructor-args "$MARKER_ADDRESS" | jq -r ".deployedTo"'
TARGET_DEPLOY_COMMAND='cd "$REPO_ROOT" && FOUNDRY_PROFILE=credible-block forge create examples/credible-block/src/GuardedName.sol:GuardedName --rpc-url "$RPC_URL" --private-key "$ADMIN_KEY" --broadcast --json --constructor-args "$REGISTRY_ADDRESS" "$EXPECTED_THRESHOLD" | jq -r ".deployedTo"'

"$SCRIPT" \
    --registry-deploy-command "$REGISTRY_DEPLOY_COMMAND" \
    --target-deploy-command "$TARGET_DEPLOY_COMMAND" \
    --guarded-call "setName(string)" \
    --guarded-call-arg "hello world" \
    --state-read-call "name()(string)" \
    --state-before '""' \
    --state-after '"hello world"' \
    --rpc-port "${RPC_PORT:-18545}"
