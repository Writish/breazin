import { createHash } from "node:crypto";

import { validateRepairScope } from "./approved-repair-contract.mjs";

const COMMIT = /^[a-f0-9]{40}$/;
const RUN_ID = /^[1-9][0-9]{0,19}$/;
const CHANGE_ID = /^CHG-[0-9]{4,12}$/;
const MAX_PATCH_BYTES = 10 * 1024 * 1024;

export function createRepairEvaluationRequest({
  event,
  packet,
  baselineCommit,
  candidateCommit,
  changedPaths,
  patchBytes,
  ciRunId,
  ciRunAttempt,
}) {
  const repository = event?.repository?.full_name;
  const pullRequest = event?.pull_request;
  const branch = pullRequest?.head?.ref;
  const branchMatch = typeof branch === "string"
    ? branch.match(/^repair\/(CHG-[0-9]{4,12})-([1-9][0-9]{0,19})$/)
    : null;
  let issueNumber;
  try {
    issueNumber = extractRepairIssueNumber(event);
  } catch {
    throw new Error("repair evaluation request is invalid");
  }
  if (
    typeof repository !== "string" ||
    !pullRequest ||
    pullRequest.draft !== true ||
    !Number.isInteger(pullRequest.number) ||
    pullRequest.number < 1 ||
    pullRequest.base?.ref !== "main" ||
    pullRequest.head?.repo?.full_name !== repository ||
    pullRequest.head?.sha !== candidateCommit ||
    branchMatch === null ||
    !CHANGE_ID.test(packet?.changeId ?? "") ||
    branchMatch[1] !== packet.changeId ||
    packet.repository !== repository ||
    packet.risk !== "low" ||
    !COMMIT.test(baselineCommit ?? "") ||
    !COMMIT.test(candidateCommit ?? "") ||
    baselineCommit === candidateCommit ||
    !Buffer.isBuffer(patchBytes) ||
    patchBytes.length === 0 ||
    patchBytes.length > MAX_PATCH_BYTES ||
    !RUN_ID.test(ciRunId ?? "") ||
    !RUN_ID.test(ciRunAttempt ?? "")
  ) {
    throw new Error("repair evaluation request is invalid");
  }
  validateRepairScope({ changedPaths, packet });

  const core = {
    schema_version: 1,
    kind: "repair_evaluation_request",
    status: "awaiting_adapter_execution",
    repository,
    pull_request_number: pullRequest.number,
    issue_number: issueNumber,
    change_id: packet.changeId,
    risk: packet.risk,
    repair_authority_run_id: branchMatch[2],
    ci_run_id: ciRunId,
    ci_run_attempt: ciRunAttempt,
    baseline_commit: baselineCommit,
    candidate_commit: candidateCommit,
    candidate_patch_sha256: sha256(patchBytes),
    changed_paths: [...changedPaths].sort(),
    baseline_evidence: {
      status: packet.baselineEvidence.status,
      evidence_ids: [...packet.baselineEvidence.evidenceIds],
    },
    required_ci_jobs: ["Approved Repair Contract", "Build & Test"],
    l2_evaluation_complete: false,
    human_review_still_required: true,
    merge_authorized: false,
    publication_authorized: false,
  };
  return {
    ...core,
    evaluation_request_id: sha256(Buffer.from(JSON.stringify(core))),
  };
}

export function extractRepairIssueNumber(event) {
  const body = event?.pull_request?.body;
  const issueNumbers = typeof body === "string"
    ? [...body.matchAll(/Issue #([1-9][0-9]{0,9})/g)].map(
        (match) => match[1],
      )
    : [];
  const uniqueIssueNumbers = [...new Set(issueNumbers)];
  if (uniqueIssueNumbers.length !== 1) {
    throw new Error("repair PR must cite exactly one approved Issue");
  }
  return Number(uniqueIssueNumbers[0]);
}

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}
