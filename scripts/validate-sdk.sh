#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"

sdk="${1:-$dist_dir/sdk}"
[[ -d "$sdk" ]] || die "SDK directory does not exist: $sdk"
sdk="$(realpath -e -- "$sdk")"
reference="${REFERENCE_DIR:-$build_dir/reference-sdk}"
[[ -d "$reference" ]] || die "SDK reference directory does not exist: $reference"
reference="$(realpath -e -- "$reference")"
[[ "$reference" != "$sdk" ]] ||
    die "SDK reference and candidate resolve to the same directory: $sdk"

verify_cached_release_archive "$PLATFORM_TOOLS_RELEASE_ASSET"
verify_cached_release_archive "$NDK_RELEASE_ASSET"

[[ -d "$sdk/ndk/$SDK_NDK_VERSION" ]] ||
    die "SDK does not contain the required NDK $SDK_NDK_VERSION"

require_x86_64_reference_elf() {
    local path="$1" kind
    [[ -f "$path" ]] || die "required x86_64 reference file is missing: $path"
    kind="$(file -b -- "$path")"
    [[ "$kind" == ELF* && "$kind" == *x86-64* ]] ||
        die "SDK reference is not the official Linux x86_64 layout: $path: $kind"
}

for relative in \
    build-tools/36.0.0/aapt \
    cmake/3.22.1/bin/cmake \
    cmake/4.1.2/bin/cmake \
    cmdline-tools/latest/bin/android \
    platform-tools/adb; do
    require_x86_64_reference_elf "$reference/$relative"
done

reference_ndk="$reference/ndk/$SDK_NDK_VERSION"
reference_ndk_x86_64_roots=(
    toolchains/llvm/prebuilt/linux-x86_64
    prebuilt/linux-x86_64
    shader-tools/linux-x86_64
    simpleperf/bin/linux/x86_64
)
reference_ndk_aarch64_roots=(
    toolchains/llvm/prebuilt/linux-aarch64
    prebuilt/linux-aarch64
    shader-tools/linux-aarch64
    simpleperf/bin/linux/aarch64
)
for relative in "${reference_ndk_x86_64_roots[@]}"; do
    [[ -d "$reference_ndk/$relative" ]] ||
        die "SDK reference is missing the Linux x86_64 NDK host root: $relative"
done
for relative in "${reference_ndk_aarch64_roots[@]}"; do
    [[ ! -e "$reference_ndk/$relative" && ! -L "$reference_ndk/$relative" ]] ||
        die "SDK reference unexpectedly contains a Linux AArch64 NDK host root: $relative"
done

expected_reference_entries=31095
if [[ -e "$reference/.knownPackages" || -L "$reference/.knownPackages" ]]; then
    [[ -f "$reference/.knownPackages" && ! -L "$reference/.knownPackages" ]] ||
        die "SDK reference .knownPackages entry is not a regular file"
    ((expected_reference_entries += 1))
fi
actual_reference_entries=$(find "$reference" -mindepth 1 -printf . | wc -c)
[[ "$actual_reference_entries" == "$expected_reference_entries" ]] ||
    die "SDK reference entry count mismatch: expected $expected_reference_entries, got $actual_reference_entries"
! find "$reference" -type f \( -name '*.pyc' -o -name '*.pyo' \) \
    -print -quit | grep -q . || die "SDK reference contains generated Python bytecode"
! find "$reference" -type d -name __pycache__ -not -empty \
    -print -quit | grep -q . || die "SDK reference contains a non-empty Python cache directory"

archive="$dist_dir/android-sdk-linux.zip"
checksum="$archive.sha256"
[[ -f "$archive" ]] || die "SDK archive does not exist: $archive"
[[ -f "$checksum" ]] || die "SDK archive checksum does not exist: $checksum"
(
    cd "$(dirname -- "$archive")"
    sha256sum --check "$(basename -- "$checksum")"
)
python3 -B "$project_root/scripts/check-zip-metadata.py" "$archive"

python3 -B "$project_root/tests/compare_reference_layout_test.py"
"$project_root/tests/check-aarch64-elf-test.sh"
"$project_root/tests/check-aarch64-host-archives-test.sh"

grep -Fqx "Pkg.Revision=$SDK_BUILD_TOOLS_VERSION" \
    "$sdk/build-tools/$SDK_BUILD_TOOLS_VERSION/source.properties"
grep -Fqx "Pkg.Revision=$SDK_PLATFORM_TOOLS_VERSION" \
    "$sdk/platform-tools/source.properties"
grep -Fqx "Pkg.Revision=$SDK_CMDLINE_TOOLS_VERSION" \
    "$sdk/cmdline-tools/latest/source.properties"
