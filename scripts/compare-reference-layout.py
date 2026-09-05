#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0

from __future__ import annotations

import argparse
import hashlib
import os
import stat
import sys
import zipfile
from dataclasses import dataclass
from pathlib import Path

sys.dont_write_bytecode = True
script_dir = str(Path(__file__).resolve().parent)
if script_dir not in sys.path:
    sys.path.insert(0, script_dir)
from elf_validation import is_valid_elf_machine


# SDK-owned additions are exact relative links, never another host tree.
SDK_COMPATIBILITY_LINKS = {
    "ndk/27.3.13750724/toolchains/llvm/prebuilt/linux-x86_64": "linux-aarch64",
}


HOST_ELF_CONTENT_DIFFERENCES = {
    "build-tools/36.0.0/aapt",
    "build-tools/36.0.0/aapt2",
    "build-tools/36.0.0/aidl",
    "build-tools/36.0.0/dexdump",
    "build-tools/36.0.0/split-select",
    "build-tools/36.0.0/zipalign",
    "build-tools/36.0.0/lib64/libc++.so",
    "build-tools/36.0.0/lib64/libc++.so.1",
    "cmake/3.22.1/bin/cmake",
    "cmake/3.22.1/bin/cpack",
    "cmake/3.22.1/bin/ctest",
    "cmake/3.22.1/bin/ninja",
    "cmake/4.1.2/bin/cmake",
    "cmake/4.1.2/bin/cpack",
    "cmake/4.1.2/bin/ctest",
    "cmake/4.1.2/bin/ninja",
    "platform-tools/adb",
    "platform-tools/etc1tool",
    "platform-tools/fastboot",
    "platform-tools/hprof-conv",
    "platform-tools/make_f2fs",
    "platform-tools/make_f2fs_casefold",
    "platform-tools/mke2fs",
    "platform-tools/sqlite3",
    "platform-tools/lib64/libc++.so",
}

HOST_SCRIPT_CONTENT_DIFFERENCES = {
    "build-tools/36.0.0/bcc_compat",
    "build-tools/36.0.0/llvm-rs-cc",
    "build-tools/36.0.0/lld-bin/lld",
    "cmdline-tools/latest/bin/android",
}

HOST_SCRIPT_TEMPLATES = {
    "build-tools/36.0.0/bcc_compat": "renderscript-unsupported",
    "build-tools/36.0.0/llvm-rs-cc": "renderscript-unsupported",
    "build-tools/36.0.0/lld-bin/lld": "build-tools-lld",
    "cmdline-tools/latest/bin/android": "android-offline",
}

GENERIC_METADATA_FIELDS = {
    "build-tools/36.0.0/package.xml": (
        "build-tools;36.0.0", "36", "0", "0",
        "Android SDK Build-Tools 36 Linux AArch64",
    ),
    "cmake/3.22.1/package.xml": (
        "cmake;3.22.1", "3", "22", "1", "CMake 3.22.1 Linux AArch64",
    ),
    "cmake/4.1.2/package.xml": (
        "cmake;4.1.2", "4", "1", "2", "CMake 4.1.2 Linux AArch64",
    ),
    "ndk/27.3.13750724/package.xml": (
        "ndk;27.3.13750724", "27", "3", "13750724",
        "NDK (Side by side) 27.3.13750724 Linux AArch64",
    ),
}

DIRECT_METADATA_TEMPLATES = {
    "platforms/android-36/package.xml": "package-platform.xml.in",
}

RELEASE_METADATA = {
    "platform-tools/package.xml": "platform-tools/package.xml",
}

GENERATED_METADATA = (
    set(GENERIC_METADATA_FIELDS) | set(DIRECT_METADATA_TEMPLATES) | set(RELEASE_METADATA)
)

INTENTIONAL_MISSING = {
    ".knownPackages",
    "build-tools/36.0.0/lib64/libLLVM_android.so",
    "build-tools/36.0.0/lib64/libbcc.so",
    "build-tools/36.0.0/lib64/libbcinfo.so",
    "build-tools/36.0.0/lib64/libclang_android.so",
}


