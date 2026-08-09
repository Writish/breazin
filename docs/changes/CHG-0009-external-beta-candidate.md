# CHG-0009: Build an external Beta candidate

> Proposed release-authority change. This document and its JSON are review
> material only. They do not authorize secret installation, workflow dispatch,
> publication, appcast mutation, tester distribution, merge, or Stable release.

## Identity

- Change ID: `CHG-0009`
- Owner: Walle / Breazin release governance
- Risk: critical
- Source: M5 external-Beta exit conditions in workspace
  `MILESTONE_STATUS.md`
- Decision records: client ADR 0001 and platform ADR 0004/0006
- Status: proposed; no control-plane decision or identified approval exists

## User intent

Produce one content-addressed `com.writish.breazin.beta` candidate that an
external tester could reasonably install after separate evaluation and human
promotion, without rebuilding, relabeling, or granting the build publication
authority.

## Dependencies

- Client and platform implementation PRs are reviewed and merged to `main`.
- `calibration-set-v2` and `quality-policy-v1` have accepted identified-human
  reviews; the complete frozen scenario plan has real immutable evidence.
- A valid Developer ID Application certificate/private key, Apple notary API
  key, and Sparkle key pair are available to the protected `beta-release`
  environment without entering the repository or chat transcript.
- The exact source Change Packet, candidate commit, dependency lock, and Beta
  identity are frozen before workflow dispatch.

## Non-goals and tradeoffs

- Do not publish a GitHub Release, edit `appcast-beta.xml`, distribute to a
  tester, merge a PR, or authorize Stable promotion.
- Do not build the production Bundle ID or reuse Production Keychain,
  telemetry, feedback, upload, signing, or release authority.
- Do not import a long-lived identity into the login Keychain. CI uses an
  ephemeral Keychain and deletes it on success, failure, or cancellation.
- Do not put P12, notary, or Sparkle bytes, passwords, tokens, or private-key
  material in Git, artifacts, logs, issue bodies, Change Packets, or evidence.
- Do not treat a signed/notarized artifact, green CI, or a quality score as
  publication approval.

## Contract

- The only build entry is `.github/workflows/release-candidate.yml` on the
  default branch, invoked from an exact `release/*` ref with `channel=beta`.
- The `beta-release` GitHub Environment requires identified Writish review and
  exposes exactly the nine documented signing/notary/Sparkle secret names.
- The workflow builds once with staging configuration and Bundle ID
  `com.writish.breazin.beta`, then signs the app and DMG with the same Developer
  ID team, enables Hardened Runtime, notarizes both, staples both, and requires
  Gatekeeper acceptance.
- Sparkle signs the exact DMG bytes. Provenance binds repository, commit,
  dependency-lock SHA-256, version/build, Bundle ID, team/authority, both
  notarization IDs, artifact size/SHA-256, and Sparkle signature.
- The uploaded candidate and receipts are one immutable evaluation input with
  `publicationAuthorized=false` and `humanApprovalStillRequired=true`.
- L2/L3 evaluation, accepted governance, clean-Mac verification, exact-hash
  finalization, and a second protected promotion approval remain mandatory.
- Any failure, cancellation, identity mismatch, secret absence, artifact hash
  change, rejected notarization, failed staple, or Gatekeeper rejection leaves
  no published item and no appcast change.

## Acceptance

### L0/L1 deterministic

- Release workflow and provenance tests reject ad-hoc identity, wrong Bundle
  ID/environment/channel, mismatched Team ID, missing Hardened Runtime,
  notarization/staple/Gatekeeper failure, changed artifact bytes, mutable URL,
  non-monotonic build, cross-channel promotion, or self-authorization.
- Full client CI passes on the exact candidate commit before dispatch.
- A repository scan finds only the nine secret names and no credential bytes.
- The workflow is present on `main`, the ref is `release/*`, and the protected
  environment reviewer is identified before any secret becomes available.

### Candidate runtime and human verification

- Verify app/DMG signatures, Developer ID authority and Team ID, Hardened
  Runtime flags, notarization receipts, staples, Gatekeeper, Sparkle signature,
  DMG SHA-256, and provenance against the exact uploaded bytes.
- On a clean Mac, mount and launch without bypassing Gatekeeper; confirm the
  Beta display name, Bundle ID, update channel, local-state namespace, MCP
  default-off boundary, and absence of Production credentials/data.
