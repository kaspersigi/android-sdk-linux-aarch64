#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0

from __future__ import annotations

import os
from pathlib import Path
import runpy
import struct
import subprocess
import sys
import tempfile
import unittest
import zipfile


PROJECT_ROOT = Path(__file__).resolve().parents[1]
MODULE = runpy.run_path(str(PROJECT_ROOT / "scripts/compare-reference-layout.py"))
Entry = MODULE["Entry"]
content_difference_is_expected = MODULE["content_difference_is_expected"]


def write_elf(path: Path, machine: int) -> None:
    identity = b"\x7fELF" + bytes((2, 1, 1)) + bytes(9)
    header = struct.pack(
        "<16sHHIQQQIHHHHHH",
        identity, 3, machine, 1, 0, 64, 0, 0, 64, 56, 1, 64, 0, 0,
    )
    program = struct.pack("<IIQQQQQQ", 1, 5, 0, 0, 0, 120, 120, 4096)
    path.write_bytes(header + program)


class NdkHostElfDifferenceTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        root = Path(self.temporary_directory.name)
        self.reference = root / "reference"
        self.candidate = root / "candidate"
        write_elf(self.reference, 62)
        write_elf(self.candidate, 183)
        self.expected = Entry("file", self.reference, 0o755)
        self.actual = Entry("file", self.candidate, 0o755)

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def test_rebuilt_ndk_host_elf_positions_are_allowed(self) -> None:
        paths = (
            "ndk/27.3.13750724/prebuilt/linux-aarch64/bin/make",
            "ndk/27.3.13750724/shader-tools/linux-aarch64/glslc",
            "ndk/27.3.13750724/simpleperf/bin/linux/aarch64/simpleperf",
            "ndk/27.3.13750724/toolchains/llvm/prebuilt/linux-aarch64/bin/clang-18",
            "ndk/27.3.13750724/toolchains/llvm/prebuilt/linux-aarch64/lib/liblldb.so",
            "ndk/27.3.13750724/toolchains/llvm/prebuilt/linux-aarch64/"
            "musl/lib/libclang.so",
            "ndk/27.3.13750724/toolchains/llvm/prebuilt/linux-aarch64/"
            "python3/bin/python3.11",
            "ndk/27.3.13750724/toolchains/llvm/prebuilt/linux-aarch64/"
            "lib/python3.11/host.so",
        )
        for relative in paths:
            with self.subTest(relative=relative):
                self.assertTrue(
                    content_difference_is_expected(
                        relative, self.expected, self.actual
                    )
                )

    def test_android_target_elf_positions_are_rejected(self) -> None:
        paths = (
            "ndk/27.3.13750724/toolchains/llvm/prebuilt/linux-aarch64/"
            "sysroot/usr/lib/x86_64-linux-android/21/crtbegin_dynamic.o",
            "ndk/27.3.13750724/toolchains/llvm/prebuilt/linux-aarch64/"
            "lib/clang/18/lib/linux/libclang_rt.asan-x86_64-android.so",
            "platforms/android-36/x86_64/target.so",
        )
        for relative in paths:
            with self.subTest(relative=relative):
                self.assertFalse(
                    content_difference_is_expected(
                        relative, self.expected, self.actual
                    )
                )

    def test_truncated_host_elf_is_rejected(self) -> None:
        self.candidate.write_bytes(self.candidate.read_bytes()[:64])
        self.assertFalse(
            content_difference_is_expected(
                "ndk/27.3.13750724/toolchains/llvm/prebuilt/"
                "linux-aarch64/bin/clang-tidy",
                self.expected,
                self.actual,
            )
        )

    def test_relocatable_object_is_rejected_as_host_program(self) -> None:
        content = bytearray(self.candidate.read_bytes())
        struct.pack_into("<H", content, 16, 1)
        self.candidate.write_bytes(content)
        self.assertFalse(
            content_difference_is_expected(
                "ndk/27.3.13750724/toolchains/llvm/prebuilt/"
                "linux-aarch64/bin/clang-tidy",
                self.expected,
                self.actual,
            )
        )

    def test_explicit_sdk_host_elf_requires_valid_structures(self) -> None:
        relative = "build-tools/36.0.0/aapt"
        self.assertTrue(
            content_difference_is_expected(relative, self.expected, self.actual)
        )
        self.candidate.write_bytes(self.candidate.read_bytes()[:64])
        self.assertFalse(
            content_difference_is_expected(relative, self.expected, self.actual)
        )


class HostScriptDifferenceTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        root = Path(self.temporary_directory.name)
        self.reference = root / "reference"
        self.candidate = root / "candidate"
        self.reference.write_text("official x86_64 script\n", encoding="utf-8")

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def entry(self, path: Path) -> Entry:
        return Entry("file", path, 0o755)

    def test_sdk_script_must_equal_its_checked_in_template(self) -> None:
        relative = "build-tools/36.0.0/bcc_compat"
        template = PROJECT_ROOT / "templates/renderscript-unsupported"
        self.candidate.write_bytes(template.read_bytes())
        self.assertTrue(
            content_difference_is_expected(
                relative, self.entry(self.reference), self.entry(self.candidate)
            )
        )
        self.candidate.write_bytes(b"")
        self.assertFalse(
            content_difference_is_expected(
                relative, self.entry(self.reference), self.entry(self.candidate)
            )
        )

    def test_ndk_script_rejects_unpinned_content(self) -> None:
        archive = Path(self.temporary_directory.name) / "ndk.zip"
        with zipfile.ZipFile(archive, "w") as output:
            output.writestr("android-ndk-r27d/ndk-gdb", b"release script\n")
        function_globals = content_difference_is_expected.__globals__
        original_archive = function_globals["NDK_RELEASE_ARCHIVE"]
        function_globals["NDK_RELEASE_ARCHIVE"] = archive
        try:
            self.candidate.write_bytes(b"release script\n")
            self.assertTrue(
                content_difference_is_expected(
                    "ndk/27.3.13750724/ndk-gdb",
                    self.entry(self.reference),
                    self.entry(self.candidate),
                )
            )
            self.candidate.write_bytes(b"")
            self.assertFalse(
                content_difference_is_expected(
                    "ndk/27.3.13750724/ndk-gdb",
                    self.entry(self.reference),
                    self.entry(self.candidate),
                )
            )
        finally:
            function_globals["NDK_RELEASE_ARCHIVE"] = original_archive

    def test_environment_cannot_replace_ndk_release_archive(self) -> None:
        original = os.environ.get("NDK_RELEASE_ARCHIVE")
        os.environ["NDK_RELEASE_ARCHIVE"] = "/tmp/unverified-ndk.zip"
        try:
            fresh_module = runpy.run_path(
                str(PROJECT_ROOT / "scripts/compare-reference-layout.py")
            )
        finally:
            if original is None:
                os.environ.pop("NDK_RELEASE_ARCHIVE", None)
            else:
                os.environ["NDK_RELEASE_ARCHIVE"] = original
        self.assertEqual(
            fresh_module["NDK_RELEASE_ARCHIVE"],
            PROJECT_ROOT / ".cache/android-ndk-r27d-linux.zip",
        )

    def test_ndk_entrypoint_fixes_are_release_pinned_not_broad_exemptions(self) -> None:
        paths = ("simpleperf/simpleperf_utils.py", "prebuilt/linux-aarch64/bin/ndkgdb.pyz",
                 "build/cmake/hooks/post/Android-Determine.cmake", "prebuilt/linux-aarch64/bin/ndk-which")
        archive = Path(self.temporary_directory.name) / "ndk-entrypoints.zip"
        with zipfile.ZipFile(archive, "w") as output:
            for relative in paths:
                output.writestr("android-ndk-r27d/" + relative, b"release-fixed-entrypoint")
        function_globals = content_difference_is_expected.__globals__
        original = function_globals["NDK_RELEASE_ARCHIVE"]
        function_globals["NDK_RELEASE_ARCHIVE"] = archive
        try:
            for relative in paths:
                with self.subTest(path=relative):
                    self.candidate.write_bytes(b"release-fixed-entrypoint")
                    self.assertTrue(content_difference_is_expected(
                        "ndk/27.3.13750724/" + relative,
                        self.entry(self.reference), self.entry(self.candidate)))
                    self.candidate.write_bytes(b"tampered-entrypoint")
                    self.assertFalse(content_difference_is_expected(
                        "ndk/27.3.13750724/" + relative,
                        self.entry(self.reference), self.entry(self.candidate)))
        finally:
            function_globals["NDK_RELEASE_ARCHIVE"] = original

    def test_ndk_generated_text_must_equal_selected_release(self) -> None:
        relative = (
            "ndk/27.3.13750724/toolchains/llvm/prebuilt/linux-aarch64/"
            "python3/include/python3.11/pyconfig.h"
        )
        member = "android-ndk-r27d/" + relative.removeprefix(
            "ndk/27.3.13750724/"
        )
        archive = Path(self.temporary_directory.name) / "ndk-generated-text.zip"
        payload = b"#define SIZEOF_VOID_P 8\n"
        with zipfile.ZipFile(archive, "w") as output:
            output.writestr(member, payload)
        function_globals = content_difference_is_expected.__globals__
        original_archive = function_globals["NDK_RELEASE_ARCHIVE"]
        function_globals["NDK_RELEASE_ARCHIVE"] = archive
        try:
            self.candidate.write_bytes(payload)
            self.assertTrue(
                content_difference_is_expected(
                    relative, self.entry(self.reference), self.entry(self.candidate)
                )
            )
            self.candidate.write_bytes(b"")
            self.assertFalse(
                content_difference_is_expected(
                    relative, self.entry(self.reference), self.entry(self.candidate)
                )
            )
        finally:
            function_globals["NDK_RELEASE_ARCHIVE"] = original_archive


class GeneratedMetadataDifferenceTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        root = Path(self.temporary_directory.name)
        self.reference = root / "reference.xml"
        self.candidate = root / "candidate.xml"
        self.reference.write_text("official x86_64 metadata\n", encoding="utf-8")

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def entry(self, path: Path) -> Entry:
        return Entry("file", path, 0o644)

    def assert_metadata_result(self, relative: str, expected: bool) -> None:
        self.assertEqual(
            content_difference_is_expected(
                relative, self.entry(self.reference), self.entry(self.candidate)
            ),
            expected,
        )

    def test_generic_metadata_must_equal_rendered_template(self) -> None:
        relative = "build-tools/36.0.0/package.xml"
        fields = MODULE["GENERIC_METADATA_FIELDS"][relative]
        content = (PROJECT_ROOT / "templates/package-generic.xml.in").read_text(
            encoding="utf-8"
        )
        for placeholder, value in zip(
            ("@PATH@", "@MAJOR@", "@MINOR@", "@MICRO@", "@DISPLAY@"),
            fields,
        ):
            content = content.replace(placeholder, value)
        self.candidate.write_text(content, encoding="utf-8")
        self.assert_metadata_result(relative, True)
        self.candidate.write_text(
            content.replace(
                "Android SDK Build-Tools 36 Linux AArch64", "tampered metadata"
            ),
            encoding="utf-8",
        )
        self.assert_metadata_result(relative, False)

    def test_direct_metadata_must_equal_checked_in_template(self) -> None:
        relative = "platforms/android-36/package.xml"
        self.candidate.write_bytes(
            (PROJECT_ROOT / "templates/package-platform.xml.in").read_bytes()
        )
        self.assert_metadata_result(relative, True)
        self.candidate.write_bytes(b"")
        self.assert_metadata_result(relative, False)

    def test_platform_tools_metadata_must_equal_selected_release(self) -> None:
        relative = "platform-tools/package.xml"
        archive = Path(self.temporary_directory.name) / "platform-tools.zip"
        payload = b"release package metadata\n"
        with zipfile.ZipFile(archive, "w") as output:
            output.writestr("platform-tools/package.xml", payload)
        function_globals = content_difference_is_expected.__globals__
        original_archive = function_globals["PLATFORM_TOOLS_RELEASE_ARCHIVE"]
        function_globals["PLATFORM_TOOLS_RELEASE_ARCHIVE"] = archive
        try:
            self.candidate.write_bytes(payload)
            self.assert_metadata_result(relative, True)
            self.candidate.write_bytes(b"")
            self.assert_metadata_result(relative, False)
        finally:
            function_globals["PLATFORM_TOOLS_RELEASE_ARCHIVE"] = original_archive


