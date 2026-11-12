#!/usr/bin/env python3
"""Install a checksum-verified official Godot editor and selected export templates.

Uses only Python's standard library. Archives stay in DESTINATION/.downloads so
CI can cache them; archive paths are never extracted directly to the filesystem.
"""
from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path, PurePosixPath
import platform
import re
import shutil
import stat
import sys
import tempfile
import time
import urllib.error
import urllib.request
import zipfile


RELEASE_ROOT = "https://github.com/godotengine/godot-builds/releases/download"
VERSION_PATTERN = re.compile(r"[0-9]+\.[0-9]+(?:\.[0-9]+)?\Z")
USER_AGENT = "InkTide-CI-Godot-Installer/1.0"


def target_platform(system: str | None = None, machine: str | None = None) -> str:
    system = sys.platform if system is None else system
    machine = platform.machine() if machine is None else machine
    if machine.lower() not in {"x86_64", "amd64"}:
        raise ValueError(f"Only Windows/Linux x64 runners are supported, got {machine}")
    if system == "win32":
        return "windows"
    if system.startswith("linux"):
        return "linux"
    raise ValueError(f"Unsupported runner platform: {system}")


def asset_names(version: str, target: str) -> tuple[str, str, tuple[str, str]]:
    if not VERSION_PATTERN.fullmatch(version):
        raise ValueError("--version must be a stable numeric version, for example 4.7.2")
    prefix = f"Godot_v{version}-stable"
    if target == "windows":
        return (prefix + "_win64.exe.zip", prefix + "_win64.exe",
                ("windows_debug_x86_64.exe", "windows_release_x86_64.exe"))
    if target == "linux":
        return (prefix + "_linux.x86_64.zip", prefix + "_linux.x86_64",
                ("linux_debug.x86_64", "linux_release.x86_64"))
    raise ValueError(f"Unsupported target: {target}")


def parse_checksums(contents: str) -> dict[str, str]:
    result: dict[str, str] = {}
    for line in contents.splitlines():
        match = re.fullmatch(r"([0-9a-fA-F]{128})\s+\*?(.+)", line.strip())
        if not match:
            continue
        digest, filename = match.groups()
        if filename in result:
            raise ValueError(f"Duplicate checksum entry: {filename}")
        result[filename] = digest.lower()
    if not result:
        raise ValueError("Official SHA512-SUMS.txt contains no valid checksum entries")
    return result


def file_sha512(path: Path) -> str:
    digest = hashlib.sha512()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _request(url: str) -> urllib.request.Request:
    return urllib.request.Request(url, headers={"User-Agent": USER_AGENT})


def read_manifest(url: str) -> dict[str, str]:
    for attempt in range(3):
        try:
            with urllib.request.urlopen(_request(url), timeout=120) as response:
                contents = response.read(1024 * 1024 + 1)
            if len(contents) > 1024 * 1024:
                raise ValueError("Checksum manifest unexpectedly exceeds 1 MiB")
            return parse_checksums(contents.decode("utf-8-sig"))
        except (OSError, urllib.error.URLError) as error:
            if attempt == 2:
                raise RuntimeError(f"Could not download official checksum manifest: {error}") from error
            time.sleep(2 ** (attempt + 1))
    raise AssertionError("unreachable")


def download_verified(url: str, destination: Path, expected: str) -> Path:
    """Check every cached/downloaded byte before opening an archive."""
    partial = destination.with_name(destination.name + ".part")
    if destination.is_symlink() or partial.is_symlink():
        raise ValueError(f"Archive cache may not contain symbolic links: {destination.name}")
    if destination.is_file() and file_sha512(destination) == expected:
        print(f"Verified cached archive: {destination.name}", flush=True)
        return destination
    destination.parent.mkdir(parents=True, exist_ok=True)
    for attempt in range(3):
        try:
            print(f"Downloading {destination.name} (attempt {attempt + 1}/3)", flush=True)
            digest = hashlib.sha512()
            total = 0
            with urllib.request.urlopen(_request(url), timeout=120) as source, partial.open("wb") as output:
                expected_length = source.headers.get("Content-Length")
                while chunk := source.read(1024 * 1024):
                    output.write(chunk)
                    digest.update(chunk)
                    total += len(chunk)
            if expected_length and total != int(expected_length):
                raise ValueError(f"Truncated download of {destination.name}")
            if digest.hexdigest() != expected:
                raise ValueError(f"SHA-512 mismatch for {destination.name}; archive was rejected")
            partial.replace(destination)
            print(f"SHA-512 verified: {destination.name}", flush=True)
            return destination
        except (OSError, urllib.error.URLError, ValueError) as error:
            partial.unlink(missing_ok=True)
            if attempt == 2:
                raise RuntimeError(f"Download failed for {destination.name}: {error}") from error
            time.sleep(2 ** (attempt + 1))
    raise AssertionError("unreachable")


