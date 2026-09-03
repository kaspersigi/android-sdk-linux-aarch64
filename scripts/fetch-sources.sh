#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"

include_ndk=1
if [[ "${1:-}" == "--without-ndk" ]]; then
    include_ndk=0
    shift
fi
(( $# == 0 )) || die "usage: $0 [--without-ndk]"

download_checked "$GOOGLE_BASE_URL/$BUILD_TOOLS_ARCHIVE" \
    "$cache_dir/$BUILD_TOOLS_ARCHIVE" sha1 "$BUILD_TOOLS_SHA1"
download_checked "$GOOGLE_BASE_URL/$PLATFORM_ARCHIVE" \
    "$cache_dir/$PLATFORM_ARCHIVE" sha1 "$PLATFORM_SHA1"
download_checked "$GOOGLE_BASE_URL/$CMDLINE_TOOLS_ARCHIVE" \
    "$cache_dir/$CMDLINE_TOOLS_ARCHIVE" sha1 "$CMDLINE_TOOLS_SHA1"
download_checked "$GOOGLE_BASE_URL/$GOOGLE_CMAKE_3_ARCHIVE" \
    "$cache_dir/$GOOGLE_CMAKE_3_ARCHIVE" sha1 "$GOOGLE_CMAKE_3_SHA1"
download_checked "$GOOGLE_BASE_URL/$GOOGLE_CMAKE_4_ARCHIVE" \
    "$cache_dir/$GOOGLE_CMAKE_4_ARCHIVE" sha1 "$GOOGLE_CMAKE_4_SHA1"

download_checked "$CMAKE_3_AARCH64_URL" \
    "$cache_dir/cmake-3.22.1-linux-aarch64.tar.gz" sha256 "$CMAKE_3_AARCH64_SHA256"
download_checked "$CMAKE_4_AARCH64_URL" \
    "$cache_dir/cmake-4.1.2-linux-aarch64.tar.gz" sha256 "$CMAKE_4_AARCH64_SHA256"
download_checked "$NINJA_1_10_SOURCE_URL" \
    "$cache_dir/ninja-v1.10.2.tar.gz" sha256 "$NINJA_1_10_SOURCE_SHA256"
download_checked "$NINJA_1_12_AARCH64_URL" \
    "$cache_dir/ninja-linux-aarch64-v1.12.1.zip" sha256 "$NINJA_1_12_AARCH64_SHA256"
download_checked "$PLATFORM_TOOLS_URL" \
    "$cache_dir/platform-tools_r37.0.1-linux.zip" sha256 "$PLATFORM_TOOLS_SHA256"

if (( include_ndk )); then
    download_checked "$NDK_RELEASE_URL" "$cache_dir/$NDK_RELEASE_ASSET" \
        sha256 "$NDK_RELEASE_SHA256"
fi

echo "All requested component archives are present and checksum verified."
