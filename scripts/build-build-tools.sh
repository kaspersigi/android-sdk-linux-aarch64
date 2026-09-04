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
python3 "$script_dir/verify-source-snapshot.py"

rm -rf -- "$cmake_build" "$output"
mkdir -p -- "$output"

cmake -S "$source_root" -B "$cmake_build" -GNinja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_TOOLCHAIN_FILE="$source_root/cmake/aarch64-linux-gnu.cmake" \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
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
done

echo "Built Build-Tools $SDK_BUILD_TOOLS_VERSION from embedded Android 16 sources for GNU/Linux AArch64."
