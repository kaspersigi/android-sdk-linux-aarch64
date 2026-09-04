# Android Build-Tools 36.0.0 for GNU/Linux AArch64

This directory is a self-contained, ordinary CMake project that builds the six
native Android SDK Build-Tools host programs required by this SDK:

- `aapt`
- `aapt2`
- `aidl`
- `dexdump`
- `split-select`
- `zipalign`

It does not use Soong, does not build Android or Bionic, does not clone AOSP,
and does not apply patches at build time. The GNU cross compiler supplied by
Ubuntu 26.04 produces AArch64 executables with the glibc interpreter
`/lib/ld-linux-aarch64.so.1`.

## Source provenance

The source snapshot was imported on 2026-09-04 from the local Android 16 QSSI
tree at `/mnt/develop/linux/build-tools/LA.QSSI.16.0/LINUX/android`, build ID
`BQ2A.250610.001-BP2A.250605.031.A3`. The original per-project Git metadata was
not retained, so individual upstream commit IDs cannot be reconstructed from
this trimmed import. `SOURCE_TREE_SHA256` records a deterministic digest for
every imported top-level source tree, and every build verifies those digests
before compiling. The digest records Git-stable regular-file and symlink entry
types plus executable bits, rather than checkout permissions affected by the
user's `umask`; empty directories are intentionally excluded because Git does
not store them. Validation also rejects ignored source files that would be
absent from a fresh checkout. Only the source files and shared library projects
needed by the six executable targets are included here.

The CMake target descriptions were adapted from the Apache-2.0
`lzhiyong/android-sdk-tools` and `soobujmiah/adt` standalone-build work. GNU
and glibc compatibility changes are already incorporated into this source
snapshot. Generated AIDL parser and AAPT2 protobuf C++ files are checked in,
so the cross build does not write into the source tree or execute generated
target programs.

Host/target source selection follows the upstream `Android.bp` definitions.
In particular, `dexdump` uses `libartpalette/system/palette_fake.cc` on Linux;
the Android/APEX loader is not linked and no `libartpalette-system.so` is
required at runtime.

Upstream license and metadata files are preserved with their corresponding
source directories. Android sources are predominantly Apache-2.0; bundled
third-party projects retain their own license files.

## Standalone build

From the SDK repository root:

```bash
cmake -S build-tools -B build/build-tools-cmake -GNinja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_TOOLCHAIN_FILE="$PWD/build-tools/cmake/aarch64-linux-gnu.cmake" \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -Dprotobuf_BUILD_TESTS=OFF
cmake --build build/build-tools-cmake --parallel "$(nproc)" \
  --target aapt aapt2 aidl dexdump split-select zipalign
```

The normal entry point is `scripts/build-build-tools.sh`, which also strips
and validates the six outputs before staging them in
`build/build-tools-aarch64/`.
