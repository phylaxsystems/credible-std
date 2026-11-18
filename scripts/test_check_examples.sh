#!/usr/bin/env bash
# Exercise discovery and guards without compiling Solidity. Requires bash, git, jq.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture"/{scripts,bin,examples/{assertions-book,micro-patterns,new_demo,vault_demo}}
cp "$root/scripts/check_examples.sh" "$fixture/scripts/"
git -C "$fixture" init -q

# Model tool boundaries: an invalid configuration must fail before tests/builds.
cat > "$fixture/bin/forge" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
directory="examples/$FOUNDRY_PROFILE"
[[ "$FOUNDRY_PROFILE" != vault-demo ]] || directory=examples/vault_demo
case "$1" in
  config)
    jq -n --arg src "${FOUNDRY_SRC:-$directory/src}" --arg test "${FOUNDRY_TEST:-$directory/test}" \
      '{src: $src, test: $test}'
    ;;
  fmt) ;;
  build) printf '%s\n' "$@" > "$BUILD_LOG" ;;
  *) exit 99 ;;
esac
EOF
cat > "$fixture/bin/pcl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "$FOUNDRY_PROFILE" >> "$PCL_LOG"
printf '%s\n' '<testcase name="fixture" />' 'Assertion gas cost: 1'
EOF
chmod +x "$fixture/bin/forge" "$fixture/bin/pcl"
export PATH="$fixture/bin:$PATH"
export BUILD_LOG="$fixture/build.log" PCL_LOG="$fixture/pcl.log"
unset FOUNDRY_SRC FOUNDRY_TEST
check="$fixture/scripts/check_examples.sh"

expect_rejection() {
  local diagnostic="$1"
  shift
  rm -f "$BUILD_LOG" "$PCL_LOG"
  if "$@" > "$fixture/output" 2>&1; then
    echo "Expected rejection: $*" >&2
    exit 1
  fi
  grep -Fq "$diagnostic" "$fixture/output"
  [[ ! -e "$BUILD_LOG" && ! -e "$PCL_LOG" ]]
}

"$check" --matrix | jq -e \
  '.profile == ["assertions-book", "micro-patterns", "new_demo", "vault-demo"]' >/dev/null
"$check" new_demo vault-demo >/dev/null
[[ "$(cat "$PCL_LOG")" == $'new_demo\nvault-demo' ]]
expect_rejection 'Unknown example profile' "$check" new-demo
expect_rejection 'expected src under' env FOUNDRY_SRC=src "$check" micro-patterns
expect_rejection 'test at examples/micro-patterns/test' \
  env FOUNDRY_TEST=examples/kyber/test "$check" micro-patterns

# A build-only profile must include both assertions and their teaching mocks.
"$check" assertions-book
[[ "$(cat "$BUILD_LOG")" == $'build\nexamples/assertions-book/assertions/src\nexamples/assertions-book/src' ]]

# Match Foundry's recursive test discovery, including below a hidden directory.
mkdir -p "$fixture/examples/assertions-book/test/.nested"
touch "$fixture/examples/assertions-book/test/.nested/Discovery.t.sol"
expect_rejection 'now has tests; remove its build-only classification' "$check" assertions-book
echo 'Example check regressions passed'
