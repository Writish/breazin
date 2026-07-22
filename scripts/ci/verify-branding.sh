#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

fail_matches() {
  local message="$1"
  shift
  local output
  if output="$(rg -n "$@" 2>/dev/null)"; then
    echo "!! $message" >&2
    echo "$output" >&2
    exit 1
  fi
}

# Product source may retain the old identity only in the documented compatibility
# registration and in the real, checksummed upstream model host.
fail_matches "unexpected upstream product brand in active source" \
  -i "palmier" Sources/Breazin \
  --glob '!**/App/AppEnvironment.swift' \
  --glob '!**/Resources/Info.plist' \
  --glob '!**/Search/SearchIndexConfig.swift'

fail_matches "unexpected upstream product name in model tooling" \
  -i "Palmier ?Pro|PalmierProTests" models

fail_matches "fictional Breazin endpoint found" \
  "breazin-io|breazin\\.io|founders@breazin\\.io" . \
  --glob '!.build/**' \
  --glob '!docs/upstream/**' \
  --glob '!scripts/ci/verify-branding.sh'

rg -q 'name: "Breazin"' Package.swift
rg -q 'path: "Sources/Breazin"' Package.swift
rg -q 'com\.writish\.breazin\.dev' Sources/Breazin/Resources/Info.plist
rg -q 'io\.palmier\.project' Sources/Breazin/Resources/Info.plist
test -f Sources/Breazin/Resources/AppIcon.icns
test -f Sources/Breazin/Resources/MCPB/breazin.mcpb

echo "Branding and compatibility source checks passed."
