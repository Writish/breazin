import assert from "node:assert/strict";
import test from "node:test";

import { createRepairEvaluationRequest } from "./repair-evaluation-request.mjs";

const repository = "Writish/breazin";
const baselineCommit = "1".repeat(40);
const candidateCommit = "2".repeat(40);

test("binds one approved internal repair PR to an evidence-empty L2 request", () => {
  const request = createRepairEvaluationRequest({
    event: pullRequestEvent(),
    packet: changePacket(),
    baselineCommit,
    candidateCommit,
    changedPaths: ["Sources/Breazin/Example.swift"],
    patchBytes: Buffer.from("synthetic repair patch\n"),
    ciRunId: "30759000000",
    ciRunAttempt: "1",
  });
  assert.equal(request.status, "awaiting_adapter_execution");
  assert.equal(request.change_id, "CHG-9001");
  assert.equal(request.issue_number, 42);
  assert.equal(request.repair_authority_run_id, "30758000000");
  assert.equal(request.baseline_commit, baselineCommit);
  assert.equal(request.candidate_commit, candidateCommit);
  assert.match(request.candidate_patch_sha256, /^[a-f0-9]{64}$/);
  assert.match(request.evaluation_request_id, /^[a-f0-9]{64}$/);
  assert.deepEqual(request.required_ci_jobs, [
    "Approved Repair Contract",
    "Build & Test",
  ]);
  assert.equal(request.l2_evaluation_complete, false);
  assert.equal(request.human_review_still_required, true);
  assert.equal(request.merge_authorized, false);
  assert.equal(request.publication_authorized, false);
  assert.ok(!("outcome" in request));
  assert.ok(!("evidence_ids" in request));
});

test("rejects fork, non-repair, non-main, identity-mismatched, or non-low-risk PRs", () => {
  const cases = [
    (event, packet) => { event.pull_request.head.repo.full_name = "attacker/fork"; },
    (event, packet) => { event.pull_request.head.ref = "feature/not-repair"; },
    (event, packet) => { event.pull_request.base.ref = "release/test"; },
    (event, packet) => { event.pull_request.head.ref = "repair/CHG-9999-30758000000"; },
    (event, packet) => { packet.changeId = "CHG-9999"; },
    (event, packet) => { packet.risk = "medium"; },
    (event, packet) => { packet.repository = "Writish/other"; },
  ];
  for (const mutate of cases) {
    const event = pullRequestEvent();
    const packet = changePacket();
    mutate(event, packet);
    assert.throws(
      () => createRepairEvaluationRequest({
        event,
        packet,
        baselineCommit,
        candidateCommit,
        changedPaths: ["Sources/Breazin/Example.swift"],
        patchBytes: Buffer.from("synthetic repair patch\n"),
        ciRunId: "30759000000",
        ciRunAttempt: "1",
      }),
      /repair evaluation request is invalid/,
    );
  }
});

test("rejects empty, frozen, outside-scope, or commit-tampered candidate input", () => {
  const cases = [
    { changedPaths: [], patchBytes: Buffer.from("patch\n"), candidateCommit },
    { changedPaths: ["Tests/Fixtures/frozen.json"], patchBytes: Buffer.from("patch\n"), candidateCommit },
    { changedPaths: ["README.md"], patchBytes: Buffer.from("patch\n"), candidateCommit },
    { changedPaths: ["Sources/Breazin/Example.swift"], patchBytes: Buffer.alloc(0), candidateCommit },
    { changedPaths: ["Sources/Breazin/Example.swift"], patchBytes: Buffer.from("patch\n"), candidateCommit: baselineCommit },
    { changedPaths: ["Sources/Breazin/Example.swift"], patchBytes: Buffer.from("patch\n"), candidateCommit: "not-a-commit" },
  ];
  for (const input of cases) {
    assert.throws(
      () => createRepairEvaluationRequest({
        event: pullRequestEvent(),
        packet: changePacket(),
        baselineCommit,
        ciRunId: "30759000000",
        ciRunAttempt: "1",
        ...input,
      }),
      /repair evaluation request is invalid|repair modified|no file changes/,
    );
  }
});

function pullRequestEvent() {
  return {
    repository: { full_name: repository },
    pull_request: {
      number: 17,
      draft: true,
      body: [
        "Isolated repair generated from signed, human-approved Issue #42.",
        "- Spec: signed Change Packet in Issue #42",
        "- Decision record: Issue #42",
      ].join("\n"),
      base: { ref: "main" },
      head: {
        ref: "repair/CHG-9001-30758000000",
        sha: candidateCommit,
        repo: { full_name: repository },
      },
    },
  };
}

function changePacket() {
  return {
    changeId: "CHG-9001",
    repository,
    risk: "low",
    objective: "Correct one bounded behavior.",
    expectedOutputs: ["A source fix"],
    acceptanceCriteria: ["The focused regression passes"],
    allowedPaths: ["Sources/Breazin", "Tests/BreazinTests"],
    frozenPaths: ["Tests/Fixtures"],
    baselineEvidence: {
      status: "captured",
      evidenceIds: ["ev_baseline_123"],
    },
  };
}
