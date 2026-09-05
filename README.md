# Android SDK 36 for Linux AArch64

This project assembles a fixed Android SDK for Ubuntu 26.04 AArch64. Its
version set mirrors `/mnt/develop/android/sdk`:

- Build-Tools 36.0.0
- Platform android-36 revision 2
- Command-line Tools 22.0
- CMake 3.22.1 with Ninja 1.10.2
- CMake 4.1.2 with Ninja 1.12.1
- Platform-Tools 37.0.1 package layout, rebuilt from the locked public 37.0.0
  source line
- NDK 27.3.13750724 (r27d)

The assembled directory is `dist/sdk`. The final archive is
`dist/android-sdk-linux.zip` and has one top-level `sdk/` directory.
Sorted paths, stripped ZIP extra fields, and a fixed
`2008-01-01 00:00:00 UTC` timestamp make packaging reproducible for unchanged
assembled content.

The installed SDK is fixed and offline-capable: assembly does not invoke
`sdkmanager`, and consumers do not need it to download or update components.

## Repository dependencies

This repository is the integration layer. NDK and Platform-Tools are built and
released by their own repositories; this project downloads their latest
published full Release archives and combines them with the remaining fixed SDK
components:

```text
android-ndk-r27d-linux-aarch64 release ---------+
                                                 |
platform-tools_r37.0.1-linux-aarch64 release ---+--> android-sdk-linux.zip
                                                 |
Google SDK archives + Kitware CMake + Ninja -----+
                                                 |
embedded Build-Tools 36 source ------------------+
```

`sources.lock` fixes the component source versions, producer repositories, and
expected asset names:

- The latest full Release of the Platform-Tools producer is installed as
  `platform-tools/`, while the package/source boundary stays 37.0.1/37.0.0.
- The latest full Release of the NDK producer is installed as
  `ndk/27.3.13750724/`, while the source version stays r27d.
- Google SDK, Kitware CMake, and Ninja upstream archives with fixed versions
  and checksums for the other SDK components.

For each producer, the build resolves latest once and downloads the ZIP and its
`.sha256` from that same Release. The Release tag is a producer build-script
revision, not an Android component version. The SDK build does not clone or
rebuild either standalone repository, and there is no cyclic dependency. To
integrate a producer fix:

1. Build, validate, and publish the corresponding standalone project.
2. Run a clean SDK build; it selects the newly published latest Release.
3. Validate the complete SDK before publishing its Release.

## Build on Ubuntu 26.04

```bash
./scripts/resolute-install-deps.sh
./scripts/resolute-local-build.sh
```

The build entry runs an NDK consumer preflight **after downloading and before
building Ninja or Build-Tools**. It checks both exact CMake versions, three
Android configuration routes (legacy, non-legacy, native), C/C++ linking,
ndk-build's four target ABIs, compressed debugger host discovery, shell
launchers, and Simpleperf's default library lookup with packaged AArch64 Python.
Debugger tests also verify the archive-relative NDK root, real Make-variable
lookup, API parsing, and main-flow lldb-server selection before device writes
(with simulated device replies, not a real debugging session).
An older producer Release missing these fixes fails here, not after a long
SDK build. Publish the fixed standalone NDK first, then build this SDK.

```bash
# Download once and run the early gate, without building SDK components:
./scripts/resolute-local-build.sh --preflight-only
# With already downloaded dependencies, test a local producer candidate:
bash scripts/preflight-ndk.sh /path/to/android-ndk-r27d
```

The optional local path is diagnostic only; it cannot replace the
checksum-verified Release archive used by final layout/provenance validation.
Preflight combines Google's modules with the exact Kitware AArch64 CMake
binary, using host Ninja. Final validation repeats with the assembled SDK's
own CMake **and Ninja**, so preflight does not stand in for artifact testing.

Project policy requires every local build and validation run to use all
processors reported by `nproc`. Do not set `JOBS=4` locally to imitate the
hosted workflow; the shared build entry rejects a smaller local `JOBS` value.
`JOBS` is reserved for CI, and GitHub Actions explicitly sets `JOBS=4` for
the free hosted runner.

The build entry rejects hosts other than Ubuntu 26.04 unless
`ALLOW_UNSUPPORTED_HOST=1` is explicitly set.

The complete file, link, content, and normalized permission comparison always
constructs a fresh x86_64 reference tree from checksum-pinned Google archives.
Set `REFERENCE_DIR` only to explicitly select an existing official x86_64 SDK
tree. The validator rejects an AArch64, incomplete, bytecode-contaminated, or
self-referential reference tree; reference validation is never silently
skipped.

Validation also structurally parses every NDK host ELF position, checks every
host ELF's package-local SONAME dependency closure, verifies the pinned member
inventory and relocatable-object (`ET_REL`) structure of all NDK host static
libraries, loads each host C++ runtime independently, and verifies that
compiler-rt does not depend on a
system `libstdc++.so`. It then uses the packaged Clang and LLD to link a C
executable and C++ shared library for `aarch64-linux-android21`. These checks
verify the downloaded producer artifact again after it has been integrated
into the complete SDK. The SDK-level gate also checks every explicit
Build-Tools, CMake, Ninja, and Platform-Tools host ELF against the permitted
GNU/Linux runtime dependency set (excluding system `libgcc_s.so.1`), verifies
component libc++ SONAMEs, and loads all component libc++ runtimes independently.
SDK-generated host wrapper scripts must exactly match their checked-in
templates, while the thirteen patched NDK host script/archive files must remain byte-identical
to the checksum-verified NDK archive from the selected latest full Release.
The NDK's four CPython configuration files and all compiler-rt `*.syms` files
are also compared byte-for-byte with that selected archive. SDK-generated
package metadata must match its checked-in template exactly, and the
Platform-Tools `package.xml` must match the selected Platform-Tools Release.
Before any Release content is used as a comparison anchor, the SDK validator
rechecks both cached community archives against their downloaded checksum
assets; ambient environment variables cannot redirect those anchors.

