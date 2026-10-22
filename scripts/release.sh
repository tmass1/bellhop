#!/bin/zsh
# Cuts a release: universal build, Developer ID signature, notarization, a zip (for Homebrew and Sparkle), a disk
# image (for people) and the Sparkle appcast on a GitHub release, and the Homebrew cask bumped to match.
# Needs docs/releases/<version>.md (the notes people see in the update window) and Bellhop's update-signing key in
# the login keychain (`generate_keys --account bellhop`, once per Mac that releases).
#   scripts/release.sh                 → everything, for the version in Resources/Info.plist
#   scripts/release.sh --skip-notarize → sign and package without notarizing (Gatekeeper will complain; for testing)
#   scripts/release.sh --dry-run       → build, sign, notarize and package (dist/Bellhop.zip, dist/Bellhop.dmg), but no
#                                        GitHub release and no tap push: the way to make a build to hand to someone
# Notarization reuses Burn's stored credential (same team). To make a new one:
#   xcrun notarytool store-credentials bellhop-notary --apple-id <apple id> --team-id Y5V8Y3BH9A
set -euo pipefail
cd "$(dirname "$0")/.."

NOTARIZE=1
PUBLISH=1
for arg in "$@"; do
  case "$arg" in
    --skip-notarize) NOTARIZE=0 ;;
    --dry-run) PUBLISH=0 ;;
  esac
done

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" Resources/Info.plist)
TAG="v$VERSION"
APP=dist/Bellhop.app
ZIP=dist/Bellhop.zip   # constant names, so releases/latest/download/Bellhop.zip and Bellhop.dmg always work
DMG=dist/Bellhop.dmg
APPCAST=dist/appcast.xml   # releases/latest/download/appcast.xml is the SUFeedURL every copy reads
NOTES_FILE="docs/releases/$VERSION.md"
SPARKLE_BIN=.build/artifacts/sparkle/Sparkle/bin
DEVELOPER_ID="${BELLHOP_DEVELOPER_ID:-Developer ID Application: Thomas Massaro (Y5V8Y3BH9A)}"
NOTARY_PROFILE="${BELLHOP_NOTARY_PROFILE:-burn-notary}"
TAP_REPO="${BELLHOP_TAP_REPO:-tmass1/homebrew-tap}"
RELEASE_REPO="${BELLHOP_RELEASE_REPO:-tmass1/bellhop}"

echo "→ Bellhop $VERSION ($BUILD)"
# The CLI reports BellhopCore.version; it has to agree with the app's.
grep -q "version = \"$VERSION\"" Sources/BellhopCore/BellhopCore.swift \
  || { echo "BellhopCore.version doesn't match $VERSION in Info.plist"; exit 1; }
if [[ $PUBLISH -eq 1 ]] && gh release view "$TAG" --repo "$RELEASE_REPO" >/dev/null 2>&1; then
  echo "release $TAG already exists: bump CFBundleShortVersionString first"; exit 1
fi
# Fail before the build if anything the end of the run needs is missing.
[[ -f "$NOTES_FILE" ]] || { echo "no release notes: write $NOTES_FILE first (they show in the update window)"; exit 1; }
[[ -x "$SPARKLE_BIN/sign_update" ]] || swift package resolve >/dev/null
"$SPARKLE_BIN/generate_keys" --account bellhop -p >/dev/null 2>&1 \
  || { echo "no update-signing key: run $SPARKLE_BIN/generate_keys --account bellhop"; exit 1; }
# Sparkle compares build numbers: each release's CFBundleVersion must beat the one already published.
PUBLISHED=$(curl -fsSL "https://github.com/$RELEASE_REPO/releases/latest/download/appcast.xml" 2>/dev/null \
  | sed -n 's:.*<sparkle\:version>\([0-9.]*\)</sparkle\:version>.*:\1:p' | head -1 || true)
if [[ -n "$PUBLISHED" ]] && ! [[ "$BUILD" -gt "$PUBLISHED" ]]; then
  echo "CFBundleVersion $BUILD must be greater than the published build $PUBLISHED"; exit 1
fi
if [[ $NOTARIZE -eq 1 ]] && ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  echo "no notarization credential '$NOTARY_PROFILE': run"
  echo "  xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <apple id> --team-id Y5V8Y3BH9A"
  exit 1
