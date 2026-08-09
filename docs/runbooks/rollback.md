# Rollback runbook

1. Stop the affected appcast from advertising the bad version.
2. Restore the last known-good signed, notarized, immutable artifact; do not rebuild it.
3. Publish a higher-version corrective release when Sparkle clients have already observed the bad version.
4. Preserve the failed artifact, logs, checksums, release approvals, and incident timeline.
5. Verify old project read compatibility and open/save/reopen behavior before resuming rollout.

Never solve a rollback by silently replacing bytes at an existing release URL.
