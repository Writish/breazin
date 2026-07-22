#!/bin/bash
set -euo pipefail

APP="${1:-.build/Breazin.app}"
APP_ENV="${2:-development}"
PLIST="$APP/Contents/Info.plist"

case "$APP_ENV" in
  development)
    EXPECTED_DISPLAY="呼息 Dev"
    EXPECTED_BUNDLE_ID="com.writish.breazin.dev"
    EXPECTED_SCHEME="breazin-dev"
    EXPECTED_UTI="com.writish.breazin.project.dev"
    EXPECTED_MCP_NAME="breazin-dev"
    EXPECTED_MCP_PORT="19790"
    ;;
  staging)
    EXPECTED_DISPLAY="呼息 Beta"
    EXPECTED_BUNDLE_ID="com.writish.breazin.beta"
    EXPECTED_SCHEME="breazin-beta"
    EXPECTED_UTI="com.writish.breazin.project.beta"
    EXPECTED_MCP_NAME="breazin-beta"
    EXPECTED_MCP_PORT="19791"
    ;;
  production)
    EXPECTED_DISPLAY="呼息"
    EXPECTED_BUNDLE_ID="com.writish.breazin"
    EXPECTED_SCHEME="breazin"
    EXPECTED_UTI="com.writish.breazin.project"
    EXPECTED_MCP_NAME="breazin"
    EXPECTED_MCP_PORT="19789"
    ;;
  *)
    echo "unknown environment: $APP_ENV" >&2
    exit 1
    ;;
esac

assert_plist() {
  local key="$1" expected="$2" actual
  actual="$(/usr/libexec/PlistBuddy -c "Print :$key" "$PLIST")"
  if [ "$actual" != "$expected" ]; then
    echo "!! plist $key expected '$expected', got '$actual'" >&2
    exit 1
  fi
}

test -x "$APP/Contents/MacOS/Breazin"
test -f "$APP/Contents/Resources/AppIcon.icns"
test -f "$APP/Contents/Resources/breazin.mcpb"
test -d "$APP/Contents/Frameworks/Sparkle.framework"

assert_plist BreazinEnvironment "$APP_ENV"
assert_plist CFBundleExecutable "Breazin"
assert_plist CFBundleDisplayName "$EXPECTED_DISPLAY"
assert_plist CFBundleIdentifier "$EXPECTED_BUNDLE_ID"
assert_plist CFBundleURLTypes:0:CFBundleURLSchemes:0 "$EXPECTED_SCHEME"
assert_plist CFBundleDocumentTypes:0:LSItemContentTypes:0 "$EXPECTED_UTI"
assert_plist CFBundleDocumentTypes:1:LSItemContentTypes:0 "io.palmier.project"

MANIFEST="$(unzip -p "$APP/Contents/Resources/breazin.mcpb" manifest.json)"
if [ "$(printf '%s' "$MANIFEST" | jq -r .name)" != "$EXPECTED_MCP_NAME" ]; then
  echo "!! wrong MCP service name" >&2
  exit 1
fi
if [ "$(printf '%s' "$MANIFEST" | jq -r '.server.mcp_config.args[-1]')" != "$EXPECTED_MCP_PORT" ]; then
  echo "!! wrong MCP service port" >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$APP"
echo "Bundle smoke check passed for $APP_ENV: $APP"
