# CHG-0006: Consented Development journey observations

> Proposed child change of platform `CHG-0004`. This document and the JSON
> below are review material only. They grant no repository, telemetry, upload,
> Beta, Production, merge, or release authority.

## Identity

- Change ID: `CHG-0006`
- Owner: Walle / Breazin client and privacy governance
- Risk: high
- Source feedback: `feedback_id=90c67a1e-56bb-4b3b-8482-ed2f813e2da5`
- Parent specification:
  `Writish/breazin-platform/docs/changes/CHG-0004-consented-journey-observations.md`
- Dependency: accepted CHG-0005 Development endpoint, migration, privacy
  canary, deletion, and Access evidence
- Decision record: not yet created
- Status: proposed; blocked on CHG-0005 acceptance

## User intent

Let a user explicitly opt in to sending a small, inspectable, first-party
record of selected product journeys so Development usage frequency and bounded
outcomes can be compared with scenario evaluation without treating telemetry
as satisfaction or release authority.

## Non-goals and tradeoffs

- Do not enable collection by default or provision Beta/Production.
- Do not collect prompts, project content, paths, project IDs, media,
  credentials, authorization headers, model/tool names, external MCP client
  identity, free text, screen/input capture, or arbitrary properties.
- Do not reuse `Analytics.Payload`, `Telemetry.Payload`, or the
  `generation-jobs.sqlite3` store. The queue has a separate Feedback-domain
  SQLite owner and schema.
- Do not identify a user, expose per-device history, or infer satisfaction from
  completion, duration, frequency, retention, or a model label.
- Do not double-send the same journey to PostHog once the first-party path is
  enabled. Sentry crash consent remains independent.
- Do not start upload until the exact CHG-0005 Development contract is deployed
  and verified.

## Contract

- Source of truth: typed Feedback-domain mappings create
  `journey-observation-v1`; a dedicated SQLite queue owns unsent local state.
- Initial journey/event combinations are closed to:
  `JRN-01/project_open` and `JRN-07/export`.
- An event contains only `client_event_id`, `occurred_at`, Development
  app/build identity, `journey_id`, `event_name`, `phase`, `outcome`, optional
  bounded `elapsed_ms`, and `consent_revision`.
- Consent defaults off and is environment-scoped. Settings lists every
  transmitted field, endpoint, 30-day Development retention, deletion
  behavior, and the limits of the signal.
- Enabling consent affects later events only. Disabling it immediately stops
  collection and deletes all unsent observations.
- The queue survives ordinary restart, stores at most 500 events, drops the
  oldest on overflow with a local aggregate counter, and contains no project
  identifier or free-form value.
- No feedback device credential, wrong environment, disabled consent, or
  unverified platform contract means zero network requests.
- Upload sends 1–50 events per request with bounded jittered backoff. Retry
  preserves `client_event_id`; duplicate acceptance drains the event once.
- Collection and disk/network work never block the main actor or product work.
  Background work has an owned lifecycle and terminal diagnostics without
  payload contents.
- With first-party consent enabled, corresponding legacy Analytics journey
  events are suppressed before PostHog capture. Other Analytics and Sentry
  consent remain separate.
- Self-delete clears unsent local observations before the remote deletion
  request and reports the server's journey-observation deletion count.
- Client rollback stops producing and sending events. It does not weaken
  server retention or deletion duties.

## Acceptance

### L0/L1 deterministic

- Add failing tests before implementation for exact encoding, prohibited
  canaries, consent default-off, missing credential, wrong environment,
  unverified server, queue cap, restart restore, purge, retry, duplicate drain,
  and PostHog double-send suppression.
- Prove all journey/event/phase/outcome mappings are enumerated and unknown
  combinations cannot be represented or decoded.
- Prove the queue contains no prompt, project value/path/ID, media, provider
  credential, authorization header, model/tool name, external-client identity,
  free text, or arbitrary properties.
- Prove SQLite work and request encoding run outside the main actor and do not
  block project open or export completion.
- Run focused Feedback suites, affected export tests, full `swift test`,
  `swift build`, real app assembly, strict deep codesign, and bundle smoke.

### L2 scenarios

| Scenario revision | Trials | Graders | Key-journey floor | Evidence |
|---|---:|---|---:|---|
| `SCN-FBK-0005@1` consent off and queue purge | 5 | privacy contract, local-state probe | hard veto | request log, queue snapshot |
| `SCN-FBK-0006@1` retry and duplicate intake | 5 | idempotency, D1 projection | 1.0 | request IDs, row counts |

These revisions must be proposed and reviewed separately; this change cannot
edit the frozen scenario registry.

### Human verification

- Setup: exact CHG-0005 Development deployment, Dev app, test project, and the
  current device's Keychain-backed feedback credential.
- Actions: inspect consent copy and recent-event preview; leave consent off and
  open a project; enable it; open a project; run one successful export and one
  failed or cancelled export; restart; disable consent; request self-delete.
- Expected result: zero requests while off; only enumerated fields while on;
  retry survives restart without duplicates; disabling empties the queue; the
  Access aggregate changes without exposing a device; deletion removes server
  and local subject-linked state.
