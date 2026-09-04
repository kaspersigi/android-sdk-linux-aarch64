#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"

for command_name in cmake ninja aarch64-linux-gnu-gcc \
    aarch64-linux-gnu-g++ readelf tar; do
    command -v "$command_name" >/dev/null || die "missing command: $command_name"
done

rm -rf -- "$sources_dir/cmake-3.22.1-aarch64" \
    "$sources_dir/cmake-4.1.2-aarch64" "$sources_dir/ninja-1.10.2" \
    "$sources_dir/ninja-1.12.1" "$build_dir/ninja-1.10.2" \
    "$build_dir/ninja-1.12.1" "$build_dir/cmake-aarch64"
mkdir -p -- "$sources_dir/cmake-3.22.1-aarch64" \
    "$sources_dir/cmake-4.1.2-aarch64" "$sources_dir/ninja-1.10.2" \
    "$sources_dir/ninja-1.12.1" "$build_dir/ninja-1.10.2" \
    "$build_dir/ninja-1.12.1" "$build_dir/cmake-aarch64/3.22.1/bin" \
    "$build_dir/cmake-aarch64/4.1.2/bin"

tar -xzf "$cache_dir/cmake-3.22.1-linux-aarch64.tar.gz" \
    -C "$sources_dir/cmake-3.22.1-aarch64" --strip-components=1
tar -xzf "$cache_dir/cmake-4.1.2-linux-aarch64.tar.gz" \
    -C "$sources_dir/cmake-4.1.2-aarch64" --strip-components=1
tar -xzf "$cache_dir/ninja-v1.10.2.tar.gz" \
    -C "$sources_dir/ninja-1.10.2" --strip-components=1
tar -xzf "$cache_dir/ninja-v1.12.1.tar.gz" \
    -C "$sources_dir/ninja-1.12.1" --strip-components=1

for version in 1.10.2 1.12.1; do
    cmake -S "$sources_dir/ninja-$version" -B "$build_dir/ninja-$version" \
        -G Ninja \
        -DCMAKE_SYSTEM_NAME=Linux \
        -DCMAKE_SYSTEM_PROCESSOR=aarch64 \
        -DCMAKE_C_COMPILER=aarch64-linux-gnu-gcc \
        -DCMAKE_CXX_COMPILER=aarch64-linux-gnu-g++ \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_EXE_LINKER_FLAGS='-static-libgcc -static-libstdc++' \
        -DBUILD_TESTING=OFF
    cmake --build "$build_dir/ninja-$version" --parallel "$jobs"
done

for name in cmake cpack ctest; do
    install -m 0755 "$sources_dir/cmake-3.22.1-aarch64/bin/$name" \
        "$build_dir/cmake-aarch64/3.22.1/bin/$name"
    install -m 0755 "$sources_dir/cmake-4.1.2-aarch64/bin/$name" \
        "$build_dir/cmake-aarch64/4.1.2/bin/$name"
done
install -m 0755 "$build_dir/ninja-1.10.2/ninja" \
    "$build_dir/cmake-aarch64/3.22.1/bin/ninja"
install -m 0755 "$build_dir/ninja-1.12.1/ninja" \
    "$build_dir/cmake-aarch64/4.1.2/bin/ninja"

for version in 3.22.1 4.1.2; do
    for name in cmake cpack ctest ninja; do
        require_aarch64_elf "$build_dir/cmake-aarch64/$version/bin/$name"
    done
    ninja_binary="$build_dir/cmake-aarch64/$version/bin/ninja"
    if readelf -d "$ninja_binary" |
       grep -Fq 'Shared library: [libstdc++.so'; then
        die "$ninja_binary depends on the host libstdc++ runtime"
    fi
done

echo "Built exact-version CMake/Ninja host binaries for Linux AArch64."