- Exercise the accepted external-Beta security checklist with this exact
  candidate, including one-tool Agent approval behavior and log canaries.
- Required approver: identified release owner who did not create the machine
  outcome being approved.

## Baseline evidence

- 2026-08-09 local identity check: `0 valid identities found`.
- `beta-release` and `stable-release` currently expose zero configured secret
  names; no signed candidate exists.
- Both appcasts are intentionally empty. Existing ad-hoc builds are internal
  Dev evidence and are not release candidates.

## Candidate evidence

- Candidate commit/artifact: not started.
- Notarization, staple, Gatekeeper, Sparkle, clean-Mac, evaluation, finalization,
  and promotion receipts: not started.

## Proposed Change Packet JSON

Paste this only into a matching pending decision after independently reviewing
the complete dependency and authority boundary.

```json
{
  "change_id": "CHG-0009",
  "repository": "Writish/breazin",
  "risk": "critical",
  "objective": "Build one immutable Developer-ID-signed, notarized, stapled, Gatekeeper-accepted and Sparkle-signed com.writish.breazin.beta candidate without granting publication authority.",
  "expected_outputs": [
    "One exact release-branch Beta app and DMG built once under the protected beta-release environment.",
    "Content-bound Developer ID, Hardened Runtime, notarization, staple, Gatekeeper, dependency-lock, artifact SHA-256 and Sparkle provenance.",
    "An immutable candidate evaluation input with publicationAuthorized false and a separately required human promotion receipt.",
    "Clean-Mac identity, isolation, capability, update-channel and log-canary verification for the exact candidate."
  ],
  "acceptance_criteria": [
    "Client and platform implementation PRs are reviewed and merged, governance reviews are accepted, and the frozen evaluation plan has real immutable evidence before dispatch.",
    "The default-branch release workflow runs only from an exact release branch with channel beta and identified beta-release approval.",
    "All nine signing, notary and Sparkle values remain protected environment secrets and never enter Git, logs, issues, artifacts, Change Packets or chat.",
    "The app and DMG use com.writish.breazin.beta and one Developer ID team, Hardened Runtime, accepted notarization, valid staples and Gatekeeper acceptance.",
    "The exact DMG bytes, source commit, dependency lock, version/build, identity, notary receipts and Sparkle signature are content-bound in immutable provenance.",
    "Any missing or mismatched identity, receipt, secret, hash, staple, Gatekeeper result or channel fails closed without publication or appcast mutation.",
    "Full client CI and release contract tests pass on the exact candidate commit.",
    "A clean-Mac human review verifies install, launch, Beta identity, environment isolation, MCP and Agent boundaries, Keychain behavior and privacy-safe logs.",
    "The resulting candidate still declares publicationAuthorized false and requires L2/L3 evaluation, exact-hash finalization and a second protected human promotion approval."
  ],
  "allowed_paths": [
    ".github/workflows/release-candidate.yml",
    "appcast-beta.xml",
    "docs/changes/CHG-0009-external-beta-candidate.md",
    "docs/development/external-beta-security-acceptance.md",
    "docs/development/release.md",
    "scripts/ci/release-build-provenance.mjs",
    "scripts/ci/release-build-provenance.test.mjs",
    "scripts/ci/release-promotion.mjs",
    "scripts/ci/release-promotion.test.mjs"
  ],
  "frozen_paths": [
    "Sources/",
    "Tests/",
    "Package.resolved",
    "appcast.xml",
    "scripts/release.sh"
  ],
  "baseline_evidence": {
    "status": "evidence_gap",
    "evidence_ids": []
  }
}
```

## Delivery

1. Satisfy and review every dependency; freeze this exact packet with an
   identified release owner.
2. Import credentials only into protected GitHub Environment secrets; never
   expose values during verification.
3. Merge the reviewed workflow to `main`, create the exact release branch, and
   dispatch one protected Beta candidate build.
4. Freeze candidate provenance and run the complete scenario/security/clean-Mac
   acceptance against those exact bytes.
5. Finalize the exact candidate in release governance. Publication and appcast
   mutation require a separate protected human promotion receipt.
6. On failure, delete the candidate artifact and ephemeral credentials; do not
   weaken a gate, rebuild under the same candidate identity, or publish.
