#!/bin/bash
set -euo pipefail
: "${APPLE_ID:?}" "${APPLE_ID_PWD:?}" "${APPLE_TEAM_ID:?}" "${SIGNING_CERTIFICATE_NAME:?}"
bash "$(dirname "$0")/validate-notary.sh"
APP_PATH=output/output.xcarchive/Products/Applications/FineText.app
codesign --verify --deep --strict "$APP_PATH"
# Notarize and staple the app before making the distribution image.
ditto -c -k --keepParent "$APP_PATH" output/FineText.zip
xcrun notarytool submit output/FineText.zip --apple-id "$APPLE_ID" --password "$APPLE_ID_PWD" --team-id "$APPLE_TEAM_ID" --wait
xcrun stapler staple "$APP_PATH"
mkdir -p output/dmg
ditto "$APP_PATH" output/dmg/FineText.app
ln -s /Applications output/dmg/Applications
hdiutil create -volname FineText -srcfolder output/dmg -ov -format UDZO FineText.dmg
codesign --sign "$SIGNING_CERTIFICATE_NAME" --timestamp FineText.dmg
xcrun notarytool submit FineText.dmg --apple-id "$APPLE_ID" --password "$APPLE_ID_PWD" --team-id "$APPLE_TEAM_ID" --wait
xcrun stapler staple FineText.dmg
xcrun stapler validate FineText.dmg
