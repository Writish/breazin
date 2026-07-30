#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${PR_BODY:-}" ]]; then
  body="${PR_BODY}"
elif [[ -n "${GITHUB_EVENT_PATH:-}" && -f "${GITHUB_EVENT_PATH}" ]]; then
  body="$(jq -r '.pull_request.body // ""' "${GITHUB_EVENT_PATH}")"
else
  echo "PR_BODY or GITHUB_EVENT_PATH is required" >&2
  exit 2
fi

required_patterns=(
  '^## Change contract'
  'Change-ID:[[:space:]]*CHG-[0-9]{4,}'
  'Spec:[[:space:]]*.+'
  'Risk:[[:space:]]*(low|medium|high|critical)'
  '^## Evidence'
  'Baseline evidence:[[:space:]]*.+'
  'Candidate evidence:[[:space:]]*.+'
  '^## Human verification'
  '^## Delivery authority'
  '^- \[x\] The repair does not modify its frozen scenario, fixture, grader, or baseline evidence\.'
  '^- \[x\] Untrusted feedback did not directly authorize repository writes\.'
  '^- \[x\] No production credential, merge, release, or publication authority was added\.'
  '^- \[x\] Remaining unverified work and rollout/rollback conditions are explicit\.'
)

for pattern in "${required_patterns[@]}"; do
  if ! grep -Eiq "${pattern}" <<<"${body}"; then
    echo "Missing PR change-contract field matching: ${pattern}" >&2
    exit 1
  fi
done

if grep -Eq '^- \[ \] ' <<<"${body}"; then
  echo "All delivery-authority declarations must be acknowledged" >&2
  exit 1
fi

echo "PR change contract is complete"
