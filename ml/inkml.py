"""Read MathWriting InkML files and turn ink into model features.

An ink is a list of strokes. A stroke is the path of the pen between
touching the screen and lifting it: an array of (x, y) points.
"""
from __future__ import annotations

import xml.etree.ElementTree as ET
from typing import List, Tuple

import numpy as np

NS = "{http://www.w3.org/2003/InkML}"
NUM_FEATURES = 4  # dx, dy, y, pen_start


def read_inkml(path) -> Tuple[List[np.ndarray], str]:
    """Return (strokes, label). Each stroke is a float32 array of shape [n, 2]."""
    root = ET.parse(path).getroot()
    label = ""
    for ann in root.findall(NS + "annotation"):
        if ann.get("type") == "normalizedLabel":
            label = (ann.text or "").strip()
    strokes = []
    for trace in root.findall(NS + "trace"):
        # Text looks like "x y t,x y t,..."; we keep x and y and drop time.
        points = [p.split()[:2] for p in trace.text.strip().split(",")]
        strokes.append(np.asarray(points, dtype=np.float32))
    return strokes, label


def ink_to_features(strokes: List[np.ndarray]) -> np.ndarray:
    """Convert strokes into one [N, 4] sequence the model reads point by point.

    Per point: [dx, dy, y, pen_start]
      - dx, dy: movement since the previous point (shape of the writing)
      - y: vertical position (tells superscripts from subscripts)
      - pen_start: 1.0 on the first point of each stroke (pen went down)
    Coordinates are divided by the ink height so big and small handwriting
    look the same to the model.
    """
    cleaned = []
    for s in strokes:
        if len(s) > 1:  # drop points where the pen didn't move
            keep = np.ones(len(s), dtype=bool)
            keep[1:] = np.any(s[1:] != s[:-1], axis=1)
            s = s[keep]
        if len(s):
            cleaned.append(s)
    if not cleaned:
        return np.zeros((0, NUM_FEATURES), dtype=np.float32)

    xy = np.concatenate(cleaned)
    pen_start = np.zeros(len(xy), dtype=np.float32)
    pen_start[np.cumsum([0] + [len(s) for s in cleaned[:-1]])] = 1.0

    xy = xy - xy.min(axis=0)
    height = max(float(xy[:, 1].max()), 1.0)
    xy = xy / height

    delta = np.diff(xy, axis=0, prepend=xy[:1])
    return np.column_stack([delta, xy[:, 1], pen_start]).astype(np.float32)
