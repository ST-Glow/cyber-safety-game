"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const os = require("node:os");
const path = require("node:path");
const { createTicket } = require("../src/auth");
const { createApp } = require("../src/create-app");
const { createCloudAdapter } = require("../src/cloud");

test("mock API accepts three files and writes a manifest", async (context) => {
  const mockRoot = await fs.mkdtemp(path.join(os.tmpdir(), "cyber-upload-"));
  context.after(() => fs.rm(mockRoot, { recursive: true, force: true }));
  const config = {
    linkSecret: "test-secret-at-least-16-characters",
    allowedOrigins: ["http://127.0.0.1:4173"],
    mockRoot,
    publicBaseUrl: "",
    ossRegion: "",
    ossBucket: "",
    ossRoleArn: "",
    ossInternal: false,
  };
  const server = createApp({ config, cloud: createCloudAdapter(config) }).listen(0, "127.0.0.1");
  await new Promise((resolve) => server.once("listening", resolve));
  context.after(() => server.close());
  const base = `http://127.0.0.1:${server.address().port}`;
  config.publicBaseUrl = base;
  const ticket = createTicket({
    class_id: "CLASS-5A",
    student_code: "S001",
    upload_id: "upload_001",
    exp: Math.floor(Date.now() / 1000) + 3600,
  }, config.linkSecret);

  const blockedOrigin = await fetch(`${base}/api/upload/credentials`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Origin: "https://untrusted.example" },
    body: JSON.stringify({ ticket, recording_extension: "webm", recording_available: true }),
  });
  assert.equal(blockedOrigin.status, 403);

  const credentialsResponse = await fetch(`${base}/api/upload/credentials`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Origin: "http://127.0.0.1:4173" },
    body: JSON.stringify({ ticket, recording_extension: "webm", recording_available: true }),
  });
  assert.equal(credentialsResponse.status, 200);
  const credentials = await credentialsResponse.json();
  assert.equal(credentials.mode, "mock");

  for (const [key, content, type] of [
    ["events", "{\"event_type\":\"session_completed\"}\n", "application/x-ndjson"],
    ["summary", "{\"session_id\":\"abc\"}", "application/json"],
    ["recording", "fake-webm-bytes", "video/webm"],
  ]) {
    const upload = await fetch(credentials.upload_urls[key], {
      method: "PUT",
      headers: { Authorization: `Bearer ${ticket}`, "Content-Type": type, Origin: "http://127.0.0.1:4173" },
      body: content,
    });
    assert.equal(upload.status, 201);
  }

  const completeResponse = await fetch(`${base}/api/upload/complete`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Origin: "http://127.0.0.1:4173" },
    body: JSON.stringify({ ticket, recording_extension: "webm", recording_available: true }),
  });
  assert.equal(completeResponse.status, 200);
  const completed = await completeResponse.json();
  assert.equal(completed.status, "complete");
  const manifest = JSON.parse(await fs.readFile(path.join(mockRoot, "sessions", "CLASS-5A", "S001", "upload_001", "manifest.json"), "utf8"));
  assert.equal(manifest.status, "complete");
});
