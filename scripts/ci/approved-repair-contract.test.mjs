import assert from "node:assert/strict";
import {
  generateKeyPairSync,
  sign,
} from "node:crypto";
import test from "node:test";

import {
  validateRepairScope,
  verifyApprovedRepairIssue,
} from "./approved-repair-contract.mjs";

const { privateKey, publicKey } = generateKeyPairSync("ec", {
  namedCurve: "P-256",
});
const publicKeyPem = publicKey.export({ type: "spki", format: "pem" });
const repository = "Writish/breazin";
const now = Date.parse("2026-08-03T01:00:00.000Z");

test("accepts one exact signed low-risk approval and returns its immutable envelope", () => {
  const payload = approvalEnvelope();
  const compactJws = signEnvelope(payload);
  const issueBody = issueFor(compactJws, payload.outboxEventId);
  assert.deepEqual(
    verifyApprovedRepairIssue({
      issueBody,
      expectedRepository: repository,
      publicKey: publicKeyPem,
      acceptedKeyId: "development-2026-07",
      now,
    }),
    payload,
  );
});

test("rejects forged, duplicated, stale-identity, or protected-path authority", () => {
  const base = approvalEnvelope();
  const valid = signEnvelope(base);
  const forgedPayload = { ...base, approvedBy: "access:attacker@example.test" };
  const forged = `${valid.split(".")[0]}.${encode(forgedPayload)}.${valid.split(".")[2]}`;
  assert.throws(
    () => verify(forged, base.outboxEventId),
    /signature is invalid/,
  );
  assert.throws(
    () => verifyApprovedRepairIssue({
      issueBody: `${issueFor(valid, base.outboxEventId)}\n<!-- breazin-change-packet-jws: ${valid} -->`,
      expectedRepository: repository,
      publicKey: publicKeyPem,
      acceptedKeyId: "development-2026-07",
      now,
    }),
    /exactly one signed Change Packet/,
  );

  const wrongMarker = signEnvelope({ ...base, jti: "22222222-2222-4222-8222-222222222222" });
  assert.throws(
    () => verify(wrongMarker, base.outboxEventId),
    /approval envelope is invalid/,
  );

  const protectedAuthority = approvalEnvelope();
  protectedAuthority.changePacket.allowedPaths = [".github/workflows"];
  assert.throws(
    () => verify(signEnvelope(protectedAuthority), protectedAuthority.outboxEventId),
    /cannot authorize protected path/,
  );
});

test("requires identified approval provenance and a coherent issued-at time", () => {
  for (const mutate of [
    (value) => { value.approvedBy = ""; },
    (value) => { value.approvalRationale = ""; },
    (value) => { value.decisionId = "not-a-uuid"; },
    (value) => { value.approvedAt = "not-a-time"; },
    (value) => { value.iat += 60; },
  ]) {
    const payload = approvalEnvelope();
    mutate(payload);
    assert.throws(
      () => verify(signEnvelope(payload), payload.outboxEventId),
      /approval envelope is invalid/,
    );
  }
});

test("scope validation rejects frozen, hard-protected, outside, or empty patches", () => {
  const packet = approvalEnvelope().changePacket;
  assert.deepEqual(
    validateRepairScope({
      changedPaths: ["Sources/Breazin/Example.swift", "Tests/BreazinTests/ExampleTests.swift"],
      packet,
    }),
    ["Sources/Breazin/Example.swift", "Tests/BreazinTests/ExampleTests.swift"],
  );
  assert.throws(
    () => validateRepairScope({ changedPaths: [], packet }),
    /no file changes/,
  );
  assert.throws(
    () => validateRepairScope({ changedPaths: [".github/workflows/ci.yml"], packet }),
    /hard-protected path/,
  );
  assert.throws(
    () => validateRepairScope({ changedPaths: ["Tests/Fixtures/frozen.json"], packet }),
    /frozen path/,
  );
  assert.throws(
    () => validateRepairScope({ changedPaths: ["README.md"], packet }),
    /outside approved scope/,
  );
});

function verify(compactJws, marker) {
  return verifyApprovedRepairIssue({
    issueBody: issueFor(compactJws, marker),
    expectedRepository: repository,
    publicKey: publicKeyPem,
    acceptedKeyId: "development-2026-07",
    now,
  });
}

function approvalEnvelope() {
  return {
    version: 1,
    iss: "breazin-control-plane",
    aud: "breazin-approved-repair",
    sub: "CHG-9001",
    jti: "11111111-1111-4111-8111-111111111111",
    iat: Math.floor(Date.parse("2026-08-03T00:30:00.000Z") / 1_000),
    feedbackId: "44444444-4444-4444-8444-444444444444",
    decisionId: "33333333-3333-4333-8333-333333333333",
    outboxEventId: "11111111-1111-4111-8111-111111111111",
    approvedBy: "access:walle@example.test",
    approvalRationale: "Bounded repair is appropriate and independently reviewed.",
    approvedAt: "2026-08-03T00:30:00.000Z",
    changePacket: {
      changeId: "CHG-9001",
      repository,
      risk: "low",
      objective: "Correct the isolated fixture behavior.",
      expectedOutputs: ["A bounded source change"],
      acceptanceCriteria: ["Focused regression passes"],
      allowedPaths: ["Sources/Breazin", "Tests/BreazinTests"],
      frozenPaths: ["Tests/Fixtures"],
      baselineEvidence: {
        status: "captured",
        evidenceIds: ["ev_baseline_123"],
      },
    },
  };
}

function signEnvelope(payload) {
  const header = encode({
    alg: "ES256",
    typ: "breazin-change-packet+jwt",
    kid: "development-2026-07",
  });
  const body = encode(payload);
  const signature = sign(
    "sha256",
    Buffer.from(`${header}.${body}`),
    { key: privateKey, dsaEncoding: "ieee-p1363" },
  ).toString("base64url");
  return `${header}.${body}.${signature}`;
}

function issueFor(compactJws, marker) {
  return [
    `<!-- breazin-outbox:${marker} -->`,
    `<!-- breazin-change-packet-jws: ${compactJws} -->`,
  ].join("\n");
}

function encode(value) {
  return Buffer.from(JSON.stringify(value)).toString("base64url");
}
