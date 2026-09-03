#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
project_root="$(cd -- "$script_dir/.." && pwd -P)"
cache_dir="$project_root/.cache"
sources_dir="$project_root/sources"
build_dir="$project_root/build"
dist_dir="$project_root/dist"

# shellcheck disable=SC1091
source "$project_root/sources.lock"

jobs="${JOBS:-$(nproc)}"
[[ "$jobs" =~ ^[1-9][0-9]*$ ]] || {
    echo "error: JOBS must be a positive integer" >&2
    exit 2
}

die() {
    echo "error: $*" >&2
    exit 1
}

download_checked() {
    local url="$1" output="$2" algorithm="$3" expected="$4"
    local actual temporary
    mkdir -p -- "$(dirname -- "$output")"

    if [[ -f "$output" ]]; then
        actual="$(${algorithm}sum "$output" | awk '{print $1}')"
        if [[ "$actual" == "$expected" ]]; then
            echo "Using cached $(basename -- "$output")"
            return
        fi
        rm -f -- "$output"
    fi

    temporary="${output}.part"
    rm -f -- "$temporary"
    curl --fail --location --retry 3 --output "$temporary" "$url"
    actual="$(${algorithm}sum "$temporary" | awk '{print $1}')"
    [[ "$actual" == "$expected" ]] || {
        rm -f -- "$temporary"
        die "checksum mismatch for $url: expected $expected, got $actual"
    }
    mv -- "$temporary" "$output"
}

copy_google_package() {
    local archive="$1" package_path="$2" destination="$3"
    local temporary package_root
    local -a property_files
    temporary="$(mktemp -d)"
    unzip -q "$archive" -d "$temporary"
    package_root="$(find "$temporary" -type f -name source.properties -print0 | \
        while IFS= read -r -d '' properties; do
            if grep -Fqx "Pkg.Path=$package_path" "$properties" ||
               grep -Fqx "Pkg.Path = $package_path" "$properties"; then
                dirname -- "$properties"
                break
            fi
        done)"
    if [[ -z "$package_root" ]]; then
        mapfile -d '' -t property_files < <(find "$temporary" -type f -name source.properties -print0)
        if (( ${#property_files[@]} == 1 )); then
            package_root="$(dirname -- "${property_files[0]}")"
        fi
    fi
    [[ -n "$package_root" ]] || {
        rm -rf -- "$temporary"
        die "could not find $package_path inside $(basename -- "$archive")"
    }
    mkdir -p -- "$destination"
    cp -a -- "$package_root/." "$destination/"
    rm -rf -- "$temporary"
}

require_aarch64_elf() {
    local path="$1"
    file -b "$path" | grep -Eq 'ARM aarch64|AArch64' ||
        die "$path is not an AArch64 ELF"
}
