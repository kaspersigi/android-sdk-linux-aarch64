#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0

from __future__ import annotations

from pathlib import Path
import runpy
import subprocess
import sys
import tempfile
import unittest


PROJECT_ROOT = Path(__file__).resolve().parents[1]
MODULE = runpy.run_path(str(PROJECT_ROOT / "scripts/compare-reference-layout.py"))
Entry = MODULE["Entry"]
content_difference_is_expected = MODULE["content_difference_is_expected"]


def write_elf(path: Path, machine: int) -> None:
    header = bytearray(20)
    header[:4] = b"\x7fELF"
    header[5] = 1
    header[18:20] = machine.to_bytes(2, "little")
    path.write_bytes(header)


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


if __name__ == "__main__":
    unittest.main()
