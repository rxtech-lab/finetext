#!/bin/bash
# Local build check: generates the Xcode project and builds without signing.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
xcodegen generate --spec "$ROOT/project.yml" --project "$ROOT" --quiet
xcodebuild -project "$ROOT/FineText.xcodeproj" -scheme FineText -configuration "${CONFIGURATION:-Debug}" \
  -destination 'generic/platform=macOS' -derivedDataPath "$ROOT/build/DerivedData" CODE_SIGNING_ALLOWED=NO build "$@"
