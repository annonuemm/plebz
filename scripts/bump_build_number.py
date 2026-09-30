#!/usr/bin/env python3
"""Increment the build metadata of the top-level pubspec version.

The build number is this fork's running version counter: it becomes the Android
versionCode, so every build installs over the previous one as an update instead
of being rejected as a downgrade.

Only the top-level `version:` line is touched — nested `version:` keys under
dependencies are left alone, matching pubspec_version.parse_pubspec_version.
"""

import argparse
from pathlib import Path
import re
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))

from pubspec_version import parse_pubspec_version  # noqa: E402


_TOP_LEVEL_VERSION_LINE = re.compile(r"^(version:[ \t]*)(\S+)(.*)$")


def bump_build_number(contents: str) -> tuple[str, str]:
    """Return the rewritten pubspec and the new `major.minor.patch+build`."""
    version, build = parse_pubspec_version(contents)
    base = version.rsplit("+", 1)[0]
    new_version = f"{base}+{int(build) + 1}"

    lines = contents.splitlines(keepends=True)
    for index, line in enumerate(lines):
        match = _TOP_LEVEL_VERSION_LINE.match(line)
        if not match:
            continue
        # parse_pubspec_version already guaranteed exactly one of these, and
        # that its value is well formed, so this is the line to rewrite.
        lines[index] = f"{match.group(1)}{new_version}{match.group(3)}"
        if line.endswith("\n"):
            lines[index] += "\n"
        return "".join(lines), new_version

    raise ValueError("no top-level 'version:' line to rewrite")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Increment the pubspec build number by one."
    )
    parser.add_argument(
        "pubspec",
        nargs="?",
        type=Path,
        default=Path("pubspec.yaml"),
        help="path to pubspec.yaml (default: ./pubspec.yaml)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="print the next version without writing it back",
    )
    args = parser.parse_args()

    try:
        contents = args.pubspec.read_text(encoding="utf-8")
        updated, new_version = bump_build_number(contents)
        if not args.dry_run:
            args.pubspec.write_text(updated, encoding="utf-8")
    except (OSError, UnicodeError, ValueError) as error:
        print(f"Error: {args.pubspec}: {error}", file=sys.stderr)
        return 1

    print(new_version)
    return 0


if __name__ == "__main__":
    sys.exit(main())
