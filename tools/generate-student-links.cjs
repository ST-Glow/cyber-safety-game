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
const students = argument("students").split(",").map((item) => item.trim().toUpperCase()).filter(Boolean);
const output = argument("output");
const hours = Number(argument("hours", "12"));
const secret = process.env.UPLOAD_LINK_SECRET || "";

if (!baseUrl || !classId || students.length === 0 || !secret) {
  console.error("Usage: set UPLOAD_LINK_SECRET, then pass --base-url, --class, --students S001,S002 and optional --hours/--output");
  process.exit(1);
}

const expiresAt = Math.floor(Date.now() / 1000 + hours * 3600);
const rows = [["student_code", "game_url", "upload_id", "expires_at"]];
for (const studentCode of students) {
  const uploadId = crypto.randomUUID().replaceAll("-", "");
  const ticket = createTicket({ class_id: classId, student_code: studentCode, upload_id: uploadId, exp: expiresAt }, secret);
  const url = new URL(baseUrl);
  url.searchParams.set("student", studentCode);
  url.searchParams.set("ticket", ticket);
  rows.push([studentCode, url.toString(), uploadId, new Date(expiresAt * 1000).toISOString()]);
}
const content = `${rows.map((row) => row.map(csv).join(",")).join("\n")}\n`;
if (output) {
  fs.mkdirSync(path.dirname(path.resolve(output)), { recursive: true });
  fs.writeFileSync(output, content, "utf8");
  console.log(`Generated ${students.length} links: ${path.resolve(output)}`);
} else {
  process.stdout.write(content);
}
