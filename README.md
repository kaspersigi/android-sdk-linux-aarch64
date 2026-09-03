# Android SDK 36 for Linux AArch64

This project assembles a fixed Android SDK for Ubuntu 26.04 AArch64. Its
version set mirrors `/mnt/develop/android/sdk`:

- Build-Tools 36.0.0
- Platform android-36 revision 2
- Command-line Tools 22.0
- CMake 3.22.1 with Ninja 1.10.2
- CMake 4.1.2 with Ninja 1.12.1
- Platform-Tools 37.0.1
- NDK 27.3.13750724 (r27d)

The assembled directory is `dist/sdk`. The final archive is
`dist/android-sdk-linux.zip` and has one top-level `sdk/` directory.
The installed SDK is fixed and offline-capable: assembly does not invoke
`sdkmanager`, and consumers do not need it to download or update components.

## Build on Ubuntu 26.04

```bash
./scripts/resolute-install-deps.sh
./scripts/resolute-local-build.sh
```

To omit the NDK while developing another component:

```bash
./scripts/resolute-local-build.sh --without-ndk
```

Local builds use `nproc` by default. CI can set `JOBS=4`.

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
- Platform-Tools comes from the checksum-pinned `v1.0.0` release of
  `kaspersigi/platform-tools_r37.0.1-linux-aarch64`.
- NDK comes from the checksum-pinned `v1.0.1` release of
  `kaspersigi/android-ndk-r27d-linux-aarch64` and reports revision
  `27.3.13750724`.

Google does not publish the Command-line Tools 22 `android` bootstrapper for
Linux AArch64. It is an online self-updater, so this fixed SDK replaces it with
an explicit offline notice. Java tools such as `sdkmanager`, `avdmanager`,
`lint`, `apkanalyzer`, `d8`, and `r8` remain intact.

Build-Tools 36 still contains deprecated RenderScript host entries. The two
command entry points are explicit unsupported stubs, and four RenderScript-only
shared libraries are omitted. RenderScript target libraries under ABI-named
directories remain byte-for-byte identical to Google's package.
