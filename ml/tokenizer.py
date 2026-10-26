"""Split LaTeX strings into tokens and map tokens to integer ids.

Example: r"\frac{dy}{dt}" -> ["\frac", "{", "d", "y", "}", "{", "d", "t", "}"]
"""
from __future__ import annotations

import json
import re
from collections import Counter
from typing import Iterable, List

# A command like \frac, an escaped symbol like \{ or \,, or any single non-space char.
TOKEN_RE = re.compile(r"\\[a-zA-Z]+|\\.|\S")

BLANK, UNK = "<blank>", "<unk>"  # CTC needs a "blank" token at id 0


def tokenize(latex: str) -> List[str]:
    return TOKEN_RE.findall(latex)


class Tokenizer:
    def __init__(self, tokens: List[str]):
        self.itos = [BLANK, UNK] + [t for t in tokens if t not in (BLANK, UNK)]
        self.stoi = {t: i for i, t in enumerate(self.itos)}

    @classmethod
    def build(cls, labels: Iterable[str], min_count: int = 1) -> "Tokenizer":
        counts = Counter(t for label in labels for t in tokenize(label))
        return cls(sorted(t for t, c in counts.items() if c >= min_count))

    def __len__(self) -> int:
        return len(self.itos)

    @property
    def blank_id(self) -> int:
        return 0

    def encode(self, latex: str) -> List[int]:
        unk = self.stoi[UNK]
        return [self.stoi.get(t, unk) for t in tokenize(latex)]

    def decode(self, ids: Iterable[int]) -> str:
        """Join tokens back into LaTeX.

        A space is added only where LaTeX needs one ("\\alpha x", not "\\alphax"),
        plus after the row break "\\\\" to match MathWriting's label style.
        """
        out, prev = "", ""
        for i in ids:
            if i == self.blank_id:
                continue
            tok = self.itos[i]
            if prev == "\\\\" or (re.fullmatch(r"\\[a-zA-Z]+", prev) and tok[0].isalpha()):
                out += " "
            out += tok
            prev = tok
        return out

    def save(self, path) -> None:
        with open(path, "w") as f:
            json.dump(self.itos, f, ensure_ascii=False, indent=0)

    @classmethod
    def load(cls, path) -> "Tokenizer":
        with open(path) as f:
            return cls(json.load(f))
