import { createPublicKey, verify } from "node:crypto";

export const hardProtectedPaths = Object.freeze([
  ".github",
  "scripts/ci/approved-repair-contract.mjs",
  "scripts/ci/verify-approved-repair.mjs",
  "scripts/ci/verify-repair-scope.mjs",
]);

const CHANGE_ID = /^CHG-[0-9]{4,12}$/;
const REPOSITORY = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const ACTOR = /^access:\S{3,505}$/;

export function verifyApprovedRepairIssue({
  issueBody,
  expectedRepository,
  publicKey,
  acceptedKeyId,
  now = Date.now(),
}) {
  if (
    typeof issueBody !== "string" ||
    !REPOSITORY.test(expectedRepository ?? "") ||
    typeof acceptedKeyId !== "string" ||
    !/^[A-Za-z0-9._-]{3,100}$/.test(acceptedKeyId) ||
    !Number.isFinite(now)
  ) {
    throw new Error("approved repair verification input is invalid");
  }
  const matches = [
    ...issueBody.matchAll(
      /<!-- breazin-change-packet-jws: ([A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+) -->/g,
    ),
  ];
  if (matches.length !== 1 || !matches[0]?.[1]) {
    throw new Error("issue must contain exactly one signed Change Packet");
  }
  const compactJws = matches[0][1];
  if (compactJws.length > 32_000) {
    throw new Error("signed Change Packet exceeds the size limit");
  }
  const [encodedHeader, encodedPayload, encodedSignature] = compactJws.split(".");
  if (!encodedHeader || !encodedPayload || !encodedSignature) {
    throw new Error("signed Change Packet is malformed");
  }
  const header = parseJsonSegment(encodedHeader, "JWS header");
  const payload = parseJsonSegment(encodedPayload, "JWS payload");
  if (
    header.alg !== "ES256" ||
    header.typ !== "breazin-change-packet+jwt" ||
    header.kid !== acceptedKeyId ||
    Object.keys(header).length !== 3
  ) {
    throw new Error("signed Change Packet header is not accepted");
  }
  let key;
  try {
    key = createPublicKey(publicKey);
  } catch {
    throw new Error("Change Packet verification key is invalid");
  }
  if (
    !verify(
      "sha256",
      Buffer.from(`${encodedHeader}.${encodedPayload}`),
      { key, dsaEncoding: "ieee-p1363" },
      decodeBase64Url(encodedSignature),
    )
  ) {
    throw new Error("Change Packet signature is invalid");
  }
  validateApprovalEnvelope({
    value: payload,
    expectedRepository,
    issueBody,
    now,
  });
  return payload;
}

export function validateRepairScope({ changedPaths, packet }) {
  if (
    !packet ||
    typeof packet !== "object" ||
    !Array.isArray(packet.allowedPaths) ||
    !Array.isArray(packet.frozenPaths)
  ) {
    throw new Error("verified Change Packet is missing path authority");
  }
  if (!Array.isArray(changedPaths) || changedPaths.length === 0) {
    throw new Error("repair produced no file changes");
  }
  const unique = new Set();
  for (const path of changedPaths) {
    if (!safeRepositoryPath(path) || unique.has(path)) {
      throw new Error(`repair produced an invalid changed path: ${path}`);
    }
    unique.add(path);
    if (hardProtectedPaths.some((prefix) => pathWithin(path, prefix))) {
      throw new Error(`repair modified hard-protected path: ${path}`);
    }
    if (packet.frozenPaths.some((prefix) => pathWithin(path, prefix))) {
      throw new Error(`repair modified frozen path: ${path}`);
    }
    if (!packet.allowedPaths.some((prefix) => pathWithin(path, prefix))) {
      throw new Error(`repair modified path outside approved scope: ${path}`);
    }
  }
  return [...changedPaths];
}

function validateApprovalEnvelope({ value, expectedRepository, issueBody, now }) {
  const approvedAt = Date.parse(value?.approvedAt);
  const approvedSecond = Math.floor(approvedAt / 1_000);
  if (
    !value ||
    value.version !== 1 ||
    value.iss !== "breazin-control-plane" ||
    value.aud !== "breazin-approved-repair" ||
    !UUID.test(value.jti ?? "") ||
    value.jti !== value.outboxEventId ||
    value.sub !== value.changePacket?.changeId ||
    !UUID.test(value.feedbackId ?? "") ||
    !UUID.test(value.decisionId ?? "") ||
    !UUID.test(value.outboxEventId ?? "") ||
    !ACTOR.test(value.approvedBy ?? "") ||
    typeof value.approvalRationale !== "string" ||
    value.approvalRationale.trim().length < 3 ||
    value.approvalRationale.length > 4_000 ||
    !Number.isFinite(approvedAt) ||
    !Number.isInteger(value.iat) ||
    value.iat !== approvedSecond ||
    value.iat * 1_000 > now + 5 * 60 * 1_000 ||
    typeof value.changePacket !== "object" ||
    value.changePacket === null
  ) {
    throw new Error("Change Packet approval envelope is invalid");
  }
  validateChangePacket(value.changePacket, expectedRepository);
  const markers = [
    ...issueBody.matchAll(/<!-- breazin-outbox:([0-9a-f-]+) -->/gi),
  ];
  if (
    markers.length !== 1 ||
    markers[0]?.[1] !== value.outboxEventId
  ) {
    throw new Error("Change Packet approval envelope is invalid");
  }
}

function validateChangePacket(packet, expectedRepository) {
  if (
    !CHANGE_ID.test(packet.changeId ?? "") ||
    packet.repository !== expectedRepository ||
    !["low", "medium", "high", "critical"].includes(packet.risk) ||
    typeof packet.objective !== "string" ||
    packet.objective.trim().length === 0 ||
    packet.objective.length > 4_000 ||
    !nonEmptyStringArray(packet.expectedOutputs) ||
    !nonEmptyStringArray(packet.acceptanceCriteria) ||
    !nonEmptyStringArray(packet.allowedPaths) ||
    !stringArray(packet.frozenPaths) ||
    typeof packet.baselineEvidence !== "object" ||
    packet.baselineEvidence === null ||
    !["captured", "evidence_gap"].includes(packet.baselineEvidence.status) ||
    !stringArray(packet.baselineEvidence.evidenceIds)
  ) {
    throw new Error("Change Packet body is invalid");
  }
  if (
    packet.baselineEvidence.status === "captured" &&
    packet.baselineEvidence.evidenceIds.length === 0
  ) {
    throw new Error("captured baseline requires evidence IDs");
  }
  for (const path of [...packet.allowedPaths, ...packet.frozenPaths]) {
    if (!safeRepositoryPath(path)) {
      throw new Error(`unsafe repository path in Change Packet: ${path}`);
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
      throw new Error(`Change Packet cannot authorize protected path: ${allowedPath}`);
    }
  }
}

function parseJsonSegment(value, name) {
  let parsed;
  try {
    parsed = JSON.parse(decodeBase64Url(value).toString("utf8"));
  } catch {
    throw new Error(`${name} is invalid JSON`);
  }
  if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
    throw new Error(`${name} must be an object`);
  }
  return parsed;
}

function decodeBase64Url(value) {
  if (typeof value !== "string" || !/^[A-Za-z0-9_-]+$/.test(value)) {
    throw new Error("JWS contains invalid base64url");
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
    !value.split("/").some((part) => part === "" || part === "." || part === "..")
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
    value.every(
      (item) =>
        typeof item === "string" &&
        item.trim().length > 0 &&
        item.length <= 1_000,
    )
  );
}

function nonEmptyStringArray(value) {
  return stringArray(value) && value.length > 0;
}
