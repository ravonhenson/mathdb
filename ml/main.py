"""Command-line entry point for the handwriting -> LaTeX proof of concept.

    python main.py prepare --splits valid train test   # parse InkML once into a cache
    python main.py train --limit 2000 --epochs 1        # quick smoke run
    python main.py train --epochs 10                    # real run
    python main.py eval --split test
    python main.py predict $MW/test/<id>.inkml
"""
from __future__ import annotations

import argparse

import torch

from paths import CHECKPOINT_DIR


def cmd_prepare(args):
    from data import prepare
    for split in args.splits:
        prepare(split, workers=args.workers)


def cmd_train(args):
    from train import train
    train(args)


def cmd_eval(args):
    from data import InkDataset
    from train import evaluate, load_checkpoint, make_loader, pick_device
    device = pick_device()
    model, tokenizer, _ = load_checkpoint(args.ckpt, device)
    dataset = InkDataset([args.split], tokenizer, max_points=10**9, limit=args.limit)
    cer, exact, examples = evaluate(model, make_loader(dataset, 64, shuffle=False, device=device), tokenizer, device, show=10)
    print(f"{args.split}: {len(dataset):,} inks  CER {cer:.3f}  exact match {exact:.1%}")
    for sid, target, pred in examples:
        print(f"  {sid}\n    target: {target}\n    pred:   {pred}")


def cmd_predict(args):
    from inkml import ink_to_features, read_inkml
    from model import greedy_decode
    from train import load_checkpoint, pick_device
    device = pick_device()
    model, tokenizer, _ = load_checkpoint(args.ckpt, device)
    for path in args.files:
        strokes, label = read_inkml(path)
        x = torch.from_numpy(ink_to_features(strokes))[None].to(device)
        with torch.no_grad():
            log_probs, out_lens = model(x, torch.tensor([x.shape[1]], device=device))
        pred = tokenizer.decode(greedy_decode(log_probs, out_lens, tokenizer.blank_id)[0])
        print(f"{path}\n  pred:  {pred}\n  label: {label}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("prepare", help="parse InkML into the cache (outside the repo)")
    p.add_argument("--splits", nargs="+", default=["train", "valid", "test"])
    p.add_argument("--workers", type=int, default=8)
    p.set_defaults(func=cmd_prepare)

    p = sub.add_parser("train", help="train the CTC model")
    p.add_argument("--epochs", type=int, default=10)
    p.add_argument("--batch-size", type=int, default=256)
    p.add_argument("--lr", type=float, default=1e-3)
    p.add_argument("--hidden", type=int, default=256)
    p.add_argument("--layers", type=int, default=3)
    p.add_argument("--max-points", type=int, default=2048, help="skip longer inks")
    p.add_argument("--limit", type=int, default=0, help="use only N training inks (0 = all)")
    p.add_argument("--valid-limit", type=int, default=2000, help="valid inks scored each epoch")
    p.add_argument("--use-synthetic", action="store_true", help="also train on synthetic/")
    p.add_argument("--log-every", type=int, default=100)
    p.set_defaults(func=cmd_train)

    p = sub.add_parser("eval", help="score a checkpoint on a split")
    p.add_argument("--split", default="test")
    p.add_argument("--ckpt", default=str(CHECKPOINT_DIR / "best.pt"))
    p.add_argument("--limit", type=int, default=0)
    p.set_defaults(func=cmd_eval)

    p = sub.add_parser("predict", help="transcribe InkML files")
    p.add_argument("files", nargs="+")
    p.add_argument("--ckpt", default=str(CHECKPOINT_DIR / "best.pt"))
    p.set_defaults(func=cmd_predict)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
