"""Prevent publishing mislabeled versions or shell-shaped tag strings."""
import importlib.util
from pathlib import Path
import tempfile
import unittest


MODULE = Path(__file__).resolve().parents[1] / "tools/ci/release_metadata.py"
spec = importlib.util.spec_from_file_location("release_metadata", MODULE)
metadata = importlib.util.module_from_spec(spec)
spec.loader.exec_module(metadata)


class ReleaseVersionTests(unittest.TestCase):
    def test_exact_tag_and_artifact_only(self):
        self.assertEqual(metadata.validate_tag("v0.2.2-beta", "0.2.2-beta"), "v0.2.2-beta")
        self.assertEqual(metadata.validate_tag("", "0.2.2-beta"), "")

    def test_stale_and_untrusted_tag_rejected(self):
        for tag in ["v0.2.1-beta", "0.2.2-beta", "v0.2.2-beta\nfoo=bar", "v0.2.2-beta; echo token"]:
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                metadata.validate_tag(tag, "0.2.2-beta")

    def test_invalid_or_missing_project_version_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for config in ['config/version="../../out"', "[application]\n", 'config/version="1.2.3\ninvalid"']:
                (root / "project.godot").write_text(config, encoding="utf-8")
                with self.subTest(config=config), self.assertRaises(ValueError):
                    metadata.project_version(root)


if __name__ == "__main__":
    unittest.main()
