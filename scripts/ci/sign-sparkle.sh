#!/bin/bash
set -euo pipefail

: "${SIGNING_CERTIFICATE_NAME:?SIGNING_CERTIFICATE_NAME is required}"
APP_PATH="${APP_PATH:-output/output.xcarchive/Products/Applications/FineText.app}"
FRAMEWORK="$APP_PATH/Contents/Frameworks/Sparkle.framework/Versions/B"

retry_codesign() {
  local attempt
  for attempt in 1 2 3; do
    if codesign --force --options runtime --timestamp --sign "$SIGNING_CERTIFICATE_NAME" "$@"; then
      return 0
    fi
    if [ "$attempt" -lt 3 ]; then sleep 15; fi
  done
  return 1
}

# Sign inside out. Preserve the Downloader's own entitlements and the app's
# archived provisioning entitlements; do not propagate app entitlements to helpers.
retry_codesign "$FRAMEWORK/XPCServices/Installer.xpc"
retry_codesign --preserve-metadata=entitlements "$FRAMEWORK/XPCServices/Downloader.xpc"
retry_codesign "$FRAMEWORK/Autoupdate"
retry_codesign "$FRAMEWORK/Updater.app"
retry_codesign "$APP_PATH/Contents/Frameworks/Sparkle.framework"
retry_codesign --preserve-metadata=entitlements "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

# FineText intentionally disables App Sandbox so local agent CLIs can run.
# Require the explicit false value so lost entitlements still fail validation.
codesign -d --entitlements - --xml "$APP_PATH" 2>/dev/null |
  python3 -c 'import plistlib,sys; e=plistlib.loads(sys.stdin.buffer.read()); assert e.get("com.apple.security.app-sandbox") is False, "FineText must retain its non-sandboxed app entitlements"; assert "app.rxlab.finetext-spki" in e.get("com.apple.security.temporary-exception.mach-lookup.global-name", []), "Missing Sparkle installer Mach lookup entitlement"'
