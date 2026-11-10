#!/usr/bin/env python3
"""Check the app's preset template renderer against the website's shared cases, the bundled
catalog, structured output parsing and the preset store's cache/offline behaviour."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='finetext-presets-') as temporary:
    binary = Path(temporary) / 'tests'
    sources = [
        'FineText/Localization/LocalizableKey.swift', 'FineText/Models.swift', 'FineText/Persistence.swift',
        'FineText/Services/OpenAIClient.swift', 'FineText/Services/GenerationUsage.swift',
        'FineText/Services/PresetTemplate.swift', 'FineText/Services/Presets.swift',
        'scripts/tests/PresetTests.swift',
    ]
    subprocess.run([
        'swiftc', '-swift-version', '6', '-strict-concurrency=complete', '-parse-as-library',
        '-module-cache-path', str(Path(temporary) / 'module-cache'),
        *[str(root / source) for source in sources], '-o', str(binary),
    ], check=True)
    subprocess.run([str(binary), str(root), temporary], check=True, timeout=60)
