#!/usr/bin/env python3
"""Exercise the production TextKit layout and word identities without provider calls."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='finetext-animation-tests-') as temporary:
    binary = Path(temporary) / 'tests'
    subprocess.run([
        'swiftc', '-swift-version', '6', '-strict-concurrency=complete',
        '-module-cache-path', str(Path(temporary) / 'module-cache'),
        str(root / 'FineText/Views/RefinementWordLayout.swift'),
        str(root / 'scripts/tests/RefinementWordLayoutTests.swift'), '-o', str(binary),
    ], check=True)
    subprocess.run([str(binary)], check=True, timeout=15)
