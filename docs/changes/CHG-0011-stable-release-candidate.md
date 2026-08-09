# CHG-0011: Build and evaluate a Stable release candidate

> Proposed release-authority change. This document and its JSON are review
> material only. They do not authorize credentials, workflow dispatch,
> publication, appcast mutation, distribution, merge, or Stable promotion.

## Identity

- Change ID: `CHG-0011`
- Owner: Walle / Breazin release governance
- Risk: critical
- Source: M6 immutable Stable-promotion exit condition
- Decision records: client ADR 0001 and platform ADR 0004/0006
- Status: proposed; blocked on accepted external-Beta evidence

## User intent

Produce and fully evaluate one production-identity Release Candidate so Stable
can later change only immutable channel metadata, without pretending the
different-identity Beta binary is the same artifact.

## Dependencies

- CHG-0009 Beta candidate and CHG-0010 Beta control plane are accepted and
  external-Beta install/update/rollback, privacy, deletion, trajectory, and
  critical-journey evidence meet the reviewed policy.
- Beta findings select an exact reviewed source commit; all fixes have their
  own approved Change Packets and immutable evidence.
- Production signing/notary/Sparkle authority is available only through the
  protected `stable-release` environment.
- Production control-plane provisioning has a separately reviewed packet; no
  Development or Beta identity is reused.

## Contract

- Build once from an exact `release/*` ref with `channel=stable-candidate`,
  production configuration, Bundle ID and Keychain namespace
  `com.writish.breazin`, and stable feed identity.
- Use Developer ID, Hardened Runtime, app/DMG notarization and staples,
  Gatekeeper, Sparkle signature, dependency-lock digest, source commit, and
  artifact SHA-256 exactly as in the signed-build provenance contract.
- The Beta DMG is evidence that shaped source selection; it is never renamed,
  copied, or promoted as the Stable artifact.
- Re-run the complete deterministic, 40-scenario/628-attempt, privacy,
  Production-isolation, clean-Mac, update, rollback, and Keychain-continuity
  acceptance against the exact production-identity bytes.
- Release governance binds the exact RC, quality report, evaluation evidence,
  policy/calibration reviews, signing/notary receipts, and artifact hash while
  retaining `publicationAuthorized=false`.
- A second identified `stable-release` promotion approval may later update only
  immutable release metadata and `appcast.xml` to the already accepted bytes.

## Acceptance

- All release provenance and promotion negative tests pass on the exact commit.
- Full client CI passes before the protected candidate build.
- Clean-Mac verification proves Stable identity, Gatekeeper, update, rollback,
  Keychain continuity, no Beta/Development data access, and privacy-safe logs.
- All 628 production-identity attempts have immutable evidence; the accepted
  report explains journey improvements/regressions, confidence, hard vetoes,
  and human review rather than only a green boolean.
- Any changed bytes, identity mismatch, missing evidence, failed critical floor,
  unresolved veto, or absent approval leaves appcast and publication unchanged.

## Baseline and candidate evidence

- Baseline: no production-identity RC, quality report, appcast item, or Stable
  promotion receipt exists.
- Candidate: not started; all exact artifact, scenario, clean-Mac, update,
  rollback, governance, and promotion receipts remain required.

## Proposed Change Packet JSON

```json
{
  "change_id": "CHG-0011",
  "repository": "Writish/breazin",
  "risk": "critical",
  "objective": "Build and fully evaluate one signed, notarized production-identity Release Candidate whose exact bytes alone may later be promoted to Stable by a separate identified approval.",
  "expected_outputs": [
    "One com.writish.breazin Release Candidate built once from an exact reviewed release commit.",
    "Immutable signing, notarization, staple, Gatekeeper, Sparkle, dependency-lock and artifact provenance with publicationAuthorized false.",
    "Complete deterministic, 40-scenario, privacy, Production-isolation, clean-Mac, update, rollback and Keychain evidence for the exact RC.",
    "A final-candidate manifest that permits only a later exact-byte Stable metadata promotion."
  ],
  "acceptance_criteria": [
    "External Beta evidence and all Beta-derived fixes are accepted before selecting the Stable RC source commit.",
    "The protected default-branch workflow builds only channel stable-candidate from an exact release branch under identified stable-release review.",
    "The production app and DMG use com.writish.breazin, one Developer ID team, Hardened Runtime, accepted notarization, valid staples, Gatekeeper and a stable Sparkle signature.",
    "The Beta artifact is never renamed or promoted as Stable; the production-identity RC is a distinct build with its own complete evidence.",
    "All deterministic checks and all 628 frozen attempts run against the exact RC bytes and produce immutable evidence and an accepted explanatory quality report.",
    "Clean-Mac install, update, rollback, Keychain continuity, environment isolation and log-canary checks pass for the exact RC.",
    "Changed bytes, missing evidence, critical-journey floor failure, hard veto, identity mismatch or absent human review fails closed.",
    "The finalized candidate retains publicationAuthorized false; only a separate identified Stable promotion receipt may update immutable release metadata and appcast.xml."
  ],
  "allowed_paths": [
    ".github/workflows/release-candidate.yml",
    "appcast.xml",
    "docs/changes/CHG-0011-stable-release-candidate.md",
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
    "appcast-beta.xml",
    "scripts/release.sh"
  ],
  "baseline_evidence": {
    "status": "evidence_gap",
    "evidence_ids": []
  }
}
```

## Delivery

1. Accept external-Beta evidence and every Beta-derived change independently.
2. Freeze the exact source and this packet through identified release review.
3. Build one protected production-identity RC and freeze its provenance.
4. Run the complete evaluation and human acceptance against those exact bytes.
5. Finalize without publication authority; obtain a separate protected Stable
   promotion receipt before changing release metadata or `appcast.xml`.
6. On any failure, retain the last accepted Stable artifact and do not rebuild,
   relabel, weaken policy, or reuse Beta authority.
