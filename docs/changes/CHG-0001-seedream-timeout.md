# CHG-0001: Close synchronous Seedream timeout

## Identity

- Risk: high
- Historical baseline: `cf4890d40f3a79150ad9a9e902c4507d2021bec0`
- Historical candidate: `d3648ff1015f2265d6032c265a48c1a7f99a5551`
- Scenario: `SCN-GEN-0001@1`
- Status: accepted historically; live baseline replay pending

## User intent

When a synchronous Seedream request times out without a provider task ID, stop active progress and report a truthful terminal failure. Do not claim that the result can be polled, recovered, or safely resubmitted.

## Contract

- SQLite generation Job state is the execution truth.
- A response timeout without a task ID becomes terminal `failed`.
- Bound temporary references are cleaned and progress ends.
- The warning states that the provider may still have processed the request.
- No recovery polling or automatic resubmit occurs without a provider task ID.
- Explicit provider rejection is terminal; genuinely ambiguous asynchronous submission remains `needs_attention`.

## Acceptance

- Deterministic regression checks assert terminal Job state, inactive progress, cleanup, warning semantics, and no false remote recovery path.
- Scenario `SCN-GEN-0001@1` independently checks project integrity, intent fulfillment, absence of a fabricated result, and operational cleanup.
- The checked-in platform manifest records the historical candidate result. It is a provenance bootstrap, not a claim that the baseline commit was freshly executed by the new harness.

## Evidence gap

The original repair predates this evidence pipeline. Commit history proves the before/candidate boundary, but a content-addressed baseline failure artifact was not captured before the repair. A live worktree replay of both commits is still required to upgrade this record to complete Red-before-Green evidence.
