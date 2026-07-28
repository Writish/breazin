# External Beta security acceptance

Updated 2026-07-28. No externally distributed Beta is approved by this record.
Every gate below must be green for the exact candidate artifact.

## Capability and MCP contract

| Gate | Automated evidence | Manual candidate check |
| --- | --- | --- |
| Default boundary | MCP is off by default, loopback-only, has no sessionless fallback, limits sessions to four, expires them after 15 idle minutes, and rate-limits pairing and client requests. | Launch a clean Beta profile; confirm MCP is stopped until enabled and no non-loopback listener exists. |
| Per-client identity | Pairing returns a one-time per-client token; only its SHA-256 digest is retained. A session cannot be reused by another paired client. | Pair two clients, verify both appear in Settings, revoke one, and confirm only that client loses access. |
| External capabilities | New clients are read-only. Reversible project edits require that client's explicit capability. External import/export/generation is blocked unattended and high-impact actions are denied. | With a temporary project, verify read, denied edit, enabled edit plus Undo, blocked import/export/generation, and denied high-impact action. |
| In-app Agent | L1 edits require the AI Chat edit preference. Every L2 external/paid action and L3 high-impact action pauses for a one-tool `Allow once` or `Deny` receipt; cancel/session change denies the pending request. | Exercise one L1, one paid generation, and one L3 action. Confirm Deny and Escape/cancel create no mutation, charge, or stale approval. |
| Audit safety | MCP analytics include the opaque paired-client ID but not tokens, prompts, signed URLs, or local paths. | Inspect unified logs from the candidate flow and confirm no credential or signed URL appears. |

## Upload Broker contract

- The staging Worker must use a private R2 binding and the five required encrypted
  secrets. No long-lived R2 secret or plaintext device credential may exist in
  the app bundle, repository, generated types, or logs.
- Upload authorization is per opaque subject/device. Handles and object prefixes
  bind both identities; cross-device complete/refresh/delete must fail.
- The authenticated acceptance harness must pass health, create, presigned PUT,
  object metadata and byte validation, complete, GET, refresh, delete, and
  post-delete `404`. The two-day `tmp/` lifecycle rule must be enabled.
- The current deployed staging version passes deployment/configuration, health,
  unauthenticated rejection, and lifecycle checks. Its authenticated round trip
  remains pending until the test Mac is unlocked for the Beta Keychain read.

## Project schema and persistence contract

- Root schema `1` and manifest schema `2` are explicit. Future versions are
  rejected before document mutation or autosave.
- Unversioned and older packages migrate in memory. The first in-place save makes
  one sibling backup containing the original bytes; repeated saves do not replace
  that backup.
- In-place save creates a complete same-volume sibling package and installs it
  only after preparation succeeds. Interruption and out-of-space failures preserve
  the live package and clean staging output.
- The repository golden is an anonymous package encoded by pinned upstream tag
  `v0.6.13`. Automated coverage verifies timeline and clip identity, offline
  project-relative media, schema migration, original backup bytes, and repeated
  save/reopen semantics.

## Distribution gates

Before giving the app to any external tester:

1. Run the complete client and Broker suites on the release commit and retain the
   deterministic/scenario artifacts.
2. Complete the authenticated staging Broker round trip and the manual MCP/Agent
   checks above with the exact Beta bundle.
3. Build once with the Beta identifiers, sign with Developer ID, submit for Apple
   notarization, staple the ticket, and verify on a clean Mac. Ad-hoc signing is
   internal-only evidence.
4. Verify Beta Keychain, project, Job, log, Broker, R2, telemetry, Sparkle feed,
   and signing identities cannot read or mutate Production state.
5. Require green PR checks and record any accepted exception. A draft PR or a
   locally passing suite is not a release approval.