fi

# 1. Build both architectures and sign with the Developer ID certificate (hardened runtime, secure timestamp).
CODESIGN_IDENTITY="$DEVELOPER_ID" scripts/bundle.sh --release --universal
codesign --verify --deep --strict "$APP"
lipo -archs "$APP/Contents/MacOS/Bellhop"
codesign -dv --verbose=2 "$APP" 2>&1 | grep -E "Authority=Developer ID|TeamIdentifier" | head -2

# 2. Notarize the zipped app, staple the ticket to the app, then zip again for distribution.
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
if [[ $NOTARIZE -eq 1 ]]; then
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  spctl -a -vv -t exec "$APP" 2>&1 | tail -2
else
  echo "(not notarized)"
fi
SHA=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)
echo "→ $ZIP  sha256 $SHA"

# 3. The disk image: the (stapled) app beside an Applications link, signed and notarized in its own right so it
# opens cleanly offline too.
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/Bellhop.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Bellhop" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov -quiet "$DMG"
rm -rf "$STAGE"
codesign --sign "$DEVELOPER_ID" --timestamp "$DMG"
if [[ $NOTARIZE -eq 1 ]]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  spctl -a -vv -t open --context context:primary-signature "$DMG" 2>&1 | tail -1
fi
echo "→ $DMG  $(du -h "$DMG" | cut -f1)"

# 4. The appcast: the zip (the same stapled app the disk image holds) signed with Bellhop's update key, and the notes.
SIGNED=$("$SPARKLE_BIN/sign_update" --account bellhop "$ZIP")
ED_SIGNATURE=$(sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' <<< "$SIGNED")
LENGTH=$(sed -n 's/.*length="\([0-9]*\)".*/\1/p' <<< "$SIGNED")
[[ -n "$ED_SIGNATURE" && -n "$LENGTH" ]] || { echo "sign_update failed: $SIGNED"; exit 1; }
python3 scripts/appcast.py --version "$VERSION" --build "$BUILD" \
  --url "https://github.com/$RELEASE_REPO/releases/download/$TAG/Bellhop.zip" \
  --signature "$ED_SIGNATURE" --length "$LENGTH" --notes "$NOTES_FILE" --out "$APPCAST"
echo "→ $APPCAST  build $BUILD, signed"

[[ $PUBLISH -eq 1 ]] || { echo "dry run: stopping before the GitHub release and the tap"; exit 0; }

# 5. The GitHub release: the zip, the disk image and the appcast, with the same notes the update window shows.
gh release create "$TAG" "$ZIP" "$DMG" "$APPCAST" --repo "$RELEASE_REPO" --title "Bellhop $VERSION" \
  --notes-file "$NOTES_FILE"

# 6. The cask: version and checksum, in the tap (Homebrew takes the zip). Bellhop updates itself, so
# `auto_updates` keeps `brew upgrade` from fighting it.
TAP_DIR=$(mktemp -d)
gh repo clone "$TAP_REPO" "$TAP_DIR" -- --quiet
mkdir -p "$TAP_DIR/Casks"
cat > "$TAP_DIR/Casks/bellhop.rb" <<CASK
cask "bellhop" do
  version "$VERSION"
  sha256 "$SHA"

  url "https://github.com/$RELEASE_REPO/releases/download/v#{version}/Bellhop.zip"
  name "Bellhop"
  desc "Condense the menu bar and run any of its items from the keyboard"
  homepage "https://github.com/$RELEASE_REPO"

  auto_updates true
  depends_on macos: ">= :sonoma"

  app "Bellhop.app"
  binary "#{appdir}/Bellhop.app/Contents/Helpers/bellhop"

  zap trash: [
    "~/Library/Application Support/Bellhop",
    "~/Library/Preferences/com.tommymassaro.bellhop.plist",
  ]
end
CASK
git -C "$TAP_DIR" add Casks/bellhop.rb
git -C "$TAP_DIR" commit -q -m "bellhop $VERSION" || true
git -C "$TAP_DIR" push -q
rm -rf "$TAP_DIR"
echo "→ released $TAG; brew install --cask ${TAP_REPO/homebrew-/}/bellhop"
