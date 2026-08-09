# Project subsystem rules

- Preserve read compatibility with the pinned v0.6.13 fixture and every shipped Breazin Stable fixture.
- Migrations happen in memory, back up before first write, replace atomically, and remain idempotent.
- Future unsupported schemas must never be autosaved into an older format.
- Project format or destructive changes require focused round-trip tests and human approval.
