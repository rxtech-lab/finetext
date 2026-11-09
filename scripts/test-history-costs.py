#!/usr/bin/env python3
"""Exercise production SwiftData paging and accounting with no provider calls."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='finetext-history-costs-') as temporary:
    binary = Path(temporary) / 'tests'
    sources = [
        'FineText/Localization/LocalizableKey.swift', 'FineText/Models.swift',
        'FineText/Persistence.swift', 'FineText/Services/HistoryStore.swift',
        'FineText/Services/OpenAIClient.swift', 'scripts/tests/HistoryCostsTests.swift',
    ]
    subprocess.run([
        'swiftc', '-swift-version', '6', '-strict-concurrency=complete',
        '-module-cache-path', str(Path(temporary) / 'module-cache'),
        *[str(root / source) for source in sources], '-o', str(binary),
    ], check=True)
    subprocess.run([str(binary), temporary], check=True, timeout=30)
