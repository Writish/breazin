#!/usr/bin/env node

import { createPublicKey, verify } from "node:crypto";
import { appendFileSync } from "node:fs";
import { readFile, writeFile } from "node:fs/promises";

const hardProtectedPaths = [
  ".github",
  "scripts/ci/verify-approved-repair.mjs",
  "scripts/ci/verify-repair-scope.mjs",
];

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

const jwsMatches = [
  ...issue.body.matchAll(
    /<!-- breazin-change-packet-jws: ([A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+) -->/g,
  ),
];
if (jwsMatches.length !== 1 || !jwsMatches[0]?.[1]) {
  fail("issue must contain exactly one signed Change Packet");
}
const compactJws = jwsMatches[0][1];
if (compactJws.length > 32_000) {
  fail("signed Change Packet exceeds the size limit");
}
const [encodedHeader, encodedPayload, encodedSignature] = compactJws.split(".");
if (!encodedHeader || !encodedPayload || !encodedSignature) {
  fail("signed Change Packet is malformed");
}
const header = parseJsonSegment(encodedHeader, "JWS header");
const payload = parseJsonSegment(encodedPayload, "JWS payload");
if (
  header.alg !== "ES256" ||
  header.typ !== "breazin-change-packet+jwt" ||
  header.kid !== "development-2026-07"
) {
  fail("signed Change Packet header is not an accepted development key");
}
const publicKey = createPublicKey(
  await readFile(
    new URL("../../.github/breazin-change-packet-public.pem", import.meta.url),
    "utf8",
  ),
);
const valid = verify(
  "sha256",
  Buffer.from(`${encodedHeader}.${encodedPayload}`),
  { key: publicKey, dsaEncoding: "ieee-p1363" },
  decodeBase64Url(encodedSignature),
);
if (!valid) {
  fail("Change Packet signature is invalid");
}

validatePayload(payload, repository, issue.body);
await writeFile(outputPath, `${JSON.stringify(payload, null, 2)}\n`, {
  mode: 0o600,
});
appendOutput("change_id", payload.changePacket.changeId);
appendOutput("risk", payload.changePacket.risk);
appendOutput("outbox_event_id", payload.outboxEventId);
console.log(
  `Verified ${payload.changePacket.changeId} from decision ${payload.decisionId}`,
);

function validatePayload(value, expectedRepository, issueBody) {
  if (
    value.version !== 1 ||
    value.iss !== "breazin-control-plane" ||
    value.aud !== "breazin-approved-repair" ||
    typeof value.jti !== "string" ||
    value.jti !== value.outboxEventId ||
    typeof value.sub !== "string" ||
    typeof value.approvedBy !== "string" ||
    typeof value.approvalRationale !== "string" ||
    typeof value.approvedAt !== "string" ||
    typeof value.changePacket !== "object" ||
    value.changePacket === null
  ) {
    fail("Change Packet approval envelope is invalid");
  }
  const packet = value.changePacket;
  if (
    !/^CHG-[0-9]{4,12}$/.test(packet.changeId ?? "") ||
    value.sub !== packet.changeId ||
    packet.repository !== expectedRepository ||
    !["low", "medium", "high", "critical"].includes(packet.risk) ||
    typeof packet.objective !== "string" ||
    packet.objective.trim().length === 0 ||
    !nonEmptyStringArray(packet.expectedOutputs) ||
    !nonEmptyStringArray(packet.acceptanceCriteria) ||
    !nonEmptyStringArray(packet.allowedPaths) ||
    !stringArray(packet.frozenPaths) ||
    typeof packet.baselineEvidence !== "object" ||
    packet.baselineEvidence === null ||
    !["captured", "evidence_gap"].includes(packet.baselineEvidence.status) ||
    !stringArray(packet.baselineEvidence.evidenceIds)
  ) {
    fail("Change Packet body is invalid");
  }
  if (
    packet.baselineEvidence.status === "captured" &&
    packet.baselineEvidence.evidenceIds.length === 0
  ) {
    fail("captured baseline requires evidence IDs");
  }
  for (const path of [...packet.allowedPaths, ...packet.frozenPaths]) {
    if (!safeRepositoryPath(path)) {
      fail(`unsafe repository path in Change Packet: ${path}`);
    }
  }
  for (const allowedPath of packet.allowedPaths) {
    if (
      hardProtectedPaths.some(
        (protectedPath) =>
          pathWithin(protectedPath, allowedPath) ||
          pathWithin(allowedPath, protectedPath),
      )
    ) {
      fail(`Change Packet cannot authorize protected path: ${allowedPath}`);
    }
  }
  if (
    !issueBody.includes(`<!-- breazin-outbox:${value.outboxEventId} -->`)
  ) {
    fail("Issue marker does not match the signed outbox event");
  }
}

function parseJsonSegment(value, name) {
  try {
    const parsed = JSON.parse(decodeBase64Url(value).toString("utf8"));
    if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
      fail(`${name} must be an object`);
    }
    return parsed;
  } catch {
    fail(`${name} is invalid JSON`);
  }
}

function decodeBase64Url(value) {
  if (!/^[A-Za-z0-9_-]+$/.test(value)) {
    fail("JWS contains invalid base64url");
  }
  return Buffer.from(value, "base64url");
}

function safeRepositoryPath(value) {
  return (
    typeof value === "string" &&
    value.length > 0 &&
    value.length <= 512 &&
    !value.startsWith("/") &&
    !value.startsWith("~") &&
    !value.includes("\\") &&
    !value.split("/").some((part) => part === "." || part === "..")
  );
}

function pathWithin(path, prefix) {
  const normalized = prefix.endsWith("/") ? prefix : `${prefix}/`;
  return path === prefix || path.startsWith(normalized);
}

function stringArray(value) {
  return (
    Array.isArray(value) &&
    value.length <= 100 &&
    value.every((item) => typeof item === "string" && item.length <= 1_000)
  );
}

function nonEmptyStringArray(value) {
  return stringArray(value) && value.length > 0;
}

function appendOutput(name, value) {
  if (!process.env.GITHUB_OUTPUT) return;
  appendFileSync(process.env.GITHUB_OUTPUT, `${name}=${value}\n`);
}

function fail(message) {
  console.error(message);
  process.exit(1);
}
