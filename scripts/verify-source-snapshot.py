#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0

import argparse
import hashlib
import os
import shutil
import stat
import subprocess
import sys
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parent.parent
SOURCE_ROOT = PROJECT_ROOT / "build-tools" / "src"
MANIFEST = PROJECT_ROOT / "build-tools" / "SOURCE_TREE_SHA256"


def update_field(digest: "hashlib._Hash", value: bytes) -> None:
    digest.update(str(len(value)).encode("ascii"))
    digest.update(b":")
    digest.update(value)


def tree_digest(root: Path) -> str:
    digest = hashlib.sha256()
    digest.update(b"android-sdk-linux-aarch64-source-tree-v3\0")

    def visit(directory: Path, prefix: Path) -> None:
        children = sorted(os.scandir(directory), key=lambda entry: os.fsencode(entry.name))
        for child in children:
            path = Path(child.path)
            relative = (prefix / child.name).as_posix().encode("utf-8", "surrogateescape")
            metadata = child.stat(follow_symlinks=False)
            if stat.S_ISLNK(metadata.st_mode):
                digest.update(b"L")
                update_field(digest, relative)
                update_field(digest, os.fsencode(os.readlink(path)))
            elif stat.S_ISDIR(metadata.st_mode):
                # Git doesn't store directories, so including them would make
                # an empty directory in the import impossible to reproduce in
                # a fresh checkout. File and symlink paths already encode the
                # complete Git-representable directory structure.
                visit(path, prefix / child.name)
            elif stat.S_ISREG(metadata.st_mode):
                digest.update(b"F")
                git_mode = b"100755" if metadata.st_mode & stat.S_IXUSR else b"100644"
                update_field(digest, git_mode)
                update_field(digest, relative)
                update_field(digest, str(metadata.st_size).encode("ascii"))
                with path.open("rb") as stream:
                    for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                        digest.update(chunk)
            else:
                raise ValueError(f"unsupported entry type: {path}")

    visit(root, Path())
    return digest.hexdigest()


def ignored_source_paths() -> list[str]:
    """Return ignored files that would disappear from a fresh Git checkout."""
    if shutil.which("git") is None:
        return []
    probe = subprocess.run(
        [
            "git",
            "-C",
            str(PROJECT_ROOT),
            "rev-parse",
            "--is-inside-work-tree",
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if probe.returncode != 0:
        return []
    result = subprocess.run(
        [
            "git",
            "-C",
            str(PROJECT_ROOT),
            "ls-files",
            "--others",
            "--ignored",
            "--exclude-standard",
            "-z",
            "--",
            "build-tools/src",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )
    return [
        os.fsdecode(path)
        for path in result.stdout.split(b"\0")
        if path
    ]


def calculate() -> dict[str, str]:
    modules = sorted(
        (path for path in SOURCE_ROOT.iterdir() if path.is_dir()),
        key=lambda path: os.fsencode(path.name),
    )
    return {f"src/{module.name}": tree_digest(module) for module in modules}


def read_manifest() -> dict[str, str]:
    expected: dict[str, str] = {}
    for line_number, raw_line in enumerate(MANIFEST.read_text().splitlines(), 1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        try:
            digest, relative = line.split("  ", 1)
        except ValueError as error:
            raise ValueError(f"invalid manifest line {line_number}: {raw_line}") from error
        if len(digest) != 64 or any(character not in "0123456789abcdef" for character in digest):
            raise ValueError(f"invalid SHA-256 on manifest line {line_number}")
        expected[relative] = digest
    return expected


def main() -> int:
    parser = argparse.ArgumentParser(description="Verify the embedded Build-Tools source snapshot.")
    parser.add_argument("--print", action="store_true", dest="print_manifest")
    args = parser.parse_args()

    ignored = ignored_source_paths()
    if ignored:
        for relative in ignored[:100]:
            print(
                f"ignored source would be absent from a fresh Git checkout: {relative}",
                file=sys.stderr,
            )
        if len(ignored) > 100:
            print(f"... {len(ignored) - 100} more ignored source paths", file=sys.stderr)
        return 1

    actual = calculate()
    if args.print_manifest:
        for relative, digest in actual.items():
            print(f"{digest}  {relative}")
        return 0

    expected = read_manifest()
    if expected != actual:
        for relative in sorted(expected.keys() | actual.keys(), key=os.fsencode):
            if expected.get(relative) != actual.get(relative):
                print(
                    f"source snapshot mismatch: {relative}: "
                    f"expected={expected.get(relative, 'missing')} "
                    f"actual={actual.get(relative, 'missing')}",
                    file=sys.stderr,
                )
        return 1

    print(f"verified_source_modules={len(actual)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
