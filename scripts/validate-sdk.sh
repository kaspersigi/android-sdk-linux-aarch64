#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"

sdk="${1:-$dist_dir/sdk}"
[[ -d "$sdk" ]] || die "SDK directory does not exist: $sdk"

grep -Fqx "Pkg.Revision=$SDK_BUILD_TOOLS_VERSION" \
    "$sdk/build-tools/$SDK_BUILD_TOOLS_VERSION/source.properties"
grep -Fqx "Pkg.Revision=$SDK_PLATFORM_TOOLS_VERSION" \
    "$sdk/platform-tools/source.properties"
grep -Fqx "Pkg.Revision=$SDK_CMDLINE_TOOLS_VERSION" \
    "$sdk/cmdline-tools/latest/source.properties"
grep -Fqx 'Pkg.Revision = 3.22.1' "$sdk/cmake/3.22.1/source.properties"
grep -Fqx 'Pkg.Revision = 4.1.2' "$sdk/cmake/4.1.2/source.properties"

host_elfs=(
    build-tools/36.0.0/aapt
    build-tools/36.0.0/aapt2
    build-tools/36.0.0/aidl
    build-tools/36.0.0/dexdump
    build-tools/36.0.0/split-select
    build-tools/36.0.0/zipalign
    build-tools/36.0.0/lib64/libc++.so
    build-tools/36.0.0/lib64/libc++.so.1
    cmake/3.22.1/bin/cmake
    cmake/3.22.1/bin/cpack
    cmake/3.22.1/bin/ctest
    cmake/3.22.1/bin/ninja
    cmake/4.1.2/bin/cmake
    cmake/4.1.2/bin/cpack
    cmake/4.1.2/bin/ctest
    cmake/4.1.2/bin/ninja
    platform-tools/adb
    platform-tools/etc1tool
    platform-tools/fastboot
    platform-tools/hprof-conv
    platform-tools/make_f2fs
    platform-tools/make_f2fs_casefold
    platform-tools/mke2fs
    platform-tools/sqlite3
    platform-tools/lib64/libc++.so
)
if [[ -f "$sdk/build-tools/36.0.0/lld-bin/lld" ]] &&
   file -b "$sdk/build-tools/36.0.0/lld-bin/lld" | grep -q ELF; then
    host_elfs+=(build-tools/36.0.0/lld-bin/lld)
fi
for relative in "${host_elfs[@]}"; do
    require_aarch64_elf "$sdk/$relative"
done

native_build_tools=(aapt aapt2 aidl dexdump split-select zipalign)
for name in "${native_build_tools[@]}"; do
    path="$sdk/build-tools/$SDK_BUILD_TOOLS_VERSION/$name"
    readelf -l "$path" |
        grep -Fq 'Requesting program interpreter: /lib/ld-linux-aarch64.so.1' ||
        die "$path is not linked for GNU/glibc AArch64"
    if readelf -d "$path" | grep -q 'libc_musl'; then
        die "$path unexpectedly depends on musl"
    fi
done

