# Generation subsystem rules

- `GenerationService` owns app lifecycle; provider adapters own external API differences.
- Persist a local idempotency key before remote submission and provider job ID immediately after success.
- Never log API keys, Authorization headers, signed URLs, absolute user paths, prompts, or media content.
- A restart must not duplicate ambiguous remote submissions. Tests must cover retries, cancellation races, expiry, corrupt downloads, and recovery.
