#!/bin/zsh
# Builds dist/Bellhop.app from the SwiftPM product. No Xcode project needed.
#   scripts/bundle.sh          → dist/Bellhop.app (debug, fast incremental builds)
#   scripts/bundle.sh --release
#   scripts/bundle.sh --release --universal   → both Mac families, for releases
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=debug
ARCHS=()
for arg in "$@"; do
  case "$arg" in
    --release) CONFIG=release ;;
    --universal) ARCHS=(--arch arm64 --arch x86_64) ;;
  esac
done

# A stable identity keeps the Accessibility grant across rebuilds; ad-hoc signatures change every build.
SIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
if [[ -z "$SIGN_IDENTITY" ]] || ! security find-identity -v -p codesigning | grep -qF "$SIGN_IDENTITY"; then
  echo "warning: signing identity '${SIGN_IDENTITY}' not found, signing ad-hoc (Accessibility must be re-granted after each build)"
  SIGN_IDENTITY="-"
fi

# The repo lives in Dropbox; the toolchain cache and app bundle must not sync.
mkdir -p .build dist
xattr -w com.dropbox.ignored 1 .build dist 2>/dev/null || true

swift build -c "$CONFIG" "${ARCHS[@]}" --product BellhopApp
swift build -c "$CONFIG" "${ARCHS[@]}" --product bellhop
BIN="$(swift build -c "$CONFIG" "${ARCHS[@]}" --show-bin-path)/BellhopApp"
[[ -x "$BIN" ]] || { echo "build failed: $BIN missing"; exit 1; }

APP=dist/Bellhop.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Bellhop"
# The `bellhop` CLI rides along in Helpers (MacOS can't hold both `Bellhop` and `bellhop` on a case-insensitive
# disk). Homebrew links it onto PATH.
mkdir -p "$APP/Contents/Helpers"
cp "$(dirname "$BIN")/bellhop" "$APP/Contents/Helpers/bellhop"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns Resources/BellhopMenuTemplate.png Resources/BellhopMenuTemplate@2x.png "$APP/Contents/Resources/"
# SwiftPM resource bundles (KeyboardShortcuts' localizations) sit beside the binary. Packages look them up at
# runtime and crash without them, so ship every one.
for bundle in "$(dirname "$BIN")"/*.bundle; do
  [[ -d "$bundle" ]] && cp -R "$bundle" "$APP/Contents/Resources/"
done
# Sparkle, for in-app updates. Its XPC services are only for sandboxed apps, which Bellhop isn't, so they stay
# behind. Every piece is signed from the inside out: notarization wants each Mach-O signed with the hardened
# runtime, and library validation wants the framework signed by the same team as the app.
SPARKLE=.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework
[[ -d "$SPARKLE" ]] || { echo "Sparkle.framework missing: run swift package resolve"; exit 1; }
mkdir -p "$APP/Contents/Frameworks"
ditto "$SPARKLE" "$APP/Contents/Frameworks/Sparkle.framework"
FW="$APP/Contents/Frameworks/Sparkle.framework"
rm -rf "$FW/Versions/B/XPCServices" "$FW/XPCServices"
TIMESTAMP=(--timestamp=none)
[[ "$SIGN_IDENTITY" != "-" && "$CONFIG" == release ]] && TIMESTAMP=(--timestamp)
sign() { codesign --force --options runtime "${TIMESTAMP[@]}" --sign "$SIGN_IDENTITY" "$@"; }
sign "$FW/Versions/B/Autoupdate"
sign "$FW/Versions/B/Updater.app"
sign "$FW"
sign "$APP/Contents/Helpers/bellhop"
sign "$APP"
echo "built $APP"