grep -Fqx 'Pkg.Revision = 3.22.1' "$sdk/cmake/3.22.1/source.properties"
grep -Fqx 'Pkg.Revision = 4.1.2' "$sdk/cmake/4.1.2/source.properties"

ndk="$sdk/ndk/$SDK_NDK_VERSION"
ndk_toolchain="$ndk/toolchains/llvm/prebuilt/linux-aarch64"
ndk_agp_toolchain="$ndk/toolchains/llvm/prebuilt/linux-x86_64"
[[ -L "$ndk_agp_toolchain" && "$(readlink -- "$ndk_agp_toolchain")" == linux-aarch64 ]] ||
    die "missing or incorrect AGP NDK compatibility link"
for tool in llvm-strip llvm-objcopy; do
    require_aarch64_elf "$ndk_agp_toolchain/bin/$tool"
done
ndk_host_runtime_dir="$ndk_toolchain/lib/aarch64-unknown-linux-gnu"
ndk_compiler_rt_dir="$ndk_toolchain/lib/clang/18/lib/aarch64-unknown-linux-gnu"
declare -A ndk_packaged_host_sonames=()
ndk_host_elf_count=0

validate_ndk_host_elf() {
    local path="$1"
    case "$path" in
        "$ndk_compiler_rt_dir/clang_rt.crtbegin.o"|\
        "$ndk_compiler_rt_dir/clang_rt.crtend.o")
            "$project_root/scripts/check-aarch64-elf.sh" \
                --allow-relocatable "$path"
            ;;
        *)
            require_aarch64_elf "$path"
            ;;
    esac
}

register_ndk_packaged_host_sonames() {
    local root="$1" scope="$2" path kind soname dynamic_section
    local -a find_args=("$root")

    [[ -d "$root" ]] || die "required NDK host directory is missing: $root"
    if [[ "$scope" == "shallow" ]]; then
        find_args+=(-maxdepth 1)
    fi
    while IFS= read -r -d '' path; do
        kind="$(file -b -- "$path")"
        [[ "$kind" == ELF* ]] || continue
        validate_ndk_host_elf "$path"
        dynamic_section="$(read_elf_dynamic_section "$path")" ||
            die "cannot read NDK host ELF dynamic section: $path"
        soname="$(sed -n 's/.*Library soname: \[\([^]]*\)\].*/\1/p' \
            <<< "$dynamic_section")"
        if [[ -n "$soname" ]]; then
            ndk_packaged_host_sonames["$soname"]="$path"
        fi
    done < <(find "${find_args[@]}" -type f -print0)
}

check_ndk_host_dependency_closure() {
    local path="$1" dependency dynamic_section
    local nis_extension="$ndk_toolchain/python3/lib/python3.11/lib-dynload/nis.cpython-311-aarch64-linux-gnu.so"

    dynamic_section="$(read_elf_dynamic_section "$path")" ||
        die "cannot read NDK host ELF dynamic section: $path"

    while IFS= read -r dependency; do
        case "$dependency" in
            libc.so.6|libm.so.6|libdl.so.2|libpthread.so.0|librt.so.1|ld-linux-aarch64.so.1)
                ;;
            libnsl.so.1)
                [[ "$path" == "$nis_extension" ]] ||
                    die "unexpected external shared-library dependency in $path: $dependency"
                ;;
            libgcc_s.so.1)
                [[ "$path" == "$ndk_compiler_rt_dir/"* ]] ||
                    die "unexpected external shared-library dependency in $path: $dependency"
                ;;
            *)
                [[ ${ndk_packaged_host_sonames[$dependency]+present} ]] ||
                    die "NDK host ELF depends on an unpackaged shared library in $path: $dependency"
                ;;
        esac
    done < <(sed -n 's/.*Shared library: \[\([^]]*\)\].*/\1/p' \
        <<< "$dynamic_section")
}

check_ndk_runtime_needed_libraries() {
    local path="$1" allow_libgcc="$2" dependency dynamic_section

    require_aarch64_elf "$path"
    dynamic_section="$(read_elf_dynamic_section "$path")" ||
        die "cannot read NDK runtime dynamic section: $path"

    while IFS= read -r dependency; do
        case "$dependency" in
            libc.so.6|libm.so.6|libdl.so.2|libpthread.so.0|librt.so.1|ld-linux-aarch64.so.1)
                ;;
            libgcc_s.so.1)
                [[ "$allow_libgcc" == 1 ]] ||
                    die "unexpected external shared-library dependency in $path: $dependency"
                ;;
            *)
                die "unexpected shared-library dependency in NDK runtime $path: $dependency"
                ;;
        esac
    done < <(sed -n 's/.*Shared library: \[\([^]]*\)\].*/\1/p' \
        <<< "$dynamic_section")
}

