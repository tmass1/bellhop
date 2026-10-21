#!/bin/zsh
# Builds dist/Valet.app from the SwiftPM product. No Xcode project needed.
#   scripts/bundle.sh          → dist/Valet.app (debug, fast incremental builds)
#   scripts/bundle.sh --release
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=debug
for arg in "$@"; do
  case "$arg" in
    --release) CONFIG=release ;;
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

swift build -c "$CONFIG" --product ValetApp
BIN="$(swift build -c "$CONFIG" --show-bin-path)/ValetApp"
[[ -x "$BIN" ]] || { echo "build failed: $BIN missing"; exit 1; }

APP=dist/Valet.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Valet"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns Resources/ValetMenuTemplate.png Resources/ValetMenuTemplate@2x.png "$APP/Contents/Resources/"
codesign --force --options runtime --sign "$SIGN_IDENTITY" "$APP"
echo "built $APP"
