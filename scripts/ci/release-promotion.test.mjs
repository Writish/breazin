import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdtemp, readFile, stat, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import {
  preparePromotion,
  renderAppcast,
} from "./release-promotion.mjs";

function candidate(channel = "beta") {
  const stable = channel === "stable-candidate";
  return {
    schemaVersion: 1,
    stage: "final_candidate",
    candidateId: `${channel}-1.0.0-1-1`,
    channel,
    changeId: "CHG-0004",
    version: "1.0.0",
    buildVersion: "42",
    source: {
      repository: "Writish/breazin",
      commit: "a".repeat(40),
      lockSha256: "b".repeat(64),
    },
    artifact: {
      filename: "Breazin.dmg",
      sha256: "",
      size: 0,
    },
    identity: {
      environment: stable ? "production" : "staging",
      bundleId: stable
        ? "com.writish.breazin"
        : "com.writish.breazin.beta",
      teamId: "ABCDE12345",
      authority: "Developer ID Application: Example (ABCDE12345)",
      hardenedRuntime: true,
    },
    notarization: {
      status: "accepted",
      appSubmissionId: "app-notary-id",
      dmgSubmissionId: "dmg-notary-id",
      appStapled: true,
      dmgStapled: true,
      gatekeeper: "accepted",
    },
    sparkle: {
      signature:
        "VGVzdFNwYXJrbGVTaWduYXR1cmVXaXRoRW5vdWdoTGVuZ3RoMTIzNDU2Nzg5MA==",
      feed: stable ? "stable" : "beta",
    },
    evaluation: {
      qualityReportEvidenceId: "ev_quality_123",
      qualityReportEvidenceSha256: "c".repeat(64),
      qualityReportSha256: "",
      releaseBuildEvidenceId: "ev_release_build_123",
      evaluationEvidenceIds: ["ev_evaluation_manifest_123"],
      artifactSha256: "",
      releaseEligible: true,
      policyStatus: "accepted",
      policyVersion: "quality-policy-v1",
      policyReviewEvidenceId: "ev_policy_review_123",
      calibrationStatus: "accepted",
      calibrationSourceVersion: "calibration-set-v2",
      calibrationAcceptedVersion: "calibration-set-v3",
      calibrationReviewEvidenceId: "ev_calibration_review_123",
      humanApprovalStillRequired: true,
    },
    publicationAuthorized: false,
    humanApprovalStillRequired: true,
    approval: {
      requiredEnvironment: stable ? "stable-release" : "beta-release",
    },
  };
}

async function fixture(channel = "beta") {
  const directory = await mkdtemp(join(tmpdir(), "breazin-promotion-"));
  const artifactPath = join(directory, "Breazin.dmg");
  const qualityReportPath = join(directory, "quality-report.json");
  const candidateManifestPath = join(directory, "candidate.json");
  await writeFile(artifactPath, "signed-notarized-release-bytes");
  await writeFile(qualityReportPath, '{"releaseRecommendation":{"eligible":true}}');
  const value = candidate(channel);
  value.artifact.sha256 = await sha256(artifactPath);
  value.artifact.size = (await stat(artifactPath)).size;
  value.evaluation.artifactSha256 = value.artifact.sha256;
  value.evaluation.qualityReportSha256 = await sha256(qualityReportPath);
  await writeFile(candidateManifestPath, JSON.stringify(value));
  return {
    artifactPath,
    candidate: value,
    candidateManifestPath,
    qualityReportPath,
  };
}

test("prepares an exact-hash Beta promotion without publishing", async () => {
  const value = await fixture();
  const promotion = await preparePromotion({
    candidate: value.candidate,
    candidateManifestPath: value.candidateManifestPath,
    qualityReportPath: value.qualityReportPath,
    artifactPath: value.artifactPath,
    target: "beta",
    approvalEnvironment: "beta-release",
    immutableUrl:
      "https://github.com/Writish/breazin/releases/download/v1.0.0-beta.42/Breazin.dmg",
    approvedBy: "github:Writish",
    approvedAt: "2026-07-30T11:00:00.000Z",
  });

  assert.equal(promotion.artifactSha256, value.candidate.artifact.sha256);
  assert.equal(promotion.publicationAuthorized, false);
  assert.equal(promotion.humanApprovalReceiptRequired, true);
});

test("renders a monotonic appcast item for the matching channel", async () => {
  const value = await fixture();
  const current = `<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Breazin beta updates</title>
    <item><sparkle:version>41</sparkle:version></item>
  </channel>
</rss>
`;
  const rendered = renderAppcast({
    currentXml: current,
    candidate: value.candidate,
    target: "beta",
    immutableUrl:
      "https://github.com/Writish/breazin/releases/download/v1.0.0-beta.42/Breazin.dmg",
    publishedAt: "2026-07-30T11:00:00.000Z",
  });

  assert.match(rendered, /<sparkle:version>42<\/sparkle:version>/);
  assert.match(rendered, /sparkle:edSignature="VGVzdF/);
  assert.match(rendered, /releases\/download\/v1\.0\.0-beta\.42\/Breazin\.dmg/);
});

test("rejects cross-channel, non-monotonic, and self-authorized publication", async () => {
  const value = await fixture();
  const current =
    "<rss><channel><title>Breazin beta updates</title><sparkle:version>42</sparkle:version></channel></rss>";
  assert.throws(
    () =>
      renderAppcast({
        currentXml: current,
        candidate: value.candidate,
        target: "stable",
        immutableUrl:
          "https://github.com/Writish/breazin/releases/download/v1.0.0/Breazin.dmg",
        publishedAt: "2026-07-30T11:00:00.000Z",
      }),
    /channel/,
  );
  assert.throws(
    () =>
      renderAppcast({
        currentXml: current,
        candidate: value.candidate,
        target: "beta",
        immutableUrl:
          "https://github.com/Writish/breazin/releases/download/v1.0.0-beta.42/Breazin.dmg",
        publishedAt: "2026-07-30T11:00:00.000Z",
      }),
    /greater than/,
  );
  value.candidate.identity.authority = "adhoc";
  assert.throws(
    () =>
      renderAppcast({
        currentXml:
          "<rss><channel><title>Breazin beta updates</title></channel></rss>",
        candidate: value.candidate,
        target: "beta",
        immutableUrl:
          "https://github.com/Writish/breazin/releases/download/v1.0.0-beta.42/Breazin.dmg",
        publishedAt: "2026-07-30T11:00:00.000Z",
      }),
    /signing identity/,
  );
  value.candidate.identity.authority =
    "Developer ID Application: Example (ABCDE12345)";
  value.candidate.publicationAuthorized = true;
  assert.throws(
    () =>
      renderAppcast({
        currentXml: "<rss><channel></channel></rss>",
        candidate: value.candidate,
        target: "beta",
        immutableUrl:
          "https://github.com/Writish/breazin/releases/download/v1.0.0-beta.42/Breazin.dmg",
        publishedAt: "2026-07-30T11:00:00.000Z",
      }),
    /cannot grant/,
  );
});

async function sha256(path) {
  return createHash("sha256").update(await readFile(path)).digest("hex");
}
