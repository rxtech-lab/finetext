#!/usr/bin/env python3
"""Exercise both CLI adapters through RxAgentSDK without accounts or paid requests."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--sdk-path', type=Path, help='Use an existing RxAgentSDK checkout')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='finetext-agent-tests-') as temporary:
    package = Path(temporary)
    source = package / 'Sources' / 'AdapterTests'
    source.mkdir(parents=True)
    dependency = (f'.package(path: {json.dumps(str(args.sdk_path.resolve()))})' if args.sdk_path else
                  '.package(url: "https://github.com/rxtech-lab/RxAgentSDK", revision: "5f2eba0a2f55d1a4181f4a82a6046f3a8445310a")')
    identity = args.sdk_path.name if args.sdk_path else 'RxAgentSDK'
    (package / 'Package.swift').write_text('''// swift-tools-version: 6.3
import PackageDescription
let package = Package(name: "AdapterTests", platforms: [.macOS(.v26)],
  dependencies: [''' + dependency + '''],
  targets: [.executableTarget(name: "AdapterTests", dependencies: [
    .product(name: "RxAgentSDK", package: "''' + identity + '''")])])
''')
    for relative in ['FineText/Services/AgentTextSession.swift', 'FineText/Services/ClaudeCode.swift',
                     'FineText/Services/Codex.swift', 'FineText/Services/GenerationUsage.swift',
                     'FineText/Localization/LocalizableKey.swift', 'FineText/Models.swift',
                     'FineText/Persistence.swift', 'FineText/Services/OpenAIClient.swift',
                     'FineText/Services/PresetTemplate.swift', 'FineText/Services/Presets.swift',
                     'FineText/Services/GrammarMarkup.swift',
                     'scripts/tests/ClaudeCodeSessionTests.swift']:
        shutil.copy(root / relative, source)
    subprocess.run(['swift', 'run', '--package-path', str(package), 'AdapterTests'], check=True, timeout=300)
