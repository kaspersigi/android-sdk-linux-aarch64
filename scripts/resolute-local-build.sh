#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"
require_resolute_host

(( $# == 0 )) || { echo "usage: $0" >&2; exit 2; }

if [[ ${REFERENCE_DIR+x} == x ]]; then
    [[ -n "$REFERENCE_DIR" ]] || die "REFERENCE_DIR must not be empty"
    reference="$REFERENCE_DIR"
    [[ -d "$reference" ]] || die "REFERENCE_DIR does not exist: $reference"
    generate_reference=0
else
    reference="$build_dir/reference-sdk"
    generate_reference=1
fi

fetch_args=()
(( generate_reference )) && fetch_args+=(--with-reference)
"$script_dir/fetch-sources.sh" "${fetch_args[@]}"
"$script_dir/build-cmake.sh"
"$script_dir/build-build-tools.sh"
"$script_dir/assemble-sdk.sh"
if (( generate_reference )); then
    "$script_dir/assemble-reference-sdk.sh"
fi
REFERENCE_DIR="$reference" "$script_dir/validate-sdk.sh"
