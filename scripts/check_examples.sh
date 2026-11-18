#!/usr/bin/env bash
# Run from any directory. Requires Foundry, PCL 1.6.0, and jq.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

profiles=()
for directory in examples/*/; do
  profile="${directory#examples/}"
  profile="${profile%/}"
  profiles+=("${profile//_/-}")
done

if [[ "${1:-}" == --matrix ]]; then
  printf '%s\n' "${profiles[@]}" | jq -Rsc '{profile: split("\n")[:-1]}'
  exit 0
fi

if (( $# > 0 )); then
  for requested in "$@"; do
    if [[ " ${profiles[*]} " != *" ${requested} "* ]]; then
      echo "Unknown example profile: ${requested}" >&2
      exit 1
    fi
  done
  profiles=("$@")
fi

report="$(mktemp)"
trap 'rm -f "$report"' EXIT
export RUST_MIN_STACK="${RUST_MIN_STACK:-16777216}"
for profile in "${profiles[@]}"; do
  export FOUNDRY_PROFILE="$profile"
  directory="examples/${profile}"
  [[ "$profile" != vault-demo ]] || directory=examples/vault_demo
  # A misspelled/missing profile must not silently fall back to the root suite.
  forge config --json | jq -e --arg directory "$directory" \
    '.src | startswith($directory + "/")' >/dev/null
  forge fmt --check "$directory"
  if [[ "$profile" == assertions-book ]]; then
    # Docs snippets currently have no test suite; compile them explicitly.
    forge build
    continue
  fi
  if ! pcl test -vv --junit > "$report"; then
    cat "$report"
    exit 1
  fi
  testcase_count=$(grep -c '<testcase ' "$report" || true)
  assertion_count=$(grep -c 'Assertion gas cost:' "$report" || true)
  if [[ "$testcase_count" -eq 0 ]]; then
    echo "No executed testcases for ${profile}" >&2
    exit 1
  fi
  case "$profile" in
    cap|lighter|royco|symbiotic)
      # These suites currently verify quarantine/deployment behavior only.
      # Passing them is not evidence of runtime assertion coverage.
      echo "${profile}: ${testcase_count} tests (quarantine/deployment checks)"
      ;;
    *)
      if [[ "$assertion_count" -eq 0 ]]; then
        echo "No runtime assertion execution evidence for ${profile}" >&2
        exit 1
      fi
      echo "${profile}: ${testcase_count} tests, ${assertion_count} assertion executions"
      ;;
  esac
done
