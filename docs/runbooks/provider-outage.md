# Provider outage runbook

1. Disable new submissions for the affected provider without disabling local editing or export.
2. Keep persisted jobs and provider job IDs; do not blindly resubmit an ambiguous request.
3. Mark recoverable jobs for backoff and unrecoverable ambiguity as `needs_attention`.
4. Redact keys, signed URLs, prompts, user paths, and media before collecting diagnostics.
5. Restore polling gradually, verify downloads and checksums, and reconcile each terminal state once.

Legacy backend outages must not prevent the application from opening local projects.
