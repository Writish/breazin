# Temporary generation reference assets

Breazin uses a narrow Cloudflare Worker and private R2 Standard buckets for local media that must be reachable by a generation provider. The Broker is an upload control plane only: it never receives prompts, calls Volcengine, or owns generation Job state.

## Boundary and flow

1. The macOS client creates the generation Job and upload row in local SQLite before network work.
2. Images are normalized to JPEG, PNG, or WebP; video to MP4/H.264; audio to M4A/AAC. The client computes a streaming SHA-256 digest.
3. The client asks the Broker for a 15-minute presigned `PUT`. The signed upload handle binds the Job, source asset, object key, content type, byte length, digest, and logical expiry.
4. The client uploads the file directly to R2. The body never passes through the Worker.
5. The Broker verifies the resulting R2 object through its bucket binding, then returns a six-hour presigned `GET` for Seedance/Seedream.
6. Before provider submission, the client refreshes URLs that have less than 15 minutes remaining. It persists the refreshed URL and expiry on the upload row.
7. On terminal success, terminal provider failure, cancellation, or partial-upload failure, the client asks the Broker to delete bound objects. A two-day `tmp/` R2 lifecycle rule is the fallback.

R2 Access Key ID and Secret Access Key exist only as Worker secrets. The client stores only its Broker credential in Keychain. Presigned URLs, upload handles, prompts, absolute source paths, and API keys must not be logged.

## Durable state and recovery

`generation_jobs` is the execution source of truth. The project manifest stores only a stable local Job ID plus provider/result metadata needed for compatibility and presentation. `generation_uploads` owns the durable binding between each reference and the Job, including the standardized relative path, digest, opaque Broker handle, remote URL, and expiries.

Remote submit uses a persisted idempotency key. The provider task ID is persisted immediately after submission. A crash with no provider task ID is marked `needs_attention`; recovery never blindly submits an ambiguous request again.

At app launch, an app-global coordinator scans every non-terminal SQLite Job, independent of which projects are open. Jobs with provider IDs resume polling. Provider-complete jobs download result URLs to `Application Support/Generation/Outputs/<job-id>` and persist only validated relative paths in SQLite. They remain in `finalizing` until the owning project opens, at which point the project service atomically takes over, commits staged media into the project package, finalizes assets, and removes the app-level staged files. Repeated scans and project takeover cannot run the same recovery operation concurrently.

Cancellation is intent-first. SQLite records `cancel_requested` before the provider call. If no remote task exists, the Job becomes cancelled locally. If a remote cancellation cannot be confirmed, local cancellation still wins and cleanup runs; a late provider success cannot move the Job back to downloading, finalizing, or succeeded. Terminal states and forward progress are monotonic.

## Authentication evolution

The initial Broker bearer token is a development/bootstrap credential, not the public-commercial authentication design. Before external distribution it must be replaced by short-lived per-user or per-device authorization, with rate limits and revocation, without changing the upload or Job contracts.

Provider-specific authentication stays outside this boundary. OpenAI OAuth and the future Midjourney Discord bot adapter consume the same durable Job and reference URL abstractions.
