"""Export a checksummed single-threaded Web build, optionally install into Paper."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import zipfile

from build_client import ROOT, digest, extract_engine_licenses, resolve_version, run_checked


def validate_export(directory: Path) -> dict[str, str]:
    required = ("index.html", "index.js", "index.wasm", "index.pck", "index.audio.worklet.js",
                "index.audio.position.worklet.js", "bootstrap.js", "shell.css")
    for name in required:
        if not (directory / name).is_file() or (directory / name).stat().st_size == 0:
            raise ValueError(f"Web export is missing {name}")
    with (directory / "index.wasm").open("rb") as wasm:
        if wasm.read(4) != b"\0asm":
            raise ValueError("Web export does not contain a valid WASM header")
    html = (directory / "index.html").read_text(encoding="utf-8")
    if "$GODOT_" in html:
        raise ValueError("Custom HTML contains unresolved Godot placeholders")
    return {item.name: digest(item) for item in sorted(directory.iterdir()) if item.is_file()}


def build(godot: Path, output: Path, version: str) -> Path:
    output = output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.is_relative_to(ROOT / "dist"):
        (ROOT / "dist/.gdignore").touch()
    logs = output.parent / "web-logs"
    editor = godot.resolve(strict=True)
    engine_version = run_checked([str(editor), "--version"], cwd=ROOT, log=logs / "version.log").strip()
    run_checked([str(editor), "--headless", "--path", str(ROOT), "--editor", "--import", "--quit"],
                cwd=ROOT, log=logs / "import.log")
    with tempfile.TemporaryDirectory(prefix="web-export-", dir=output.parent) as temporary:
        stage = Path(temporary)
        run_checked([str(editor), "--headless", "--path", str(ROOT), "--export-release", "Web Release", str(stage / "index.html")],
                    cwd=ROOT, log=logs / "export.log")
        for name in ("bootstrap.js", "shell.css"):
            shutil.copyfile(ROOT / "web" / name, stage / name)
        shutil.copyfile(ROOT / "THIRD_PARTY_NOTICES.md", stage / "THIRD_PARTY_NOTICES.md")
        shutil.copyfile(ROOT / "assets/fonts/OFL.txt", stage / "FONT_LICENSE.txt")
        extract_engine_licenses(editor, stage, logs)
        files = validate_export(stage)
        commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
        dirty = bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True).strip())
        manifest = {"name": "Ink Tide", "version": version, "platform": "web",
                    "godot_version": engine_version, "thread_support": False,
                    "source_commit": commit, "source_dirty": dirty,
                    "built_utc": datetime.now(timezone.utc).isoformat(), "files_sha256": files}
        (stage / "BUILD-MANIFEST.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        output.mkdir(parents=True, exist_ok=True)
        # Copy only the verified build. No recursive deletion of caller paths.
        for item in stage.iterdir():
            if item.is_file():
                shutil.copyfile(item, output / item.name)
        archive = output.parent / f"InkTide-{version}-Web.zip"
        with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as bundle:
            for item in sorted(stage.iterdir()):
                if item.is_file():
                    bundle.write(item, item.name)
        archive.with_name(archive.name + ".sha256.txt").write_text(f"{digest(archive)}  {archive.name}\n", encoding="utf-8")
    print(f"Web build: {output}\nVerified Web archive: {archive}", flush=True)
    return archive


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, type=Path)
    parser.add_argument("--output", type=Path, default=ROOT / "dist/web")
    parser.add_argument("--version")
    parser.add_argument("--paper-root", type=Path, help="Install this verified build into a local Paper checkout")
    args = parser.parse_args()
    try:
        version = resolve_version(args.version, ROOT / "project.godot")
        archive = build(args.godot, args.output, version)
        if args.paper_root:
            importer = args.paper_root.resolve() / "scripts/import-ink-tide.py"
            subprocess.run([sys.executable, str(importer), "--from", str(archive)], check=True)
        return 0
    except (OSError, RuntimeError, ValueError, subprocess.SubprocessError) as error:
        print(f"Web build failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
