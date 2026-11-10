"""Build, smoke-test and package the relay on its native Windows/Linux runner."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import time
import urllib.request
import zipfile

from release_metadata import project_version, VERSION_PATTERN

ROOT = Path(__file__).resolve().parents[2]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", choices=["windows", "linux"], required=True)
    parser.add_argument("--version", default=project_version())
    parser.add_argument("--output", type=Path, default=ROOT / "dist/release")
    args = parser.parse_args()
    if not VERSION_PATTERN.fullmatch(args.version) or args.version != project_version():
        raise ValueError("Relay package version must match project.godot")
    if args.platform != ("windows" if os.name == "nt" else "linux"):
        raise ValueError("Native smoke testing requires the matching platform runner")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    folder = output / "staging" / f"relay-{args.platform}"
    folder.mkdir(parents=True, exist_ok=True)
    binary = folder / ("ink-tide-relay.exe" if args.platform == "windows" else "ink-tide-relay")
    environment = os.environ.copy()
    environment.update(CGO_ENABLED="0", GOOS=args.platform, GOARCH="amd64")
    subprocess.run(["go", "build", "-trimpath", f"-ldflags=-s -w -X main.version={args.version}", "-o", str(binary), "."],
                   cwd=ROOT / "server", env=environment, check=True, timeout=180)
    import socket
    with socket.socket() as socket_:
        socket_.bind(("127.0.0.1", 0))
        port = socket_.getsockname()[1]
    with tempfile.TemporaryDirectory(prefix="ink-relay-smoke-") as temporary:
        with open(Path(temporary) / "relay.log", "w", encoding="utf-8") as log:
            process = subprocess.Popen([str(binary), "-addr", f"127.0.0.1:{port}"],
                                       cwd=temporary, stdout=log, stderr=log)
            try:
                for _ in range(50):
                    if process.poll() is not None:
                        raise RuntimeError("Relay stopped before its health check")
                    try:
                        with urllib.request.urlopen(f"http://127.0.0.1:{port}/healthz", timeout=1) as response:
                            health = json.load(response)
                        if health.get("ok") is True and health.get("room_capacity") == 4 and health.get("version") == args.version:
                            break
                        raise RuntimeError(f"Unexpected health response: {health}")
                    except OSError:
                        time.sleep(0.1)
                else:
                    raise RuntimeError("Relay health check timed out")
            finally:
                process.terminate()
                process.wait(timeout=10)
    for name in ["README.md", "THIRD_PARTY_LICENSES.md"]:
        shutil.copyfile(ROOT / "server" / name, folder / name)
    # The deploy instructions retain the established platform-specific names.
    final_binary = folder / f"ink-tide-relay-{args.platform}-amd64{'.exe' if args.platform == 'windows' else ''}"
    binary.replace(final_binary)
    binary = final_binary
    manifest = {"version": args.version, "platform": args.platform, "arch": "amd64",
                "binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(), "health_check": "passed"}
    (folder / "BUILD-MANIFEST.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    suffix = "Windows-x64.zip" if args.platform == "windows" else "Linux-x64.tar.gz"
    archive = output / f"InkTide-Relay-{args.version}-{suffix}"
    if args.platform == "windows":
        with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as packed:
            for path in sorted(folder.iterdir()):
                packed.write(path, arcname=f"relay/{path.name}")
    else:
        binary.chmod(0o755)
        with tarfile.open(archive, "w:gz") as packed:
            packed.add(folder, arcname="relay")
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    Path(str(archive) + ".sha256.txt").write_text(f"{digest}  {archive.name}\n", encoding="utf-8")
    print(f"Built and health-checked {archive}")


if __name__ == "__main__":
    main()
