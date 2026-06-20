#!/usr/bin/env python3
"""Run the lightweight Python validation suite used by CI."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

COMMANDS = [
    [sys.executable, "-m", "compileall", "-q", "Python", "tools"],
    [
        sys.executable,
        "-m",
        "ruff",
        "check",
        "Python",
        "tools",
        "--select",
        "E9,F63,F7,F82",
        "--output-format=github",
    ],
    [sys.executable, "-m", "unittest", "discover", "-s", "Python/tests"],
]


def main() -> int:
    for command in COMMANDS:
        print(f"+ {' '.join(command)}", flush=True)
        completed = subprocess.run(command, cwd=ROOT)
        if completed.returncode != 0:
            return completed.returncode
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
