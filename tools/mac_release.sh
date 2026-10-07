#!/bin/sh
# Sign, notarize and staple the macOS build, then wrap it in a DMG that is
# notarized and stapled too. Works on a desk with your login keychain, and
# in CI with a temporary one.
#   tools/mac_release.sh build/ParAndParcel.zip [build/ParAndParcel.dmg]
# Needs:
#   MACOS_CERTIFICATE_NAME   a "Developer ID Application: ..." identity in the keychain
#   APPLE_API_KEY            the App Store Connect API key: the .p8 contents, base64 of it, or a path to it
#   APPLE_API_KEY_ID         the key's id
#   APPLE_API_ISSUER         the issuer id
# Optional: APPLE_TEAM_ID (only checked against the identity), VOLUME_NAME.
set -eu
ZIP="${1:?the exported zip}"
OUT="${2:-${ZIP%.zip}.dmg}"
: "${MACOS_CERTIFICATE_NAME:?MACOS_CERTIFICATE_NAME is not set}"
: "${APPLE_API_KEY:?APPLE_API_KEY is not set}"
: "${APPLE_API_KEY_ID:?APPLE_API_KEY_ID is not set}"
: "${APPLE_API_ISSUER:?APPLE_API_ISSUER is not set}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/parandparcel-release.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# the API key, however it was handed over
KEY_FILE="$WORK/AuthKey.p8"
umask 077
if [ -f "$APPLE_API_KEY" ]; then
	cp "$APPLE_API_KEY" "$KEY_FILE"
elif printf '%s' "$APPLE_API_KEY" | grep -q 'BEGIN PRIVATE KEY'; then
	printf '%s\n' "$APPLE_API_KEY" | tr -d '\r' > "$KEY_FILE"
else
	printf '%s' "$APPLE_API_KEY" | tr -d '\r\n ' | base64 --decode > "$KEY_FILE"
fi
umask 022
KEYARGS="--key $KEY_FILE --key-id $APPLE_API_KEY_ID --issuer $APPLE_API_ISSUER"

notarize() {
	# submit, wait, and on a rejection fetch Apple's log so the reason is in the output
	OUT_TXT="$(xcrun notarytool submit "$1" $KEYARGS --wait 2>&1)" || true
	printf '%s\n' "$OUT_TXT"
	ID="$(printf '%s\n' "$OUT_TXT" | grep -Eo 'id: [0-9a-f-]{36}' | head -1 | awk '{print $2}')"
	STATUS="$(printf '%s\n' "$OUT_TXT" | grep -E '^[[:space:]]*status:' | tail -1 | awk '{print $2}')"
	if [ "$STATUS" != "Accepted" ]; then
		echo "notarization of $1 ended with status '${STATUS:-unknown}'" >&2
		[ -n "$ID" ] && xcrun notarytool log "$ID" $KEYARGS 2>&1 || true
		exit 1
	fi
}

echo "== unpacking $ZIP"
ditto -x -k "$ZIP" "$WORK/app"
APP="$(find "$WORK/app" -maxdepth 2 -name "*.app" | head -1)"
[ -n "$APP" ] || { echo "no .app inside $ZIP" >&2; exit 1; }
xattr -cr "$APP"
# Godot writes the project's name into Info.plist without escaping it, and
# "Par & Parcel" is not valid XML. Mend it, or codesign cannot bind the plist.
PLIST="$APP/Contents/Info.plist"
if ! plutil -lint -s "$PLIST" >/dev/null 2>&1; then
	sed -i '' -E 's/&([^a-zA-Z#][^;]*|$)/\&amp;\1/g' "$PLIST"
	plutil -lint -s "$PLIST" || { echo "Info.plist is still not valid" >&2; exit 1; }
	echo "== mended the ampersand in Info.plist"
fi

# Hardened runtime with the two exceptions a GDScript Godot game needs.
ENT="$WORK/entitlements.plist"
cat > "$ENT" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.cs.allow-unsigned-executable-memory</key>
	<true/>
	<key>com.apple.security.cs.allow-dyld-environment-variables</key>
	<true/>
</dict>
</plist>
PLIST

echo "== signing $(basename "$APP") as $MACOS_CERTIFICATE_NAME"
security find-identity -v -p codesigning | grep -q "$MACOS_CERTIFICATE_NAME" || { echo "identity not in the keychain" >&2; exit 1; }
# anything executable inside apart from the main program (which is signed
# with the bundle), then the bundle itself
find "$APP/Contents" -type f -perm -u+x ! -path "$APP/Contents/MacOS/*" | while IFS= read -r f; do
	file "$f" | grep -q "Mach-O" || continue
	codesign --force --sign "$MACOS_CERTIFICATE_NAME" --timestamp --options runtime "$f"
done
codesign --force --sign "$MACOS_CERTIFICATE_NAME" --timestamp --options runtime --entitlements "$ENT" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "== notarizing the app"
ditto -c -k --keepParent "$APP" "$WORK/notarize.zip"
notarize "$WORK/notarize.zip"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "== building the disk image"
STAGE="$WORK/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
rm -f "$OUT"
HERE="$(cd "$(dirname "$0")" && pwd)"
# the volume icon, from the game's icon
ICONSET="$WORK/vol.iconset"
mkdir -p "$ICONSET"
for sz in 16 32 128 256 512; do
	sips -z $sz $sz "$HERE/../icon.png" --out "$ICONSET/icon_${sz}x${sz}.png" >/dev/null
	sips -z $((sz * 2)) $((sz * 2)) "$HERE/../icon.png" --out "$ICONSET/icon_${sz}x${sz}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$WORK/vol.icns"
# the backdrop, sharp on a Retina screen
tiffutil -cathidpicheck "$HERE/dmg/background.png" "$HERE/dmg/background@2x.png" -out "$WORK/background.tiff" >/dev/null 2>&1 || cp "$HERE/dmg/background.png" "$WORK/background.tiff"
CREATE_DMG="$(command -v create-dmg || true)"
if [ -n "$CREATE_DMG" ]; then
	# the game on the left, Applications on the right, the arrow painted between them
	"$CREATE_DMG" --volname "${VOLUME_NAME:-Par & Parcel}" --volicon "$WORK/vol.icns" \
		--background "$WORK/background.tiff" --window-pos 200 120 --window-size 660 400 \
		--icon-size 128 --text-size 14 --icon "$(basename "$APP")" 170 205 --hide-extension "$(basename "$APP")" \
		--app-drop-link 490 205 --no-internet-enable "$OUT" "$STAGE" || { echo "create-dmg failed" >&2; exit 1; }
else
	echo "create-dmg is not installed (brew install create-dmg): making a plain disk image" >&2
	ln -s /Applications "$STAGE/Applications"
	hdiutil create -volname "${VOLUME_NAME:-Par & Parcel}" -srcfolder "$STAGE" -ov -format UDZO -quiet "$OUT"
fi
codesign --force --sign "$MACOS_CERTIFICATE_NAME" --timestamp "$OUT"
echo "== notarizing the disk image"
notarize "$OUT"
xcrun stapler staple "$OUT"
xcrun stapler validate "$OUT"
spctl -a -vv -t open --context context:primary-signature "$OUT" 2>&1 | tail -2 || true
echo "== done: $OUT"
