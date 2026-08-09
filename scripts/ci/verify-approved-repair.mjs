#!/usr/bin/env node

import { appendFileSync } from "node:fs";
import { readFile, writeFile } from "node:fs/promises";
import { verifyApprovedRepairIssue } from "./approved-repair-contract.mjs";

const issueNumber = process.argv[2];
const outputPath =
  process.argv[3] ?? "/tmp/breazin-approved-change-packet.json";
const repository = process.env.GITHUB_REPOSITORY;
const token = process.env.GH_TOKEN;
if (!/^[1-9][0-9]{0,9}$/.test(issueNumber ?? "")) {
  fail("issue number must be a positive integer");
}
if (!repository || !/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repository)) {
  fail("GITHUB_REPOSITORY is invalid");
}
if (!token) {
  fail("GH_TOKEN is required");
}

const response = await fetch(
  `https://api.github.com/repos/${repository}/issues/${issueNumber}`,
  {
    headers: {
      Accept: "application/vnd.github+json",
      Authorization: `Bearer ${token}`,
      "User-Agent": "breazin-approved-repair-verifier",
      "X-GitHub-Api-Version": "2022-11-28",
    },
  },
);
if (!response.ok) {
  fail(`GitHub issue lookup failed with status ${response.status}`);
}
const issue = await response.json();
if (
  typeof issue !== "object" ||
  issue === null ||
  typeof issue.body !== "string" ||
  issue.pull_request !== undefined
) {
  fail("approved repair input must be a GitHub Issue");
}

let payload;
try {
  payload = verifyApprovedRepairIssue({
    issueBody: issue.body,
    expectedRepository: repository,
    publicKey: await readFile(
      new URL("../../.github/breazin-change-packet-public.pem", import.meta.url),
      "utf8",
    ),
    acceptedKeyId: "development-2026-07",
  });
} catch (error) {
  fail(error instanceof Error ? error.message : "Change Packet verification failed");
}
await writeFile(outputPath, `${JSON.stringify(payload, null, 2)}\n`, {
  mode: 0o600,
});
appendOutput("change_id", payload.changePacket.changeId);
appendOutput("risk", payload.changePacket.risk);
appendOutput("outbox_event_id", payload.outboxEventId);
console.log(
  `Verified ${payload.changePacket.changeId} from decision ${payload.decisionId}`,
);

function appendOutput(name, value) {
  if (!process.env.GITHUB_OUTPUT) return;
  appendFileSync(process.env.GITHUB_OUTPUT, `${name}=${value}\n`);
}

function fail(message) {
  console.error(message);
  process.exit(1);
}
