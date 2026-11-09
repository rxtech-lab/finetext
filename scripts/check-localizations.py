#!/usr/bin/env python3
"""Check localization coverage, duplicate keys, and format argument parity on macOS."""
import json
from pathlib import Path
import re
import subprocess

root = Path(__file__).resolve().parents[1] / 'FineText'
localization = root / 'Localization'
keys = re.findall(r'^  case (\w+)$', (localization / 'LocalizableKey.swift').read_text(), re.M)
assert len(keys) == len(set(keys)), 'Duplicate LocalizableKey cases'
tables = {}
for language in ('en', 'zh-CN', 'zh-HK', 'zh-TW'):
    path = localization / f'{language}.lproj' / 'Localizable.strings'
    raw_keys = re.findall(r'^"(\w+)"\s*=', path.read_text(), re.M)
    assert len(raw_keys) == len(set(raw_keys)), f'{language}: duplicate keys'
    table = json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(path)]))
    assert set(table) == set(keys), f'{language}: keys differ from LocalizableKey'
    assert all(table.values()), f'{language}: empty translations'
    tables[language] = table

def placeholders(value):
    # Positional markers may be reordered by translators; compare argument positions and types.
    matches = re.findall(r'%(?:(\d+)\$)?(lld|@)', value)
    return sorted((int(position) if position else index, kind)
                  for index, (position, kind) in enumerate(matches, 1))

for language, table in tables.items():
    for key, value in table.items():
        assert placeholders(value) == placeholders(tables['en'][key]), f'{language}/{key}: placeholders differ'
for path in root.rglob('*.swift'):
    used = set(re.findall(r'LocalizableKey\.(\w+)\.(?:string|format)', path.read_text()))
    assert used <= set(keys), f'{path}: unknown keys {used - set(keys)}'
print(f'Validated {len(keys)} keys across {len(tables)} locales, including format arguments and Swift references.')
