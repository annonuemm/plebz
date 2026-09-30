import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from bump_build_number import bump_build_number


SCRIPT = SCRIPT_DIR / "bump_build_number.py"


class BumpBuildNumberTest(unittest.TestCase):
    def test_increments_only_the_build_metadata(self) -> None:
        contents = "name: example\nversion: 2.15.0+131\n"

        updated, version = bump_build_number(contents)

        self.assertEqual(version, "2.15.0+132")
        self.assertEqual(updated, "name: example\nversion: 2.15.0+132\n")

    def test_leaves_nested_version_keys_alone(self) -> None:
        contents = """\
name: example
dependencies:
  first:
    version: 9.9.9+999
version: 2.8.0+119
"""

        updated, version = bump_build_number(contents)

        self.assertEqual(version, "2.8.0+120")
        self.assertIn("    version: 9.9.9+999\n", updated)
        self.assertIn("version: 2.8.0+120\n", updated)

    def test_preserves_a_trailing_comment(self) -> None:
        contents = "version: 1.2.3+4  # keep me\n"

        updated, _ = bump_build_number(contents)

        self.assertEqual(updated, "version: 1.2.3+5  # keep me\n")

    def test_preserves_a_missing_trailing_newline(self) -> None:
        updated, _ = bump_build_number("version: 1.2.3+4")

        self.assertEqual(updated, "version: 1.2.3+5")

    def test_rejects_a_malformed_version(self) -> None:
        with self.assertRaises(ValueError):
            bump_build_number("version: 1.2.3\n")

    def test_build_numbers_stay_monotonic_across_repeated_bumps(self) -> None:
        contents = "version: 2.15.0+131\n"
        seen = []
        for _ in range(3):
            contents, version = bump_build_number(contents)
            seen.append(version)

        self.assertEqual(seen, ["2.15.0+132", "2.15.0+133", "2.15.0+134"])


class BumpBuildNumberCliTest(unittest.TestCase):
    def _run(self, contents: str, *args: str) -> tuple[subprocess.CompletedProcess, Path]:
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        pubspec = Path(directory.name) / "pubspec.yaml"
        pubspec.write_text(contents, encoding="utf-8")
        result = subprocess.run(
            [sys.executable, str(SCRIPT), str(pubspec), *args],
            capture_output=True,
            text=True,
        )
        return result, pubspec

    def test_writes_the_next_version_and_prints_it(self) -> None:
        result, pubspec = self._run("version: 2.15.0+131\n")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "2.15.0+132")
        self.assertEqual(pubspec.read_text(encoding="utf-8"), "version: 2.15.0+132\n")

    def test_dry_run_leaves_the_file_untouched(self) -> None:
        result, pubspec = self._run("version: 2.15.0+131\n", "--dry-run")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "2.15.0+132")
        self.assertEqual(pubspec.read_text(encoding="utf-8"), "version: 2.15.0+131\n")

    def test_reports_a_malformed_pubspec(self) -> None:
        result, _ = self._run("version: nope\n")

        self.assertEqual(result.returncode, 1)
        self.assertIn("Error", result.stderr)


if __name__ == "__main__":
    unittest.main()