NDK_HOST_PREFIXES = (
    ("toolchains/llvm/prebuilt/linux-x86_64", "toolchains/llvm/prebuilt/linux-aarch64"),
    ("prebuilt/linux-x86_64", "prebuilt/linux-aarch64"),
    ("shader-tools/linux-x86_64", "shader-tools/linux-aarch64"),
    ("simpleperf/bin/linux/x86_64", "simpleperf/bin/linux/aarch64"),
)

NDK_HOST_GENERATED_CONTENT_PREFIXES = (
    "ndk/27.3.13750724/toolchains/llvm/prebuilt/linux-aarch64/"
    "lib/aarch64-unknown-linux-gnu",
    "ndk/27.3.13750724/toolchains/llvm/prebuilt/linux-aarch64/"
    "lib/clang/18/lib/aarch64-unknown-linux-gnu",
)

NDK_HOST_GENERATED_CONTENT_FILES = {
    "ndk/27.3.13750724/prebuilt/linux-aarch64/lib/libyasm.a",
    "ndk/27.3.13750724/toolchains/llvm/prebuilt/linux-aarch64/lib/libbolt_rt_instr.a",
}

NDK_PYTHON_CONFIG_FILES = {
    "ndk/27.3.13750724/toolchains/llvm/prebuilt/linux-aarch64/"
    "python3/include/python3.11/pyconfig.h",
    "ndk/27.3.13750724/toolchains/llvm/prebuilt/linux-aarch64/"
    "python3/lib/pkgconfig/python-3.11-embed.pc",
    "ndk/27.3.13750724/toolchains/llvm/prebuilt/linux-aarch64/"
    "python3/lib/pkgconfig/python-3.11.pc",
    "ndk/27.3.13750724/toolchains/llvm/prebuilt/linux-aarch64/"
    "python3/lib/python3.11/_sysconfigdata__linux_aarch64-linux-gnu.py",
}

NDK_COMPILER_RT_GENERATED_TEXT_PREFIX = (
    "ndk/27.3.13750724/toolchains/llvm/prebuilt/linux-aarch64/"
    "lib/clang/18/lib/aarch64-unknown-linux-gnu/"
)

NDK_HOST_ELF_CONTENT_PREFIXES = (
    "ndk/27.3.13750724/prebuilt/linux-aarch64/bin",
    "ndk/27.3.13750724/shader-tools/linux-aarch64",
    "ndk/27.3.13750724/simpleperf/bin/linux/aarch64",
    "ndk/27.3.13750724/toolchains/llvm/prebuilt/linux-aarch64/bin",
    "ndk/27.3.13750724/toolchains/llvm/prebuilt/linux-aarch64/python3",
    "ndk/27.3.13750724/toolchains/llvm/prebuilt/linux-aarch64/lib/python3.11",
)

NDK_HOST_ELF_CONTENT_DIRECTORIES = {
    "ndk/27.3.13750724/toolchains/llvm/prebuilt/linux-aarch64/lib",
    "ndk/27.3.13750724/toolchains/llvm/prebuilt/linux-aarch64/musl/lib",
}

NDK_HOST_SCRIPT_DIFFERENCES = {
    "ndk/27.3.13750724/build/cmake/android-legacy.toolchain.cmake",
    "ndk/27.3.13750724/build/cmake/android.toolchain.cmake",
    "ndk/27.3.13750724/build/ndk-build",
    "ndk/27.3.13750724/build/tools/make_standalone_toolchain.py",
    "ndk/27.3.13750724/build/tools/ndk_bin_common.sh",
    "ndk/27.3.13750724/ndk-gdb",
    "ndk/27.3.13750724/ndk-lldb",
    "ndk/27.3.13750724/ndk-stack",
    "ndk/27.3.13750724/ndk-which",
    "ndk/27.3.13750724/simpleperf/simpleperf_utils.py",
    "ndk/27.3.13750724/prebuilt/linux-aarch64/bin/ndkgdb.pyz",
    "ndk/27.3.13750724/prebuilt/linux-aarch64/bin/ndk-which",
    "ndk/27.3.13750724/build/cmake/hooks/post/Android-Determine.cmake",
}

