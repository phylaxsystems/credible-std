#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT="${CREDIBLE_STD_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
readonly LOCK_FILE="${ROOT}/credible-sdk-interfaces.lock"
readonly RELEASE_BASE_URL="${CREDIBLE_SDK_RELEASE_BASE_URL:-https://github.com/phylaxsystems/credible-sdk/releases/download}"
readonly INTERFACES=(IAssertion.sol PhEvm.sol TriggerRecorder.sol SpecRecorder.sol)

usage() {
  cat <<'EOF'
Usage:
  scripts/sync-credible-interfaces.sh <sdk-version>
  scripts/sync-credible-interfaces.sh --check

Sync copies the canonical Solidity interfaces from a credible-sdk release and
writes credible-sdk-interfaces.lock. Check verifies the vendored files against
the exact released archive and pinned SHA-256.
EOF
}

validate_version() {
  local version="$1"
  if [[ ! "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$ ]]; then
    echo "invalid SDK release version: ${version}" >&2
    exit 1
  fi
}

download_release() {
  local version="$1"
  local destination="$2"
  local archive_name="credible-solidity-interfaces-${version}.tar.gz"
  local archive="${destination}/${archive_name}"
  local checksum_file="${archive}.sha256"
  local remote_sha
  local actual_sha

  curl -fsSL "${RELEASE_BASE_URL}/${version}/${archive_name}" -o "${archive}"
  curl -fsSL "${RELEASE_BASE_URL}/${version}/${archive_name}.sha256" -o "${checksum_file}"

  remote_sha="$(awk -v name="${archive_name}" '$2 == name || $2 == "*" name { print $1 }' "${checksum_file}")"
  if [[ ! "${remote_sha}" =~ ^[0-9a-fA-F]{64}$ ]]; then
    echo "release checksum file is malformed for ${archive_name}" >&2
    exit 1
  fi

  actual_sha="$(sha256sum "${archive}" | awk '{ print $1 }')"
  if [[ "${actual_sha}" != "${remote_sha}" ]]; then
    echo "release checksum mismatch for ${archive_name}" >&2
    exit 1
  fi

  mapfile -t archive_entries < <(tar -tzf "${archive}" | LC_ALL=C sort)
  mapfile -t expected_entries < <(printf '%s\n' "${INTERFACES[@]}" | LC_ALL=C sort)
  if [[ "${archive_entries[*]}" != "${expected_entries[*]}" ]]; then
    echo "release archive must contain exactly: ${INTERFACES[*]}" >&2
    exit 1
  fi

  mkdir -p "${destination}/interfaces"
  tar -xzf "${archive}" -C "${destination}/interfaces"
  DOWNLOADED_SHA="${actual_sha}"
  DOWNLOADED_INTERFACES="${destination}/interfaces"
}

read_lock() {
  if [[ ! -f "${LOCK_FILE}" ]]; then
    echo "${LOCK_FILE} is missing; sync a released SDK version first" >&2
    exit 1
  fi

  LOCKED_VERSION="$(sed -n 's/^sdk_version=//p' "${LOCK_FILE}")"
  LOCKED_SHA="$(sed -n 's/^sha256=//p' "${LOCK_FILE}")"
  validate_version "${LOCKED_VERSION}"
  if [[ ! "${LOCKED_SHA}" =~ ^[0-9a-fA-F]{64}$ ]]; then
    echo "invalid SHA-256 in ${LOCK_FILE}" >&2
    exit 1
  fi
}

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

case "${1:-}" in
  --check)
    read_lock
    download_release "${LOCKED_VERSION}" "${tmp}"
    if [[ "${DOWNLOADED_SHA}" != "${LOCKED_SHA}" ]]; then
      echo "released interface archive does not match the pinned SHA-256" >&2
      exit 1
    fi
    for interface in "${INTERFACES[@]}"; do
      diff -u "${DOWNLOADED_INTERFACES}/${interface}" "${ROOT}/src/${interface}"
    done
    echo "credible-std interfaces match credible-sdk ${LOCKED_VERSION}"
    ;;
  --help|-h)
    usage
    ;;
  "")
    usage >&2
    exit 1
    ;;
  *)
    validate_version "$1"
    download_release "$1" "${tmp}"
    mkdir -p "${ROOT}/src"
    for interface in "${INTERFACES[@]}"; do
      cp "${DOWNLOADED_INTERFACES}/${interface}" "${ROOT}/src/${interface}"
    done
    printf 'sdk_version=%s\nsha256=%s\n' "$1" "${DOWNLOADED_SHA}" > "${LOCK_FILE}"
    echo "synced credible-sdk $1 interfaces; commit src/*.sol and credible-sdk-interfaces.lock"
    ;;
esac