while IFS= read -r -d '' path; do
    relative="${path#"$sdk/"}"
    kind="$(file -b "$path")"
    [[ "$kind" == ELF* && "$kind" == *x86-64* ]] || continue
    case "/$relative/" in
        */renderscript/lib/*/x86_64/*|\
        */ndk/*/simpleperf/bin/android/x86_64/*|\
        */ndk/*/toolchains/llvm/prebuilt/linux-aarch64/lib/x86_64-unknown-linux-musl/*|\
        */ndk/*/toolchains/llvm/prebuilt/linux-aarch64/lib/clang/*/lib/x86_64-unknown-linux-musl/*|\
        */ndk/*/toolchains/llvm/prebuilt/linux-aarch64/sysroot/usr/lib/x86_64-linux-android/*|\
        */ndk/*/toolchains/llvm/prebuilt/linux-aarch64/lib/clang/*/lib/linux/*x86_64*|\
        */ndk/*/toolchains/llvm/prebuilt/linux-aarch64/musl/lib/x86_64-unknown-linux-musl/*) ;;
        *) die "x86_64 ELF remains in a host position: $relative" ;;
    esac
done < <(find "$sdk" -type f -print0)

reference="${REFERENCE_DIR:-/mnt/develop/android/sdk}"
if [[ -d "$reference" ]]; then
    compare_args=()
    [[ -d "$sdk/ndk/$SDK_NDK_VERSION" ]] || compare_args+=(--without-ndk)
    "$script_dir/compare-reference-layout.py" "${compare_args[@]}" "$reference" "$sdk"
fi

runner=()
case "$(uname -m)" in
    aarch64|arm64) ;;
    *)
        command -v qemu-aarch64 >/dev/null || die "qemu-aarch64 is required on a non-AArch64 host"
        if [[ -e "$cache_dir/runtime-sysroot/usr/lib/ld-linux-aarch64.so.1" ]]; then
            runner=(qemu-aarch64 -L "$cache_dir/runtime-sysroot")
        elif [[ -e /lib/aarch64-linux-gnu/ld-linux-aarch64.so.1 ]]; then
            runner=(qemu-aarch64 -L /)
        elif [[ -e /usr/aarch64-linux-gnu/lib/ld-linux-aarch64.so.1 ]]; then
            runner=(qemu-aarch64 -L /usr/aarch64-linux-gnu)
        else
            die "no AArch64 runtime sysroot is available"
        fi
        ;;
esac

run_arm64() {
    "${runner[@]}" "$@"
}

print_first_line() {
    local output="$1"
    printf '%s\n' "${output%%$'\n'*}"
}

print_first_line "$(run_arm64 "$sdk/cmake/3.22.1/bin/cmake" --version)"
run_arm64 "$sdk/cmake/3.22.1/bin/ninja" --version
print_first_line "$(run_arm64 "$sdk/cmake/4.1.2/bin/cmake" --version)"
run_arm64 "$sdk/cmake/4.1.2/bin/ninja" --version
run_arm64 "$sdk/build-tools/36.0.0/aapt2" version
run_arm64 "$sdk/build-tools/36.0.0/aapt" version
run_arm64 "$sdk/build-tools/36.0.0/aidl" --help >/dev/null 2>&1
run_arm64 "$sdk/build-tools/36.0.0/split-select" --help >/dev/null 2>&1
run_arm64 "$sdk/platform-tools/adb" version

probe="$(mktemp -d)"
known_packages="$sdk/.knownPackages"
known_packages_backup="$probe/.knownPackages.before"
known_packages_existed=0
if [[ -e "$known_packages" || -L "$known_packages" ]]; then
    cp -a -- "$known_packages" "$known_packages_backup"
    known_packages_existed=1
fi
cleanup_probe() {
    rm -f -- "$known_packages"
    if (( known_packages_existed )); then
        cp -a -- "$known_packages_backup" "$known_packages"
    fi
    rm -rf -- "$probe"
}
trap cleanup_probe EXIT
mkdir -p -- "$probe/res/values" "$probe/compiled" "$probe/dex"
printf '%s\n' '<resources><string name="app_name">SDK probe</string></resources>' > \
    "$probe/res/values/strings.xml"
printf '%s\n' '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="dev.sdk.probe"><application android:label="@string/app_name"/></manifest>' > \
    "$probe/AndroidManifest.xml"
run_arm64 "$sdk/build-tools/36.0.0/aapt2" compile --dir "$probe/res" \
    -o "$probe/compiled/resources.zip"
run_arm64 "$sdk/build-tools/36.0.0/aapt2" link \
    -I "$sdk/platforms/android-36/android.jar" \
    --manifest "$probe/AndroidManifest.xml" \
    -o "$probe/probe.apk" "$probe/compiled/resources.zip"
unzip -t "$probe/probe.apk" >/dev/null

mkdir -p -- "$probe/aidl-src/dev/sdk/probe" "$probe/aidl-out"
printf '%s\n' 'package dev.sdk.probe; interface IProbe { void ping(); }' > \
    "$probe/aidl-src/dev/sdk/probe/IProbe.aidl"
run_arm64 "$sdk/build-tools/36.0.0/aidl" --lang=java \
    --include="$probe/aidl-src" --out="$probe/aidl-out" \
    "$probe/aidl-src/dev/sdk/probe/IProbe.aidl"
[[ -f "$probe/aidl-out/dev/sdk/probe/IProbe.java" ]] ||
    die "aidl did not generate the expected Java source"

mkdir -p -- "$probe/zip-input"
printf '%s\n' probe > "$probe/zip-input/probe.txt"
(cd "$probe/zip-input" && zip -q "$probe/input.zip" probe.txt)
run_arm64 "$sdk/build-tools/36.0.0/zipalign" -f 4 \
    "$probe/input.zip" "$probe/aligned.zip"
run_arm64 "$sdk/build-tools/36.0.0/zipalign" -c 4 "$probe/aligned.zip"

"$sdk/build-tools/36.0.0/apksigner" version
"$sdk/build-tools/36.0.0/d8" --version
mkdir -p -- "$probe/java-src/dev/sdk/probe" "$probe/java-classes"
printf '%s\n' \
    'package dev.sdk.probe; public final class Probe { public static void ping() {} }' > \
    "$probe/java-src/dev/sdk/probe/Probe.java"
javac --release 8 -Xlint:-options -d "$probe/java-classes" \
    "$probe/java-src/dev/sdk/probe/Probe.java"
"$sdk/build-tools/36.0.0/d8" --output "$probe/dex" \
    "$probe/java-classes/dev/sdk/probe/Probe.class"
run_arm64 "$sdk/build-tools/36.0.0/dexdump" "$probe/dex/classes.dex" >/dev/null
"$sdk/cmdline-tools/latest/bin/lint" --version

installed_packages="$probe/installed-packages.txt"
"$sdk/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$sdk" --list_installed > \
    "$installed_packages"
for package in build-tools\;36.0.0 cmake\;3.22.1 cmake\;4.1.2 \
    platform-tools platforms\;android-36; do
    grep -Fq "$package" "$installed_packages" || die "sdkmanager did not recognize $package"
done
if [[ -d "$sdk/ndk/$SDK_NDK_VERSION" ]]; then
    grep -Fq "ndk;$SDK_NDK_VERSION" "$installed_packages" ||
        die "sdkmanager did not recognize ndk;$SDK_NDK_VERSION"
fi

if "$sdk/cmdline-tools/latest/bin/android" >/dev/null 2>&1; then
    die "offline android launcher unexpectedly succeeded"
fi

archive="$dist_dir/android-sdk-linux.zip"
[[ -d "$sdk/ndk/$SDK_NDK_VERSION" ]] ||
    archive="$dist_dir/android-sdk-linux-without-ndk.zip"
unzip -t "$archive" >/dev/null
cleanup_probe
trap - EXIT

echo "Validated fixed Android SDK layout and Linux AArch64 host architecture."
echo "Known exclusions: four deprecated RenderScript host shared libraries."
