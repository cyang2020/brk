#!/bin/bash
# Notarizes an app signed by scripts/sign-developer-id.sh and staples the ticket to it, so Gatekeeper opens the
# downloaded app without a network check or a warning. Uses an App Store Connect API key (docs/release.md).
#
#   NOTARY_KEY=/path/AuthKey_XXXX.p8 NOTARY_KEY_ID=XXXX NOTARY_ISSUER=<issuer uuid> scripts/notarize.sh dist/Brk.app
#
# Submits a zip of the app (ditto keeps the signature and the framework symlinks), waits for Apple's verdict and, on
# anything but Accepted, prints Apple's log and fails. Several apps can be notarized at once: run one per app.
set -euo pipefail
APP="${1:?usage: NOTARY_KEY=... NOTARY_KEY_ID=... NOTARY_ISSUER=... notarize.sh <path to .app>}"
: "${NOTARY_KEY:?}" "${NOTARY_KEY_ID:?}" "${NOTARY_ISSUER:?}"
AUTH=(--key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER")
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ditto -c -k --keepParent "$APP" "$WORK/submit.zip"
echo "[notarize] submitting $APP ($(du -h "$WORK/submit.zip" | cut -f1))"
xcrun notarytool submit "$WORK/submit.zip" "${AUTH[@]}" --wait --timeout 45m --output-format json > "$WORK/result.json" || true
cat "$WORK/result.json"
ID="$(/usr/bin/python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1])).get("id", ""))' "$WORK/result.json" 2>/dev/null || true)"
STATUS="$(/usr/bin/python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1])).get("status", ""))' "$WORK/result.json" 2>/dev/null || true)"
if [ "$STATUS" != "Accepted" ]; then
  echo "[notarize] $APP: status '${STATUS:-none}'" >&2
  [ -n "$ID" ] && xcrun notarytool log "$ID" "${AUTH[@]}" >&2 || true
  exit 1
fi
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
if ! spctl --assess --type execute -vvv "$APP"; then
  syspolicy_check distribution "$APP" --verbose >&2 || true
  exit 1
fi
echo "[notarize] $APP notarized ($ID) and stapled"
