#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Consumer contract gate BEFORE building Ninja or Build-Tools.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"
(( $# <= 1 )) || die "usage: $0 [local-ndk-directory-for-diagnostics]"
for required in python3 ninja unzip tar sha256sum; do
    command -v "$required" >/dev/null ||
        die "missing $required; run ./scripts/resolute-install-deps.sh"
done
select_arm64_runtime

temporary=$(mktemp -d "${TMPDIR:-/tmp}/sdk-ndk-preflight.XXXXXX")
trap 'rm -rf -- "$temporary"' EXIT
if (( $# )); then
    ndk=$(realpath -e -- "$1")
    echo "Local NDK diagnostic only (not Release provenance validation): $ndk"
else
    verify_cached_release_archive "$NDK_RELEASE_ASSET"
    unzip -q "$cache_dir/$NDK_RELEASE_ASSET" -d "$temporary/ndk"
    ndk="$temporary/ndk/android-ndk-r27d"
fi

python3 -B "$project_root/tests/compare_reference_layout_test.py"
python3 -B "$project_root/tests/verify_source_snapshot_test.py"
"$project_root/tests/check-aarch64-elf-test.sh"
"$project_root/tests/check-aarch64-host-archives-test.sh"

cmake_options=()
for version in 3.22.1 4.1.2; do
    # Exactly the module/binary combination used by assemble-sdk.sh, without
    # waiting for Ninja or Build-Tools to build. Host Ninja is enough here.
    destination="$temporary/cmake/$version"
    copy_google_package "$cache_dir/cmake-$version-linux.zip" "cmake;$version" "$destination"
    tar -xzf "$cache_dir/cmake-$version-linux-aarch64.tar.gz" -C "$temporary" \
        "cmake-$version-linux-aarch64/bin/cmake"
    install -m 0755 "$temporary/cmake-$version-linux-aarch64/bin/cmake" "$destination/bin/cmake"
    cmake_options+=(--cmake "$destination/bin/cmake")
done

if ! python3 -B "$project_root/tests/ndk_entrypoints_test.py" --ndk "$ndk" \
        "${cmake_options[@]}" --ninja "$(command -v ninja)" --runtime; then
    die "NDK/CMake entrypoint preflight failed BEFORE the SDK build. Check diagnostics/dependencies above; if this is an old NDK Release, publish the fixed standalone NDK first."
fi
echo "NDK consumer entrypoint preflight passed; final SDK validation is still required."
