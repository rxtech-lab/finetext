#!/bin/bash
set -euo pipefail

# These values must come from this repository's RxLab-specific secrets.
: "${APPLE_ID:?RXLAB_APPLE_ID repository secret is required}"
: "${APPLE_ID_PWD:?RXLAB_APPLE_ID_PWD repository secret is required}"
: "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required}"
if [[ "$APPLE_TEAM_ID" != T7GYB573Y6 ]]; then
  echo '::error::FineText requires Rxlab LIMITED team T7GYB573Y6'
  exit 1
fi

# Authenticate before spending time building. Never print submission history.
xcrun notarytool history --apple-id "$APPLE_ID" --password "$APPLE_ID_PWD" \
  --team-id "$APPLE_TEAM_ID" --output-format json >/dev/null
echo 'RxLab notarization credentials validated.'
