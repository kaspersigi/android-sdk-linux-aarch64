#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0

from __future__ import annotations

from pathlib import Path
import runpy
import tempfile
import unittest


PROJECT_ROOT = Path(__file__).resolve().parents[1]
MODULE = runpy.run_path(str(PROJECT_ROOT / "scripts/verify-source-snapshot.py"))
calculate = MODULE["calculate"]


class SourceRootCoverageTest(unittest.TestCase):
    def test_module_directories_are_hashed(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            module = root / "module"
            module.mkdir()
            (module / "source.cc").write_text("source\n", encoding="utf-8")
            self.assertEqual(set(calculate(root)), {"src/module"})

    def test_top_level_file_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            (root / "untracked-input.txt").write_text("input\n", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "unexpected entries"):
                calculate(root)

    def test_top_level_symlink_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            module = root / "module"
            module.mkdir()
            (root / "module-link").symlink_to(module, target_is_directory=True)
            with self.assertRaisesRegex(ValueError, "unexpected entries"):
                calculate(root)


if __name__ == "__main__":
    unittest.main()
