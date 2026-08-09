# Testing

Minimum source gate:

```bash
scripts/ci/verify-branding.sh
swift build
swift test
```

Packaging gate:

```bash
BREAZIN_ENVIRONMENT=development scripts/bundle.sh debug --fast --without-speech
scripts/ci/verify-bundle.sh .build/Breazin.app development
```

Project compatibility changes must add or update anonymized fixtures and cover open, no-op save, close, and reopen. A baseline environment-sensitive Metal failure is not silently waived: compare it with `UPSTREAM_BASELINE.md`, preserve the exact failure output, and determine whether the affected source changed.
