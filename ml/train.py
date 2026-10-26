"""Training loop, evaluation, and checkpoint helpers."""
from __future__ import annotations

import contextlib
import math
import time

import torch
from torch.utils.data import DataLoader

from data import InkDataset, LengthBucketSampler, collate, load_labels
from model import CTCModel, greedy_decode
from paths import CHECKPOINT_DIR
from tokenizer import Tokenizer


def pick_device() -> torch.device:
    if torch.backends.mps.is_available():
        return torch.device("mps")  # Apple Silicon GPU
    if torch.cuda.is_available():
        # TF32 matmuls are a free win on Ampere/Ada GPUs. NOT cudnn.benchmark:
        # the length-bucketed sampler feeds it a continuously varying range of
        # shapes, so it keeps re-autotuning and caching new workspaces instead
        # of converging, and reserved memory grows until CUDA OOMs mid-run.
        torch.backends.cuda.matmul.allow_tf32 = True
        torch.backends.cudnn.allow_tf32 = True
        return torch.device("cuda")
    return torch.device("cpu")


def autocast(device: torch.device):
    if device.type == "cuda":
        return torch.autocast(device_type="cuda", dtype=torch.bfloat16)
    return contextlib.nullcontext()


def make_loader(dataset, batch_size, shuffle, device):
    sampler = LengthBucketSampler(dataset.lengths(), batch_size, shuffle=shuffle)
    # Overlap host-side batch prep with GPU compute; pointless on CPU/MPS.
    on_gpu = device.type == "cuda"
    return DataLoader(dataset, batch_sampler=sampler, collate_fn=collate,
                       num_workers=4 if on_gpu else 0, pin_memory=on_gpu,
                       persistent_workers=on_gpu)


def edit_distance(a, b) -> int:
    """Levenshtein distance between two token lists (insert/delete/substitute = 1)."""
    prev = list(range(len(b) + 1))
    for i, ta in enumerate(a, 1):
        cur = [i]
        for j, tb in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ta != tb)))
        prev = cur
    return prev[-1]


@torch.no_grad()
def evaluate(model, loader, tokenizer, device, show: int = 5):
    """Return token error rate (CER over LaTeX tokens), exact-match rate, and a few examples."""
    model.eval()
    errors = total = exact = count = 0
    examples = []
    for x, x_lens, y, y_lens, ids in loader:
        x, x_lens = x.to(device, non_blocking=True), x_lens.to(device, non_blocking=True)
        with autocast(device):
            log_probs, out_lens = model(x, x_lens)
        preds = greedy_decode(log_probs, out_lens, tokenizer.blank_id)
        targets = torch.split(y, y_lens.tolist())
        for pred, target, sid in zip(preds, targets, ids):
            target = target.tolist()
            errors += edit_distance(pred, target)
            total += len(target)
            exact += pred == target
            count += 1
            if len(examples) < show:
                examples.append((sid, tokenizer.decode(target), tokenizer.decode(pred)))
    model.train()
    return errors / max(total, 1), exact / max(count, 1), examples


def save_checkpoint(path, model, tokenizer, extra):
    path.parent.mkdir(parents=True, exist_ok=True)
    torch.save({"model": model.state_dict(), "config": model.config,
                "vocab": tokenizer.itos, **extra}, path)


def load_checkpoint(path, device):
    ckpt = torch.load(path, map_location=device)
    tokenizer = Tokenizer(ckpt["vocab"])
    model = CTCModel(**ckpt["config"]).to(device)
    model.load_state_dict(ckpt["model"])
    model.eval()
    return model, tokenizer, ckpt


def train(args):
    device = pick_device()
    splits = ["train"] + (["synthetic"] if args.use_synthetic else [])

    # Vocabulary = every LaTeX token seen in the training labels.
    tokenizer = Tokenizer.build(label for s in splits for label in load_labels(s))
    print(f"[train] device={device} splits={splits} vocab={len(tokenizer)} tokens")

    train_set = InkDataset(splits, tokenizer, max_points=args.max_points, limit=args.limit)
    valid_set = InkDataset(["valid"], tokenizer, max_points=args.max_points, limit=args.valid_limit)
    train_loader = make_loader(train_set, args.batch_size, shuffle=True, device=device)
    valid_loader = make_loader(valid_set, args.batch_size, shuffle=False, device=device)
    print(f"[train] {len(train_set):,} train inks, {len(valid_set):,} valid inks")

    model = CTCModel(len(tokenizer), hidden=args.hidden, layers=args.layers).to(device)
    print(f"[train] model has {sum(p.numel() for p in model.parameters()) / 1e6:.1f}M parameters")

    optimizer = torch.optim.AdamW(model.parameters(), lr=args.lr, weight_decay=1e-2)
    total_steps = args.epochs * len(train_loader)
    warmup = min(1000, total_steps // 10)
    # Linear warmup, then cosine decay to 0.
    schedule = torch.optim.lr_scheduler.LambdaLR(optimizer, lambda s: min(
        (s + 1) / max(warmup, 1), 0.5 * (1 + math.cos(math.pi * min(s / max(total_steps, 1), 1)))))
    ctc = torch.nn.CTCLoss(blank=tokenizer.blank_id, zero_infinity=True)

    step, best_cer = 0, float("inf")
    for epoch in range(1, args.epochs + 1):
        start, running = time.time(), 0.0
        for x, x_lens, y, y_lens, _ in train_loader:
            x, x_lens = x.to(device, non_blocking=True), x_lens.to(device, non_blocking=True)
            with autocast(device):
                log_probs, out_lens = model(x, x_lens)
            log_probs = log_probs.transpose(0, 1).float()
            if device.type == "mps":
                # CTC loss isn't implemented on MPS, so compute it on CPU.
                # Gradients still flow back to the GPU tensors.
                loss = ctc(log_probs.cpu(), y, out_lens.cpu(), y_lens)
            else:
                loss = ctc(log_probs, y.to(device, non_blocking=True), out_lens.cpu(), y_lens)
            optimizer.zero_grad()
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            optimizer.step()
            schedule.step()
            step += 1
            running += loss.item()
            if step % args.log_every == 0:
                print(f"  epoch {epoch} step {step}/{total_steps} loss {running / args.log_every:.3f} "
                      f"lr {schedule.get_last_lr()[0]:.2e} ({time.time() - start:.0f}s)")
                running = 0.0

        cer, exact, examples = evaluate(model, valid_loader, tokenizer, device)
        print(f"[epoch {epoch}] valid CER {cer:.3f}  exact match {exact:.1%}")
        for sid, target, pred in examples:
            print(f"    {sid}\n      target: {target}\n      pred:   {pred}")

        extra = {"epoch": epoch, "valid_cer": cer, "args": vars(args)}
        save_checkpoint(CHECKPOINT_DIR / "last.pt", model, tokenizer, extra)
        if cer < best_cer:
            best_cer = cer
            save_checkpoint(CHECKPOINT_DIR / "best.pt", model, tokenizer, extra)
            print(f"    new best -> {CHECKPOINT_DIR / 'best.pt'}")
