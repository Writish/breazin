# Release process

Development builds are ad-hoc signed and contain no claim of external readiness. For Beta or Stable:

1. Create a release branch and run all deterministic CI checks.
2. Build once with the correct environment identity.
3. Sign with Developer ID, notarize, staple, and verify Gatekeeper on a clean Mac.
4. Sign the Sparkle archive, generate checksums and provenance, and upload an immutable artifact.
5. Promote that same artifact through a protected GitHub environment after human approval.
6. Update only the matching beta or stable appcast.

Do not run `scripts/release.sh` as an unattended publication mechanism. Its direct Git/tag/release behavior remains legacy until replaced by an approved GitHub workflow.

## Protected signed-build workflow

`.github/workflows/release-candidate.yml` builds but does not publish:

- it runs only from `release/*`;
- `beta` requires `beta-release`, while `stable-candidate` requires
  `stable-release`; both environments require Writish review;
- Developer ID, Apple notary, and Sparkle keys exist only in the selected
  environment and an ephemeral runner Keychain;
- the app and DMG must both be notarized/stapled, the app must pass Gatekeeper,
  and the assembled Bundle ID/Team ID/Hardened Runtime are checked;
- the DMG, notarization receipts, codesign facts, Sparkle signature, dependency
  lock digest, source commit, and artifact SHA-256 are uploaded as one
  evaluation input with `publicationAuthorized=false`;
- credentials are destroyed even when the job fails.

This first job is intentionally not a release. Scenario evaluation must bind a
quality report to the exact DMG hash; Calibration and Quality Policy must be
accepted; release governance must finalize the manifest; and a separate
protected human promotion approval must still update the channel metadata.

Required environment secrets:

- `DEVELOPER_ID_APPLICATION_P12_BASE64`
- `DEVELOPER_ID_APPLICATION_P12_PASSWORD`
- `DEVELOPER_ID_APPLICATION_IDENTITY`
- `DEVELOPER_ID_TEAM_ID`
- `APPLE_NOTARY_KEY_BASE64`
- `APPLE_NOTARY_KEY_ID`
- `APPLE_NOTARY_ISSUER_ID`
- `SPARKLE_PRIVATE_KEY`
- `SPARKLE_PUBLIC_KEY`