def selected_member(archive: zipfile.ZipFile, filename: str) -> zipfile.ZipInfo:
    """Accept exactly one regular member with the requested basename."""
    candidates = []
    for member in archive.infolist():
        path = PurePosixPath(member.filename)
        if path.name != filename:
            continue
        if (path.is_absolute() or ".." in path.parts or "\\" in member.filename
                or ":" in member.filename or member.is_dir()):
            raise ValueError(f"Unsafe archive member for {filename}")
        if stat.S_ISLNK(member.external_attr >> 16):
            raise ValueError(f"Archive member is a symlink: {filename}")
        candidates.append(member)
    if len(candidates) != 1:
        raise ValueError(f"Expected one {filename} archive member, found {len(candidates)}")
    return candidates[0]


def install_member(archive: zipfile.ZipFile, member: zipfile.ZipInfo,
                   directory: Path, filename: str, executable: bool = False) -> Path:
    directory = directory.resolve()
    directory.mkdir(parents=True, exist_ok=True)
    target = directory / filename
    if target.resolve().parent != directory:
        raise ValueError(f"Installation target escapes its directory: {filename}")
    descriptor, temporary = tempfile.mkstemp(prefix=".godot-install-", dir=directory)
    temporary_path = Path(temporary)
    try:
        with os.fdopen(descriptor, "wb") as output, archive.open(member) as source:
            shutil.copyfileobj(source, output, length=1024 * 1024)
        if executable:
            temporary_path.chmod(0o755)
        temporary_path.replace(target)
    finally:
        temporary_path.unlink(missing_ok=True)
    return target


def template_directory(version: str, target: str) -> Path:
    if target == "windows":
        appdata = os.environ.get("APPDATA")
        if not appdata:
            raise ValueError("APPDATA is required to install Windows Godot export templates")
        data_root = Path(appdata) / "Godot"
    else:
        data_root = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local" / "share")) / "godot"
    return data_root / "export_templates" / f"{version}.stable"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True, help="Official stable release number, e.g. 4.7.2")
    parser.add_argument("--destination", required=True, type=Path, help="Editor installation and archive cache directory")
    parser.add_argument("--templates", action="store_true", help="Install this runner OS's x64 debug/release export templates")
    parser.add_argument("--web-templates", action="store_true", help="Install single-threaded Web debug/release templates")
    arguments = parser.parse_args(argv)
    try:
        target = target_platform()
        editor_archive, editor_member, templates = asset_names(arguments.version, target)
        destination = arguments.destination.resolve()
        cache = destination / ".downloads"
        if not cache.resolve().is_relative_to(destination):
            raise ValueError("Archive cache escapes the requested installation directory")
        release_url = f"{RELEASE_ROOT}/{arguments.version}-stable"
        checksums = read_manifest(f"{release_url}/SHA512-SUMS.txt")
        required_assets = [editor_archive]
        templates_archive = f"Godot_v{arguments.version}-stable_export_templates.tpz"
        if arguments.templates or arguments.web_templates:
            required_assets.append(templates_archive)
        for asset in required_assets:
            if asset not in checksums:
                raise ValueError(f"Official SHA-512 manifest is missing required asset: {asset}")
        editor_zip = download_verified(f"{release_url}/{editor_archive}", cache / editor_archive,
                                       checksums[editor_archive])
        with zipfile.ZipFile(editor_zip) as archive:
            executable_name = "godot.exe" if target == "windows" else "godot"
            engine = install_member(archive, selected_member(archive, editor_member),
                                    destination, executable_name, executable=True)
            if target == "windows":
                wrapper_name = editor_member.removesuffix(".exe") + "_console.exe"
                install_member(archive, selected_member(archive, wrapper_name),
                               destination, "godot_console.exe", executable=True)
        print(f"Godot executable: {engine}", flush=True)
        if arguments.templates or arguments.web_templates:
            template_zip = download_verified(f"{release_url}/{templates_archive}", cache / templates_archive,
                                             checksums[templates_archive])
            template_root = template_directory(arguments.version, target)
            with zipfile.ZipFile(template_zip) as archive:
                selected_templates = list(templates) if arguments.templates else []
                if arguments.web_templates:
                    selected_templates.extend(("web_nothreads_debug.zip", "web_nothreads_release.zip"))
                for filename in selected_templates:
                    installed = install_member(archive, selected_member(archive, filename), template_root,
                                               filename, executable=True)
                    print(f"Export template: {installed}", flush=True)
        if github_path := os.environ.get("GITHUB_PATH"):
            with open(github_path, "a", encoding="utf-8") as output:
                output.write(str(destination) + "\n")
        return 0
    except (OSError, RuntimeError, ValueError, zipfile.BadZipFile) as error:
        print(f"Godot installation failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