The shared consumer contract is `tests/ndk_entrypoints_test.py`, kept identical
to the standalone NDK repository. The SDK does not repatch the producer or
modify Google's CMake modules; the NDK's post-Android-Determine hook provides
the native/non-legacy fix. On x86_64, QEMU/binfmt and the AArch64 runtime sysroot
are required. Only uname identity is simulated for host shell/CMake processes;
there are no forced `HOST_ARCH`/`ANDROID_HOST_TAG` values. Passing this suite
does not establish native AArch64 device/debugger or arbitrary Gradle coverage.

## Recommended environment

After extracting or installing the generated `sdk/` directory at
`/mnt/develop/android/sdk`, add the fixed SDK to your shell environment:

```bash
echo 'export ANDROID_HOME=/mnt/develop/android/sdk' >> ~/.bashrc
echo 'export PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools' >> ~/.bashrc
source ~/.bashrc
```

Single quotes are intentional: `$PATH` and `$ANDROID_HOME` should be expanded
when a shell reads `.bashrc`, not when the lines are appended.

## GitHub release

Pushing a version tag runs the Ubuntu 26.04 workflow in
`.github/workflows/release.yml`. It builds with four jobs, validates the SDK and
archive, then creates or updates the matching GitHub Release with these assets:

- `android-sdk-linux.zip`
- `android-sdk-linux.zip.sha256`

After the project files have been committed, create and push the next release
tag (replace `vX.Y.Z` with the intended version):

```bash
git tag vX.Y.Z
git push origin vX.Y.Z
```

Release publishing uses the repository's built-in `GITHUB_TOKEN`; no additional
secret is required.

## Build-Tools source model

The six native Build-Tools programs `aapt`, `aapt2`, `aidl`, `dexdump`,
`split-select`, and `zipalign` are built from the self-contained source tree in
[`build-tools/`](build-tools/README.md). This is a normal CMake/Ninja GNU/Linux
cross build using Ubuntu's `aarch64-linux-gnu-gcc/g++` and glibc sysroot. The six
programs statically link their C++ compiler runtime and zlib instead of relying
on the host's `libstdc++.so` or `libz.so`. Build-Tools independently creates and
carries its own LLVM 22 `lib64/libc++.so` and `libc++.so.1` compatibility
entries; it does not reuse the Platform-Tools copy. `$ORIGIN/lib64` remains the
component-local shared-library search path, matching Google's package model.

The build does not clone AOSP, run Soong, build Bionic, download an external
standalone-build framework, or apply a patch series. The trimmed Android 16
source snapshot and its required shared dependencies are part of this project;
all GNU/glibc compatibility changes and generated parser/protobuf sources are
already incorporated.

## Component provenance and limits

- Architecture-independent files come from checksum-pinned Google SDK
  archives. Their six x86_64 Build-Tools executables are replaced by the local
  AArch64 source build.
- CMake comes from matching Kitware AArch64 releases. Ninja 1.10.2 and 1.12.1
  are cross-built from their pinned sources with the C++ runtime linked
  statically, avoiding the system `libstdc++.so.6` dependency just as Google's
  Linux x86_64 package does.
- Platform-Tools comes from the latest full Release of
  `kaspersigi/platform-tools_r37.0.1-linux-aarch64`. Google publishes the
  37.0.1 binary package, but the locked public source line is 37.0.0; the
  community AArch64 `adb` and `fastboot` binaries therefore report 37.0.0.
- NDK comes from the latest full Release of
  `kaspersigi/android-ndk-r27d-linux-aarch64` and remains locked to revision
  `27.3.13750724` (r27d).

Google does not publish the Command-line Tools 22 `android` bootstrapper for
Linux AArch64. It is an online self-updater, so this fixed SDK replaces it with
an explicit offline notice. Java tools such as `sdkmanager`, `avdmanager`,
`lint`, `apkanalyzer`, `d8`, and `r8` remain intact.

Build-Tools 36 still contains deprecated RenderScript host entries. The two
command entry points are explicit unsupported stubs, and four RenderScript-only
shared libraries are omitted. RenderScript target libraries under ABI-named
directories remain byte-for-byte identical to Google's package.

The official x86_64 Build-Tools 36 package includes LLD 9.0.7. This SDK does not
build that legacy LLVM tree: `build-tools/36.0.0/lld-bin/lld` is an explicit
wrapper around the pinned NDK r27d LLD 18.0.4. That linker is validated during
the SDK build and is the linker used by the supported NDK workflow.

## License

Repository-owned code is licensed under the Apache License 2.0; see
[`LICENSE`](LICENSE) and [`NOTICE`](NOTICE). Embedded and packaged upstream
components retain their original license and notice files at their
corresponding paths.
