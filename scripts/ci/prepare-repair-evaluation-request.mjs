#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { readFile, writeFile } from "node:fs/promises";

import { verifyApprovedRepairIssue } from "./approved-repair-contract.mjs";
import {
  createRepairEvaluationRequest,
  extractRepairIssueNumber,
} from "./repair-evaluation-request.mjs";

const eventPath = process.env.GITHUB_EVENT_PATH;
const repository = process.env.GITHUB_REPOSITORY;
const token = process.env.GH_TOKEN;
const ciRunId = process.env.GITHUB_RUN_ID;
const ciRunAttempt = process.env.GITHUB_RUN_ATTEMPT;
const outputPath = process.argv[2] ?? "repair-evaluation-request.json";

if (!eventPath || !repository || !token || !ciRunId || !ciRunAttempt) {
  fail("repair evaluation environment is incomplete");
}

try {
  const event = JSON.parse(await readFile(eventPath, "utf8"));
  if (event?.repository?.full_name !== repository) {
    throw new Error("repair event repository is invalid");
  }
  const issueNumber = extractRepairIssueNumber(event);
  const issueResponse = await fetch(
    `https://api.github.com/repos/${repository}/issues/${issueNumber}`,
    {
      headers: {
        Accept: "application/vnd.github+json",
        Authorization: `Bearer ${token}`,
        "User-Agent": "breazin-repair-evaluation-request",
        "X-GitHub-Api-Version": "2022-11-28",
      },
    },
  );
  if (!issueResponse.ok) {
    throw new Error(`GitHub issue lookup failed with status ${issueResponse.status}`);
  }
  const issue = await issueResponse.json();
  if (
    !issue ||
    typeof issue !== "object" ||
    typeof issue.body !== "string" ||
    issue.pull_request !== undefined
  ) {
    throw new Error("repair authority must be a GitHub Issue");
  }
  const envelope = verifyApprovedRepairIssue({
    issueBody: issue.body,
    expectedRepository: repository,
    publicKey: await readFile(
      new URL("../../.github/breazin-change-packet-public.pem", import.meta.url),
      "utf8",
    ),
    acceptedKeyId: "development-2026-07",
  });
  const candidateCommit = git(["rev-parse", "HEAD"]).toString("utf8").trim();
  const baselineCommit = git([
    "merge-base",
    "origin/main",
    candidateCommit,
  ]).toString("utf8").trim();
  const changedPaths = git([
    "diff",
    "--name-only",
    "--no-renames",
    "-z",
    baselineCommit,
    candidateCommit,
  ]).toString("utf8").split("\0").filter(Boolean);
  const patchBytes = git([
    "diff",
    "--binary",
    "--no-renames",
    baselineCommit,
    candidateCommit,
  ]);
  const request = createRepairEvaluationRequest({
    event,
    packet: envelope.changePacket,
    baselineCommit,
    candidateCommit,
    changedPaths,
    patchBytes,
    ciRunId,
    ciRunAttempt,
  });
  await writeFile(outputPath, `${JSON.stringify(request, null, 2)}\n`, {
    mode: 0o600,
  });
  console.log(
    `Prepared evidence-empty L2 request ${request.evaluation_request_id} for ${request.change_id}`,
  );
} catch (error) {
  fail(error instanceof Error ? error.message : "repair evaluation request failed");
}

function git(args) {
  return execFileSync("git", args, {
    maxBuffer: 10 * 1024 * 1024,
  });
}

function fail(message) {
  console.error(message);
  process.exit(1);
}
