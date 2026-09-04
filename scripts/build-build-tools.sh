#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"

source_root="$project_root/build-tools"
cmake_build="$build_dir/build-tools-cmake"
output="$build_dir/build-tools-aarch64"
targets=(aapt aapt2 aidl dexdump split-select zipalign)

for command_name in cmake ninja aarch64-linux-gnu-gcc \
    aarch64-linux-gnu-g++ aarch64-linux-gnu-strip file readelf; do
    command -v "$command_name" >/dev/null || die "missing command: $command_name"
done

[[ -f "$source_root/CMakeLists.txt" ]] ||
    die "embedded Build-Tools source is missing: $source_root"
python3 -B "$project_root/tests/verify_source_snapshot_test.py"
python3 -B "$script_dir/verify-source-snapshot.py"

rm -rf -- "$cmake_build" "$output"
mkdir -p -- "$output/lib64"
libcxx_archive=/usr/lib/aarch64-linux-gnu/libc++.a
static_zlib=/usr/lib/aarch64-linux-gnu/libz.a
[[ -f "$libcxx_archive" ]] ||
    die "LLVM 22 AArch64 libc++.a is missing; run resolute-install-deps.sh"
[[ -f "$static_zlib" ]] ||
    die "AArch64 static zlib is missing; run resolute-install-deps.sh"
for soname in libc++.so libc++.so.1; do
    aarch64-linux-gnu-g++ \
        -shared -Wl,-soname,"$soname" \
        -Wl,--whole-archive "$libcxx_archive" -Wl,--no-whole-archive \
        -static-libgcc -ldl -pthread -lm \
        -o "$output/lib64/$soname"
    require_aarch64_elf "$output/lib64/$soname"
    readelf -d "$output/lib64/$soname" |
        grep -Fq "Library soname: [$soname]" ||
        die "$soname has an unexpected SONAME"
done

cmake -S "$source_root" -B "$cmake_build" -GNinja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_TOOLCHAIN_FILE="$source_root/cmake/aarch64-linux-gnu.cmake" \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DSDK_STATIC_ZLIB="$static_zlib" \
    -Dprotobuf_BUILD_TESTS=OFF
cmake --build "$cmake_build" --parallel "$jobs" --target "${targets[@]}"

for name in "${targets[@]}"; do
    binary="$cmake_build/bin/$name"
    [[ -f "$binary" ]] || die "Build-Tools build did not produce $name"
    install -m 0755 "$binary" "$output/$name"
    aarch64-linux-gnu-strip "$output/$name"
    require_aarch64_elf "$output/$name"
    readelf -l "$output/$name" |
        grep -Fq 'Requesting program interpreter: /lib/ld-linux-aarch64.so.1' ||
        die "$name is not a GNU/glibc Linux AArch64 executable"
    if readelf -d "$output/$name" | grep -q 'libc_musl'; then
        die "$name unexpectedly depends on musl"
    fi
    if readelf -d "$output/$name" |
       grep -Eq 'Shared library: \[(libstdc\+\+\.so|libgcc_s\.so|libz\.so|libc\+\+abi\.so|libunwind\.so)'; then
        die "$name depends on an unpackaged compiler, C++ or zlib runtime"
    fi
    readelf -d "$output/$name" | grep -Fq 'Library runpath: [$ORIGIN/lib64]' ||
        die "$name does not resolve libc++.so relative to Build-Tools"
done

aarch64-linux-gnu-strip "$output/lib64/libc++.so" "$output/lib64/libc++.so.1"

echo "Built Build-Tools $SDK_BUILD_TOOLS_VERSION from embedded Android 16 sources for GNU/Linux AArch64."
