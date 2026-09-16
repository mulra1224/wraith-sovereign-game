#!/usr/bin/env bash
set -euo pipefail

APK_PATH="${1:?usage: apk_security_audit.sh <apk> [expected-cert-sha256]}"
EXPECTED_CERT="${2:-}"
BUILD_TOOLS_ROOT="${ANDROID_HOME:-/opt/android-sdk}/build-tools"
AAPT="$(find "$BUILD_TOOLS_ROOT" -type f -name aapt | sort -V | tail -n 1)"
APKSIGNER="$(find "$BUILD_TOOLS_ROOT" -type f -name apksigner | sort -V | tail -n 1)"

test -s "$APK_PATH"
test -x "$AAPT"
test -x "$APKSIGNER"

PERMISSIONS="$("$AAPT" dump permissions "$APK_PATH")"
if printf '%s
' "$PERMISSIONS" | grep -q 'uses-permission:'; then
  printf '%s
' "$PERMISSIONS"
  echo "Unexpected Android permission detected." >&2
  exit 1
fi

BAD_MARKERS='android.permission.INTERNET|REQUEST_INSTALL_PACKAGES|SYSTEM_ALERT_WINDOW|BIND_ACCESSIBILITY_SERVICE|READ_SMS|SEND_SMS|QUERY_ALL_PACKAGES'
if unzip -p "$APK_PATH" AndroidManifest.xml | strings | grep -Eq "$BAD_MARKERS"; then
  echo "High-risk manifest marker detected." >&2
  exit 1
fi

"$APKSIGNER" verify --verbose --print-certs "$APK_PATH" | tee apk-signature.txt
ACTUAL_CERT="$(sed -n 's/^Signer #1 certificate SHA-256 digest: //p' apk-signature.txt | tr -d ':' | tr '[:upper:]' '[:lower:]' | head -n 1)"
test -n "$ACTUAL_CERT"

if [ -n "$EXPECTED_CERT" ] && [ "$ACTUAL_CERT" != "$(printf '%s' "$EXPECTED_CERT" | tr -d ':' | tr '[:upper:]' '[:lower:]')" ]; then
  echo "Release certificate fingerprint mismatch." >&2
  exit 1
fi

sha256sum "$APK_PATH" | tee apk-sha256.txt
echo "APK security audit passed: no requested permissions; signature verified."
