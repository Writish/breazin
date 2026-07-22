# Local setup

1. Install macOS 26, Xcode 26, and the matching Command Line Tools.
2. Install Xcode's optional Metal Toolchain with `xcodebuild -downloadComponent MetalToolchain`, then verify it with `xcrun --toolchain Metal --find metal`.
3. Clone `Writish/breazin`, then add `https://github.com/palmier-io/palmier-pro.git` as read-only `upstream`.
4. Run `swift --version`, `swift package resolve`, and `swift build`.
5. Copy `.env.example` to `.env` only when optional local values are needed. Never commit `.env*` secrets.
6. Prepare the local upload Broker from `../platform/upload-broker/.dev.vars.example`, then start it with `cd ../platform/upload-broker && npx wrangler dev --env development`.
7. Build an ad-hoc development app with `scripts/bundle.sh debug --fast --without-speech`. Omit `--without-speech` when validating the full on-device speech graph.

If the checkout is managed by iCloud or another File Provider that continuously adds Finder metadata, set a local output directory before codesigning, for example `BREAZIN_OUTPUT_DIR=/tmp/breazin-artifacts scripts/bundle.sh debug --fast --without-speech`.

The default unbundled executable uses development configuration and connects only to the local upload Broker at `127.0.0.1:8787`. Use `BREAZIN_ENVIRONMENT=staging` or `production` only for explicit package checks. External distribution additionally requires paid Apple Developer credentials, signing, notarization, and Sparkle signing.
