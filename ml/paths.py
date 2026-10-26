"""Where things live on disk.

The dataset and the preprocessed cache both live OUTSIDE the repo.
Only code (and gitignored checkpoints) live in ml/.
"""
from __future__ import annotations

import os
from pathlib import Path

ML_DIR = Path(__file__).resolve().parent
CHECKPOINT_DIR = ML_DIR / "checkpoints"


def dataset_dir() -> Path:
    """MathWriting root folder, read from the MW environment variable."""
    mw = os.environ.get("MW")
    if not mw:
        raise SystemExit(
            "MW is not set. Point it at the extracted MathWriting folder, e.g.\n"
            "  export MW=~/repos/datasets"
        )
    path = Path(mw).expanduser()
    if not (path / "train").is_dir():
        raise SystemExit(f"MW={path} does not contain a train/ folder.")
    return path


def cache_dir() -> Path:
    """Preprocessed arrays. Override with ML_CACHE; default ~/.cache/mathdb-ml."""
    path = Path(os.environ.get("ML_CACHE", "~/.cache/mathdb-ml")).expanduser()
    path.mkdir(parents=True, exist_ok=True)
    return path