scan_ndk_host_elfs() {
    local root="$1" scope="$2" path kind
    local -a find_args=("$root")

    [[ -d "$root" ]] || die "required NDK host directory is missing: $root"
    if [[ "$scope" == "shallow" ]]; then
        find_args+=(-maxdepth 1)
    fi
    while IFS= read -r -d '' path; do
        kind="$(file -b -- "$path")"
        [[ "$kind" == ELF* ]] || continue
        check_ndk_host_dependency_closure "$path"
        ((ndk_host_elf_count += 1))
    done < <(find "${find_args[@]}" -type f -print0)
}

check_sdk_host_needed_libraries() {
    local path="$1" dependency dynamic_section

    dynamic_section="$(read_elf_dynamic_section "$path")" ||
        die "cannot read SDK host ELF dynamic section: $path"

    while IFS= read -r dependency; do
        case "$dependency" in
            libc.so.6|libm.so.6|libdl.so.2|libpthread.so.0|librt.so.1|ld-linux-aarch64.so.1)
                ;;
            *)
                die "unexpected external shared-library dependency in $path: $dependency"
                ;;
        esac
    done < <(sed -n 's/.*Shared library: \[\([^]]*\)\].*/\1/p' \
        <<< "$dynamic_section")
}

grep -Fqx "Pkg.Revision = $SDK_NDK_VERSION" \
    "$ndk/source.properties" ||
    die "NDK does not report pinned revision $SDK_NDK_VERSION"
grep -Fqx 'Pkg.ReleaseName = r27d' \
    "$ndk/source.properties" ||
    die "NDK does not report pinned release name r27d"

ndk_recursive_host_roots=(
    "$ndk_toolchain/bin"
    "$ndk_toolchain/python3"
    "$ndk_toolchain/lib/python3.11"
    "$ndk/prebuilt/linux-aarch64/bin"
    "$ndk/shader-tools/linux-aarch64"
    "$ndk/simpleperf/bin/linux/aarch64"
)
ndk_shallow_host_roots=(
    "$ndk_toolchain/lib"
    "$ndk_host_runtime_dir"
    "$ndk_compiler_rt_dir"
    "$ndk_toolchain/musl/lib"
)
for root in "${ndk_recursive_host_roots[@]}"; do
    register_ndk_packaged_host_sonames "$root" recursive
done
for root in "${ndk_shallow_host_roots[@]}"; do
    register_ndk_packaged_host_sonames "$root" shallow
done
for root in "${ndk_recursive_host_roots[@]}"; do
    scan_ndk_host_elfs "$root" recursive
done
for root in "${ndk_shallow_host_roots[@]}"; do
    scan_ndk_host_elfs "$root" shallow
done
(( ndk_host_elf_count > 0 )) || die "no NDK host ELF files were found"
echo "ndk_packaged_host_sonames=${#ndk_packaged_host_sonames[@]}"
echo "ndk_aarch64_host_elfs=$ndk_host_elf_count"

"$project_root/scripts/check-aarch64-host-archives.sh" "$ndk"

for name in libc++.so libc++abi.so libunwind.so; do
    runtime="$ndk_host_runtime_dir/$name"
    [[ -f "$runtime" ]] || die "required NDK host runtime is missing: $runtime"
    dynamic_section="$(read_elf_dynamic_section "$runtime")" ||
        die "cannot read NDK host runtime dynamic section: $runtime"
    grep -Fq "Library soname: [$name]" <<< "$dynamic_section" ||
        die "NDK host runtime has an unexpected SONAME: $runtime"
    check_ndk_runtime_needed_libraries "$runtime" 0
done

ndk_compiler_rt_shared_count=0
while IFS= read -r -d '' runtime; do
    check_ndk_runtime_needed_libraries "$runtime" 1
    ((ndk_compiler_rt_shared_count += 1))
done < <(find "$ndk_compiler_rt_dir" -maxdepth 1 -type f -name '*.so' -print0)
(( ndk_compiler_rt_shared_count > 0 )) ||
    die "no NDK compiler-rt shared libraries were found"
echo "ndk_compiler_rt_shared_libraries=$ndk_compiler_rt_shared_count"

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
    check_sdk_host_needed_libraries "$sdk/$relative"
done

dynamic_section="$(read_elf_dynamic_section \
    "$sdk/build-tools/$SDK_BUILD_TOOLS_VERSION/lib64/libc++.so")" ||
    die "cannot read Build-Tools libc++.so dynamic section"
