import sys
from pathlib import Path

# Let tests import ml/ modules (inkml, tokenizer, ...) directly.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
