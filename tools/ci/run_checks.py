"""Run real Godot regressions; a zero exit code alone does not prove success."""
from __future__ import annotations

import argparse
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
ERROR = re.compile(r"^(?:SCRIPT ERROR:|ERROR:|.*\bFAIL(?:URE)?\b)", re.MULTILINE)
TESTS = [
    "tests/audio_audit.gd",
    "tests/interaction_audit.gd",
    "tests/enemy_hitbox_audit.gd",
    "tests/shot_registration_audit.gd",
    "tests/player_action_audit.gd",
    "tests/enemy_pacing_audit.gd",
    "tests/enemy_audio_audit.gd",
    "tests/special_enemy_audit.gd",
    "tests/lifetime_regression.gd",
]


def run(godot: Path, name: str, arguments: list[str], marker: str | None = None) -> None:
    logs = ROOT / "dev_shots" / "ci"
    logs.mkdir(parents=True, exist_ok=True)
    command = [str(godot), "--headless", "--path", str(ROOT), *arguments]
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True,
                            encoding="utf-8", errors="replace", timeout=180)
    output = result.stdout + result.stderr
    (logs / f"{name}.log").write_text(output, encoding="utf-8")
    print(output, flush=True)
    if result.returncode or ERROR.search(output) or (marker and marker not in output):
        raise RuntimeError(f"{name} failed; see dev_shots/ci/{name}.log")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, type=Path)
    args = parser.parse_args()
    godot = args.godot.resolve(strict=True)
    run(godot, "import", ["--editor", "--import", "--quit"])
    for script in TESTS:
        marker = "PASS" if script in ["tests/audio_audit.gd", "tests/enemy_hitbox_audit.gd"] else "failures=0"
        run(godot, Path(script).stem, ["--script", f"res://{script}", "--", "--role=ci"], marker)
    run(godot, "ten-wave-run", ["--", "--beta-test"], "[beta] RESULT failures=0")
    print("All Godot CI checks passed.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
