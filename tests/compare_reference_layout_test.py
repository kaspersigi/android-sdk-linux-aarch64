#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0

from __future__ import annotations

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
