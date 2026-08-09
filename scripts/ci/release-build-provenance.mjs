#!/usr/bin/env node

import { createHash } from "node:crypto";
import { readFile, stat, writeFile } from "node:fs/promises";
import { basename } from "node:path";
import { pathToFileURL } from "node:url";

const CHANNELS = {
  beta: {
    environment: "staging",
    bundleId: "com.writish.breazin.beta",
    feed: "beta",
    approvalEnvironment: "beta-release",
  },
  "stable-candidate": {
    environment: "production",
    bundleId: "com.writish.breazin",
    feed: "stable",
    approvalEnvironment: "stable-release",
  },
};

export async function createReleaseBuildProvenance({
  facts,
  artifactPath,
  lockPath,
}) {
  const channel = CHANNELS[facts?.channel];
  if (
    !channel ||
    facts.identity?.environment !== channel.environment ||
    facts.identity?.bundleId !== channel.bundleId ||
    facts.sparkle?.feed !== channel.feed
  ) {
    throw new Error("release channel identity is invalid");
  }
  requireString(facts.candidateId, "candidate ID");
  if (!/^CHG-\d{4}$/.test(facts.changeId)) {
    throw new Error("Change Packet ID is invalid");
  }
  if (!/^\d+(?:\.\d+){1,2}$/.test(facts.version)) {
    throw new Error("marketing version is invalid");
  }
  if (!/^\d+(?:\.\d+){0,2}$/.test(facts.buildVersion)) {
    throw new Error("build version is invalid");
  }
  if (facts.repository !== "Writish/breazin") {
    throw new Error("release repository is not allowed");
  }
  requireHex(facts.commit, 40, "source commit");
  if (
    !facts.identity.authority?.startsWith("Developer ID Application:") ||
    facts.identity.teamId === "not set" ||
    facts.identity.hardenedRuntime !== true
  ) {
    throw new Error(
      "release build requires Developer ID Application and Hardened Runtime",
    );
  }
  requireString(facts.identity.teamId, "signing team ID");
  if (!facts.identity.authority.endsWith(`(${facts.identity.teamId})`)) {
    throw new Error("certificate authority does not match signing team ID");
  }
  const notary = facts.notarization;
  if (
    notary?.appStatus !== "Accepted" ||
    notary?.dmgStatus !== "Accepted" ||
    notary?.appStapled !== true ||
    notary?.dmgStapled !== true ||
    notary?.gatekeeper !== "accepted"
  ) {
    throw new Error(
      "release build must be notarized, stapled, and accepted by Gatekeeper",
    );
  }
  requireString(notary.appSubmissionId, "app notarization submission ID");
  requireString(notary.dmgSubmissionId, "DMG notarization submission ID");
  requireString(facts.sparkle.signature, "Sparkle signature");

  const [artifactBytes, artifactStat, lockBytes] = await Promise.all([
    readFile(artifactPath),
    stat(artifactPath),
    readFile(lockPath),
  ]);
  return {
    schemaVersion: 1,
    stage: "signed_build",
    candidateId: facts.candidateId,
    channel: facts.channel,
    changeId: facts.changeId,
    version: facts.version,
    buildVersion: facts.buildVersion,
    source: {
      repository: facts.repository,
      commit: facts.commit,
      lockSha256: sha256(lockBytes),
    },
    artifact: {
      filename: basename(artifactPath),
      sha256: sha256(artifactBytes),
      size: artifactStat.size,
    },
    identity: facts.identity,
    notarization: {
      status: "accepted",
      appSubmissionId: notary.appSubmissionId,
      dmgSubmissionId: notary.dmgSubmissionId,
      appStapled: true,
      dmgStapled: true,
      gatekeeper: "accepted",
    },
    sparkle: facts.sparkle,
    evaluation: null,
    publicationAuthorized: false,
    humanApprovalStillRequired: true,
    approval: {
      requiredEnvironment: channel.approvalEnvironment,
    },
  };
}

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function requireString(value, label) {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new Error(`${label} is missing`);
  }
}

function requireHex(value, length, label) {
  if (
    typeof value !== "string" ||
    !new RegExp(`^[a-f0-9]{${length}}$`).test(value)
  ) {
    throw new Error(`${label} is invalid`);
  }
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [factsPath, artifactPath, lockPath, outputPath] =
    process.argv.slice(2);
  if (!factsPath || !artifactPath || !lockPath || !outputPath) {
    throw new Error(
      "usage: release-build-provenance.mjs <facts.json> <Breazin.dmg> <Package.resolved> <output.json>",
    );
  }
  const provenance = await createReleaseBuildProvenance({
    facts: JSON.parse(await readFile(factsPath, "utf8")),
    artifactPath,
    lockPath,
  });
  await writeFile(outputPath, `${JSON.stringify(provenance, null, 2)}\n`, {
    flag: "wx",
  });
  console.log(
    JSON.stringify({
      candidateId: provenance.candidateId,
      artifactSha256: provenance.artifact.sha256,
      publicationAuthorized: provenance.publicationAuthorized,
    }),
  );
}
