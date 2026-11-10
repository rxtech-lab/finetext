#!/usr/bin/env python3
"""Verify GIF wire requests, native bytes and persistence without provider calls."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='finetext-gif-') as temporary:
    binary = Path(temporary) / 'tests'
    sources = ['FineText/Localization/LocalizableKey.swift', 'FineText/Models.swift',
               'FineText/Persistence.swift', 'FineText/Services/OpenAIClient.swift',
               'FineText/Services/Codex.swift', 'FineText/Services/GenerationUsage.swift',
               'FineText/Services/PresetTemplate.swift', 'FineText/Services/Presets.swift',
               'scripts/tests/ImageGIFTests.swift']
    subprocess.run(['swiftc', '-swift-version', '6', '-strict-concurrency=complete',
                    '-module-cache-path', str(Path(temporary) / 'module-cache'),
                    *[str(root / source) for source in sources], '-o', str(binary)], check=True)
    subprocess.run([str(binary), temporary], check=True, timeout=30)
