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

sdk="$dist_dir/sdk"
rm -rf -- "$sdk"
mkdir -p -- "$sdk/build-tools/$SDK_BUILD_TOOLS_VERSION" \
    "$sdk/cmake/3.22.1" "$sdk/cmake/4.1.2" "$sdk/cmdline-tools/latest" \
    "$sdk/licenses" "$sdk/platforms/$SDK_PLATFORM_VERSION" "$sdk/.temp"

copy_google_package "$cache_dir/$BUILD_TOOLS_ARCHIVE" \
    "build-tools;$SDK_BUILD_TOOLS_VERSION" "$sdk/build-tools/$SDK_BUILD_TOOLS_VERSION"
copy_google_package "$cache_dir/$CMDLINE_TOOLS_ARCHIVE" \
    "cmdline-tools;$SDK_CMDLINE_TOOLS_VERSION" "$sdk/cmdline-tools/latest"
copy_google_package "$cache_dir/$PLATFORM_ARCHIVE" \
    "platforms;$SDK_PLATFORM_VERSION" "$sdk/platforms/$SDK_PLATFORM_VERSION"
copy_google_package "$cache_dir/$GOOGLE_CMAKE_3_ARCHIVE" \
    "cmake;3.22.1" "$sdk/cmake/3.22.1"
copy_google_package "$cache_dir/$GOOGLE_CMAKE_4_ARCHIVE" \
    "cmake;4.1.2" "$sdk/cmake/4.1.2"

write_generic_package_xml "$sdk/build-tools/$SDK_BUILD_TOOLS_VERSION/package.xml" \
    "build-tools;$SDK_BUILD_TOOLS_VERSION" 36 0 0 "Android SDK Build-Tools 36 Linux AArch64"
write_generic_package_xml "$sdk/cmake/3.22.1/package.xml" \
    "cmake;3.22.1" 3 22 1 "CMake 3.22.1 Linux AArch64"
write_generic_package_xml "$sdk/cmake/4.1.2/package.xml" \
    "cmake;4.1.2" 4 1 2 "CMake 4.1.2 Linux AArch64"
install -m 0644 "$project_root/templates/package-platform.xml.in" \
    "$sdk/platforms/$SDK_PLATFORM_VERSION/package.xml"

temporary="$(mktemp -d)"
unzip -q "$cache_dir/$PLATFORM_TOOLS_RELEASE_ASSET" -d "$temporary"
[[ -d "$temporary/platform-tools" ]] || die "unexpected Platform-Tools archive layout"
cp -a -- "$temporary/platform-tools" "$sdk/platform-tools"
rm -rf -- "$temporary"

for version in 3.22.1 4.1.2; do
    for name in cmake cpack ctest ninja; do
        install -m 0755 "$build_dir/cmake-aarch64/$version/bin/$name" \
            "$sdk/cmake/$version/bin/$name"
    done
done

bt="$sdk/build-tools/$SDK_BUILD_TOOLS_VERSION"
host_paths=(
    aapt aapt2 aidl bcc_compat dexdump llvm-rs-cc split-select zipalign
    lld-bin/lld
    lib64/libLLVM_android.so lib64/libbcc.so lib64/libbcinfo.so
    lib64/libc++.so lib64/libc++.so.1 lib64/libclang_android.so
)
for relative in "${host_paths[@]}"; do
    rm -f -- "$bt/$relative"
done
for name in aapt aapt2 aidl dexdump split-select zipalign; do
    install -m 0755 "$build_dir/build-tools-aarch64/$name" "$bt/$name"
done
install -m 0755 "$project_root/templates/renderscript-unsupported" "$bt/bcc_compat"
install -m 0755 "$project_root/templates/renderscript-unsupported" "$bt/llvm-rs-cc"
install -m 0755 "$project_root/templates/android-offline" \
    "$sdk/cmdline-tools/latest/bin/android"

# The working Platform-Tools package already carries the same LLVM libc++ ABI
# needed by this SDK. The remaining removed lib64 files only support deprecated
# RenderScript host tools and deliberately have no fake replacements.
mkdir -p -- "$bt/lib64" "$bt/lld-bin"
install -m 0755 "$sdk/platform-tools/lib64/libc++.so" "$bt/lib64/libc++.so"
install -m 0644 "$sdk/platform-tools/lib64/libc++.so" "$bt/lib64/libc++.so.1"
install -m 0755 "$project_root/templates/build-tools-lld" "$bt/lld-bin/lld"

if (( include_ndk )); then
    [[ -f "$cache_dir/$NDK_RELEASE_ASSET" ]] ||
        die "missing NDK Release archive; run fetch-sources.sh after the Release is available"
    temporary="$(mktemp -d)"
    unzip -q "$cache_dir/$NDK_RELEASE_ASSET" -d "$temporary"
    ndk_root="$temporary/android-ndk-r27d"
    [[ -d "$ndk_root" ]] || die "unexpected NDK archive layout"
    mkdir -p -- "$sdk/ndk/$SDK_NDK_VERSION"
    cp -a -- "$ndk_root/." "$sdk/ndk/$SDK_NDK_VERSION/"
    write_generic_package_xml "$sdk/ndk/$SDK_NDK_VERSION/package.xml" \
        "ndk;$SDK_NDK_VERSION" 27 3 13750724 \
        "NDK (Side by side) $SDK_NDK_VERSION Linux AArch64"
    rm -rf -- "$temporary"
fi

printf '\n%s' '24333f8a63b6825ea9c5514f83c2829b004d1fee' > \
    "$sdk/licenses/android-sdk-license"
chmod 0644 "$sdk/licenses/android-sdk-license"

# sdkmanager normalizes installed package permissions according to the user's
# umask. Use the equivalent non-group-writable canonical modes in the archive.
find "$sdk" -type d -exec chmod 0755 {} +
find "$sdk" -type f -perm /0111 -exec chmod 0755 {} +
find "$sdk" -type f ! -perm /0111 -exec chmod 0644 {} +

archive="$dist_dir/android-sdk-linux.zip"
if (( ! include_ndk )); then
    archive="$dist_dir/android-sdk-linux-without-ndk.zip"
fi
rm -f -- "$archive" "$archive.sha256"
(
    cd "$dist_dir"
    find sdk -print | LC_ALL=C sort | zip -X -q -y "$archive" -@
)
(
    cd "$dist_dir"
    archive_name="$(basename -- "$archive")"
    sha256sum "$archive_name" > "$archive_name.sha256"
)
echo "$archive"
