"use strict";

const fs = require("node:fs");
const crypto = require("node:crypto");
const path = require("node:path");
const { createTicket } = require("../cloud/aliyun-upload-api/src/auth");

function argument(name, fallback = "") {
  const index = process.argv.indexOf(`--${name}`);
  return index >= 0 ? process.argv[index + 1] || fallback : fallback;
}

function csv(value) {
  return `"${String(value).replaceAll('"', '""')}"`;
}

const baseUrl = argument("base-url");
const classId = argument("class");
const explicitStudents = argument("students").split(",").map((item) => item.trim().toUpperCase()).filter(Boolean);
const count = Number(argument("count", "0"));
const start = Number(argument("start", "1"));
const prefix = argument("prefix", "P").trim().toUpperCase();
const output = argument("output");
const hours = Number(argument("hours", "12"));
const studyVersion = argument("study-version", "digcomp-v1").trim();
const seed = argument("seed", classId).trim();
const secret = process.env.UPLOAD_LINK_SECRET || "";

if (explicitStudents.length > 0 && count > 0) {
  console.error("Choose either --students or --count, not both");
  process.exit(1);
}

let students = explicitStudents;
if (count > 0) {
  if (!Number.isInteger(count) || count > 1000 || !Number.isInteger(start) || start < 0 || !/^[A-Z0-9_-]{1,40}$/.test(prefix)) {
    console.error("--count must be 1-1000, --start must be a non-negative integer, and --prefix must use A-Z, 0-9, _ or -");
    process.exit(1);
  }
  const width = Math.max(3, String(start + count - 1).length);
  students = Array.from({ length: count }, (_, index) => `${prefix}${String(start + index).padStart(width, "0")}`);
}

if (new Set(students).size !== students.length) {
  console.error("Participant codes must be unique");
  process.exit(1);
}

if (!baseUrl || !classId || students.length === 0 || !secret || !studyVersion || !seed || !Number.isFinite(hours) || hours <= 0) {
  console.error("Usage: set UPLOAD_LINK_SECRET, then pass --base-url, --class, either --students S001,S002 or --count 30 [--prefix P], and optional --start/--hours/--study-version/--seed/--output");
  process.exit(1);
}

const expiresAt = Math.floor(Date.now() / 1000 + hours * 3600);
const rankedStudents = [...students].sort((left, right) => {
  const leftRank = crypto.createHmac("sha256", seed).update(left).digest("hex");
  const rightRank = crypto.createHmac("sha256", seed).update(right).digest("hex");
  return leftRank.localeCompare(rightRank) || left.localeCompare(right);
});
const conditionByStudent = new Map(rankedStudents.map((studentCode, index) => [studentCode, index % 2 === 0 ? "active" : "passive"]));
const rows = [["student_code", "condition", "game_url", "upload_id", "expires_at", "study_version"]];
for (const studentCode of students) {
  const uploadId = crypto.randomUUID().replaceAll("-", "");
  const condition = conditionByStudent.get(studentCode);
  const ticket = createTicket({
    study_version: studyVersion,
    condition,
    class_id: classId,
    student_code: studentCode,
    upload_id: uploadId,
    exp: expiresAt,
  }, secret);
  const url = new URL(baseUrl);
  url.searchParams.set("ticket", ticket);
  rows.push([studentCode, condition, url.toString(), uploadId, new Date(expiresAt * 1000).toISOString(), studyVersion]);
}
const content = `${rows.map((row) => row.map(csv).join(",")).join("\n")}\n`;
if (output) {
  fs.mkdirSync(path.dirname(path.resolve(output)), { recursive: true });
  fs.writeFileSync(output, content, "utf8");
  console.log(`Generated ${students.length} links: ${path.resolve(output)}`);
} else {
  process.stdout.write(content);
}
