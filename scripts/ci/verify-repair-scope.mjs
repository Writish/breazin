#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import { validateRepairScope } from "./approved-repair-contract.mjs";

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
try {
  validateRepairScope({ changedPaths, packet });
} catch (error) {
  fail(error instanceof Error ? error.message : "repair scope verification failed");
}
console.log(
  `Repair scope verified for ${changedPaths.length} changed file(s): ${changedPaths.join(", ")}`,
);

function fail(message) {
  console.error(message);
  process.exit(1);
}
