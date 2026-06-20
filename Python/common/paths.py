"""Path helpers shared by Python training scripts."""

from __future__ import annotations

from pathlib import Path

PYTHON_DIR = Path(__file__).resolve().parents[1]
PROJECT_ROOT = PYTHON_DIR.parent


def default_model_dir() -> Path:
    """Return the repository-level model output directory."""
    return PROJECT_ROOT / "Files" / "models"


def resolve_output_dir(output_dir: str | Path | None = None) -> Path:
    """Resolve an output directory independently of the current cwd."""
    if output_dir is None:
        return default_model_dir()

    path = Path(output_dir)
    if path.is_absolute():
        return path
    return (PYTHON_DIR / path).resolve()
