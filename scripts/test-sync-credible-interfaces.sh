#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly SYNC="${SCRIPT_DIR}/sync-credible-interfaces.sh"
readonly VERSION="9.9.9-test"
readonly ARCHIVE="credible-solidity-interfaces-${VERSION}.tar.gz"

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

release_dir="${tmp}/releases/${VERSION}"
target="${tmp}/credible-std"
mkdir -p "${release_dir}" "${target}/src"

tar -czf "${release_dir}/${ARCHIVE}" \
  -C "${ROOT}/src" \
  IAssertion.sol PhEvm.sol TriggerRecorder.sol SpecRecorder.sol
(
  cd "${release_dir}"
  sha256sum "${ARCHIVE}" > "${ARCHIVE}.sha256"
)

export CREDIBLE_STD_ROOT="${target}"
export CREDIBLE_SDK_RELEASE_BASE_URL="file://${tmp}/releases"

"${SYNC}" "${VERSION}"
"${SYNC}" --check

printf '\n// deliberate drift\n' >> "${target}/src/PhEvm.sol"
if "${SYNC}" --check >/dev/null 2>&1; then
  echo "interface check accepted a modified file" >&2
  exit 1
fi

echo "interface sync tests passed"
