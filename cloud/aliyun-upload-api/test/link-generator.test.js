"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const childProcess = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

test("batch link generator creates one isolated ticket per participant", (context) => {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "cyber-links-"));
  context.after(() => fs.rmSync(tempRoot, { recursive: true, force: true }));
  const output = path.join(tempRoot, "links.csv");
  const script = path.resolve(__dirname, "../../../tools/generate-student-links.cjs");

  const result = childProcess.spawnSync(process.execPath, [
    script,
    "--base-url", "https://example.test/game/",
    "--class", "PILOT_A",
    "--count", "3",
    "--prefix", "USER",
    "--hours", "24",
    "--output", output,
  ], {
    encoding: "utf8",
    env: { ...process.env, UPLOAD_LINK_SECRET: "batch-test-secret-that-is-at-least-32-characters" },
  });

  assert.equal(result.status, 0, result.stderr);
  const lines = fs.readFileSync(output, "utf8").trim().split("\n");
  assert.equal(lines.length, 4);
  assert.match(lines[1], /^"USER001",/);
  assert.match(lines[2], /^"USER002",/);
  assert.match(lines[3], /^"USER003",/);

  const uploadIds = lines.slice(1).map((line) => line.split('","')[2]);
  assert.equal(new Set(uploadIds).size, 3);
});
