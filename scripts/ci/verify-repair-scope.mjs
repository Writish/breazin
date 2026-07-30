#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { readFile } from "node:fs/promises";

const hardProtectedPaths = [
  ".github",
  "scripts/ci/verify-approved-repair.mjs",
  "scripts/ci/verify-repair-scope.mjs",
];

const packetPath =
  process.argv[2] ?? "/tmp/breazin-approved-change-packet.json";
const envelope = JSON.parse(await readFile(packetPath, "utf8"));
const packet = envelope.changePacket;
if (
  typeof packet !== "object" ||
  packet === null ||
  !Array.isArray(packet.allowedPaths) ||
  !Array.isArray(packet.frozenPaths)
) {
  fail("verified Change Packet is missing path authority");
}

execFileSync("git", ["add", "-N", "."], { stdio: "ignore" });
const output = execFileSync(
  "git",
  ["diff", "--name-only", "--no-renames", "-z", "HEAD"],
  { encoding: "utf8" },
);
const changedPaths = output.split("\0").filter(Boolean);
if (changedPaths.length === 0) {
  fail("repair produced no file changes");
}
for (const path of changedPaths) {
  if (hardProtectedPaths.some((prefix) => pathWithin(path, prefix))) {
    fail(`repair modified hard-protected path: ${path}`);
  }
  if (packet.frozenPaths.some((prefix) => pathWithin(path, prefix))) {
    fail(`repair modified frozen path: ${path}`);
  }
  if (!packet.allowedPaths.some((prefix) => pathWithin(path, prefix))) {
    fail(`repair modified path outside approved scope: ${path}`);
  }
}
console.log(
  `Repair scope verified for ${changedPaths.length} changed file(s): ${changedPaths.join(", ")}`,
);

function pathWithin(path, approved) {
  const normalized = approved.endsWith("/") ? approved : `${approved}/`;
  return path === approved || path.startsWith(normalized);
}

function fail(message) {
  console.error(message);
  process.exit(1);
}
