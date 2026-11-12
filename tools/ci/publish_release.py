"""Publish only a complete, checksummed set of native and Web release packages."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess

from release_metadata import project_version, validate_tag


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--directory", type=Path, required=True)
    args = parser.parse_args()
    version = project_version()
    validate_tag(args.tag, version)
    if not args.tag:
        raise ValueError("Publishing requires an existing version tag")
    directory = args.directory.resolve(strict=True)
    files: list[Path] = []
    checksums: list[str] = []
    for product in ["InkTide", "InkTide-Relay"]:
        for suffix in ["Windows-x64.zip", "Linux-x64.tar.gz"]:
            archive = directory / f"{product}-{version}-{suffix}"
            sidecar = directory / f"{archive.name}.sha256.txt"
            digest = hashlib.sha256(archive.read_bytes()).hexdigest()
            if sidecar.read_text(encoding="utf-8-sig").strip() != f"{digest}  {archive.name}":
                raise ValueError(f"Checksum mismatch: {archive.name}")
            files.extend([archive, sidecar])
            checksums.append(f"{digest}  {archive.name}")
    web = directory / f"InkTide-{version}-Web.zip"
    web_sidecar = directory / f"{web.name}.sha256.txt"
    web_digest = hashlib.sha256(web.read_bytes()).hexdigest()
    if web_sidecar.read_text(encoding="utf-8-sig").strip() != f"{web_digest}  {web.name}":
        raise ValueError(f"Checksum mismatch: {web.name}")
    files.extend([web, web_sidecar])
    checksums.append(f"{web_digest}  {web.name}")
    combined = directory / "SHA256SUMS.txt"
    combined.write_text("\n".join(checksums) + "\n", encoding="utf-8")
    files.append(combined)
    existing = subprocess.run(["gh", "release", "view", args.tag, "--json", "isDraft,url"],
                              capture_output=True, text=True)
    if existing.returncode:
        command = ["gh", "release", "create", args.tag, "--verify-tag", "--draft",
                   "--title", f"Ink Tide {version}", "--generate-notes"]
        if "-" in version:
            command.append("--prerelease")
        subprocess.run(command, check=True)
        is_draft = True
    else:
        is_draft = bool(json.loads(existing.stdout)["isDraft"])
    subprocess.run(["gh", "release", "upload", args.tag, *map(str, files), "--clobber"], check=True)
    if is_draft:
        subprocess.run(["gh", "release", "edit", args.tag, "--draft=false"], check=True)
    print(f"Published five verified packages for {args.tag}")


if __name__ == "__main__":
    main()