grep -Fq 'Library soname: [libc++.so]' <<< "$dynamic_section" ||
    die "Build-Tools libc++.so has an unexpected SONAME"
dynamic_section="$(read_elf_dynamic_section \
    "$sdk/build-tools/$SDK_BUILD_TOOLS_VERSION/lib64/libc++.so.1")" ||
    die "cannot read Build-Tools libc++.so.1 dynamic section"
grep -Fq 'Library soname: [libc++.so.1]' <<< "$dynamic_section" ||
    die "Build-Tools libc++.so.1 has an unexpected SONAME"
dynamic_section="$(read_elf_dynamic_section \
    "$sdk/platform-tools/lib64/libc++.so")" ||
    die "cannot read Platform-Tools libc++.so dynamic section"
grep -Fq 'Library soname: [libc++.so]' <<< "$dynamic_section" ||
    die "Platform-Tools libc++.so has an unexpected SONAME"

native_build_tools=(aapt aapt2 aidl dexdump split-select zipalign)
for name in "${native_build_tools[@]}"; do
    path="$sdk/build-tools/$SDK_BUILD_TOOLS_VERSION/$name"
    program_headers="$(read_elf_program_headers "$path")" ||
        die "cannot read program headers from $path"
    dynamic_section="$(read_elf_dynamic_section "$path")" ||
        die "cannot read dynamic section from $path"
    grep -Fq 'Requesting program interpreter: /lib/ld-linux-aarch64.so.1' \
        <<< "$program_headers" ||
        die "$path is not linked for GNU/glibc AArch64"
    if grep -q 'libc_musl' <<< "$dynamic_section"; then
        die "$path unexpectedly depends on musl"
    fi
    if grep -Eq 'Shared library: \[(libstdc\+\+\.so|libgcc_s\.so|libz\.so|libc\+\+abi\.so|libunwind\.so)' \
        <<< "$dynamic_section"; then
        die "$path depends on an unpackaged compiler, C++ or zlib runtime"
    fi
    grep -Fq 'Library runpath: [$ORIGIN/lib64]' <<< "$dynamic_section" ||
        die "$path does not resolve libc++.so relative to Build-Tools"
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

"$script_dir/compare-reference-layout.py" "$reference" "$sdk"

runner=()
select_arm64_runtime
case "$(uname -m)" in
    aarch64|arm64) ;;
    *)
        runner=(qemu-aarch64 -L "$QEMU_LD_PREFIX")
        ;;
esac

run_arm64() {
    "${runner[@]}" "$@"
}

for name in libc++.so libc++abi.so libunwind.so; do
    run_arm64 "$ndk_toolchain/python3/bin/python3.11" -c \
        'import ctypes, sys; ctypes.CDLL(sys.argv[1])' \
        "$ndk_host_runtime_dir/$name"
done
for runtime in \
    "$sdk/build-tools/$SDK_BUILD_TOOLS_VERSION/lib64/libc++.so" \
    "$sdk/build-tools/$SDK_BUILD_TOOLS_VERSION/lib64/libc++.so.1" \
    "$sdk/platform-tools/lib64/libc++.so"; do
    run_arm64 "$ndk_toolchain/python3/bin/python3.11" -c \
        'import ctypes, sys; ctypes.CDLL(sys.argv[1])' "$runtime"
done

print_first_line() {
    local output="$1"
    printf '%s\n' "${output%%$'\n'*}"
}

print_first_line "$(run_arm64 "$sdk/cmake/3.22.1/bin/cmake" --version)"
run_arm64 "$sdk/cmake/3.22.1/bin/ninja" --version
print_first_line "$(run_arm64 "$sdk/cmake/4.1.2/bin/cmake" --version)"
run_arm64 "$sdk/cmake/4.1.2/bin/ninja" --version
python3 -B "$project_root/tests/ndk_entrypoints_test.py" --ndk "$ndk" --runtime \
    --cmake "$sdk/cmake/3.22.1/bin/cmake" --cmake "$sdk/cmake/4.1.2/bin/cmake"
run_arm64 "$sdk/build-tools/36.0.0/aapt2" version
run_arm64 "$sdk/build-tools/36.0.0/aapt" version
run_arm64 "$sdk/build-tools/36.0.0/aidl" --help >/dev/null 2>&1
run_arm64 "$sdk/build-tools/36.0.0/split-select" --help >/dev/null 2>&1
build_tools_lld_version="$("$sdk/build-tools/36.0.0/lld-bin/lld" \
    -flavor gnu --version)"
