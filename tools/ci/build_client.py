"""Build and smoke-test an official Godot release-template client.

The Godot editor and matching native export templates must already be installed.
No third-party Python packages are needed. Run from any working directory.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[2]
VERSION = re.compile(r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?$")
ENGINE_ERROR = re.compile(r"^(?:SCRIPT ERROR:|ERROR:)", re.MULTILINE)
RUNTIME_MARKER = "[runtime] title, map, settings, audio and content loaded"
PLATFORMS = {
    "windows": ("Windows Release", "Windows-x64", "InkTide.exe"),
    "linux": ("Linux Release", "Linux-x64", "InkTide.x86_64"),
}


def project_version(project_file: Path) -> str:
    match = re.search(r'^config/version="([^"\r\n]+)"$', project_file.read_text(encoding="utf-8-sig"), re.MULTILINE)
    if not match:
        raise ValueError("project.godot must define application config/version")
    return checked_version(match.group(1))


def checked_version(value: str) -> str:
    if not VERSION.fullmatch(value):
        raise ValueError(f"Expected a safe semantic version such as 0.2.2-beta, got {value!r}")
    return value


def resolve_version(requested: str | None, project_file: Path) -> str:
    actual = project_version(project_file)
    requested = actual if requested is None else checked_version(requested)
    if requested != actual:
        raise ValueError(f"Release version {requested!r} does not match project.godot {actual!r}; update the project before tagging")
    return actual


def digest(path: Path) -> str:
    checksum = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            checksum.update(chunk)
    return checksum.hexdigest()


def run_checked(command: list[str], *, cwd: Path, log: Path, timeout: int = 900) -> str:
    print("Running:", " ".join(command), flush=True)
    try:
        result = subprocess.run(command, cwd=cwd, text=True, encoding="utf-8", errors="replace", stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, timeout=timeout, check=False)
    except subprocess.TimeoutExpired as error:
        raise RuntimeError(f"Command exceeded {timeout} seconds: {command[0]}") from error
    output = result.stdout or ""
    log.parent.mkdir(parents=True, exist_ok=True)
    log.write_text(output, encoding="utf-8")
    print(output, end="" if output.endswith("\n") else "\n", flush=True)
    if result.returncode != 0 or ENGINE_ERROR.search(output):
        raise RuntimeError(f"Godot command failed (exit {result.returncode}); see {log}")
    return output


def extract_engine_licenses(godot: Path, package: Path, log_directory: Path) -> None:
    # Run without the project loaded; this reads the licenses from the exact
    # editor that built this release instead of fetching a different web copy.
    script_text = '''extends SceneTree
func _initialize() -> void:
    var destination := OS.get_cmdline_user_args()[0]
    var output := FileAccess.open(destination, FileAccess.WRITE)
    output.store_string(Engine.get_license_text() + "\\n\\nBundled dependency licenses\\n")
    var licenses := Engine.get_license_info()
    for key in licenses:
        output.store_string("\\n===== " + String(key) + " =====\\n" + String(licenses[key]) + "\\n")
    output.store_string("\\nBundled dependency copyright notices\\n")
    output.store_string(JSON.stringify(Engine.get_copyright_info(), "  ") + "\\n")
    output.close()
    quit(0)
'''
    with tempfile.TemporaryDirectory(prefix="ink-tide-licenses-") as directory:
        temporary = Path(directory)
        script = temporary / "licenses.gd"
        script.write_text(script_text, encoding="utf-8")
        run_checked([str(godot), "--headless", "--path", str(temporary), "--script", str(script), "--",
                     str(package / "ENGINE_LICENSES.txt")], cwd=temporary,
                    log=log_directory / "engine-licenses.log", timeout=45)
    if (package / "ENGINE_LICENSES.txt").stat().st_size < 1000:
        raise RuntimeError("Engine license extraction returned an incomplete document")


def verify_runtime(executable: Path, log_directory: Path) -> None:
    runtime_log = (log_directory / "runtime.log").resolve()
    with tempfile.TemporaryDirectory(prefix="ink-tide-runtime-") as directory:
        temporary = Path(directory)
        run_checked([str(executable), "--headless", "--log-file", str(runtime_log), "--", "--verify-runtime"],
                    cwd=temporary, log=log_directory / "runtime-process.log", timeout=30)
    if not runtime_log.is_file():
        raise RuntimeError("The exported client did not create its verification log")
    text = runtime_log.read_text(encoding="utf-8-sig", errors="replace")
    if ENGINE_ERROR.search(text) or RUNTIME_MARKER not in text:
        raise RuntimeError(f"Exported client failed resource/startup verification; see {runtime_log}")


def make_archive(package: Path, output: Path, archive_name: str, platform: str) -> Path:
    output.mkdir(parents=True, exist_ok=True)
    extension = ".zip" if platform == "windows" else ".tar.gz"
    archive = output / (archive_name + extension)
    if platform == "windows":
        with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as packed:
            for item in sorted(package.rglob("*")):
                if item.is_file():
                    packed.write(item, (Path(archive_name) / item.relative_to(package)).as_posix())
    else:
        def preserve_native_execution(info: tarfile.TarInfo) -> tarfile.TarInfo:
            if Path(info.name).name == "InkTide.x86_64":
                info.mode |= 0o111
            return info
        with tarfile.open(archive, "w:gz", compresslevel=9) as packed:
            packed.add(package, arcname=archive_name, filter=preserve_native_execution)
    archive.with_name(archive.name + ".sha256.txt").write_text(f"{digest(archive)}  {archive.name}\n", encoding="ascii")
    return archive


def checked_out_commit() -> str:
    result = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True, text=True)
    return result.stdout.strip() if result.returncode == 0 else "uncommitted"


def build(godot: Path, platform: str, version: str, output: Path) -> Path:
    preset, label, executable_name = PLATFORMS[platform]
    native_platform = "windows" if sys.platform == "win32" else "linux" if sys.platform.startswith("linux") else None
    if platform != native_platform:
        raise ValueError("Build on the target OS so the exported executable is tested before publication")
    godot = godot.resolve(strict=True)
    # Windows' official console wrapper waits for the editor and preserves its
    # exit code when launched by a terminal. Prefer it for import and export.
    console = godot.with_name(godot.stem + "_console.exe") if platform == "windows" else godot
    editor = console if console.is_file() else godot
    output = output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    log_directory = output / "logs" / platform
    engine_version = run_checked([str(editor), "--version"], cwd=ROOT,
                                 log=log_directory / "engine-version.log", timeout=30).strip()
    run_checked([str(editor), "--headless", "--path", str(ROOT), "--editor", "--import", "--quit"],
                cwd=ROOT, log=log_directory / "import.log")
    staging = output / "staging"
    staging.mkdir(exist_ok=True)
    # A unique staging directory avoids recursive deletion of any user path.
    with tempfile.TemporaryDirectory(prefix=platform + "-", dir=staging) as directory:
        package = Path(directory) / "client"
        package.mkdir()
        executable = package / executable_name
        run_checked([str(editor), "--headless", "--path", str(ROOT), "--export-release", preset, str(executable)],
                    cwd=ROOT, log=log_directory / "export.log")
        if not executable.is_file() or not (package / "InkTide.pck").is_file():
            raise RuntimeError("Official export must contain both the native executable and InkTide.pck")
        if platform == "linux":
            executable.chmod(executable.stat().st_mode | 0o111)
        shutil.copyfile(ROOT / "THIRD_PARTY_NOTICES.md", package / "THIRD_PARTY_NOTICES.md")
        shutil.copyfile(ROOT / "assets/fonts/OFL.txt", package / "FONT_LICENSE.txt")
        extract_engine_licenses(editor, package, log_directory)
        package.joinpath("README.txt").write_text(
            f"Ink Tide / 墨潮 {version} — {label}\n\n"
            f"Extract the complete folder and run {executable_name}. Godot does not need to be installed.\n"
            "Keep InkTide.pck beside the executable. A Vulkan-capable graphics driver is required.\n"
            "Friends: select 同守 (multiplayer) on the title screen. Direct connections use UDP 7777;\n"
            "the standalone relay uses TCP 7778. The relay runs separately on Windows or Linux.\n"
            "This client uses Godot's official release export template.\n"
            "Licenses: THIRD_PARTY_NOTICES.md, FONT_LICENSE.txt and ENGINE_LICENSES.txt.\n",
            encoding="utf-8")
        verify_runtime(executable, log_directory)
        file_hashes = {item.relative_to(package).as_posix(): digest(item) for item in sorted(package.rglob("*")) if item.is_file()}
        manifest = {"name": "Ink Tide", "version": version, "platform": label,
                    "packaging": "official-godot-release-export-template", "preset": preset,
                    "godot_version": engine_version,
                    "built_utc": datetime.now(timezone.utc).isoformat(),
                    "source_commit": checked_out_commit(), "headless_startup_exit_code": 0,
                    "files_sha256": file_hashes}
        package.joinpath("BUILD-MANIFEST.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        package.joinpath("SHA256SUMS.txt").write_text(
            "".join(f"{value}  {filename}\n" for filename, value in file_hashes.items()), encoding="utf-8")
        return make_archive(package, output, f"InkTide-{version}-{label}", platform)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--platform", choices=PLATFORMS, required=True)
    parser.add_argument("--version")
    parser.add_argument("--output", type=Path, default=ROOT / "dist/release")
    arguments = parser.parse_args()
    try:
        version = resolve_version(arguments.version, ROOT / "project.godot")
        archive = build(arguments.godot, arguments.platform, version, arguments.output)
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"Build failed: {error}", file=sys.stderr)
        return 1
    print(f"Verified client archive: {archive}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
