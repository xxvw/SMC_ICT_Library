#!/usr/bin/env python3
"""Install the repository's shared Git hooks for this local clone."""

import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

if __name__ == "__main__":
    subprocess.run(["git", "config", "--local", "core.hooksPath", ".githooks"], cwd=ROOT, check=True)
    print("Installed .githooks. Push feature branches, then open a PR targeting main.")
