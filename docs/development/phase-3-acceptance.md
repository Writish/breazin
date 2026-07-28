# Phase 3 backend-removal acceptance

Updated 2026-07-28. This record applies to the Client shipping graph on
`feature/breazin-foundation`.

## Exit-condition result

Phase 3 is complete against `PLAN.md`:

- `ModelCatalog` is app-owned and populated from installed provider adapters.
- Cloud transcription is a separate OpenAI BYOK adapter with local fallback.
- Credits, subscriptions, Clerk, Convex, billing, `PalmierClient`, legacy Agent
  and generation clients, and their SwiftPM dependencies are absent from the
  shipping graph.
- Legacy project identifiers and fields remain decode/registration contracts
  only. They do not select a remote backend.
- No request destination in the shipping source points to a Palmier private
  service.

## Runtime request inventory

| Destination | Trigger and ownership |
| --- | --- |
| `ark.cn-beijing.volces.com` | Explicit Seedream/Seedance generation using the user's Ark API key. |
| `uploads-staging.breazin.com` / `uploads.breazin.com` | Temporary-reference Broker selected by the app environment. |
| Presigned `*.r2.cloudflarestorage.com` URLs | Short-lived URLs returned by the Broker; no R2 credential is present in the client. |
| `api.openai.com/audio/transcriptions` | Explicit cloud transcription using the independent OpenAI transcription API key. |
| `api.anthropic.com` / `api.deepseek.com` | User-selected BYOK AI Chat providers. |
| GitHub raw appcast URLs | Sparkle update channels configured by environment; disabled for Development. |
| Upstream Hugging Face model files | Public, checksummed visual-search artifacts. This is an acknowledged rehosting/supply-chain follow-up, not a Palmier account or private API. |
| User/provider supplied media URLs | Explicit import, generated-result download, or explicitly configured sample/skill catalog flow. |
| `127.0.0.1` | Development Broker and loopback-only MCP endpoints. |

The optional sample catalog makes no request without `BreazinSampleCatalogURL`.
The optional community skill catalog makes no request without
`BREAZIN_SKILLS_BASE`. Telemetry is compile-time gated, requires a configured
project token, and is opt-out until the user enables it.

## Source and regression evidence

The completion audit searched `Sources`, `Package.swift`, `Package.resolved`,
bundle scripts, and notices for Palmier/Clerk/Convex/credits/subscription/
billing runtime references. Remaining Palmier strings are limited to:

- `.palmier` and `io.palmier.project` compatibility registration;
- decode-only legacy project fields;
- the checksummed public visual-search model namespace.

The lifecycle audit's focused provider/recovery/store run passed 30 tests in
three suites. GitHub Actions run `30359329719` passed the exact feature branch
with 1,234 tests in 188 suites, assembled the Development app, and passed its
bundle smoke check. `swift build --traits BundledSpeech` and the staging bundle
verifier also passed; the current internal artifact is
`/tmp/breazin-beta-audit-final/Breazin.app`. The PR additionally passes
product-identity and Dependency Review checks after CI installed `ripgrep` and
the repository Dependency graph was enabled.

## Unverified or deferred

- No paid OpenAI transcription request has been made or claimed.
- Rehosting the public visual-search model files under a Breazin-controlled,
  checksummed release channel remains recommended before relying on them as a
  long-term production supply chain.
- Optional accounts, feedback aggregation, and telemetry remain later product
  decisions and must not reintroduce a Palmier private-backend dependency.
