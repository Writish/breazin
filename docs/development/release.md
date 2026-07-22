# Release process

Development builds are ad-hoc signed and contain no claim of external readiness. For Beta or Stable:

1. Create a release branch and run all deterministic CI checks.
2. Build once with the correct environment identity.
3. Sign with Developer ID, notarize, staple, and verify Gatekeeper on a clean Mac.
4. Sign the Sparkle archive, generate checksums and provenance, and upload an immutable artifact.
5. Promote that same artifact through a protected GitHub environment after human approval.
6. Update only the matching beta or stable appcast.

Do not run `scripts/release.sh` as an unattended publication mechanism. Its direct Git/tag/release behavior remains legacy until replaced by an approved GitHub workflow.
