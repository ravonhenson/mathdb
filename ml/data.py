"""Preprocess InkML into a fast on-disk cache, and serve batches for training.

Parsing ~600k XML files is slow, so `prepare()` does it ONCE per split and
stores everything in a few numpy files under cache_dir()/<split>/:
    points.npy   float16 [total_points, 4]  all inks' features, concatenated
    offsets.npy  int64   [num_inks + 1]     ink i is points[offsets[i]:offsets[i+1]]
    labels.json  list[str]                  LaTeX target for each ink
    ids.json     list[str]                  file name (sample id) for each ink
"""
from __future__ import annotations

import json
import random
import time
from multiprocessing import Pool
from typing import List

import numpy as np
import torch
from torch.utils.data import Dataset, Sampler

from inkml import NUM_FEATURES, ink_to_features, read_inkml
from paths import cache_dir, dataset_dir
from tokenizer import Tokenizer


def _process(path):
    strokes, label = read_inkml(path)
    return path.stem, ink_to_features(strokes).astype(np.float16), label


def prepare(split: str, workers: int = 8) -> None:
    files = sorted((dataset_dir() / split).glob("*.inkml"))
    if not files:
        raise SystemExit(f"No .inkml files in {dataset_dir() / split}")
    print(f"[prepare] {split}: parsing {len(files):,} files with {workers} workers...")
    start = time.time()
    with Pool(workers) as pool:
        results = pool.map(_process, files, chunksize=256)

    ids, feats, labels = zip(*results)
    lengths = np.array([len(f) for f in feats])
    offsets = np.concatenate([[0], np.cumsum(lengths)]).astype(np.int64)

    out = cache_dir() / split
    out.mkdir(parents=True, exist_ok=True)
    np.save(out / "points.npy", np.concatenate(feats))
    np.save(out / "offsets.npy", offsets)
    (out / "labels.json").write_text(json.dumps(labels, ensure_ascii=False))
    (out / "ids.json").write_text(json.dumps(ids))
    print(
        f"[prepare] {split}: done in {time.time() - start:.0f}s -> {out}\n"
        f"          points per ink: median {int(np.median(lengths))}, "
        f"p99 {int(np.percentile(lengths, 99))}, max {lengths.max()}"
    )


def load_labels(split: str) -> List[str]:
    path = cache_dir() / split / "labels.json"
    if not path.exists():
        raise SystemExit(f"No cache for '{split}'. Run: python main.py prepare --splits {split}")
    return json.loads(path.read_text())


class InkDataset(Dataset):
    """Returns (features [T, 4] float32 tensor, target token ids, sample id)."""

    def __init__(self, splits, tokenizer: Tokenizer, max_points: int = 2048,
                 limit: int = 0, seed: int = 0):
        self.tokenizer = tokenizer
        self.items = []  # (split index, ink index, length)
        self.points, self.offsets, self.labels, self.ids = [], [], [], []
        for s_idx, split in enumerate(splits):
            folder = cache_dir() / split
            self.labels.append(load_labels(split))
            self.points.append(np.load(folder / "points.npy", mmap_mode="r"))
            self.offsets.append(np.load(folder / "offsets.npy"))
            self.ids.append(json.loads((folder / "ids.json").read_text()))
            lengths = np.diff(self.offsets[-1])
            for i, n in enumerate(lengths):
                # Skip empty inks and very long ones (they blow up memory).
                if 0 < n <= max_points:
                    self.items.append((s_idx, i, int(n)))
        if limit:
            random.Random(seed).shuffle(self.items)
            self.items = self.items[:limit]

    def __len__(self):
        return len(self.items)

    def lengths(self) -> List[int]:
        return [n for _, _, n in self.items]

    def __getitem__(self, idx):
        s, i, _ = self.items[idx]
        start, end = self.offsets[s][i], self.offsets[s][i + 1]
        x = torch.from_numpy(np.asarray(self.points[s][start:end], dtype=np.float32))
        y = torch.tensor(self.tokenizer.encode(self.labels[s][i]), dtype=torch.long)
        return x, y, self.ids[s][i]


class LengthBucketSampler(Sampler):
    """Yields batches of indices whose inks have similar lengths.

    Padding a 100-point ink to 2000 points wastes compute, so we sort by length
    inside large random chunks, cut batches, then shuffle the batch order.
    """

    def __init__(self, lengths, batch_size: int, shuffle: bool = True, seed: int = 0):
        self.lengths, self.batch_size, self.shuffle = lengths, batch_size, shuffle
        self.rng = random.Random(seed)

    def __iter__(self):
        idx = list(range(len(self.lengths)))
        if self.shuffle:
            self.rng.shuffle(idx)
        chunk = self.batch_size * 50
        batches = []
        for c in range(0, len(idx), chunk):
            part = sorted(idx[c:c + chunk], key=lambda i: self.lengths[i])
            batches += [part[b:b + self.batch_size] for b in range(0, len(part), self.batch_size)]
        if self.shuffle:
            self.rng.shuffle(batches)
        return iter(batches)

    def __len__(self):
        return (len(self.lengths) + self.batch_size - 1) // self.batch_size


def collate(batch):
    """Pad a list of samples into tensors the model and CTC loss expect."""
    xs, ys, ids = zip(*batch)
    x_lens = torch.tensor([len(x) for x in xs])
    x = torch.zeros(len(xs), int(x_lens.max()), NUM_FEATURES)
    for i, xi in enumerate(xs):
        x[i, : len(xi)] = xi
    y_lens = torch.tensor([len(y) for y in ys])
    y = torch.cat(ys)  # CTC accepts all targets concatenated into one 1-D tensor
    return x, x_lens, y, y_lens, list(ids)