NDK_ROOT_PREFIX = "ndk/27.3.13750724/"
PROJECT_ROOT = Path(__file__).resolve().parents[1]
PLATFORM_TOOLS_RELEASE_ARCHIVE = (
    PROJECT_ROOT / ".cache/platform-tools_r37.0.1-linux.zip"
)
NDK_RELEASE_ARCHIVE = PROJECT_ROOT / ".cache/android-ndk-r27d-linux.zip"


@dataclass(frozen=True)
class Entry:
    kind: str
    source: Path
    mode: int
    link: str | None = None


def map_ndk_host_name(value: str) -> str:
    for source, target in NDK_HOST_PREFIXES:
        if value == source or value.startswith(source + "/"):
            value = target + value[len(source) :]
            break
    if value.startswith("toolchains/llvm/prebuilt/linux-aarch64/"):
        if value.endswith("/lib/x86_64-unknown-linux-gnu"):
            value = value[: -len("x86_64-unknown-linux-gnu")] + "aarch64-unknown-linux-gnu"
        value = value.replace(
            "/lib/x86_64-unknown-linux-gnu/",
            "/lib/aarch64-unknown-linux-gnu/",
        )
        if "/python3/" in value or "/lib/python3.11/" in value:
            value = value.replace("x86_64-linux-gnu", "aarch64-linux-gnu")
    return value


def normalize_reference_name(relative: str) -> str:
    parts = relative.split("/", 2)
    if len(parts) == 3 and parts[0] == "ndk":
        return f"{parts[0]}/{parts[1]}/{map_ndk_host_name(parts[2])}"
    return relative


def normalize_reference_link(value: str) -> str:
    return (
        value.replace("linux-x86_64", "linux-aarch64")
        .replace("x86_64-unknown-linux-gnu", "aarch64-unknown-linux-gnu")
        .replace("x86_64-linux-gnu", "aarch64-linux-gnu")
    )


def is_rebuilt_ndk_host_elf_path(relative: str) -> bool:
    if any(
        relative.startswith(prefix + "/")
        for prefix in NDK_HOST_ELF_CONTENT_PREFIXES
    ):
        return True
    parent, separator, _ = relative.rpartition("/")
    return bool(separator) and parent in NDK_HOST_ELF_CONTENT_DIRECTORIES


def files_equal(left: Path, right: Path) -> bool:
    if left.stat().st_size != right.stat().st_size:
        return False
    with left.open("rb") as left_stream, right.open("rb") as right_stream:
        while True:
            left_chunk = left_stream.read(1024 * 1024)
            right_chunk = right_stream.read(1024 * 1024)
            if left_chunk != right_chunk:
                return False
            if not left_chunk:
                return True


