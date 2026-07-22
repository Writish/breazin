# PLAN implementation status

Updated 2026-07-22 against `PLAN.md` in the parent workspace.

## Completed foundation

- Phase 0: upstream `v0.6.13` is pinned, tagged, licensed, audited, built, and regression-tested.
- Phase 1: Breazin/呼息 product identity, supplied logo, app/project/MCP identifiers, three isolated environments, compatibility reads, signing gates, documentation, and CI smoke checks are implemented.
- Phase 2 BYOK image/video path: provider protocols, registry, credential storage, local model catalog, Volcengine Ark adapter, Seedream 5.0 Pro synchronous image generation, Seedance 2.0 asynchronous video generation, polling/recovery metadata, direct-provider UI/agent routing, and request contract tests are implemented.
- Phase 2 durability path: local SQLite Job/upload truth, idempotency and provider-task persistence, monotonic recovery, cancellation-race handling, user cancellation, local reference standardization, direct-to-R2 presigned upload, URL refresh, and terminal cleanup are implemented.
- Temporary media platform: a standalone Cloudflare Worker Broker, per-environment private R2 bindings, HMAC-bound upload handles, object verification, short URL lifetimes, and a lifecycle-rule template are implemented under `../platform/upload-broker`. Provisioning and deployment remain operator actions.
- Repository operations: nested `AGENTS.md`, Codex prompts, security/architecture/development/runbook documentation, branding checks, dependency review, and bundle verification are implemented.

## Deliberately pending

- Phase 2 follow-ups: add richer user-facing provider diagnostics, offline-aware retry/backoff, global recovery before a project is opened, and production per-user/device Broker authorization.
- OpenAI GPT Image 2 (OAuth route) and Midjourney (Discord bot route) are represented as unimplemented authentication/provider contracts only; neither integration is presented as working.
- Phase 3 optional platform accounts and aggregated feedback require a backend/privacy decision.
- Phase 4 release automation requires Apple Developer signing/notarization credentials and a Sparkle EdDSA key.
- Phases 5 and 6 remain product milestones; no placeholder cloud endpoints or fake production integrations were added.

The local development build is intentionally BYOK-first, loopback-only for MCP, telemetry-off by default, and distributable only with ad-hoc signing until release credentials are supplied.
