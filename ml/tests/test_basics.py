"""Fast checks that don't need the dataset."""
import numpy as np
import torch

from inkml import NUM_FEATURES, ink_to_features
from model import CTCModel, greedy_decode
from tokenizer import Tokenizer, tokenize
from train import edit_distance


def test_tokenize_splits_commands_and_symbols():
    assert tokenize(r"\frac{dy}{dt}") == ["\\frac", "{", "d", "y", "}", "{", "d", "t", "}"]
    assert tokenize(r"a\,b\{") == ["a", "\\,", "b", "\\{"]


def test_tokenizer_round_trip():
    labels = [r"\frac{dy}{dt}", r"\alpha x^{2}", r"\dot{y}=\sin\theta",
              r"(\begin{matrix}a&b\\ bd&d\end{matrix})"]  # "\\ b" must not look like "\b"
    tok = Tokenizer.build(labels)
    for label in labels:
        ids = tok.encode(label)
        assert 0 not in ids  # blank is never a real token
        assert tok.decode(ids) == label


def test_features_are_normalized():
    strokes = [np.array([[0, 0], [0, 0], [10, 100]], np.float32),  # repeated point gets dropped
               np.array([[50, 50]], np.float32)]                      # a dot
    f = ink_to_features(strokes)
    assert f.shape == (3, NUM_FEATURES)
    assert f[:, 2].min() == 0 and f[:, 2].max() == 1  # y scaled to [0, 1]
    assert f[:, 3].tolist() == [1, 0, 1]               # pen_start marks each stroke


def test_greedy_decode_merges_repeats_and_drops_blanks():
    steps = [3, 3, 0, 4, 4, 0, 3]  # "a a _ b b _ a"
    log_probs = torch.nn.functional.one_hot(torch.tensor(steps), 5).float()[None]
    assert greedy_decode(log_probs, torch.tensor([7])) == [[3, 4, 3]]


def test_model_output_lengths_match():
    model = CTCModel(vocab_size=10, hidden=16, layers=1)
    x, lens = torch.randn(2, 9, NUM_FEATURES), torch.tensor([9, 4])
    log_probs, out_lens = model(x, lens)
    assert log_probs.shape == (2, 5, 10)
    assert out_lens.tolist() == [5, 2]


def test_edit_distance():
    assert edit_distance([1, 2, 3], [1, 2, 3]) == 0
    assert edit_distance([1, 3], [1, 2, 3]) == 1
