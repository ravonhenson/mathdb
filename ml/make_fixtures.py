"""Write golden fixtures so the Swift app can prove it preprocesses ink like Python.

    MW=~/repos/datasets python make_fixtures.py     # -> fixtures/golden.json

For a handful of real validation inks, stores the raw strokes, the exact
float32 features from ink_to_features(), and the PyTorch prediction. A Swift
check feeds the same strokes through its FeatureEncoder / CTCDecoder and
compares. Regenerate whenever inkml.py, tokenizer.py, or the checkpoint changes.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import torch

from inkml import ink_to_features, read_inkml
from model import greedy_decode
from paths import CHECKPOINT_DIR, ML_DIR, dataset_dir
from train import load_checkpoint


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--ckpt", default=str(CHECKPOINT_DIR / "best.pt"))
    parser.add_argument("--count", type=int, default=8)
    parser.add_argument("--max-points", type=int, default=400, help="keep fixtures small")
    parser.add_argument("--out", default=str(ML_DIR / "fixtures" / "golden.json"))
    args = parser.parse_args()

    model, tokenizer, _ = load_checkpoint(args.ckpt, "cpu")
    cases = []
    for path in sorted((dataset_dir() / "valid").glob("*.inkml")):
        if len(cases) == args.count:
            break
        strokes, label = read_inkml(path)
        features = ink_to_features(strokes)
        if not 0 < len(features) <= args.max_points:
            continue
        with torch.no_grad():
            log_probs, lens = model(torch.from_numpy(features)[None], torch.tensor([len(features)]))
        ids = greedy_decode(log_probs, lens)[0]
        cases.append({
            "id": path.stem,
            "label": label,
            "strokes": [s.tolist() for s in strokes],
            "features": features.tolist(),
            "predicted_ids": ids,
            "predicted_latex": tokenizer.decode(ids),
        })

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps({"vocab_size": len(tokenizer), "cases": cases}))
    print(f"[fixtures] {len(cases)} cases -> {out}")
    for c in cases:
        print(f"  {c['id']}: {len(c['features'])} pts  label {c['label']!r}  pred {c['predicted_latex']!r}")


if __name__ == "__main__":
    main()