class TypeMismatchTest(unittest.TestCase):
    def test_file_to_same_size_directory_reports_without_traceback(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            reference = root / "reference"
            candidate = root / "candidate"
            reference.mkdir()
            candidate.mkdir()
            candidate_directory = candidate / "entry"
            candidate_directory.mkdir()
            (reference / "entry").write_bytes(
                b"\0" * candidate_directory.stat().st_size
            )

            result = subprocess.run(
                [
                    sys.executable,
                    "-B",
                    str(PROJECT_ROOT / "scripts/compare-reference-layout.py"),
                    str(reference),
                    str(candidate),
                ],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )

        self.assertEqual(result.returncode, 1)
        self.assertIn("type_mismatches=1", result.stdout)
        self.assertIn("content_mismatches=0", result.stdout)
        self.assertNotIn("Traceback", result.stderr)


class AgpNdkCompatibilityLinkTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        root = Path(self.temporary_directory.name)
        self.reference = root / "reference"
        self.candidate = root / "candidate"
        prebuilt = Path("ndk/27.3.13750724/toolchains/llvm/prebuilt")
        original = self.reference / prebuilt / "linux-x86_64"
        self.target = self.candidate / prebuilt / "linux-aarch64"
        self.alias = self.candidate / prebuilt / "linux-x86_64"
        for directory in (original, self.target):
            directory.mkdir(parents=True)
            (directory / "marker").write_text("same producer content\n")

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def compare(self) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, "-B", str(PROJECT_ROOT / "scripts/compare-reference-layout.py"),
             str(self.reference), str(self.candidate)],
            text=True, capture_output=True, check=False,
        )

    def test_relative_alias_is_accepted_without_following_its_contents(self) -> None:
        self.alias.symlink_to("linux-aarch64", target_is_directory=True)
        result = self.compare()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("extra=1\n", result.stdout)
        self.assertIn("unexpected_extra=0\n", result.stdout)
        self.assertIn("compatibility_link_mismatches=0\n", result.stdout)

    def test_missing_alias_is_rejected(self) -> None:
        result = self.compare()
        self.assertEqual(result.returncode, 1)
        self.assertIn("compatibility_link_mismatches=1\n", result.stdout)

    def test_absolute_alias_is_rejected_even_when_it_resolves(self) -> None:
        self.alias.symlink_to(self.target, target_is_directory=True)
        result = self.compare()
        self.assertEqual(result.returncode, 1)
        self.assertIn("compatibility_link_mismatches=1\n", result.stdout)

    def test_wrong_relative_alias_is_rejected(self) -> None:
        self.alias.symlink_to(".", target_is_directory=True)
        result = self.compare()
        self.assertEqual(result.returncode, 1)
        self.assertIn("compatibility_link_mismatches=1\n", result.stdout)

    def test_real_x86_64_directory_is_rejected(self) -> None:
        self.alias.mkdir()
        result = self.compare()
        self.assertEqual(result.returncode, 1)
        self.assertIn("compatibility_link_mismatches=1\n", result.stdout)

    def test_dangling_alias_is_rejected(self) -> None:
        (self.target / "marker").unlink()
        self.target.rmdir()
        self.alias.symlink_to("linux-aarch64", target_is_directory=True)
        result = self.compare()
        self.assertEqual(result.returncode, 1)
        self.assertIn("compatibility_link_mismatches=1\n", result.stdout)

    def test_other_added_paths_remain_rejected(self) -> None:
        self.alias.symlink_to("linux-aarch64", target_is_directory=True)
        (self.candidate / "unexpected").write_text("unapproved extra file\n")
        result = self.compare()
        self.assertEqual(result.returncode, 1)
        self.assertIn("unexpected_extra=1\n", result.stdout)


class NormalizedReferenceCollisionTest(unittest.TestCase):
    def test_x86_64_and_aarch64_host_paths_cannot_collapse(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            reference = root / "reference"
            candidate = root / "candidate"
            candidate.mkdir()
            for host in ("linux-x86_64", "linux-aarch64"):
                path = (
                    reference
                    / "ndk/27.3.13750724/prebuilt"
                    / host
                    / "bin/make"
                )
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(host.encode())

            with self.assertRaisesRegex(
                ValueError, "normalized reference path collision"
            ):
                MODULE["inventory"](reference, normalize_reference=True)

            result = subprocess.run(
                [
                    sys.executable,
                    "-B",
                    str(PROJECT_ROOT / "scripts/compare-reference-layout.py"),
                    str(reference),
                    str(candidate),
                ],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )

        self.assertEqual(result.returncode, 1)
        self.assertIn("normalized reference path collision", result.stderr)
        self.assertNotIn("Traceback", result.stderr)


if __name__ == "__main__":
    unittest.main()
