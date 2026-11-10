"""Offline safety checks for the official Godot installer (standard library only)."""
import hashlib
import importlib.util
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile


SCRIPT = Path(__file__).resolve().parents[1] / "tools" / "ci" / "install_godot.py"
SPEC = importlib.util.spec_from_file_location("install_godot", SCRIPT)
installer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(installer)


class GodotInstallerTests(unittest.TestCase):
    def test_unsupported_architecture_and_untrusted_version_fail(self):
        with self.assertRaises(ValueError):
            installer.target_platform("linux", "arm64")
        with self.assertRaises(ValueError):
            installer.asset_names("../../4.7.2", "linux")

    def test_checksum_manifest_rejects_duplicate_asset(self):
        digest = "a" * 128
        with self.assertRaises(ValueError):
            installer.parse_checksums(f"{digest}  same.zip\n{digest}  same.zip")

    def test_cached_archive_is_reused_only_after_hash_verification(self):
        with tempfile.TemporaryDirectory() as folder:
            archive = Path(folder) / "engine.zip"
            archive.write_bytes(b"correct bytes")
            digest = hashlib.sha512(archive.read_bytes()).hexdigest()
            with patch.object(installer.urllib.request, "urlopen", side_effect=AssertionError("cache should be verified offline")):
                self.assertEqual(installer.download_verified("https://example.invalid", archive, digest), archive)

    def test_bad_download_is_rejected_and_partial_removed(self):
        class Response(io.BytesIO):
            headers = {}
        with tempfile.TemporaryDirectory() as folder:
            archive = Path(folder) / "engine.zip"
            with patch.object(installer.urllib.request, "urlopen", side_effect=lambda *a, **kw: Response(b"wrong")), patch.object(installer.time, "sleep"):
                with self.assertRaises(RuntimeError):
                    installer.download_verified("https://example.invalid", archive, "0" * 128)
            self.assertFalse(archive.exists())
            self.assertFalse(archive.with_name("engine.zip.part").exists())

    def test_only_selected_template_is_extracted(self):
        data = io.BytesIO()
        with zipfile.ZipFile(data, "w") as archive:
            archive.writestr("templates/linux_release.x86_64", b"linux binary")
            archive.writestr("templates/windows_release_x86_64.exe", b"windows binary")
            archive.writestr("../../unexpected.txt", b"unselected malicious member")
        data.seek(0)
        with tempfile.TemporaryDirectory() as folder, zipfile.ZipFile(data) as archive:
            member = installer.selected_member(archive, "linux_release.x86_64")
            target = installer.install_member(archive, member, Path(folder), "linux_release.x86_64", True)
            self.assertEqual(target.read_bytes(), b"linux binary")
            self.assertEqual([p.name for p in Path(folder).iterdir()], ["linux_release.x86_64"])

    def test_traversal_and_duplicate_selected_members_are_rejected(self):
        for names in [("../godot",), ("one/godot", "two/godot")]:
            data = io.BytesIO()
            with zipfile.ZipFile(data, "w") as archive:
                for name in names:
                    archive.writestr(name, b"untrusted")
            data.seek(0)
            with zipfile.ZipFile(data) as archive, self.assertRaises(ValueError):
                installer.selected_member(archive, "godot")


if __name__ == "__main__":
    unittest.main()
