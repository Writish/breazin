# Phase 2 acceptance record

Recorded 2026-07-23 and updated 2026-07-28. This record separates deterministic local contracts, operator-observed Beta evidence, read-only checks against currently deployed Cloudflare resources, and production end-to-end work that still requires explicit credentials or paid-generation approval.

## Acceptance matrix

| Scope | Result | Evidence |
| --- | --- | --- |
| Global SQLite recovery | Passed locally | Automated coverage for crash restart, duplicate recovery, unopened project, `queued`/`running`/`downloading`, missing provider task ID, cancellation without a remote task, and cancellation/completion races. Recovery contains no provider submit path. |
| Offline and transient-failure scheduling | Passed locally | Both recovery paths pause provider calls while `NWPathMonitor` reports offline, persist `network_offline`, `retry_count`, and `next_retry_at` in SQLite schema v4, and resume with 2-second-base exponential backoff, ±20% jitter, and a five-minute cap. The loop rechecks cancellation at least every five seconds. Deterministic clocks and jitter cover early duplicate recovery, due retries, permanent errors, offline recovery, and cancellation preemption. |
| Provider output staging | Passed locally | Generated URLs are downloaded to app support, persisted as job-relative paths, rejected on path traversal, transferred to the project when opened, and cleaned after terminal handling. |
| Reference normalization and binding | Passed locally | Image streaming checksum, MP4/H.264 normalization, M4A/AAC normalization, Broker reserve/upload/complete/refresh/delete, and SQLite Job/upload binding are automated. |
| Volcengine request contracts | Passed locally | Seedream synchronous image and Seedance asynchronous video request mapping, content roles, polling states, cancellation, expiry, and safe remote errors are automated against fixtures. |
| Provider status observability | Passed locally | Seedance single-task and multi-task status queries, provider timestamps, queued/running/succeeded/failed/cancelled mapping, output metadata, Token usage, SQLite v3 persistence, AI Chat status receipts, and native result links are automated. `needs_attention` is actionable but not actively processing, so it no longer renders an endless spinner. A task-status query timeout remains a transient refresh error. |
| Seedream synchronous timeout | Passed locally and superseded by a successful live retry | Beta evidence showed the former URLSession default ending the synchronous request after about 63 seconds without an HTTP response, task ID, result URL, or usage. Seedream now waits up to five minutes. If that response also times out, the local job becomes terminal `failed`, temporary references are cleaned, and the UI warns that Ark may still have processed the request because there is no task ID to query or cancel. Legacy matching `needs_attention` rows are closed on launch without resubmission. |
| Upload Broker handler contracts | Passed locally | Health, missing/wrong per-device authentication, subject/device handle binding, cross-device rejection, presigned URL generation, R2 object metadata/size validation, complete, refresh, delete, missing object, expired handle, tampered handle, and lifecycle JSON are automated. |
| Cloudflare staging resources | Passed live for deployment/configuration; authenticated data path pending | Per-device Worker version `3d436d60-3096-4d30-a228-bf7667866c5c` was deployed at 100% by deployment `7fbe2660-a6ed-4e9d-acb6-52bdc9f0e762` on 2026-07-28. Current bindings contain the five required secrets and no `BROKER_TOKEN`; staging health returned `200`, unauthenticated upload creation returned `401`, and the active `tmp/` lifecycle rule remains two days. Wrangler CLI login had expired, so immutable version/deployment and bindings were verified through the Cloudflare account API rather than claimed as a Wrangler deployment. |
| Authenticated staging client flow | Previous Beta path passed; new per-device revision not yet fully verified | A prior Beta Seedance run reserved an upload, completed an authenticated presigned JPEG `PUT`, submitted the resulting reference, and deleted the bound upload after terminal success. A new per-device credential is installed in the Beta Keychain and registered in the deployed Worker. The standalone object-byte/refresh/delete harness is blocked on a Keychain read while the test Mac is locked; it is not claimed as passed. Real-time expiry also remains unverified. |
| Seedance paid generation | Passed once in Beta | On 2026-07-23 the operator completed one Seedance 2.0 image-reference video generation. SQLite recorded a provider task ID, one result URL, terminal `succeeded`, and deleted reference-upload state, which implies submit → status polling → download/project finalization → cleanup completed. This is one operator-observed flow, not a latency or reliability benchmark. |
| Seedream paid generation | Passed once in Beta | On 2026-07-25 the operator completed a Seedream 5.0 Pro image generation after the timeout fix. SQLite recorded one attempt, a provider task ID, one result, 4,450 output/total Tokens, terminal `succeeded`, and deleted reference-upload state. The end-to-end local duration was about 129 seconds. |
| Crash recovery with accepted provider task | Passed once in Beta; unopened-project staging remains local-contract evidence | On 2026-07-28 a Seedance job was created, the app exited while it was active, and a new process launched 31 seconds later. The job later reached `succeeded` with one attempt, the original provider task ID, one result, 108,900 total Tokens, and deleted upload state. This verifies restart recovery without resubmission and project finalization. The project was opened before the local terminal write, so this run does not independently prove output staging completed while no project was open. |

