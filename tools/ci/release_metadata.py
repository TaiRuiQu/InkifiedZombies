"""Validate a release tag against the version in project.godot."""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import subprocess

VERSION_PATTERN = re.compile(r"\d+\.\d+\.\d+(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?\Z")
ROOT = Path(__file__).resolve().parents[2]


def project_version(root: Path = ROOT) -> str:
    match = re.search(r'^config/version="([^"]+)"$',
                      (root / "project.godot").read_text(encoding="utf-8-sig"), re.MULTILINE)
    if not match or not VERSION_PATTERN.fullmatch(match[1]):
        raise ValueError("project.godot needs a valid config/version, e.g. 0.2.2-beta")
    return match[1]


def validate_tag(tag: str, version: str) -> str:
    if tag and tag != f"v{version}":
        raise ValueError(f"Tag {tag!r} must match project version v{version}")
    return tag


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag", default="")
    args = parser.parse_args()
    version = project_version()
    tag = validate_tag(args.tag, version)
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    if tag:
        tagged_commit = subprocess.check_output(
            ["git", "rev-parse", f"refs/tags/{tag}^{{commit}}"], cwd=ROOT, text=True).strip()
        if tagged_commit != commit:
            raise ValueError("Release tag must point to the checked-out commit")
    values = {"version": version, "tag": tag, "commit": commit,
              "publish": "true" if tag else "false"}
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
            for key, value in values.items():
                output.write(f"{key}={value}\n")
    print(f"Building {version} at {commit}; publish={bool(tag)}")


if __name__ == "__main__":
    main()
