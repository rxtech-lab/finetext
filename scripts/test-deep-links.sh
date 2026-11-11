#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPORARY="$(mktemp -d -t finetext-deep-links)"
trap 'rm -rf "$TEMPORARY"' EXIT
swiftc -swift-version 6 -module-cache-path "$TEMPORARY/module-cache" \
  "$ROOT/FineText/DeepLink.swift" "$ROOT/scripts/tests/DeepLinkTests.swift" \
  -o "$TEMPORARY/tests"
"$TEMPORARY/tests"
