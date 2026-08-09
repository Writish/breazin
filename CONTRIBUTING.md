# Contributing to Breazin

Thank you for improving Breazin. Before opening a pull request:

1. Create a focused branch from `main`.
2. Run `swift build` and the smallest relevant test target.
3. Run `swift test` before handoff and record any environment-dependent failures.
4. For packaging changes, run `scripts/bundle.sh debug --fast --without-speech` and `scripts/ci/verify-bundle.sh .build/Breazin.app development`.
5. Do not commit secrets, signing certificates, provisioning profiles, API keys, or notarization credentials.

The application module is `Sources/Breazin`, and tests live in `Tests/BreazinTests`. Product identity must come from `AppConfiguration`; do not add new hard-coded bundle IDs, URL schemes, storage paths, ports, or update feeds.

Report security issues privately to the repository owner rather than opening a public issue. General bugs and proposals belong in [GitHub Issues](https://github.com/Writish/breazin/issues).
