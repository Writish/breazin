# PLAN implementation status

Updated 2026-07-24 against `PLAN.md` in the parent workspace.

## Completed foundation

- Phase 0: upstream `v0.6.13` is pinned, tagged, licensed, audited, built, and regression-tested.
- Phase 1: Breazin/呼息 product identity, supplied logo, app/project/MCP identifiers, three isolated environments, compatibility reads, signing gates, documentation, and CI smoke checks are implemented.
- Phase 2 BYOK image/video path: provider protocols, registry, credential storage, local model catalog, Volcengine Ark adapter, Seedream 5.0 Pro synchronous image generation, Seedance 2.0 asynchronous video generation, polling/recovery metadata, direct-provider UI/agent routing, and request contract tests are implemented.
- Phase 2 durability path: local SQLite Job/upload truth, idempotency and provider-task persistence, monotonic recovery, cancellation-race handling, user cancellation, local reference standardization, direct-to-R2 presigned upload, URL refresh, and terminal cleanup are implemented.
- Phase 2 global recovery: app launch scans every non-terminal SQLite Job without waiting for a project to open. `queued`, `running`, `downloading`, and `cancel_requested` work is reconciled without calling provider submit. Missing provider task IDs move to `needs_attention`; completed provider outputs are downloaded into app-level staging and persisted as relative paths until the owning project opens.
- Phase 2 provider observability: Volcengine single-task and multi-task queries decode and persist provider status/timestamps, failure details, video output parameters, and image/video Token usage in SQLite schema v3. AI Chat generation tool rows now show live queued/running/downloading/finalizing/terminal state and expose the temporary provider result as a native user-openable link without sending the signed URL to the chat model. `get_generation_status` gives the Agent and MCP a safe structured status contract.
- Temporary media platform: a standalone Cloudflare Worker Broker, per-environment private R2 bindings, HMAC-bound upload handles, object verification, short URL lifetimes, lifecycle verification, and a real-staging acceptance harness are implemented under `../platform/upload-broker`.
- Seedream uses the current `doubao-seedream-5-0-pro-260628` model identifier and its documented 1K/2K resolution contract. Seedance retains the current asynchronous task submit/query contract and reference media roles.
- Repository operations: nested `AGENTS.md`, Codex prompts, security/architecture/development/runbook documentation, branding checks, dependency review, and bundle verification are implemented.

## Verification boundary

- Automated local contracts cover generation crash recovery, duplicate recovery, unopened projects, ambiguous submission, download staging, cancellation/completion races, reference standardization, upload/refresh/delete binding, Volcengine request mapping, Broker health/authentication/presigning/object verification/complete/refresh/delete, expired or tampered handles, and lifecycle configuration.
- Real Cloudflare staging resource checks confirmed the three R2 buckets exist, the staging Worker is deployed, required secret names are present, `uploads-staging.breazin.com/healthz` returns staging health, unauthenticated upload creation returns `401`, and the `tmp/` two-day lifecycle rule is active.
- A Beta Seedance run on 2026-07-23 verified authenticated reserve/presigned `PUT`/complete, provider submit/poll, generated-output finalization, and bound-upload delete once. The standalone staging harness, explicit object-byte read, refresh, and real-time expiry are still not claimed; the local acceptance-only Worker revision remains undeployed.
- One paid Seedance 2.0 image-reference generation succeeded in Beta. Seedream success remains unverified because the attempted request hit the account's Safe Experience Mode inference limit.
- The live restart drill did not reach a persisted provider task ID before exit, so it proved ambiguous-submission safety but not recovery of a genuinely queued/running remote task.

See `docs/development/phase-2-acceptance.md` for the evidence matrix and operator steps.

## Deliberately pending

- Phase 2 operator acceptance: run the standalone authenticated R2 staging harness, complete one successful Seedream request after resolving the account limit, and repeat the restart drill only after AI Chat shows a persisted Provider Task ID in `queued` or `running`.
- Phase 2 follow-ups: add offline-aware retry/backoff and production per-user/device Broker authorization. Provider status-query timeout remains a non-terminal refresh error because Volcengine does not define `timeout` as a task terminal state.
- OpenAI GPT Image 2 (OAuth route) and Midjourney (Discord bot route) are represented as unimplemented authentication/provider contracts only; neither integration is presented as working.
- Phase 3 optional platform accounts and aggregated feedback require a backend/privacy decision.
- Phase 4 release automation requires Apple Developer signing/notarization credentials and a Sparkle EdDSA key.
- Phases 5 and 6 remain product milestones; no placeholder cloud endpoints or fake production integrations were added.

The local development build is intentionally BYOK-first, loopback-only for MCP, telemetry-off by default, and distributable only with ad-hoc signing until release credentials are supplied.
