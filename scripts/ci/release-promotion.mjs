#!/usr/bin/env node

import { createHash } from "node:crypto";
import { readFile, stat, writeFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";

const TARGETS = {
  beta: {
    channel: "beta",
    environment: "staging",
    bundleId: "com.writish.breazin.beta",
    feed: "beta",
    approvalEnvironment: "beta-release",
    title: "Breazin beta updates",
  },
  stable: {
    channel: "stable-candidate",
    environment: "production",
    bundleId: "com.writish.breazin",
    feed: "stable",
    approvalEnvironment: "stable-release",
    title: "Breazin stable updates",
  },
};

export async function preparePromotion({
  candidate,
  candidateManifestPath,
  qualityReportPath,
  artifactPath,
  target,
  approvalEnvironment,
  immutableUrl,
  approvedBy,
  approvedAt,
}) {
  const targetContract = validateCandidate(candidate, target);
  const [manifestBytes, qualityReportBytes, artifactBytes, artifactStat] =
    await Promise.all([
      readFile(candidateManifestPath),
      readFile(qualityReportPath),
      readFile(artifactPath),
      stat(artifactPath),
    ]);
  const frozenCandidate = JSON.parse(manifestBytes.toString("utf8"));
  if (JSON.stringify(candidate) !== JSON.stringify(frozenCandidate)) {
    throw new Error("candidate differs from its frozen manifest");
  }
  const artifactSha256 = sha256(artifactBytes);
  if (
    artifactSha256 !== candidate.artifact.sha256 ||
    artifactStat.size !== candidate.artifact.size ||
    candidate.evaluation.artifactSha256 !== artifactSha256
  ) {
    throw new Error("candidate artifact bytes changed before promotion");
  }
  const qualityReportSha256 = sha256(qualityReportBytes);
  if (qualityReportSha256 !== candidate.evaluation.qualityReportSha256) {
    throw new Error("quality report bytes changed before promotion");
  }
  if (approvalEnvironment !== targetContract.approvalEnvironment) {
    throw new Error("promotion approval environment does not match target");
  }
  const url = validateImmutableUrl(immutableUrl);
  requireString(approvedBy, "identified promotion approver");
  if (!Number.isFinite(Date.parse(approvedAt))) {
    throw new Error("promotion approval time is invalid");
  }
  return {
    schemaVersion: 1,
    target,
    candidateManifestSha256: sha256(manifestBytes),
    qualityReportEvidenceSha256:
      candidate.evaluation.qualityReportEvidenceSha256,
    qualityReportSha256,
    artifactSha256,
    approvalEnvironment,
    immutableUrl: url.toString(),
    approvedBy,
    approvedAt: new Date(approvedAt).toISOString(),
    publicationAuthorized: false,
    humanApprovalReceiptRequired: true,
  };
}

export function renderAppcast({
  currentXml,
  candidate,
  target,
  immutableUrl,
  publishedAt,
}) {
  const targetContract = validateCandidate(candidate, target);
  if (
    typeof currentXml !== "string" ||
    !currentXml.includes("</channel>") ||
    !currentXml.includes(targetContract.title)
  ) {
    throw new Error("appcast does not match the promotion channel");
  }
  const url = validateImmutableUrl(immutableUrl);
  const buildVersion = Number(candidate.buildVersion);
  if (
    !/^\d+$/.test(candidate.buildVersion) ||
    !Number.isSafeInteger(buildVersion) ||
    buildVersion < 1
  ) {
    throw new Error("Sparkle build version must be a positive integer");
  }
  const existingBuilds = [
    ...currentXml.matchAll(
      /<sparkle:version>([0-9]+)<\/sparkle:version>/g,
    ),
  ].map((match) => Number(match[1]));
  const maximumBuild =
    existingBuilds.length === 0 ? 0 : Math.max(...existingBuilds);
  if (buildVersion <= maximumBuild) {
    throw new Error(
      `Sparkle build version must be greater than ${maximumBuild}`,
    );
  }
  const published = new Date(publishedAt);
  if (!Number.isFinite(published.getTime())) {
    throw new Error("appcast publication time is invalid");
  }
  const item = `    <item>
      <title>Version ${escapeXml(candidate.version)}</title>
      <pubDate>${published.toUTCString()}</pubDate>
      <sparkle:version>${candidate.buildVersion}</sparkle:version>
      <sparkle:shortVersionString>${escapeXml(candidate.version)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <enclosure
        url="${escapeXml(url.toString())}"
        length="${candidate.artifact.size}"
        type="application/octet-stream"
        sparkle:edSignature="${escapeXml(candidate.sparkle.signature)}"/>
    </item>`;
  return currentXml.replace("  </channel>", `${item}\n  </channel>`);
}

function validateCandidate(candidate, target) {
  const targetContract = TARGETS[target];
  if (!targetContract) throw new Error("promotion target is invalid");
  if (
    candidate?.schemaVersion !== 1 ||
    candidate.stage !== "final_candidate" ||
    candidate.channel !== targetContract.channel ||
    candidate.identity?.environment !== targetContract.environment ||
    candidate.identity?.bundleId !== targetContract.bundleId ||
    candidate.sparkle?.feed !== targetContract.feed
  ) {
    throw new Error("final candidate channel identity is invalid");
  }
  if (
    candidate.publicationAuthorized !== false ||
    candidate.humanApprovalStillRequired !== true
  ) {
    throw new Error("final candidate cannot grant its own publication");
  }
  if (
    !candidate.identity.authority?.startsWith(
      "Developer ID Application:",
    ) ||
    typeof candidate.identity.teamId !== "string" ||
    candidate.identity.teamId.length === 0 ||
    !candidate.identity.authority.endsWith(
      `(${candidate.identity.teamId})`,
    ) ||
    candidate.identity.hardenedRuntime !== true
  ) {
    throw new Error("final candidate signing identity is invalid");
  }
  if (
    candidate.notarization?.status !== "accepted" ||
    candidate.notarization.appStapled !== true ||
    candidate.notarization.dmgStapled !== true ||
    candidate.notarization.gatekeeper !== "accepted" ||
    typeof candidate.notarization.appSubmissionId !== "string" ||
    candidate.notarization.appSubmissionId.length === 0 ||
    typeof candidate.notarization.dmgSubmissionId !== "string" ||
    candidate.notarization.dmgSubmissionId.length === 0
  ) {
    throw new Error("final candidate notarization evidence is invalid");
  }
  if (
    candidate.evaluation?.releaseEligible !== true ||
    candidate.evaluation.policyStatus !== "accepted" ||
    candidate.evaluation.calibrationStatus !== "accepted" ||
    candidate.evaluation.humanApprovalStillRequired !== true
  ) {
    throw new Error("final candidate lacks accepted quality evidence");
  }
  if (
    !Array.isArray(candidate.evaluation.evaluationEvidenceIds) ||
    candidate.evaluation.evaluationEvidenceIds.length === 0 ||
    candidate.evaluation.evaluationEvidenceIds.some(
      (evidenceId) =>
        typeof evidenceId !== "string" ||
        evidenceId.trim().length === 0,
    )
  ) {
    throw new Error("final candidate lacks evaluation-manifest evidence");
  }
  for (const [value, label] of [
    [candidate.artifact?.sha256, "artifact digest"],
    [
      candidate.evaluation.qualityReportEvidenceSha256,
      "quality report evidence digest",
    ],
    [
      candidate.evaluation.qualityReportSha256,
      "quality report digest",
    ],
  ]) {
    if (typeof value !== "string" || !/^[a-f0-9]{64}$/.test(value)) {
      throw new Error(`${label} is invalid`);
    }
  }
  if (
    !Number.isSafeInteger(candidate.artifact.size) ||
    candidate.artifact.size <= 0
  ) {
    throw new Error("artifact size is invalid");
  }
  if (
    typeof candidate.sparkle.signature !== "string" ||
    candidate.sparkle.signature.length < 40 ||
    !/^[A-Za-z0-9+/]+={0,2}$/.test(candidate.sparkle.signature)
  ) {
    throw new Error("Sparkle signature is invalid");
  }
  if (
    candidate.approval?.requiredEnvironment !==
    targetContract.approvalEnvironment
  ) {
    throw new Error("candidate approval environment is invalid");
  }
  return targetContract;
}

function validateImmutableUrl(value) {
  let url;
  try {
    url = new URL(value);
  } catch {
    throw new Error("immutable release URL is invalid");
  }
  if (
    url.protocol !== "https:" ||
    url.hostname !== "github.com" ||
    !url.pathname.startsWith(
      "/Writish/breazin/releases/download/",
    ) ||
    !url.pathname.endsWith("/Breazin.dmg") ||
    url.pathname.includes("/latest/") ||
    url.username ||
    url.password ||
    url.search ||
    url.hash
  ) {
    throw new Error("immutable release URL is invalid");
  }
  return url;
}

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function requireString(value, label) {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new Error(`${label} is missing`);
  }
}

