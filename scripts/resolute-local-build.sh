#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

without_ndk=0
if [[ "${1:-}" == "--without-ndk" ]]; then without_ndk=1; shift; fi
(( $# == 0 )) || { echo "usage: $0 [--without-ndk]" >&2; exit 2; }

args=()
(( without_ndk )) && args+=(--without-ndk)
"$script_dir/fetch-sources.sh" "${args[@]}"
"$script_dir/build-cmake.sh"
"$script_dir/build-build-tools.sh"
"$script_dir/assemble-sdk.sh" "${args[@]}"
"$script_dir/validate-sdk.sh"

