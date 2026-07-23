# Phase 2 acceptance record

Recorded 2026-07-23. This record separates deterministic local contracts, read-only checks against currently deployed Cloudflare resources, and production end-to-end work that still requires operator credentials or paid-generation approval.

## Acceptance matrix

| Scope | Result | Evidence |
| --- | --- | --- |
| Global SQLite recovery | Passed locally | Automated coverage for crash restart, duplicate recovery, unopened project, `queued`/`running`/`downloading`, missing provider task ID, cancellation without a remote task, and cancellation/completion races. Recovery contains no provider submit path. |
| Provider output staging | Passed locally | Generated URLs are downloaded to app support, persisted as job-relative paths, rejected on path traversal, transferred to the project when opened, and cleaned after terminal handling. |
| Reference normalization and binding | Passed locally | Image streaming checksum, MP4/H.264 normalization, M4A/AAC normalization, Broker reserve/upload/complete/refresh/delete, and SQLite Job/upload binding are automated. |
| Volcengine request contracts | Passed locally | Seedream synchronous image and Seedance asynchronous video request mapping, content roles, polling states, cancellation, expiry, and safe remote errors are automated against fixtures. |
| Upload Broker handler contracts | Passed locally | Health, missing/wrong authentication, presigned URL generation, R2 object metadata/size validation, complete, refresh, delete, missing object, expired handle, tampered handle, and lifecycle JSON are automated. |
| Cloudflare staging resources | Partially verified live | Wrangler authentication, three R2 buckets, staging deployment, required secret names, staging health `200`, unauthenticated upload `401`, and active `tmp/` two-day lifecycle rule were checked against the Cloudflare account. |
| Authenticated staging object round trip | **Not verified** | The acceptance session had no recoverable staging Broker token. The new local Worker acceptance changes were not deployed. No authenticated presigned `PUT`, object read, `complete`, `refresh`, or `delete` result is claimed for the deployed staging Worker. |
| Seedream/Seedance paid generation | **Not verified** | No Volcengine Ark API key was available in the checked Breazin environments and no paid request was authorized. Provider billing, live model availability, generated media download, and production latency remain unverified. |

## Automated commands

Client:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/breazin-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/breazin-swiftpm-cache \
swift test --filter 'GenerationRecoveryCoordinatorTests|GenerationOutputStagerTests|TemporaryReferenceUploaderTests|VolcengineGenerationProviderTests|ReferenceAssetStandardizerTests|GenerationJobStoreTests'
```

Broker:

```bash
cd ../platform/upload-broker
npm run check
npx wrangler deploy --dry-run --env staging
```

Wrangler dry-run proves only that the local Worker bundle is buildable. It is not a staging deployment and is not evidence of a real R2 upload.

## Operator acceptance: Cloudflare staging

Manual configuration stays in `platform/upload-broker/wrangler.jsonc` for bucket bindings and custom domains, in Worker secrets for R2 credentials and Broker secrets, and in the untracked `.dev.vars` file for local development. Do not put long-lived R2 credentials in the macOS client.

1. Review `breazin-temp-staging`, `uploads-staging.breazin.com`, the five staging secret names, and `config/r2-lifecycle.json`.
2. Deploy the reviewed local revision with `npm run deploy:staging`.
3. Reapply or verify the lifecycle rule:

   ```bash
   npx wrangler r2 bucket lifecycle set breazin-temp-staging --file config/r2-lifecycle.json
   npm run verify:staging:lifecycle
   ```

4. Supply the staging Broker token only to the current shell, run the destructive-to-fixture acceptance, then clear it:

   ```bash
   read -s BREAZIN_UPLOAD_BROKER_TOKEN
   export BREAZIN_UPLOAD_BROKER_TOKEN
   npm run accept:staging
   unset BREAZIN_UPLOAD_BROKER_TOKEN
   ```

The harness creates a unique tiny PNG object, validates authenticated upload and download bytes, refreshes the GET URL, deletes the object in `finally`, and verifies refresh returns `404` after deletion. Handle expiry is deterministic in local tests. A real-time expiry exercise should use an isolated short-TTL staging deployment or wait for the configured interval; do not weaken production TTLs.

## Operator acceptance: Seedream and Seedance

1. Enter the Volcengine Ark API key and staging Broker token in the matching Breazin environment settings/Keychain, then fully relaunch the app so launch preloading and global recovery use them.
2. With a test project open, generate one low-cost Seedream 5.0 Pro 1K image from a local image reference. Confirm normalization, R2 upload, URL refresh if applicable, provider response, output download, project media creation, SQLite terminal state, and R2 cleanup.
3. Generate one minimum-duration Seedance 2.0 video with representative local image/video/audio references. Confirm standardized MP4/H.264 and M4A/AAC inputs, provider role mapping, polling, result download, project persistence, and cleanup.
4. Run a recovery drill: close the project and terminate the app during `queued` or `running`, relaunch without opening the project, then confirm polling/download staging resumes without another submit or duplicate charge. Open the project and confirm finalization.
5. Run a cancellation drill near provider completion and confirm SQLite ends `cancelled`, late success cannot win, and temporary references/staged outputs are removed.

Record provider request IDs, timings, final SQLite states, generated asset locations, and object deletion results without recording API keys, Broker tokens, signed URLs, prompts, or absolute local source paths.

Official references: [Cloudflare R2 presigned URLs](https://developers.cloudflare.com/r2/api/s3/presigned-urls/), [Cloudflare R2 object lifecycles](https://developers.cloudflare.com/r2/buckets/object-lifecycles/), [Seedance 2.0 overview](https://www.volcengine.com/docs/82379/1520758?lang=zh), [Seedance task creation](https://www.volcengine.com/docs/82379/1520757?lang=zh), [Seedream image generation](https://www.volcengine.com/docs/82379/1541523?lang=zh), and [Volcengine generation overview](https://www.volcengine.com/docs/82379/1824137?lang=zh).
