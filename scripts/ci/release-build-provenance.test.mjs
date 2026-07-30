import assert from "node:assert/strict";
import { mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import { createReleaseBuildProvenance } from "./release-build-provenance.mjs";

async function fixture() {
  const directory = await mkdtemp(join(tmpdir(), "breazin-release-build-"));
  const artifactPath = join(directory, "Breazin.dmg");
  const lockPath = join(directory, "Package.resolved");
  await writeFile(artifactPath, "signed-notarized-dmg");
  await writeFile(lockPath, '{"pins":[]}');
  return { artifactPath, lockPath };
}

test("records a signed notarized Beta build without granting publication", async () => {
  const paths = await fixture();
  const result = await createReleaseBuildProvenance({
    artifactPath: paths.artifactPath,
    lockPath: paths.lockPath,
    facts: {
      candidateId: "BETA-1.0.0-1",
      channel: "beta",
      changeId: "CHG-0003",
      version: "1.0.0",
      buildVersion: "42",
      repository: "Writish/breazin",
      commit: "a".repeat(40),
      identity: {
        environment: "staging",
        bundleId: "com.writish.breazin.beta",
        teamId: "ABCDE12345",
        authority: "Developer ID Application: Example Company (ABCDE12345)",
        hardenedRuntime: true,
      },
      notarization: {
        appSubmissionId: "app-submission-id",
        appStatus: "Accepted",
        dmgSubmissionId: "dmg-submission-id",
        dmgStatus: "Accepted",
        appStapled: true,
        dmgStapled: true,
        gatekeeper: "accepted",
      },
      sparkle: {
        signature: "sparkle-ed25519-signature",
        feed: "beta",
      },
    },
  });

  assert.equal(result.stage, "signed_build");
  assert.equal(result.changeId, "CHG-0003");
  assert.equal(result.version, "1.0.0");
  assert.equal(result.buildVersion, "42");
  assert.equal(result.artifact.filename, "Breazin.dmg");
  assert.match(result.artifact.sha256, /^[a-f0-9]{64}$/);
  assert.equal(result.evaluation, null);
  assert.equal(result.publicationAuthorized, false);
  assert.equal(result.humanApprovalStillRequired, true);
});

test("rejects ad-hoc identity and a channel/Bundle ID mismatch", async () => {
  const paths = await fixture();
  await assert.rejects(
    createReleaseBuildProvenance({
      artifactPath: paths.artifactPath,
      lockPath: paths.lockPath,
      facts: {
        candidateId: "BETA-1.0.0-1",
        channel: "beta",
        changeId: "CHG-0003",
        version: "1.0.0",
        buildVersion: "42",
        repository: "Writish/breazin",
        commit: "a".repeat(40),
        identity: {
          environment: "production",
          bundleId: "com.writish.breazin",
          teamId: "not set",
          authority: "adhoc",
          hardenedRuntime: false,
        },
        notarization: {
          appSubmissionId: "",
          appStatus: "Invalid",
          dmgSubmissionId: "",
          dmgStatus: "Invalid",
          appStapled: false,
          dmgStapled: false,
          gatekeeper: "rejected",
        },
        sparkle: { signature: "", feed: "stable" },
      },
    }),
    /release channel identity/,
  );
});

test("rejects an unbound version, Change Packet, or certificate authority", async () => {
  const paths = await fixture();
  const validFacts = {
    candidateId: "BETA-1.0.0-1",
    channel: "beta",
    changeId: "CHG-0003",
    version: "1.0.0",
    buildVersion: "42",
    repository: "Writish/breazin",
    commit: "a".repeat(40),
    identity: {
      environment: "staging",
      bundleId: "com.writish.breazin.beta",
      teamId: "ABCDE12345",
      authority: "Developer ID Application: Example Company (ABCDE12345)",
      hardenedRuntime: true,
    },
    notarization: {
      appSubmissionId: "app-submission-id",
      appStatus: "Accepted",
      dmgSubmissionId: "dmg-submission-id",
      dmgStatus: "Accepted",
      appStapled: true,
      dmgStapled: true,
      gatekeeper: "accepted",
    },
    sparkle: {
      signature: "sparkle-ed25519-signature",
      feed: "beta",
    },
  };

  for (const [mutation, expectedError] of [
    [{ version: "not-semver" }, /marketing version/],
    [{ changeId: "issue-3" }, /Change Packet ID/],
    [
      {
        identity: {
          ...validFacts.identity,
          authority: "Apple Development: Example Company (ABCDE12345)",
        },
      },
      /Developer ID Application/,
    ],
  ]) {
    await assert.rejects(
      createReleaseBuildProvenance({
        artifactPath: paths.artifactPath,
        lockPath: paths.lockPath,
        facts: { ...validFacts, ...mutation },
      }),
      expectedError,
    );
  }
});
