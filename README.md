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

To omit the NDK while developing another component:

```bash
./scripts/resolute-local-build.sh --without-ndk
```

Local builds use all processors reported by `nproc` unless `JOBS` is set.
GitHub Actions explicitly uses `JOBS=4` for the free hosted runner.
The build entry rejects hosts other than Ubuntu 26.04 unless
`ALLOW_UNSUPPORTED_HOST=1` is explicitly set.

The complete file, link, content, and normalized permission comparison always
constructs a fresh x86_64 reference tree from checksum-pinned Google archives.
Set `REFERENCE_DIR` only to explicitly select an existing official x86_64 SDK
tree. The validator rejects an AArch64, incomplete, bytecode-contaminated, or
self-referential reference tree; reference validation is never silently
skipped.

Validation also scans every NDK host ELF position for AArch64 binaries and
uses the packaged Clang and LLD to link a C executable and C++ shared library
for `aarch64-linux-android21`. This verifies the downloaded producer artifact
again after it has been integrated into the complete SDK.

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

The first release tag is `v1.0.0`. After the project files have been committed,
it can be created and pushed with:

```bash
git tag v1.0.0
git push origin v1.0.0
```

Release publishing uses the repository's built-in `GITHUB_TOKEN`; no additional
secret is required.

## Build-Tools source model

The six native Build-Tools programs `aapt`, `aapt2`, `aidl`, `dexdump`,
`split-select`, and `zipalign` are built from the self-contained source tree in
[`build-tools/`](build-tools/README.md). This is a normal CMake/Ninja GNU/Linux
cross build using Ubuntu's `aarch64-linux-gnu-gcc/g++` and glibc sysroot.

The build does not clone AOSP, run Soong, build Bionic, download an external
standalone-build framework, or apply a patch series. The trimmed Android 16
source snapshot and its required shared dependencies are part of this project;
all GNU/glibc compatibility changes and generated parser/protobuf sources are
already incorporated.

## Component provenance and limits

- Architecture-independent files come from checksum-pinned Google SDK
  archives. Their six x86_64 Build-Tools executables are replaced by the local
  AArch64 source build.
- CMake comes from matching Kitware AArch64 releases. Ninja 1.10.2 is
  cross-built from source; Ninja 1.12.1 uses its official AArch64 release.
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

## License

Repository-owned code is licensed under the Apache License 2.0; see
[`LICENSE`](LICENSE) and [`NOTICE`](NOTICE). Embedded and packaged upstream
components retain their original license and notice files at their
corresponding paths.
