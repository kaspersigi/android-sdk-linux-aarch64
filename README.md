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
Gradle consumers must also [select the AArch64 AAPT2 explicitly](#use-with-gradle-on-aarch64-required).

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
The SDK also adds one relative NDK toolchain alias for AGP, checked for its
exact link target and exercised with `llvm-strip` and `llvm-objcopy`.
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

## Use with Gradle on AArch64 (required)

This section concerns the Linux AArch64 machine running Gradle. The APK's
target ABI, such as `arm64-v8a`, does not determine the host tool architecture.
Use an AArch64 JDK 21 and this SDK on that machine.

Installing this SDK and setting `ANDROID_HOME` does not select its AAPT2 for
Android Gradle Plugin (AGP). AGP 9.3.2 defaults to the separate Google Maven
artifact `com.android.tools.build:aapt2:9.3.2-15703166:linux`, whose executable
is **x86_64**. Its platform selection distinguishes operating systems, not
Linux CPU architectures. Merely setting `buildToolsVersion` or adding the SDK
Build-Tools directory to `PATH` does not change that selection.

On an AArch64 host, this can produce `Syntax error: word unexpected
(expecting ")")` followed by `AAPT2 ... Daemon startup failed` during resource
processing. A path under `.gradle/caches/.../aapt2-...-linux/aapt2` identifies
the Maven executable; it is separate from this SDK's
`build-tools/36.0.0/aapt2`. The failure can occur after other build tasks have
completed because AAPT2 starts when resource processing needs it.

On the **AArch64 build machine**, first check the installed binary, then pass
AGP's executable override as a Gradle project property:

```bash
export ANDROID_HOME=/mnt/develop/android/sdk
file "$ANDROID_HOME/build-tools/36.0.0/aapt2"  # must report ARM aarch64
"$ANDROID_HOME/build-tools/36.0.0/aapt2" version

# Run from the Android project directory:
GRADLE_USER_HOME="$PWD/.gradle" ./gradlew --parallel --max-workers="$(nproc)" \
  "-Pandroid.aapt2FromMavenOverride=$ANDROID_HOME/build-tools/36.0.0/aapt2" \
  :app:assembleDebug
```

If `file` reports `x86-64`, select the installed AArch64 SDK before proceeding.
If the project has `local.properties`, its `sdk.dir` should point to the same
SDK as `ANDROID_HOME`.

For the application Makefiles listed below, the equivalent invocation is:

```bash
make GRADLE_FLAGS="--parallel --max-workers=$(nproc) -Pandroid.aapt2FromMavenOverride=$ANDROID_HOME/build-tools/36.0.0/aapt2"
```

For MySnapcam on a non-HWASan device, use `make no-asan-debug` with the same
`GRADLE_FLAGS`. Its JNI build also requires AArch64 host versions of NDK
`27.3.13750724`, CMake `4.1.2`, and Ninja; the AAPT2 override only selects AAPT2.

For persistent configuration, add or update this one entry in the
`gradle.properties` file **inside the Gradle user home actually used by the
build**, preserving other entries. Create the directory first if needed
(`mkdir -p .gradle` from the application project directory):

```properties
android.aapt2FromMavenOverride=/mnt/develop/android/sdk/build-tools/36.0.0/aapt2
```

For a first-time setup with no existing override entry, append it from the
application project directory. This example uses Camera; change the `cd`
path for another project. If the key already exists, edit its value instead
of appending a duplicate:

```bash
cd /mnt/develop/linux/Camera
mkdir -p .gradle
echo "android.aapt2FromMavenOverride=/mnt/develop/android/sdk/build-tools/36.0.0/aapt2" >> ".gradle/gradle.properties"
```

The file path uses ordinary double quotes, not backticks (which perform
shell command substitution). Replace the SDK path with its actual location.

Use the absolute installation path; `gradle.properties` does not expand
`$ANDROID_HOME` or `~`. All seven application Makefiles default to
`GRADLE_USER_HOME="$(CURDIR)/.gradle"`. Their machine-local configuration files
are therefore separate:

| Application project | Configuration file for its default Makefile invocation |
| --- | --- |
| Camera | `/mnt/develop/linux/Camera/.gradle/gradle.properties` |
| camera_tools/camera2 | `/mnt/develop/linux/camera_tools/camera2/.gradle/gradle.properties` |
| Camera2 | `/mnt/develop/linux/Camera2/.gradle/gradle.properties` |
| MyCamera | `/mnt/develop/linux/MyCamera/.gradle/gradle.properties` |
| MySnapcam | `/mnt/develop/linux/MySnapcam/.gradle/gradle.properties` |
| NoUI | `/mnt/develop/linux/NoUI/.gradle/gradle.properties` |
| OnlySnapshot | `/mnt/develop/linux/OnlySnapshot/.gradle/gradle.properties` |

Editing `~/.gradle/gradle.properties` alone does not affect these default
Makefile invocations. If you override `GRADLE_USER_HOME`, configure the file
in that directory instead. When calling the wrapper directly, explicitly
use the same user home to read the saved override:

```bash
GRADLE_USER_HOME="$PWD/.gradle" ./gradlew :app:assembleDebug
# MySnapcam on a non-HWASan device:
GRADLE_USER_HOME="$PWD/.gradle" ./gradlew :app:assembleNoAsanDebug
```

Without a user-home override, Gradle reads `~/.gradle/gradle.properties`.
Keep this host-specific path out of shared project configuration used by
x86_64, macOS, or Windows developers. No Gradle cache deletion or SDK rebuild
is required to change the executable selection.

AGP may print `android.aapt2FromMavenOverride ... is experimental`. This is
a warning about the override option and does not fail the build; it can be
left visible. This SDK's Build-Tools 36 AAPT2 is not the same source revision
as AGP's Maven AAPT2. Revalidate resource compilation and linking when
upgrading AGP; the SDK's direct tool probes do
not establish compatibility with every AGP version or Android project.

A local Camera consumer check with JDK 21, Gradle 9.5.0, and AGP 9.3.2 passed
`:app:processDebugResources` and `make` / `:app:assembleDebug`. It used this
SDK's AArch64 AAPT2 through a QEMU launcher on x86_64, including AppCompat
1.7.1 and Core 1.13.0 resource compilation; the Debug APK signature also
verified. The user then confirmed `make` on the native Linux AArch64 machine
`Arm64-Miku` after saving Camera's project-local override: `BUILD SUCCESSFUL
in 1m 20s`, with 10 tasks executed and 23 up-to-date. The other six application
projects share the same AGP selection behavior, but their native AArch64 host
builds have not been verified here.

See Google's [AAPT2 distribution documentation](https://developer.android.com/tools/aapt2#download_aapt2_from_google_maven)
and Gradle's [project property configuration](https://docs.gradle.org/current/userguide/build_environment.html#sec:project_properties).

## AGP native library stripping on Linux AArch64

An application with JNI libraries, such as MySnapcam, also invokes NDK tools
after resource processing. With AGP 9.3.2 and NDK r27, `NdkR25Info` always
selects `linux-x86_64` on Linux for `llvm-strip`, `llvm-objcopy`, and target
libc++ lookup. The producer NDK stores its host tools in `linux-aarch64`.
Without a compatibility path, a build can fail with:

```text
Execution failed for task ':app:stripDebugDebugSymbols'.
A problem occurred starting process 'command '.../ndk/27.3.13750724/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip''
```

This is a separate host-path selection issue from the Maven AAPT2 failure.
Camera's successful resource build did not exercise JNI symbol stripping.
Changing the AAPT2 override or selecting MySnapcam's `noAsanDebug` variant
does not change AGP's NDK host-path selection.

SDK assembly now adds this relative directory link after copying the NDK:

```text
ndk/27.3.13750724/toolchains/llvm/prebuilt/linux-x86_64 -> linux-aarch64
```

Both names reach the same AArch64 toolchain; the link does not add x86_64
binaries or rename the canonical `linux-aarch64` tree. The standalone NDK
Release files are preserved. Layout validation requires this exact relative
link and rejects a missing link, another target, or a real directory in its
place. Runtime validation checks symbol stripping and debug extraction
through the paths AGP uses. Preserve symlinks when copying or extracting the
SDK.

For an SDK installed before this fix, apply the same compatibility link on
the **Linux AArch64 build machine**. Adjust the SDK installation path first:

```bash
(
  set -eu
  cd /mnt/develop/android/sdk/ndk/27.3.13750724/toolchains/llvm/prebuilt
  test -d linux-aarch64
  if [ ! -e linux-x86_64 ] && [ ! -L linux-x86_64 ]; then
    ln -sT linux-aarch64 linux-x86_64
  fi
  test -L linux-x86_64
  test "$(readlink linux-x86_64)" = linux-aarch64
  file -L linux-x86_64/bin/llvm-strip
  ./linux-x86_64/bin/llvm-strip --version
)
```

If `linux-x86_64` already exists as a real directory or points elsewhere,
the checks stop; inspect that SDK installation before proceeding. The
executable must report `ARM aarch64`, and `--version` must run successfully.
Then retry the application build, retaining its AAPT2 override:

```bash
cd /mnt/develop/linux/MySnapcam
make
# For a non-HWASan device, use the existing variant instead:
make no-asan-debug
```

No compiler rebuild or Gradle cache deletion is needed for this path fix.
A local AGP 9.3.2 fixture using MySnapcam's three existing JNI libraries
reproduced the missing-path failure and passed with the alias. A separate
clean MySnapcam checkout then completed `make` with all 38 tasks executed,
including JNI compilation, resource processing, symbol stripping, and APK
packaging. It used a relocated copy of the SDK assembled from NDK producer
Release v1.0.6; the AArch64 tools ran through QEMU/binfmt on x86_64. All three
rebuilt JNI libraries lost their debug sections and matched the APK members
byte-for-byte, and the APK signature verified. Native AArch64 host execution
still requires a retry on the consuming machine.

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
