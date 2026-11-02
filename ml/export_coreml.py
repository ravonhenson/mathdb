"""Export a trained checkpoint to Core ML for the iOS app.

    python export_coreml.py                       # best.pt -> ../MyApp/Model/
    python export_coreml.py --ckpt checkpoints/last.pt

Writes two files the app loads at runtime:
    MathCTC.mlpackage   ink features [1, N, 4] in -> log_probs [1, ceil(N/2), vocab] out
    vocab.json          token list; index = token id (0 = CTC blank)

Then checks the Core ML model against PyTorch on real validation inks.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import coremltools as ct
import numpy as np
import torch
from torch import nn

from data import load_labels
from inkml import NUM_FEATURES
from model import greedy_decode
from paths import CHECKPOINT_DIR, ML_DIR, cache_dir
from train import edit_distance, load_checkpoint

APP_MODEL_DIR = ML_DIR.parent / "MyApp" / "Model"
MAX_POINTS = 2048  # the longest ink seen in training (train --max-points)


class InferenceWrapper(nn.Module):
    """CTCModel.forward for a single ink with no padding.

    With batch size 1 every point is real, so the padding mask is all ones and
    can be dropped. That leaves a graph with one input, which converts cleanly.
    """

    def __init__(self, model):
        super().__init__()
        self.model = model

    def forward(self, x):
        m = self.model
        h = m.input(x).transpose(1, 2)
        h = m.conv(h).transpose(1, 2)
        h, _ = m.lstm(h)
        return m.output(h).log_softmax(-1)


def convert(model, ckpt, name: str, precision: str):
    wrapper = InferenceWrapper(model).eval()
    example = torch.randn(1, 256, NUM_FEATURES)
    traced = torch.jit.trace(wrapper, example)

    mlmodel = ct.convert(
        traced,
        inputs=[ct.TensorType(name="ink", dtype=np.float32,
                              shape=(1, ct.RangeDim(1, MAX_POINTS, default=256), NUM_FEATURES))],
        outputs=[ct.TensorType(name="log_probs", dtype=np.float32)],
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS18,
        # fp16 halves the file and runs on the Neural Engine; validate() shows what it costs.
        compute_precision=ct.precision.FLOAT16 if precision == "fp16" else ct.precision.FLOAT32,
    )
    mlmodel.short_description = "Handwritten math ink -> LaTeX token log-probabilities (CTC)."
    mlmodel.input_description["ink"] = "Per-point features [dx, dy, y, pen_start] from ink_to_features()."
    mlmodel.output_description["log_probs"] = "Log-probabilities per time step; greedy CTC decode with blank = 0."
    mlmodel.user_defined_metadata.update({
        "name": name,
        "epoch": str(ckpt.get("epoch")),
        "valid_cer": f"{ckpt.get('valid_cer', float('nan')):.4f}",
        "vocab_size": str(len(ckpt["vocab"])),
        "max_points": str(MAX_POINTS),
        "precision": precision,
    })
    return mlmodel


def validate(model, tokenizer, mlmodel, count: int):
    """Compare Core ML against PyTorch (fp32) on validation inks.

    Reports how often the greedy decodes match, and the largest probability
    difference. (Log-probs aren't compared directly: tokens with ~zero
    probability can hit -inf in fp16, which is a huge but meaningless gap.)
    """
    folder = cache_dir() / "valid"
    points = np.load(folder / "points.npy", mmap_mode="r")
    offsets = np.load(folder / "offsets.npy")
    labels = load_labels("valid")

    same = checked = 0
    max_diff = 0.0
    errors_ref = errors_ml = total = 0
    for i in range(len(labels)):
        if checked == count:
            break
        start, end = offsets[i], offsets[i + 1]
        if not 0 < end - start <= MAX_POINTS:
            continue
        x = np.asarray(points[start:end], dtype=np.float32)[None]
        with torch.no_grad():
            ref, ref_lens = model(torch.from_numpy(x), torch.tensor([x.shape[1]]))
        out = mlmodel.predict({"ink": x})["log_probs"]
        max_diff = max(max_diff, float(np.abs(np.exp(out) - ref.exp().numpy()).max()))
        pred_ref = greedy_decode(ref, ref_lens)[0]
        pred_ml = greedy_decode(torch.from_numpy(out), ref_lens)[0]
        target = tokenizer.encode(labels[i])
        errors_ref += edit_distance(pred_ref, target)
        errors_ml += edit_distance(pred_ml, target)
        total += len(target)
        same += pred_ref == pred_ml
        checked += 1
    print(f"[export] Core ML vs PyTorch on {checked} valid inks: identical decode {same}/{checked}, "
          f"max |prob diff| {max_diff:.3f}, CER PyTorch {errors_ref / total:.3f} vs Core ML {errors_ml / total:.3f}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--ckpt", default=str(CHECKPOINT_DIR / "best.pt"))
    parser.add_argument("--out", default=str(APP_MODEL_DIR))
    parser.add_argument("--name", default="MathCTC")
    parser.add_argument("--precision", choices=["fp16", "fp32"], default="fp16")
    parser.add_argument("--validate", type=int, default=200, help="valid inks to compare (0 = skip)")
    args = parser.parse_args()

    model, tokenizer, ckpt = load_checkpoint(args.ckpt, "cpu")
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    mlmodel = convert(model, ckpt, args.name, args.precision)
    package = out / f"{args.name}.mlpackage"
    mlmodel.save(str(package))
    (out / "vocab.json").write_text(json.dumps(tokenizer.itos, ensure_ascii=False, indent=0))
    print(f"[export] epoch {ckpt.get('epoch')} valid CER {ckpt.get('valid_cer', float('nan')):.3f}"
          f" -> {package} (+ vocab.json, {len(tokenizer)} tokens)")

    if args.validate:
        validate(model, tokenizer, mlmodel, args.validate)


if __name__ == "__main__":
    main()
