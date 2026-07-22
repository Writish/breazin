# Build and release script rules

- Development defaults must remain ad-hoc, non-notarized, and safe without secrets.
- Signing, notarization, Sparkle keys, and production telemetry are injected only at execution time.
- Do not add direct publication to `main` or replace immutable release artifacts.
- Every identity change must be checked in the assembled app, not only source plist templates.