Strict Phase 2 is closed by the local implementation and deterministic
acceptance above. The remaining authenticated per-device staging exercise and
future paid drills remain explicitly scoped as additional production evidence
rather than being promoted to live proof.

## Operator-observed Beta timeline

- 2026-07-25 00:10:47–00:12:56: Seedream image generation completed with one
  provider submission, one output, recorded usage, project media installation,
  and reference-upload deletion.
- 2026-07-28 00:06:31: AI Chat created the Seedance generation Job and
  placeholder.
- 2026-07-28 00:07:49: the first Beta process completed application
  termination while the remote Job was active.
- 2026-07-28 00:08:20: a new Beta process launched. SQLite retained the same
  provider task ID and the final attempt count remained one.
- 2026-07-28 00:09:13: the operator opened the project.
- 2026-07-28 00:10:23: the recovered Job installed its video into the project,
  reached `succeeded`, and deleted the bound staging upload.

These observations come from the Beta SQLite database and macOS unified log.
They do not expose prompts, signed URLs, credentials, or full provider task
identifiers.

## Automated commands

Client:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/breazin-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/breazin-swiftpm-cache \
swift test --filter 'GenerationRecoveryCoordinatorTests|GenerationOutputStagerTests|TemporaryReferenceUploaderTests|VolcengineGenerationProviderTests|ReferenceAssetStandardizerTests|GenerationJobStoreTests'
```

The 2026-07-24 status-observability follow-up additionally ran:

```bash
swift test --filter 'VolcengineGenerationProviderTests|GenerationJobStoreTests|GenerationRecoveryCoordinatorTests|ToolExecutorTests'
```

This selected run passed 144 tests in 9 suites.
The earlier unfiltered `swift test --skip-build` regression passed 1,182 tests in
183 suites. A staging smoke bundle was also assembled on a local volume and
passed `scripts/ci/verify-bundle.sh` with display name `呼息 Beta` and bundle ID
`com.writish.breazin.beta`.

The Seedream timeout follow-up ran:

```bash
swift test --filter 'ProviderContractsTests|VolcengineGenerationProviderTests|GenerationRecoveryCoordinatorTests|GenerationJobStoreTests'
```

This run passed 30 tests in 4 suites, including the five-minute request
contract, terminal synchronous-image timeout classification, non-spinning
`needs_attention`, explicit provider rejection, and legacy timeout recovery.

After the timeout changes, the final unfiltered regression was repeated:

```bash
CLANG_MODULE_CACHE_PATH=/private/tmp/breazin-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/breazin-swiftpm-module-cache \
swift test --skip-build
```

This run passed 1,186 tests in 183 suites.

The offline and retry-scheduling closure ran:

```bash
swift test --filter 'GenerationRecoveryCoordinatorTests|GenerationJobStoreTests|ProviderContractsTests|ToolExecutorTests'
```

This selected run passed 150 tests in 9 suites. During hardening of output download
retries so that Seedance refreshes stale provider URLs while synchronous
Seedream retains its only result URL, the focused recovery/store/provider run
passed 28 tests in 3 suites.

The final unfiltered regression was then repeated:

```bash
CLANG_MODULE_CACHE_PATH=/private/tmp/breazin-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/breazin-swiftpm-module-cache \
swift test --skip-build
```

This run passed 1,192 tests in 183 suites.

The external-Beta policy and project-persistence closure passed the complete
client regression:

```bash
swift test --disable-sandbox
```

This intermediate run passed 1,231 tests in 188 suites. The subsequently added
upstream `v0.6.13` golden package was generated by a one-test detached worktree
at the pinned tag, then the five-test `ProjectDocumentIOTests` suite passed
migration, safe replacement, interruption, out-of-space, and idempotency
coverage. After removing the final obsolete Clerk/Convex bundle configuration
and credits localization resources, the unfiltered regression passed 1,232
tests in 188 suites.

A replacement staging smoke bundle containing the timeout fix was assembled at
`/private/tmp/breazin-beta-timeout/Breazin.app` with bundled speech disabled and
passed:

```bash
scripts/ci/verify-bundle.sh /private/tmp/breazin-beta-timeout/Breazin.app staging
```

The verifier confirmed the staging identity and a valid ad-hoc signature. AI
Chat and cloud image/video generation remain present in this smoke bundle.

The final internal staging artifact was rebuilt at
`/tmp/breazin-beta-final/Breazin.app` and passed the same staging bundle verifier,
including Beta identity, MCP metadata, and strict deep codesign verification.
It is ad-hoc signed, not Developer ID signed or notarized, and therefore is not
an external-distribution artifact.

Broker:

```bash
cd ../platform/upload-broker
npm run check
npx wrangler deploy --dry-run --env staging
```

`npm run check` passed generated types, TypeScript compilation, five Vitest
contracts, acceptance-script syntax, and lifecycle configuration. Wrangler
dry-run produced a 25.68 KiB Worker bundle. Dry-run proves only local
buildability; the separate immutable deployment evidence is recorded in the
matrix above and still does not prove the pending authenticated object
round trip.

## Operator acceptance: Cloudflare staging

Manual configuration stays in `platform/upload-broker/wrangler.jsonc` for bucket bindings and custom domains, in Worker secrets for R2 credentials and Broker secrets, and in the untracked `.dev.vars` file for local development. Do not put long-lived R2 credentials in the macOS client.

1. Review `breazin-temp-staging`, `uploads-staging.breazin.com`, the five staging secret names, and `config/r2-lifecycle.json`. `BROKER_DEVICE_CREDENTIALS` must contain one opaque subject/device record and SHA-256 token digest per authorized Beta installation. Record the client device ID shown by the Beta build; do not use an email address as the subject.
2. Confirm the reviewed Worker version is deployed and no legacy `BROKER_TOKEN` binding remains. The 2026-07-28 staging deployment satisfies this configuration check.
3. Reapply or verify the lifecycle rule:

   ```bash
   npx wrangler r2 bucket lifecycle set breazin-temp-staging --file config/r2-lifecycle.json
   npm run verify:staging:lifecycle
   ```

4. Unlock the test Mac, approve the Beta Keychain read if prompted, then supply one registered device's plaintext staging credential and matching device ID only to the current shell. Run the destructive-to-fixture acceptance, then clear them:

   ```bash
   read -s BREAZIN_UPLOAD_BROKER_TOKEN
   export BREAZIN_UPLOAD_BROKER_TOKEN
   read BREAZIN_UPLOAD_BROKER_DEVICE_ID
   export BREAZIN_UPLOAD_BROKER_DEVICE_ID
   npm run accept:staging
   unset BREAZIN_UPLOAD_BROKER_TOKEN BREAZIN_UPLOAD_BROKER_DEVICE_ID
   ```

The harness creates a unique tiny PNG object, validates authenticated upload and download bytes, refreshes the GET URL, deletes the object in `finally`, and verifies refresh returns `404` after deletion. Handle expiry is deterministic in local tests. A real-time expiry exercise should use an isolated short-TTL staging deployment or wait for the configured interval; do not weaken production TTLs.

## Operator acceptance: Seedream and Seedance

1. Enter the Volcengine Ark API key and staging Broker token in the matching Breazin environment settings/Keychain, then fully relaunch the app so launch preloading and global recovery use them.
2. Seedream success was observed once on 2026-07-25. For a future repeat, generate one low-cost Seedream 5.0 Pro 1K image from a local image reference. During the synchronous request AI Chat should show `Waiting for provider`, not a fabricated remote queue state. Confirm normalization, R2 upload, URL refresh if applicable, provider response, output download, project media creation, SQLite terminal state, and R2 cleanup. If no response arrives within five minutes, confirm the row becomes `Failed`, the spinner stops, and the warning says Ark may still have processed the request; check Ark usage before manually retrying.
3. Generate one minimum-duration Seedance 2.0 video with representative local image/video/audio references. Confirm standardized MP4/H.264 and M4A/AAC inputs, provider role mapping, polling, result download, project persistence, and cleanup.
4. Restart recovery with a persisted Provider Task ID and no duplicate submit was observed once on 2026-07-28. A future drill should leave the project closed until SQLite reaches `finalizing` with a staged output path, then open the project and confirm finalization; that stricter unopened-project staging observation has not yet been recorded live.
5. Run a cancellation drill near provider completion and confirm SQLite ends `cancelled`, late success cannot win, and temporary references/staged outputs are removed.

Record provider request IDs, timings, final SQLite states, generated asset locations, and object deletion results without recording API keys, Broker tokens, signed URLs, prompts, or absolute local source paths.

Official references: [Cloudflare R2 presigned URLs](https://developers.cloudflare.com/r2/api/s3/presigned-urls/), [Cloudflare R2 object lifecycles](https://developers.cloudflare.com/r2/buckets/object-lifecycles/), [Seedance 2.0 overview](https://www.volcengine.com/docs/82379/1520758?lang=zh), [Seedance task creation](https://www.volcengine.com/docs/82379/1520757?lang=zh), [single-task status](https://www.volcengine.com/docs/82379/1521309?lang=zh), [multi-task status](https://www.volcengine.com/docs/82379/1521675?lang=zh), [Seedream image generation](https://www.volcengine.com/docs/82379/1541523?lang=zh), and [Volcengine generation overview](https://www.volcengine.com/docs/82379/1824137?lang=zh).
