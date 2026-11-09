#!/usr/bin/env python3
"""Run round-loop regressions and offline detector helper tests without downloading models."""
from pathlib import Path
import importlib.util
import subprocess
import tempfile
import unittest
import sys

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("detector", ROOT / "FineText/Resources/ai_detector.py")
detector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(detector)


class DetectorTests(unittest.TestCase):
    def test_document_score_uses_all_windows(self):
        ids = list(range(2000))
        windows = list(detector.token_windows(ids))
        self.assertEqual([len(w) for w in windows], [766, 766, 468])
        self.assertEqual([token for window in windows for token in window], ids)

    def test_length_weighted_probability(self):
        self.assertAlmostEqual(detector.weighted_score([(0.2, 100), (0.8, 300)]), 65)

    def test_invalid_probabilities_are_rejected(self):
        for values in [[], [(float("nan"), 1)], [(float("inf"), 1)], [(1.1, 1)], [(-0.1, 1)]]:
            with self.assertRaises(ValueError):
                detector.weighted_score(values)


if __name__ == "__main__":
    with tempfile.TemporaryDirectory(prefix="finetext-humanization-") as directory:
        executable = Path(directory) / "tests"
        subprocess.run([
            "swiftc", "-swift-version", "6", "-parse-as-library", "-module-cache-path", str(Path(directory) / "cache"),
            str(ROOT / "FineText/Services/HumanizationLoop.swift"),
            str(ROOT / "scripts/tests/HumanizationLoopTests.swift"), "-o", str(executable),
        ], check=True)
        subprocess.run([str(executable)], check=True, timeout=30)
        subprocess.run([
            "swiftc", "-swift-version", "6", "-parse-as-library", "-module-cache-path", str(Path(directory) / "cache"),
            str(ROOT / "FineText/Services/DetectorProcess.swift"),
            str(ROOT / "scripts/tests/DetectorProcessTests.swift"), "-o", str(executable),
        ], check=True)
        subprocess.run([str(executable), sys.executable], check=True, timeout=30)
    unittest.main()
