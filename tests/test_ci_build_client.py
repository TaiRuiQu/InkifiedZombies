"""Release integrity checks that do not require installing Godot."""
import importlib.util
from pathlib import Path
import stat
import tarfile
import tempfile
import unittest
import zipfile

MODULE = Path(__file__).resolve().parents[1] / "tools/ci/build_client.py"
SPEC = importlib.util.spec_from_file_location("ci_build_client", MODULE)
builder = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(builder)


class ReleaseIntegrityTests(unittest.TestCase):
    def test_tag_cannot_mislabel_project_version(self):
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory) / "project.godot"
            project.write_text('[application]\nconfig/version="0.2.2-beta"\n', encoding="utf-8")
            self.assertEqual(builder.resolve_version(None, project), "0.2.2-beta")
            with self.assertRaisesRegex(ValueError, "does not match"):
                builder.resolve_version("0.2.3", project)

    def test_version_cannot_escape_artifact_directory(self):
        for value in ["../../release", "v0.2.2", "0.2.2\nother", "0.2.2/../../bad", "0.2.2;echo bad"]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                builder.checked_version(value)

    def test_archives_only_contain_package_and_preserve_linux_execution(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            package = root / "package"
            package.mkdir()
            binary = package / "InkTide.x86_64"
            binary.write_bytes(b"example native executable")
            binary.chmod(0o755)
            (package / "InkTide.pck").write_bytes(b"example game data")
            (root / "private.env").write_text("not part of the package", encoding="utf-8")
            for platform in ["windows", "linux"]:
                archive = builder.make_archive(package, root / "output", "client", platform)
                if platform == "linux":
                    with tarfile.open(archive) as packed:
                        names = packed.getnames()
                        self.assertTrue(packed.getmember("client/InkTide.x86_64").mode & stat.S_IXUSR)
                else:
                    with zipfile.ZipFile(archive) as packed:
                        names = packed.namelist()
                self.assertFalse(any("private.env" in name for name in names))
                self.assertIn("client/InkTide.pck", names)
                recorded = archive.with_name(archive.name + ".sha256.txt").read_text(encoding="ascii")
                self.assertTrue(recorded.startswith(builder.digest(archive) + "  "))

    def test_engine_script_errors_are_detected_even_with_zero_exit(self):
        self.assertIsNotNone(builder.ENGINE_ERROR.search("Godot\nSCRIPT ERROR: Parse Error\n"))
        self.assertIsNotNone(builder.ENGINE_ERROR.search("Godot\nERROR: missing resource\n"))
        self.assertIsNone(builder.ENGINE_ERROR.search("[runtime] content loaded\n"))


if __name__ == "__main__":
    unittest.main()
