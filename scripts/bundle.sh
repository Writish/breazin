#!/bin/bash
set -euo pipefail

# Usage:
#   scripts/bundle.sh [release|debug]           # ad-hoc signed dev build
#   scripts/bundle.sh debug --fast --without-speech # CI smoke: skip optional speech graph
#   scripts/bundle.sh release --sign            # build + Developer ID codesign
#   scripts/bundle.sh release --dist            # build + sign + notarize + staple + DMG

CONFIG="release"
MODE="dev"
BUNDLE_SPEECH=1
for arg in "$@"; do
  case "$arg" in
    release|debug) CONFIG="$arg" ;;
    --fast)        MODE="fast" ;;
    --sign)        MODE="sign" ;;
    --dist)        MODE="dist" ;;
    --without-speech) BUNDLE_SPEECH=0 ;;
    *) echo "unknown arg: $arg" >&2; exit 1 ;;
  esac
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

ENV_FILE=".env"
if [ "$CONFIG" = "release" ] && [ -f "$ROOT/.env.prod" ]; then
  ENV_FILE=".env.prod"
fi
if [ -f "$ROOT/$ENV_FILE" ]; then
  echo "==> Loading $ENV_FILE"
  set -a
  # shellcheck disable=SC1091
  . "$ROOT/$ENV_FILE"
  set +a
fi

APP_ENV="${BREAZIN_ENVIRONMENT:-development}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
SENTRY_DSN="${SENTRY_DSN:-}"
POSTHOG_PROJECT_TOKEN="${POSTHOG_PROJECT_TOKEN:-}"
POSTHOG_HOST="${POSTHOG_HOST:-https://us.i.posthog.com}"
PROVISION_PROFILE="${PROVISION_PROFILE:-}"
ENTITLEMENTS="$ROOT/scripts/Breazin.entitlements"
KEYCHAIN_ACCESS_GROUP="${KEYCHAIN_ACCESS_GROUP:-}"
RESOURCES="$ROOT/Sources/Breazin/Resources"
OUTPUT_ROOT="${BREAZIN_OUTPUT_DIR:-$ROOT/.build}"
mkdir -p "$OUTPUT_ROOT"
APP="$OUTPUT_ROOT/Breazin.app"
ZIP="$OUTPUT_ROOT/Breazin.zip"
DMG="$OUTPUT_ROOT/Breazin.dmg"

echo "==> Building ($CONFIG)"
TRAITS=""
if [ "$BUNDLE_SPEECH" = "1" ]; then
  TRAITS="BundledSpeech"
fi
if [ "$CONFIG" = "release" ]; then
  TRAITS="${TRAITS:+$TRAITS,}ProductionTelemetry"
fi
BUILD_ARGS=(-c "$CONFIG")
if [ -n "$TRAITS" ]; then
  BUILD_ARGS+=(--traits "$TRAITS")
fi
swift build "${BUILD_ARGS[@]}"
BIN="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)/Breazin"
SPARKLE_FW="$ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/Breazin"
cp "$RESOURCES/Info.plist" "$APP/Contents/Info.plist"

case "$APP_ENV" in
  development)
    DISPLAY_NAME="呼息 Dev"
    BUNDLE_ID="com.writish.breazin.dev"
    URL_SCHEME="breazin-dev"
    PROJECT_UTI="com.writish.breazin.project.dev"
    MCP_SERVICE_NAME="breazin-dev"
    MCP_DISPLAY_NAME="Breazin Dev"
    MCP_PORT="19790"
    UPDATE_FEED_URL=""
    ;;
  staging)
    DISPLAY_NAME="呼息 Beta"
    BUNDLE_ID="com.writish.breazin.beta"
    URL_SCHEME="breazin-beta"
    PROJECT_UTI="com.writish.breazin.project.beta"
    MCP_SERVICE_NAME="breazin-beta"
    MCP_DISPLAY_NAME="Breazin Beta"
    MCP_PORT="19791"
    UPDATE_FEED_URL="https://raw.githubusercontent.com/Writish/breazin/main/appcast-beta.xml"
    ;;
  production)
    DISPLAY_NAME="呼息"
    BUNDLE_ID="com.writish.breazin"
    URL_SCHEME="breazin"
    PROJECT_UTI="com.writish.breazin.project"
    MCP_SERVICE_NAME="breazin"
    MCP_DISPLAY_NAME="Breazin"
    MCP_PORT="19789"
    UPDATE_FEED_URL="https://raw.githubusercontent.com/Writish/breazin/main/appcast.xml"
    ;;
  *)
    echo "unknown BREAZIN_ENVIRONMENT: $APP_ENV" >&2
    exit 1
    ;;
esac

