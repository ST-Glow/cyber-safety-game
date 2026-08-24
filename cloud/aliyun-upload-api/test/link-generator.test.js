"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const childProcess = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { verifyTicket } = require("../src/auth");

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
    "--seed", "fixed-study-seed",
    "--output", output,
  ], {
    encoding: "utf8",
    env: { ...process.env, UPLOAD_LINK_SECRET: "batch-test-secret-that-is-at-least-32-characters" },
  });

  assert.equal(result.status, 0, result.stderr);
  const lines = fs.readFileSync(output, "utf8").trim().split("\n");
  assert.equal(lines.length, 4);
  assert.match(lines[1], /^"USER001","(active|passive)",/);
  assert.match(lines[2], /^"USER002","(active|passive)",/);
  assert.match(lines[3], /^"USER003","(active|passive)",/);

  const fields = lines.slice(1).map((line) => line.slice(1, -1).split('","'));
  const uploadIds = fields.map((row) => row[3]);
  assert.equal(new Set(uploadIds).size, 3);
  const activeCount = fields.filter((row) => row[1] === "active").length;
  const passiveCount = fields.filter((row) => row[1] === "passive").length;
  assert.equal(Math.abs(activeCount - passiveCount), 1);
  assert.ok(fields.every((row) => row[5] === "godot-v1"));
  for (const row of fields) {
    const generatedUrl = new URL(row[2]);
    assert.equal(generatedUrl.searchParams.has("student"), false);
    const claims = verifyTicket(
      generatedUrl.searchParams.get("ticket"),
      "batch-test-secret-that-is-at-least-32-characters"
    );
    assert.equal(claims.student_code, row[0]);
    assert.equal(claims.condition, row[1]);
    assert.equal(claims.study_version, row[5]);
  }
});
