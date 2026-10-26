"""The CTC model: ink point sequence in, one token distribution per time step out.

    features [B, T, 4]
      -> Linear              lift 4 features to 128 dims
      -> Conv1d x2           look at nearby points; the 2nd conv halves T
      -> BiLSTM x3           read the whole ink left->right and right->left
      -> Linear              scores for every token (+ blank) at every step
    log-probs [B, T/2, vocab]

CTC loss then sums over every way of aligning the target tokens to those
time steps, so we never need to know which points belong to which symbol.
"""
from __future__ import annotations

import torch
from torch import nn

from inkml import NUM_FEATURES


class CTCModel(nn.Module):
    def __init__(self, vocab_size: int, hidden: int = 256, layers: int = 3, dropout: float = 0.2):
        super().__init__()
        self.config = dict(vocab_size=vocab_size, hidden=hidden, layers=layers, dropout=dropout)
        self.input = nn.Linear(NUM_FEATURES, 128)
        self.conv = nn.Sequential(
            nn.Conv1d(128, 128, kernel_size=5, padding=2), nn.GELU(),
            nn.Conv1d(128, 128, kernel_size=3, stride=2, padding=1), nn.GELU(),
        )
        self.lstm = nn.LSTM(128, hidden, num_layers=layers, bidirectional=True,
                            batch_first=True, dropout=dropout if layers > 1 else 0.0)
        self.dropout = nn.Dropout(dropout)
        self.output = nn.Linear(2 * hidden, vocab_size)

    @staticmethod
    def output_lengths(input_lengths: torch.Tensor) -> torch.Tensor:
        # Matches the stride-2 conv: ceil(T / 2).
        return (input_lengths + 1) // 2

    def forward(self, x: torch.Tensor, lengths: torch.Tensor):
        """Return (log_probs [B, T', vocab], out_lengths [B])."""
        h = self.input(x).transpose(1, 2)        # [B, 128, T]  (Conv1d wants channels first)
        h = self.conv(h).transpose(1, 2)         # [B, T', 128]
        out_lengths = self.output_lengths(lengths)
        # Zero the padded steps. We don't use pack_padded_sequence: on Apple's MPS
        # GPU it made training ~6x slower, and length-bucketed batches have little padding.
        mask = torch.arange(h.shape[1], device=h.device)[None, :] < out_lengths[:, None]
        h, _ = self.lstm(h * mask[..., None])
        return self.output(self.dropout(h)).log_softmax(-1), out_lengths


def greedy_decode(log_probs: torch.Tensor, lengths: torch.Tensor, blank: int = 0):
    """Best token per step, then merge repeats and remove blanks.

    e.g. steps "x x _ ^ ^ _ 2" -> "x ^ 2"
    """
    best = log_probs.argmax(-1).cpu()
    results = []
    for seq, n in zip(best, lengths.cpu()):
        seq = seq[: int(n)].tolist()
        out, prev = [], None
        for t in seq:
            if t != prev and t != blank:
                out.append(t)
            prev = t
        results.append(out)
    return results
