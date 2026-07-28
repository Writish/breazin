# PLAN implementation status

Updated 2026-07-28 against `PLAN.md` in the parent workspace.

## Completed foundation

- Phase 0: upstream `v0.6.13` is pinned, tagged, licensed, audited, built, and regression-tested.
- Phase 1: Breazin/呼息 product identity, supplied logo, app/project/MCP identifiers, three isolated environments, compatibility reads, signing gates, documentation, and CI smoke checks are implemented.
- Phase 2 BYOK image/video path: provider protocols, registry, credential storage, local model catalog, Volcengine Ark adapter, Seedream 5.0 Pro synchronous image generation, Seedance 2.0 asynchronous video generation, polling/recovery metadata, direct-provider UI/agent routing, and request contract tests are implemented.
- Phase 2 durability path: local SQLite Job/upload truth, idempotency and provider-task persistence, monotonic recovery, cancellation-race handling, user cancellation, local reference standardization, direct-to-R2 presigned upload, URL refresh, and terminal cleanup are implemented.
- Phase 2 global recovery: app launch scans every non-terminal SQLite Job without waiting for a project to open. `queued`, `running`, `downloading`, and `cancel_requested` work is reconciled without calling provider submit. Missing provider task IDs move to `needs_attention`; completed provider outputs are downloaded into app-level staging and persisted as relative paths until the owning project opens.
- Phase 2 provider observability: Volcengine single-task and multi-task queries decode and persist provider status/timestamps, failure details, video output parameters, and image/video Token usage in SQLite schema v3. AI Chat generation tool rows now show live queued/running/downloading/finalizing/terminal state and expose the temporary provider result as a native user-openable link without sending the signed URL to the chat model. `get_generation_status` gives the Agent and MCP a safe structured status contract.
- Phase 2 Seedream timeout handling: the synchronous image request has a five-minute response allowance instead of URLSession's approximately one-minute default. A response timeout without a task ID now closes as `failed`, stops all progress UX, cleans bound temporary references, and warns that Ark may still have processed the request. Explicit provider rejections are terminal failures; only genuinely ambiguous asynchronous submissions remain `needs_attention`.
- Phase 2 offline and retry scheduling: the global and project-scoped recovery paths pause provider traffic while macOS reports the network unavailable, persist `retry_count` and `next_retry_at` in SQLite schema v4, and resume transient provider/status/download failures with capped exponential backoff and deterministic ±20% jitter. Cancellation is rechecked at least every five seconds and wins before a scheduled retry. Video output download retries discard stale signed result URLs and re-query the provider; synchronous Seedream retains its only result URL because no queryable provider task exists.
- Temporary media platform: a standalone Cloudflare Worker Broker, per-environment private R2 bindings, HMAC-bound upload handles, object verification, short URL lifetimes, lifecycle verification, and a real-staging acceptance harness are implemented under `../platform/upload-broker`.
- Seedream uses the current `doubao-seedream-5-0-pro-260628` model identifier and its documented 1K/2K resolution contract. Seedance retains the current asynchronous task submit/query contract and reference media roles.
- Repository operations: nested `AGENTS.md`, Codex prompts, security/architecture/development/runbook documentation, branding checks, dependency review, and bundle verification are implemented.

## Phase 3 in progress

- `ModelCatalog` no longer subscribes to Convex. The app-owned provider catalog is populated synchronously from implemented adapters, is available before account/network initialization, and currently exposes only Seedream 5.0 Pro and Seedance 2.0.
- Cloud transcription no longer stages audio through Palmier storage or submits a Palmier transcription Job. Breazin extracts a local 16 kHz mono WAV, uploads it directly to OpenAI's `audio/transcriptions` endpoint with `whisper-1` verbose word/segment timestamps, maps the result back to source/timeline time, and caches it under a provider-versioned key.
- OpenAI transcription is an independent BYOK Keychain credential (`openai-transcription`), not the planned GPT Image 2 OAuth credential. Settings and caption/speaker UX state that provider usage is billed externally; missing configuration falls back to Apple's local transcription for Agent tools.
- The retired `TranscriptionBackend` implementation has been deleted. The broader Clerk/Convex/credits/Palmier generation and account cleanup remains the next Phase 3 slice and is not represented as complete.

## Verification boundary

- Automated local contracts cover generation crash recovery, duplicate recovery, unopened projects, ambiguous submission, download staging, cancellation/completion races, reference standardization, upload/refresh/delete binding, Volcengine request mapping, Broker health/authentication/presigning/object verification/complete/refresh/delete, expired or tampered handles, and lifecycle configuration.
- Real Cloudflare staging resource checks confirmed the three R2 buckets exist, the staging Worker is deployed, required secret names are present, `uploads-staging.breazin.com/healthz` returns staging health, unauthenticated upload creation returns `401`, and the `tmp/` two-day lifecycle rule is active.
- A Beta Seedance run on 2026-07-23 verified authenticated reserve/presigned `PUT`/complete, provider submit/poll, generated-output finalization, and bound-upload delete once. The standalone staging harness, explicit object-byte read, refresh, and real-time expiry are still not claimed; the local acceptance-only Worker revision remains undeployed.
- Paid Beta generation now includes one successful Seedream 5.0 Pro image run and two successful Seedance 2.0 image-reference video runs. The successful Seedream row recorded one attempt, one result, 4,450 Tokens, terminal `succeeded`, and deleted reference-upload state.
- The 2026-07-28 Seedance restart drill exited with an accepted remote Job, relaunched 31 seconds later, and completed with the same provider task ID, one attempt, one result, 108,900 total Tokens, project media installation, and deleted upload state. This verifies no-resubmit restart recovery. Because the project was opened before the local terminal write, unopened-project output staging remains verified by deterministic tests rather than a separate live observation.
- Strict Phase 2 is closed in source and deterministic acceptance. The final retry follow-up passed 150 selected tests across 9 suites, an additional focused 28-test run during output-URL retry hardening, and—after rebasing onto the latest upstream main—the complete 1,206-test regression across 184 suites.
- Phase 3 adapter contracts currently include a 32-test focused run covering the local provider catalog, OpenAI multipart/auth/timestamp/error behavior, provider configuration fallback, cloud-language validation, and transcript cache behavior. No paid OpenAI transcription call has been made or claimed; live BYOK acceptance remains manual.

See `docs/development/phase-2-acceptance.md` for the evidence matrix and operator steps.

## Deliberately pending after strict Phase 2

- Additional production evidence: the standalone authenticated R2 harness, live cancellation-near-completion drill, and stricter unopened-project staging observation remain useful live exercises. They are not represented as completed and do not replace the deterministic Phase 2 contracts.
- External-Beta hardening: replace the bootstrap Broker bearer token with per-user/device authorization. Seedance task-status query timeout remains a non-terminal refresh error because Volcengine does not define `timeout` as a task terminal state; Seedream's synchronous response timeout is a separate terminal local condition because no queryable task ID exists.
- OpenAI GPT Image 2 (OAuth route) and Midjourney (Discord bot route) are represented as unimplemented authentication/provider contracts only; neither integration is presented as working.
- Phase 3 optional platform accounts and aggregated feedback require a backend/privacy decision.
- Phase 4 release automation requires Apple Developer signing/notarization credentials and a Sparkle EdDSA key.
- Phases 5 and 6 remain product milestones; no placeholder cloud endpoints or fake production integrations were added.

The local development build is intentionally BYOK-first, loopback-only for MCP, telemetry-off by default, and distributable only with ad-hoc signing until release credentials are supplied.