- Edge/lifecycle cases: missing/revoked credential, offline retry, app quit,
  corrupt queue row, 501st event, wrong environment, server kill switch, and
  consent change during an in-flight batch.
- Required approver: identified product/privacy owner after CHG-0005 evidence.

## Baseline evidence

- Baseline commit:
  `f4a8e54412401bc631d10106c096a008c0b79f1d`
- Reproduction command: failing tests must be captured before candidate source
  changes and uploaded as immutable `baseline_failure` evidence.
- Failure artifact: not yet captured.
- Evidence gap: current source has feedback submission and third-party
  Analytics/Sentry consent, but no typed first-party observation, queue,
  transport, consent control, restart recovery, or double-send prevention.

## Candidate evidence

- Candidate commit/artifact: not started.
- Exact commands: not started.
- Evaluation manifest: not started.
- Unverified work: all source, UI, local persistence, live request, restart,
  deletion, aggregate, privacy, and PostHog-suppression verification.

## Frozen Change Packet JSON

Do not paste or approve this packet until CHG-0005 has deployed and its
Development endpoint, aggregate-only evidence, retention, deletion, and
privacy canary have accepted human verification.

```json
{
  "change_id": "CHG-0006",
  "repository": "Writish/breazin",
  "risk": "high",
  "objective": "Add an explicitly opted-in Development-only client path for closed-schema first-party project-open and export journey observations with bounded local persistence and no duplicate PostHog journey delivery.",
  "expected_outputs": [
    "A typed closed journey-observation model and domain mapping that cannot carry project or free-form data.",
    "A separate Feedback-domain SQLite queue capped at 500 events with restart, purge, retry, and idempotency behavior.",
    "A Development-only device-authenticated batch transport and inspectable Settings consent surface.",
    "PostHog double-send prevention, Red-before-Green tests, packaged-app checks, and live Development HITL evidence."
  ],
  "acceptance_criteria": [
    "Tests fail before implementation for the missing encoding, consent, queue, transport, retry, duplicate, purge, restart, and double-send contracts.",
    "Collection defaults off and disabled consent, missing credential, wrong environment, or unverified platform contract makes zero network requests.",
    "The encoded and persisted schema is closed and passes prohibited-field privacy canaries.",
    "A separate Feedback-domain SQLite queue survives restart, caps at 500, drops oldest with a local count, and purges immediately on consent disable.",
    "Requests contain 1 to 50 events, preserve client event IDs across bounded retry, and drain duplicate acceptance once.",
    "Project-open and export mappings cover succeeded, failed, cancelled, started, and completed states without arbitrary properties.",
    "Corresponding legacy Analytics events do not reach PostHog while first-party journey consent is enabled; Sentry consent remains independent.",
    "Self-delete clears the local queue and reports the server journey-observation deletion count.",
    "Focused tests, full swift test, swift build, app assembly, strict deep codesign, bundle smoke, and all client CI jobs pass.",
    "Human verification confirms consent copy, zero-off behavior, exact payload, offline restart retry, aggregate-only Access visibility, disable purge, and deletion."
  ],
  "allowed_paths": [
    "Sources/Breazin/App/AppState.swift",
    "Sources/Breazin/App/main.swift",
    "Sources/Breazin/Export/ExportService.swift",
    "Sources/Breazin/Feedback/FeedbackClient.swift",
    "Sources/Breazin/Feedback/JourneyObservation.swift",
    "Sources/Breazin/Feedback/JourneyObservationClient.swift",
    "Sources/Breazin/Feedback/JourneyObservationService.swift",
    "Sources/Breazin/Feedback/JourneyObservationStore.swift",
    "Sources/Breazin/Settings/FeedbackPane.swift",
    "Sources/Breazin/Telemetry/Analytics.swift",
    "Tests/BreazinTests/Export/ExportServiceRoundTripTests.swift",
    "Tests/BreazinTests/Feedback/FeedbackClientTests.swift",
    "Tests/BreazinTests/Feedback/JourneyObservationClientTests.swift",
    "Tests/BreazinTests/Feedback/JourneyObservationServiceTests.swift",
    "Tests/BreazinTests/Feedback/JourneyObservationStoreTests.swift"
  ],
  "frozen_paths": [
    ".github/",
    "Package.swift",
    "docs/changes/CHG-0006-journey-observation-client.md",
    "scripts/ci/",
    "Sources/Breazin/Generation/",
    "Sources/Breazin/Telemetry/Telemetry.swift",
    "Tests/BreazinTests/Generation/"
  ],
  "baseline_evidence": {
    "status": "evidence_gap",
    "evidence_ids": []
  }
}
```

## Delivery

1. Accept CHG-0005 Development evidence and freeze the exact endpoint contract.
2. Create a separate pending human decision for this child and approve only
   the exact packet after identified review.
3. Capture failing encoding, consent, queue, transport, and Analytics
   suppression tests as immutable baseline evidence.
4. Implement only the allowed paths, with the Feedback actor owning queue and
   transport lifecycle.
5. Run focused and full tests, package the Dev app, and complete the live
   consent/restart/delete HITL sequence.
6. Keep Beta and Production unprovisioned. Roll back the client or disable
   consent/upload on privacy, duplicate, or lifecycle failure.
