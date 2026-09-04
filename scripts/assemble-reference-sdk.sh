#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"

(( $# == 0 )) || die "usage: $0"

reference="$build_dir/reference-sdk"
rm -rf -- "$reference"
mkdir -p -- "$reference/build-tools/$SDK_BUILD_TOOLS_VERSION" \
    "$reference/cmake/3.22.1" "$reference/cmake/4.1.2" \
    "$reference/cmdline-tools/latest" "$reference/licenses" \
    "$reference/platforms/$SDK_PLATFORM_VERSION" "$reference/.temp"

copy_google_package "$cache_dir/$BUILD_TOOLS_ARCHIVE" \
    "build-tools;$SDK_BUILD_TOOLS_VERSION" \
    "$reference/build-tools/$SDK_BUILD_TOOLS_VERSION"
copy_google_package "$cache_dir/$CMDLINE_TOOLS_ARCHIVE" \
    "cmdline-tools;$SDK_CMDLINE_TOOLS_VERSION" "$reference/cmdline-tools/latest"
copy_google_package "$cache_dir/$PLATFORM_ARCHIVE" \
    "platforms;$SDK_PLATFORM_VERSION" "$reference/platforms/$SDK_PLATFORM_VERSION"
copy_google_package "$cache_dir/$GOOGLE_CMAKE_3_ARCHIVE" \
    "cmake;3.22.1" "$reference/cmake/3.22.1"
copy_google_package "$cache_dir/$GOOGLE_CMAKE_4_ARCHIVE" \
    "cmake;4.1.2" "$reference/cmake/4.1.2"

write_generic_package_xml \
    "$reference/build-tools/$SDK_BUILD_TOOLS_VERSION/package.xml" \
    "build-tools;$SDK_BUILD_TOOLS_VERSION" 36 0 0 "Android SDK Build-Tools 36"
write_generic_package_xml "$reference/cmake/3.22.1/package.xml" \
    "cmake;3.22.1" 3 22 1 "CMake 3.22.1"
write_generic_package_xml "$reference/cmake/4.1.2/package.xml" \
    "cmake;4.1.2" 4 1 2 "CMake 4.1.2"
install -m 0644 "$project_root/templates/package-platform.xml.in" \
    "$reference/platforms/$SDK_PLATFORM_VERSION/package.xml"

temporary="$(mktemp -d)"
cleanup_temporary() {
    rm -rf -- "$temporary"
}
trap cleanup_temporary EXIT
unzip -q "$cache_dir/reference-$REFERENCE_PLATFORM_TOOLS_ARCHIVE" -d "$temporary"
[[ -d "$temporary/platform-tools" ]] ||
    die "unexpected official Platform-Tools reference archive layout"
cp -a -- "$temporary/platform-tools" "$reference/platform-tools"
write_generic_package_xml "$reference/platform-tools/package.xml" \
    "platform-tools" 37 0 1 "Android SDK Platform-Tools"
rm -rf -- "$temporary"
trap - EXIT

temporary="$(mktemp -d)"
trap cleanup_temporary EXIT
unzip -q "$cache_dir/reference-$REFERENCE_NDK_ARCHIVE" -d "$temporary"
[[ -d "$temporary/android-ndk-r27d" ]] ||
    die "unexpected official NDK reference archive layout"
mkdir -p -- "$reference/ndk/$SDK_NDK_VERSION"
cp -a -- "$temporary/android-ndk-r27d/." \
    "$reference/ndk/$SDK_NDK_VERSION/"
write_generic_package_xml "$reference/ndk/$SDK_NDK_VERSION/package.xml" \
    "ndk;$SDK_NDK_VERSION" 27 3 13750724 \
    "NDK (Side by side) $SDK_NDK_VERSION"
rm -rf -- "$temporary"
trap - EXIT

printf '\n%s' '24333f8a63b6825ea9c5514f83c2829b004d1fee' > \
    "$reference/licenses/android-sdk-license"
chmod 0644 "$reference/licenses/android-sdk-license"

find "$reference" -type d -exec chmod 0755 {} +
find "$reference" -type f -perm /0111 -exec chmod 0755 {} +
find "$reference" -type f ! -perm /0111 -exec chmod 0644 {} +

echo "$reference"
