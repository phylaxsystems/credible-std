#!/usr/bin/env bash

# Generate stable, source-shaped ABI artifacts for npm and GitHub releases.
# Prerequisites: Foundry and jq.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." &>/dev/null && pwd)"
ARTIFACTS_DIR="${ROOT_DIR}/artifacts"

cd "${ROOT_DIR}"
FOUNDRY_PROFILE=default forge clean
FOUNDRY_PROFILE=default forge build

if [[ "${ARTIFACTS_DIR}" != "${ROOT_DIR}/artifacts" ]]; then
  echo "Refusing to replace unexpected artifacts directory: ${ARTIFACTS_DIR}" >&2
  exit 1
fi

rm -rf "${ARTIFACTS_DIR}"
mkdir -p "${ARTIFACTS_DIR}"

artifact_count=0

while IFS= read -r forge_artifact; do
  compilation_target="$(
    jq -r '(.metadata.settings.compilationTarget // {}) | to_entries[0] // empty | select(.key | startswith("src/")) | [.key, .value] | @tsv' "${forge_artifact}"
  )"
  [[ -n "${compilation_target}" ]] || continue
  IFS=$'\t' read -r source_path contract_name <<<"${compilation_target}"

  abi_length="$(jq '.abi | length' "${forge_artifact}")"
  (( abi_length > 0 )) || continue

  relative_source="${source_path#src/}"
  source_stem="${relative_source%.sol}"
  source_name="$(basename "${source_stem}")"
  source_dir="$(dirname "${source_stem}")"

  if [[ "${contract_name}" == "${source_name}" ]]; then
    relative_output="${source_stem}.json"
  elif [[ "${source_dir}" == "." ]]; then
    relative_output="${source_name}.${contract_name}.json"
  else
    relative_output="${source_dir}/${source_name}.${contract_name}.json"
  fi

  output_path="${ARTIFACTS_DIR}/${relative_output}"
  mkdir -p "$(dirname "${output_path}")"
  jq '.abi' "${forge_artifact}" >"${output_path}"
  echo "Created artifacts/${relative_output}"
  ((artifact_count += 1))
done < <(find "${ROOT_DIR}/out" -mindepth 2 -maxdepth 2 -type f -name '*.json' | LC_ALL=C sort)

if (( artifact_count == 0 )); then
  echo "No ABI-bearing contracts from src/ were found" >&2
  exit 1
fi

duplicate_asset_names="$(find "${ARTIFACTS_DIR}" -type f -name '*.json' -exec basename {} \; | LC_ALL=C sort | uniq -d)"
if [[ -n "${duplicate_asset_names}" ]]; then
  echo "Duplicate GitHub release asset names:" >&2
  echo "${duplicate_asset_names}" >&2
  exit 1
fi

echo "Created ${artifact_count} ABI artifacts"