print_first_line "$build_tools_lld_version"
grep -Fq 'LLD 18.0.4' <<< "$build_tools_lld_version" ||
    die "Build-Tools LLD wrapper does not resolve to the pinned NDK r27d LLD"
platform_tools_version="$(run_arm64 "$sdk/platform-tools/adb" version)"
printf '%s\n' "$platform_tools_version"
grep -Fq "Version $SDK_PLATFORM_TOOLS_PUBLIC_SOURCE_VERSION-" \
    <<< "$platform_tools_version" ||
    die "adb does not report pinned public source version $SDK_PLATFORM_TOOLS_PUBLIC_SOURCE_VERSION"
fastboot_version="$(run_arm64 "$sdk/platform-tools/fastboot" --version)"
printf '%s\n' "$fastboot_version"
grep -Fq "fastboot version $SDK_PLATFORM_TOOLS_PUBLIC_SOURCE_VERSION-" \
    <<< "$fastboot_version" ||
    die "fastboot does not report pinned public source version $SDK_PLATFORM_TOOLS_PUBLIC_SOURCE_VERSION"

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

run_arm64 "$ndk_toolchain/bin/clang" --version
run_arm64 "$ndk_toolchain/bin/ld.lld" --version
printf '%s\n' 'int main(void) { return 0; }' > "$probe/ndk-smoke.c"
printf '%s\n' 'extern "C" int sdk_ndk_smoke() { return 0; }' > \
    "$probe/ndk-smoke.cpp"
run_arm64 "$ndk_toolchain/bin/clang" \
    --target=aarch64-linux-android21 \
    --sysroot="$ndk_toolchain/sysroot" \
    -fuse-ld=lld "$probe/ndk-smoke.c" -o "$probe/ndk-smoke"
run_arm64 "$ndk_toolchain/bin/clang++" \
    --target=aarch64-linux-android21 \
    --sysroot="$ndk_toolchain/sysroot" \
    -fuse-ld=lld -g -fPIC -shared -stdlib=libc++ -static-libstdc++ \
    "$probe/ndk-smoke.cpp" -o "$probe/libndk-smoke.so"
require_aarch64_elf "$probe/ndk-smoke"
require_aarch64_elf "$probe/libndk-smoke.so"

# Exercise the exact paths AGP uses for JNI stripping and debug metadata.
readelf -SW "$probe/libndk-smoke.so" > "$probe/ndk-sections.before"
grep -Fq '.debug_info' "$probe/ndk-sections.before" || die "NDK probe lacks debug info"
run_arm64 "$ndk_agp_toolchain/bin/llvm-strip" --strip-unneeded \
    -o "$probe/libndk-smoke-stripped.so" "$probe/libndk-smoke.so"
run_arm64 "$ndk_agp_toolchain/bin/llvm-objcopy" --only-keep-debug \
    "$probe/libndk-smoke.so" "$probe/libndk-smoke-debug.so"
require_aarch64_elf "$probe/libndk-smoke-stripped.so"
readelf -SW "$probe/libndk-smoke-stripped.so" > "$probe/ndk-sections.stripped"
! grep -Eq '\.(debug_info|symtab)[[:space:]]' "$probe/ndk-sections.stripped" ||
    die "AGP NDK strip path did not remove debug symbols"
readelf -SW "$probe/libndk-smoke-debug.so" > "$probe/ndk-sections.debug"
grep -Fq '.debug_info' "$probe/ndk-sections.debug" ||
    die "AGP NDK objcopy path did not preserve debug info"

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

cleanup_probe
trap - EXIT

archive_probe="$(mktemp -d)"
cleanup_archive_probe() {
    rm -rf -- "$archive_probe"
}
trap cleanup_archive_probe EXIT
unzip -t "$archive" >/dev/null
unzip -q "$archive" -d "$archive_probe"
mapfile -d '' -t archive_roots < <(
    find "$archive_probe" -mindepth 1 -maxdepth 1 -print0
)
if (( ${#archive_roots[@]} != 1 )) ||
   [[ "${archive_roots[0]}" != "$archive_probe/sdk" ]] ||
   [[ ! -d "$archive_probe/sdk" ]] || [[ -L "$archive_probe/sdk" ]]; then
    die "archive must contain exactly one top-level sdk/ directory"
fi
python3 "$script_dir/compare-extracted-tree.py" "$sdk" "$archive_probe/sdk"
cleanup_archive_probe
trap - EXIT

echo "Validated fixed Android SDK layout and Linux AArch64 host architecture."
echo "Known exclusions: four deprecated RenderScript host shared libraries."