def file_digest(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def archive_member_matches(archive_path: Path, member: str, candidate: Path) -> bool:
    try:
        with zipfile.ZipFile(archive_path) as archive:
            matches = [info for info in archive.infolist() if info.filename == member]
            if len(matches) != 1 or matches[0].is_dir():
                return False
            digest = hashlib.sha256()
            with archive.open(matches[0]) as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                    digest.update(chunk)
    except (OSError, zipfile.BadZipFile):
        return False
    return file_digest(candidate) == digest.hexdigest()


def generated_metadata_matches(relative: str, candidate: Path) -> bool:
    try:
        if relative in GENERIC_METADATA_FIELDS:
            package_path, major, minor, micro, display = GENERIC_METADATA_FIELDS[relative]
            content = (PROJECT_ROOT / "templates/package-generic.xml.in").read_text(
                encoding="utf-8"
            )
            for placeholder, value in (
                ("@PATH@", package_path),
                ("@MAJOR@", major),
                ("@MINOR@", minor),
                ("@MICRO@", micro),
                ("@DISPLAY@", display),
            ):
                content = content.replace(placeholder, value)
            return candidate.read_text(encoding="utf-8") == content
        if relative in DIRECT_METADATA_TEMPLATES:
            template = PROJECT_ROOT / "templates" / DIRECT_METADATA_TEMPLATES[relative]
            return files_equal(template, candidate)
        if relative in RELEASE_METADATA:
            return archive_member_matches(
                PLATFORM_TOOLS_RELEASE_ARCHIVE,
                RELEASE_METADATA[relative],
                candidate,
            )
    except (OSError, UnicodeError):
        return False
    return False


def ndk_release_file_matches(relative: str, candidate: Path) -> bool:
    ndk_relative = relative.removeprefix(NDK_ROOT_PREFIX)
    archive_member = f"android-ndk-r27d/{ndk_relative}"
    return archive_member_matches(NDK_RELEASE_ARCHIVE, archive_member, candidate)


def is_ndk_generated_text_path(relative: str) -> bool:
    return relative in NDK_PYTHON_CONFIG_FILES or (
        relative.startswith(NDK_COMPILER_RT_GENERATED_TEXT_PREFIX)
        and relative.endswith(".syms")
    )


def content_difference_is_expected(
    relative: str, reference: Entry, candidate: Entry
) -> bool:
    if relative in HOST_ELF_CONTENT_DIFFERENCES:
        return is_valid_elf_machine(
            reference.source, 62
        ) and is_valid_elf_machine(candidate.source, 183)
    if relative in HOST_SCRIPT_CONTENT_DIFFERENCES:
        template = Path(__file__).resolve().parents[1] / "templates" / (
            HOST_SCRIPT_TEMPLATES[relative]
        )
        return files_equal(template, candidate.source)
    if relative in NDK_HOST_SCRIPT_DIFFERENCES:
        return ndk_release_file_matches(relative, candidate.source)
    if relative in GENERATED_METADATA:
        return generated_metadata_matches(relative, candidate.source)
    if is_ndk_generated_text_path(relative):
        return ndk_release_file_matches(relative, candidate.source)
    if relative in NDK_HOST_GENERATED_CONTENT_FILES:
        return True
    if any(
        relative == prefix or relative.startswith(prefix + "/")
        for prefix in NDK_HOST_GENERATED_CONTENT_PREFIXES
    ):
        return True
    # A machine transition is valid only in an explicitly identified NDK host
    # position. Android target ELFs below the host-tagged sysroot and Clang
    # runtime directories must remain byte-for-byte identical.
    return (
        is_rebuilt_ndk_host_elf_path(relative)
        and is_valid_elf_machine(reference.source, 62)
        and is_valid_elf_machine(candidate.source, 183)
    )


def inventory(root: Path, normalize_reference: bool = False) -> dict[str, Entry]:
    result: dict[str, Entry] = {}
    for path in root.rglob("*"):
        relative = path.relative_to(root).as_posix()
        mode = stat.S_IMODE(os.lstat(path).st_mode)
        if path.is_symlink():
            link = os.readlink(path)
            if normalize_reference:
                link = normalize_reference_link(link)
            kind = "link"
        elif path.is_dir():
            link = None
            kind = "dir"
        elif path.is_file():
            link = None
            kind = "file"
        else:
            link = None
            kind = "other"
        if normalize_reference:
            relative = normalize_reference_name(relative)
        if relative in result:
            raise ValueError(f"normalized reference path collision: {relative}")
        result[relative] = Entry(kind=kind, source=path, mode=mode, link=link)
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("reference", type=Path)
    parser.add_argument("candidate", type=Path)
    args = parser.parse_args()

    try:
        reference = inventory(args.reference, normalize_reference=True)
        candidate = inventory(args.candidate)
    except (OSError, ValueError) as error:
        print(f"error: cannot inventory SDK trees: {error}", file=sys.stderr)
        return 1
    missing = sorted(set(reference) - set(candidate))
    extra = sorted(set(candidate) - set(reference))
    unexpected_extra = sorted(set(extra) - set(SDK_COMPATIBILITY_LINKS))
    compatibility_link_mismatches = []
    for relative, target in SDK_COMPATIBILITY_LINKS.items():
        entry = candidate.get(relative)
        if (
            entry is None
            or entry.kind != "link"
            or entry.link != target
            or not entry.source.is_dir()
        ):
            compatibility_link_mismatches.append(relative)
    mismatched_types = sorted(
        path for path in set(reference) & set(candidate)
        if reference[path].kind != candidate[path].kind
    )

    link_mismatches = sorted(
        path for path in set(reference) & set(candidate)
        if reference[path].kind == candidate[path].kind == "link"
        and reference[path].link != candidate[path].link
    )

    # sdkmanager-created local trees follow the user's collaborative umask and
    # commonly add group-write permission (0775/0664). Normalize only that
    # installation-policy bit; all other permission bits must match exactly.
    mode_mismatches = sorted(
        path for path in set(reference) & set(candidate)
        if reference[path].kind == candidate[path].kind
        and (reference[path].mode & ~stat.S_IWGRP)
        != (candidate[path].mode & ~stat.S_IWGRP)
    )

    expected_missing = sorted(
        path for path in INTENTIONAL_MISSING if path in reference
    )
    unexpected_missing = sorted(set(missing) - set(expected_missing))
    missing_not_observed = sorted(set(expected_missing) - set(missing))

    content_mismatches: list[str] = []
    for relative in sorted(set(reference) & set(candidate)):
        if reference[relative].kind != candidate[relative].kind:
            continue
        if reference[relative].kind != "file":
            continue
        left = reference[relative].source
        right = candidate[relative].source
        requires_explicit_content = relative in (
            HOST_SCRIPT_CONTENT_DIFFERENCES
            | NDK_HOST_SCRIPT_DIFFERENCES
            | GENERATED_METADATA
        ) or is_ndk_generated_text_path(relative)
        if (
            requires_explicit_content
            and not content_difference_is_expected(
                relative, reference[relative], candidate[relative]
            )
        ) or (
            not requires_explicit_content
            and not files_equal(left, right)
            and not content_difference_is_expected(
                relative, reference[relative], candidate[relative]
            )
        ):
            content_mismatches.append(relative)

    print(f"reference_entries={len(reference)}")
    print(f"candidate_entries={len(candidate)}")
    print(f"missing={len(missing)}")
    print(f"intentional_missing={len(set(missing) & set(expected_missing))}")
    print(f"unexpected_missing={len(unexpected_missing)}")
    print(f"extra={len(extra)}")
    print(f"intentional_extra={len(set(extra) & set(SDK_COMPATIBILITY_LINKS))}")
    print(f"unexpected_extra={len(unexpected_extra)}")
    print(f"compatibility_link_mismatches={len(compatibility_link_mismatches)}")
    print(f"type_mismatches={len(mismatched_types)}")
    print(f"link_mismatches={len(link_mismatches)}")
    print(f"content_mismatches={len(content_mismatches)}")
    print(f"mode_mismatches={len(mode_mismatches)}")

    problems = {
        "unexpected missing": unexpected_missing,
        "expected missing not observed": missing_not_observed,
        "unexpected extra": unexpected_extra,
        "compatibility link mismatch": compatibility_link_mismatches,
        "type mismatch": mismatched_types,
        "link mismatch": link_mismatches,
        "mode mismatch": mode_mismatches,
        "content mismatch": content_mismatches,
    }
    for label, paths in problems.items():
        for path in paths[:50]:
            print(f"{label}: {path}")
    return 1 if any(problems.values()) else 0


if __name__ == "__main__":
    raise SystemExit(main())