function escapeXml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll('"', "&quot;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [mode, ...args] = process.argv.slice(2);
  if (mode === "prepare") {
    const [
      candidateManifestPath,
      qualityReportPath,
      artifactPath,
      target,
      approvalEnvironment,
      immutableUrl,
      approvedBy,
      approvedAt,
      outputPath,
    ] = args;
    const candidate = JSON.parse(
      await readFile(candidateManifestPath, "utf8"),
    );
    const promotion = await preparePromotion({
      candidate,
      candidateManifestPath,
      qualityReportPath,
      artifactPath,
      target,
      approvalEnvironment,
      immutableUrl,
      approvedBy,
      approvedAt,
    });
    await writeFile(outputPath, `${JSON.stringify(promotion, null, 2)}\n`, {
      flag: "wx",
    });
  } else if (mode === "appcast") {
    const [
      currentAppcastPath,
      candidateManifestPath,
      target,
      immutableUrl,
      publishedAt,
      outputPath,
    ] = args;
    const [currentXml, candidate] = await Promise.all([
      readFile(currentAppcastPath, "utf8"),
      readFile(candidateManifestPath, "utf8").then(JSON.parse),
    ]);
    await writeFile(
      outputPath,
      renderAppcast({
        currentXml,
        candidate,
        target,
        immutableUrl,
        publishedAt,
      }),
      { flag: "wx" },
    );
  } else {
    throw new Error(
      "usage: release-promotion.mjs prepare <candidate> <quality-report> <DMG> <target> <environment> <url> <approver> <time> <output> | appcast <current> <candidate> <target> <url> <time> <output>",
    );
  }
}
