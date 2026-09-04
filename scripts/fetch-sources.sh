#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"

include_ndk=1
include_reference=0
while (( $# )); do
    case "$1" in
        --without-ndk) include_ndk=0 ;;
        --with-reference) include_reference=1 ;;
        *) die "usage: $0 [--without-ndk] [--with-reference]" ;;
    esac
    shift
done

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
platform_tools_release_tag=
download_latest_github_release_asset \
    "$PLATFORM_TOOLS_RELEASE_REPOSITORY" \
    "$PLATFORM_TOOLS_RELEASE_ASSET" \
    "$PLATFORM_TOOLS_RELEASE_CHECKSUM_ASSET" \
    "$cache_dir/$PLATFORM_TOOLS_RELEASE_ASSET" \
    platform_tools_release_tag

if (( include_ndk )); then
    ndk_release_tag=
    download_latest_github_release_asset \
        "$NDK_RELEASE_REPOSITORY" \
        "$NDK_RELEASE_ASSET" \
        "$NDK_RELEASE_CHECKSUM_ASSET" \
        "$cache_dir/$NDK_RELEASE_ASSET" \
        ndk_release_tag
fi

if (( include_reference )); then
    download_checked "$REFERENCE_PLATFORM_TOOLS_URL" \
        "$cache_dir/reference-$REFERENCE_PLATFORM_TOOLS_ARCHIVE" \
        sha256 "$REFERENCE_PLATFORM_TOOLS_SHA256"
    if (( include_ndk )); then
        download_checked "$REFERENCE_NDK_URL" \
            "$cache_dir/reference-$REFERENCE_NDK_ARCHIVE" \
            sha256 "$REFERENCE_NDK_SHA256"
    fi
fi

resolved_releases="$cache_dir/resolved-community-releases.txt"
{
    printf 'platform-tools\t%s\t%s\n' \
        "$platform_tools_release_tag" "$PLATFORM_TOOLS_RELEASE_ASSET"
    if (( include_ndk )); then
        printf 'ndk\t%s\t%s\n' "$ndk_release_tag" "$NDK_RELEASE_ASSET"
    fi
} > "$resolved_releases"

echo "All requested component archives are present and checksum verified."
