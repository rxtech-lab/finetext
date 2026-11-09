#!/usr/bin/env python3
"""Test actual offline inference using tiny synthetic DeBERTa checkpoints, not downloaded weights.

Run with the detector runtime's Python (torch, transformers, tokenizers, safetensors).
The fixtures test loading, head interpretation, long inputs, and malformed checkpoints.
They do not measure real-world detection accuracy.
"""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import torch
from safetensors.torch import save_file
from tokenizers import Tokenizer
from tokenizers.models import WordLevel
from tokenizers.pre_tokenizers import Whitespace
from tokenizers.processors import TemplateProcessing
from transformers import DebertaV2Config, DebertaV2Model, PreTrainedTokenizerFast

ROOT = Path(__file__).resolve().parents[1]
RUNNER = ROOT / "FineText/Resources/ai_detector.py"
spec = importlib.util.spec_from_file_location("detector", RUNNER)
detector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(detector)


def checkpoint(folder, labels, missing_head=False):
    config = DebertaV2Config(
        vocab_size=8, hidden_size=12, num_hidden_layers=1, num_attention_heads=3,
        intermediate_size=24, max_position_embeddings=512, relative_attention=True,
        position_biased_input=False, pos_att_type=["p2c", "c2p"], position_buckets=32,
        max_relative_positions=512,
    )
    config.detector_num_labels = labels
    config.save_pretrained(folder)
    backbone = DebertaV2Model(config)
    weights = {"model." + key: value for key, value in backbone.state_dict().items()}
    if not missing_head:
        weights["classifier.weight"] = torch.zeros(labels, config.hidden_size)
        weights["classifier.bias"] = torch.zeros(labels)
    save_file(weights, str(Path(folder) / "model.safetensors"), metadata={"format": "pt"})
    tok = Tokenizer(WordLevel({"[PAD]": 0, "[UNK]": 1, "[CLS]": 2, "[SEP]": 3, "word": 4}, unk_token="[UNK]"))
    tok.pre_tokenizer = Whitespace()
    tok.post_processor = TemplateProcessing(single="[CLS] $A [SEP]", special_tokens=[("[CLS]", 2), ("[SEP]", 3)])
    PreTrainedTokenizerFast(tokenizer_object=tok, unk_token="[UNK]", pad_token="[PAD]",
                           cls_token="[CLS]", sep_token="[SEP]").save_pretrained(folder)


class InferenceTests(unittest.TestCase):
    def test_binary_and_four_class_heads(self):
        for labels, engine, expected in [(1, "desklib", 50), (4, "tropa", 75)]:
            with tempfile.TemporaryDirectory() as folder:
                checkpoint(folder, labels)
                value = detector.score_text(folder, "word " * 1800, engine)
                self.assertAlmostEqual(value, expected)

    def test_missing_head_cannot_produce_a_random_score(self):
        with tempfile.TemporaryDirectory() as folder:
            checkpoint(folder, 1, missing_head=True)
            with self.assertRaisesRegex(ValueError, "architecture"):
                detector.score_text(folder, "word " * 60, "desklib")

    def test_wrong_engine_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            checkpoint(folder, 4)
            with self.assertRaisesRegex(ValueError, "selected engine"):
                detector.score_text(folder, "word " * 60, "desklib")

    def test_offline_stdin_protocol(self):
        with tempfile.TemporaryDirectory() as folder:
            checkpoint(folder, 1)
            env = dict(os.environ, HF_HUB_OFFLINE="1", TRANSFORMERS_OFFLINE="1", TOKENIZERS_PARALLELISM="false")
            result = subprocess.run([sys.executable, str(RUNNER)],
                input=json.dumps({"folder": folder, "engine": "desklib", "text": "word " * 60}),
                text=True, capture_output=True, env=env, check=True, timeout=30)
            self.assertEqual(json.loads(result.stdout), {"score": 50})


if __name__ == "__main__":
    unittest.main()
