#!/usr/bin/env bash
# Put the macOS signing and notarization secrets on the GitHub repo, from the
# certificate folder on this Mac. Notarization uses an App Store Connect API
# key: no Apple ID, no app-specific password. The two things not stored on
# disk, the .p12 password and the key's Issuer ID, are asked for and never
# written anywhere.
#   tools/apple_secrets.sh [owner/repo]
set -euo pipefail
REPO="${1:-linux4life1/par-and-parcel}"
DIR="${CERT_DIR:-$HOME/Desktop/cert stuff}"
CERT="$DIR/DevID_with_key.p12"                  # Developer ID Application certificate with its private key
KEY="$(ls "$DIR"/AuthKey_*.p8 | head -1)"        # the App Store Connect API key
KEY_ID="$(basename "$KEY" .p8)"; KEY_ID="${KEY_ID#AuthKey_}"
CERT_NAME="$(security find-identity -v -p codesigning | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"')"
TEAM_ID="$(printf '%s' "$CERT_NAME" | grep -o '([A-Z0-9]*)' | tr -d '()')"
[ -f "$CERT" ] || { echo "no certificate at $CERT"; exit 1; }
[ -f "$KEY" ] || { echo "no API key in $DIR"; exit 1; }
[ -n "$CERT_NAME" ] || { echo "no Developer ID Application identity in the keychain"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "run: gh auth login"; exit 1; }
echo "repo $REPO, identity $CERT_NAME, key $KEY_ID"
gh secret set MACOS_CERTIFICATE_NAME --repo "$REPO" --body "$CERT_NAME"
gh secret set APPLE_TEAM_ID          --repo "$REPO" --body "$TEAM_ID"
gh secret set APPLE_API_KEY_ID       --repo "$REPO" --body "$KEY_ID"
gh secret set MACOS_CERTIFICATE      --repo "$REPO" --body "$(base64 -i "$CERT")"
gh secret set APPLE_API_KEY          --repo "$REPO" --body "$(base64 -i "$KEY")"
read -rs -p "password of $(basename "$CERT"): " P12PWD; echo
gh secret set MACOS_CERTIFICATE_PWD  --repo "$REPO" --body "$P12PWD"; unset P12PWD
read -rp "App Store Connect Issuer ID (Users and Access, Integrations, above the keys): " ISSUER
gh secret set APPLE_API_ISSUER       --repo "$REPO" --body "$ISSUER"; unset ISSUER
echo; gh secret list --repo "$REPO" | awk '{print $1}'