PLIST="$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :BreazinEnvironment $APP_ENV" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $DISPLAY_NAME" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleURLTypes:0:CFBundleURLName $BUNDLE_ID" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleURLTypes:0:CFBundleURLSchemes:0 $URL_SCHEME" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleDocumentTypes:0:LSItemContentTypes:0 $PROJECT_UTI" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :UTExportedTypeDeclarations:0:UTTypeIdentifier $PROJECT_UTI" "$PLIST"
/usr/libexec/PlistBuddy -c "Delete :SUFeedURL" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Delete :SUPublicEDKey" "$PLIST" 2>/dev/null || true
if [ -n "$UPDATE_FEED_URL" ] && [ -n "${SPARKLE_PUBLIC_KEY:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :SUEnableAutomaticChecks true" "$PLIST"
  /usr/libexec/PlistBuddy -c "Add :SUFeedURL string $UPDATE_FEED_URL" "$PLIST"
  /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $SPARKLE_PUBLIC_KEY" "$PLIST"
else
  /usr/libexec/PlistBuddy -c "Set :SUEnableAutomaticChecks false" "$PLIST"
  echo "==> Sparkle disabled for $APP_ENV (SPARKLE_PUBLIC_KEY not set)"
fi

if [ -n "$SENTRY_DSN" ]; then
  echo "==> Injecting SentryDSN into Info.plist"
  /usr/libexec/PlistBuddy -c "Delete :SentryDSN" "$APP/Contents/Info.plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :SentryDSN string $SENTRY_DSN" "$APP/Contents/Info.plist"
else
  echo "==> SENTRY_DSN not set — telemetry will be a no-op in this build"
fi

if [ -n "$POSTHOG_PROJECT_TOKEN" ]; then
  echo "==> Injecting PostHog analytics config into Info.plist"
  /usr/libexec/PlistBuddy -c "Delete :PostHogProjectToken" "$APP/Contents/Info.plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :PostHogProjectToken string $POSTHOG_PROJECT_TOKEN" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Delete :PostHogHost" "$APP/Contents/Info.plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :PostHogHost string $POSTHOG_HOST" "$APP/Contents/Info.plist"
else
  echo "==> POSTHOG_PROJECT_TOKEN not set — product analytics will be a no-op in this build"
fi

inject_plist() {
  local key="$1" value="$2"
  if [ -z "$value" ]; then
    echo "==> $key not set in $ENV_FILE — legacy backend capability unavailable"
    return
  fi
  /usr/libexec/PlistBuddy -c "Delete :$key" "$APP/Contents/Info.plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :$key string $value" "$APP/Contents/Info.plist"
}

echo "==> Injecting backend config into Info.plist"
inject_plist BreazinClerkPublishableKey "${CLERK_PUBLISHABLE_KEY:-}"
inject_plist BreazinConvexDeploymentURL "${CONVEX_DEPLOYMENT_URL:-}"
inject_plist BreazinConvexHttpURL "${CONVEX_HTTP_URL:-}"
cp "$RESOURCES/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp -R "$SPARKLE_FW" "$APP/Contents/Frameworks/Sparkle.framework"

# Flatten SwiftPM's resource bundle into the app's Resources tree.
RES_BUNDLE="$(dirname "$BIN")/Breazin_Breazin.bundle"
if [ -d "$RES_BUNDLE/Fonts" ]; then
  cp -R "$RES_BUNDLE/Fonts" "$APP/Contents/Resources/"
else
  echo "!! missing Fonts/ in SwiftPM resource bundle at $RES_BUNDLE" >&2
  exit 1
fi

# Ensure the shipped Claude Desktop connector is always up to date with mcpb/ sources.
MCPB_SRC="$ROOT/mcpb"
MCPB_WORK="$(mktemp -d)"
MCPB_FRESH="$MCPB_WORK/breazin.mcpb"
cp -R "$MCPB_SRC/manifest.json" "$MCPB_SRC/icon.png" "$MCPB_SRC/server" "$MCPB_WORK/"
sed -i '' -e "s/\"name\": \"breazin\"/\"name\": \"$MCP_SERVICE_NAME\"/" "$MCPB_WORK/manifest.json"
sed -i '' -e "s/\"display_name\": \"Breazin\"/\"display_name\": \"$MCP_DISPLAY_NAME\"/" "$MCPB_WORK/manifest.json"
sed -i '' -e "s/\"19789\"/\"$MCP_PORT\"/" "$MCPB_WORK/manifest.json"
(cd "$MCPB_WORK" && zip -q -X -r "$MCPB_FRESH" manifest.json icon.png server/index.js server/package.json)
cp "$MCPB_FRESH" "$APP/Contents/Resources/breazin.mcpb"
rm -rf "$MCPB_WORK"
if [ -d "$RES_BUNDLE/Images" ]; then
  cp -R "$RES_BUNDLE/Images" "$APP/Contents/Resources/"
fi
# .lproj folders must live at the bundle root for macOS to resolve them —
# flatten out of Resources/Localization/ even though that's just an org folder.
if [ -d "$RES_BUNDLE/Localization" ]; then
  for locale_dir in "$RES_BUNDLE/Localization"/*.lproj; do
    [ -d "$locale_dir" ] && cp -R "$locale_dir" "$APP/Contents/Resources/"
  done
else
  echo "!! missing Localization/ in SwiftPM resource bundle at $RES_BUNDLE" >&2
  exit 1
fi
if [ -d "$RES_BUNDLE/Changelog" ]; then
  cp -R "$RES_BUNDLE/Changelog" "$APP/Contents/Resources/"
else
  echo "!! missing Changelog/ in SwiftPM resource bundle at $RES_BUNDLE" >&2
  exit 1
fi
if [ -d "$RES_BUNDLE/Models" ]; then
  cp -R "$RES_BUNDLE/Models" "$APP/Contents/Resources/"
else
  echo "!! missing Models/ in SwiftPM resource bundle at $RES_BUNDLE" >&2
  exit 1
fi

if ! ls "$RES_BUNDLE"/*.metallib >/dev/null 2>&1; then
  echo "!! no .metallib in SwiftPM resource bundle at $RES_BUNDLE — Metal effects would be missing" >&2
  exit 1
fi
cp "$RES_BUNDLE"/*.metallib "$APP/Contents/Resources/"

if [ "$BUNDLE_SPEECH" = "1" ]; then
  MLX_METALLIB="$ROOT/.build/$CONFIG/mlx.metallib"
  if [ ! -f "$MLX_METALLIB" ]; then
    echo "==> Building MLX metallib ($CONFIG)"
    BUILD_DIR="$ROOT/.build" "$ROOT/.build/checkouts/speech-swift/scripts/build_mlx_metallib.sh" "$CONFIG"
  fi
  if [ ! -f "$MLX_METALLIB" ]; then
    echo "!! missing $MLX_METALLIB — on-device speech features (VAD, speaker ID) would die silently" >&2
    exit 1
  fi
  mkdir -p "$APP/Contents/Resources/mlx-swift_Cmlx.bundle"
  cp "$MLX_METALLIB" "$APP/Contents/Resources/mlx-swift_Cmlx.bundle/default.metallib"
else
  echo "==> Bundled speech disabled for this smoke build"
fi

install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Breazin"
touch "$APP"

# iCloud/File Provider workspaces can recreate Finder metadata immediately after
# it is cleared. Stage codesigning on a local volume, then copy back without
# resource forks so the repository can live under Documents/iCloud safely.
OUTPUT_APP="$APP"
CODESIGN_WORK="$(mktemp -d /tmp/breazin-codesign.XXXXXX)"
STAGED_APP="$CODESIGN_WORK/Breazin.app"
ditto --norsrc "$OUTPUT_APP" "$STAGED_APP"
rm -rf "$OUTPUT_APP"
APP="$STAGED_APP"
xattr -cr "$APP"
find "$APP" -exec xattr -d com.apple.FinderInfo {} \; 2>/dev/null || true
find "$APP" -exec xattr -d com.apple.ResourceFork {} \; 2>/dev/null || true

publish_app() {
  rm -rf "$OUTPUT_APP"
  ditto --norsrc "$APP" "$OUTPUT_APP"
  xattr -d com.apple.FinderInfo "$OUTPUT_APP" 2>/dev/null || true
  xattr -d com.apple.ResourceFork "$OUTPUT_APP" 2>/dev/null || true
  codesign --verify --deep --strict --verbose=2 "$OUTPUT_APP"
  rm -rf "$CODESIGN_WORK"
  APP="$OUTPUT_APP"
}

if [ "$MODE" = "fast" ]; then
  echo "==> Codesigning main app with $SIGNING_IDENTITY"
  # Fast mode is an ad-hoc/CI artifact. Sign the embedded Sparkle code as well so
  # a fresh checkout can pass a strict deep verification without release keys.
  codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP"
  codesign --verify --deep --strict --verbose=2 "$APP"
  publish_app
  echo "==> Done: $APP (fast mode, no dSYM)"
  exit 0
fi

DSYM="$ROOT/.build/Breazin.dSYM"
echo "==> Generating dSYM"
rm -rf "$DSYM"
dsymutil "$APP/Contents/MacOS/Breazin" -o "$DSYM"

upload_dsyms() {
  if [ -z "${SENTRY_AUTH_TOKEN:-}" ] || [ -z "${SENTRY_ORG:-}" ] || [ -z "${SENTRY_PROJECT:-}" ]; then
    echo "==> Sentry creds not set — skipping dSYM upload"
    return
  fi
  if ! command -v sentry-cli >/dev/null 2>&1; then
    echo "!! sentry-cli not found in PATH — skipping dSYM upload"
    return
  fi
  echo "==> Uploading dSYM to Sentry"
  sentry-cli debug-files upload --include-sources "$DSYM" || echo "!! sentry-cli upload failed (continuing)"
}

if [ "$MODE" = "dev" ]; then
  echo "==> Ad-hoc signing dev app"
  codesign --force --deep --sign - "$APP"
  codesign --verify --strict --verbose=2 "$APP"
  upload_dsyms
  publish_app
  echo "==> Done: $APP (ad-hoc signed)"
  exit 0
fi

if [ "$SIGNING_IDENTITY" = "-" ]; then
  echo "!! SIGNING_IDENTITY is required for --sign and --dist" >&2
  exit 1
fi

echo "==> Codesigning nested Sparkle helpers"
SPARKLE_CURRENT="$APP/Contents/Frameworks/Sparkle.framework/Versions/Current"
for helper in \
    "$SPARKLE_CURRENT/Autoupdate" \
    "$SPARKLE_CURRENT/Updater.app/Contents/MacOS/Updater" \
    "$SPARKLE_CURRENT/Updater.app" \
    "$SPARKLE_CURRENT/XPCServices/Downloader.xpc/Contents/MacOS/Downloader" \
    "$SPARKLE_CURRENT/XPCServices/Downloader.xpc" \
    "$SPARKLE_CURRENT/XPCServices/Installer.xpc/Contents/MacOS/Installer" \
    "$SPARKLE_CURRENT/XPCServices/Installer.xpc"; do
  [ -e "$helper" ] && codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$helper"
done

echo "==> Codesigning Sparkle framework"
codesign --force --options runtime --timestamp \
  --sign "$SIGNING_IDENTITY" \
  "$APP/Contents/Frameworks/Sparkle.framework"

if [ -n "$PROVISION_PROFILE" ]; then
  if [ ! -f "$PROVISION_PROFILE" ]; then
    echo "!! provisioning profile not found at $PROVISION_PROFILE" >&2
    exit 1
  fi
  echo "==> Embedding provisioning profile"
  cp "$PROVISION_PROFILE" "$APP/Contents/embedded.provisionprofile"
fi
inject_plist BreazinClerkKeychainAccessGroup "$KEYCHAIN_ACCESS_GROUP"

echo "==> Codesigning main app"
codesign --force --options runtime --timestamp \
  --entitlements "$ENTITLEMENTS" \
  --sign "$SIGNING_IDENTITY" \
  "$APP"
codesign --verify --strict --verbose=2 "$APP"

if [ "$MODE" = "sign" ]; then
  publish_app
  echo "==> Done: $APP (signed, not notarized)"
  exit 0
fi

echo "==> Zipping .app for notarization"
if [ -z "$NOTARY_PROFILE" ]; then
  echo "!! NOTARY_PROFILE is required for --dist" >&2
  exit 1
fi
rm -f "$ZIP"
/usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Submitting to Apple notary (this can take several minutes)"
xcrun notarytool submit "$ZIP" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

echo "==> Stapling ticket to .app"
xcrun stapler staple "$APP"
rm -f "$ZIP"

echo "==> Building DMG"
rm -f "$DMG"
STAGING="$(mktemp -d)"
cp -R "$APP" "$STAGING/Breazin.app"
ln -s /Applications "$STAGING/Applications"
cp "$RESOURCES/AppIcon.icns" "$STAGING/.VolumeIcon.icns"
hdiutil create \
  -volname "Breazin" \
  -srcfolder "$STAGING" \
  -ov -format UDZO \
  "$DMG"
rm -rf "$STAGING"

echo "==> Codesigning DMG"
codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$DMG"

echo "==> Submitting DMG to notary"
xcrun notarytool submit "$DMG" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

echo "==> Stapling DMG"
xcrun stapler staple "$DMG"

upload_dsyms

publish_app

echo "==> Signing DMG with Sparkle EdDSA key"
SPARKLE_SIG="$("$ROOT/.build/artifacts/sparkle/Sparkle/bin/sign_update" "$DMG")"

echo ""
echo "==> Done"
echo "   App: $APP"
echo "   DMG: $DMG"
echo ""
echo "Sparkle signature for appcast entry:"
echo "  $SPARKLE_SIG"
echo ""
echo "Add an <item> to appcast.xml with:"
echo "  - version, shortVersionString from Info.plist"
echo "  - url pointing at the GitHub Release download"
echo "  - length=$(stat -f%z "$DMG")"
echo "  - the sparkle:edSignature from above"
