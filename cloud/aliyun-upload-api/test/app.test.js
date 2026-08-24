"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const os = require("node:os");
const path = require("node:path");
const { createTicket } = require("../src/auth");
const { createApp } = require("../src/create-app");
const { createCloudAdapter, objectNames, rolePolicy } = require("../src/cloud");

const TEST_LEVEL_PROMPTS = Object.freeze({
  ai_training_ground: "第一关隐藏教学档案",
  spinner_race: "第二关隐藏教学档案",
  data_chip_hunt: "第三关隐藏教学档案",
  signal_bomb_survival: "第四关隐藏教学档案",
});
const STUDY_CLAIMS = Object.freeze({
  study_version: "godot-v1",
  condition: "active",
});

test("browser upload policy supports resumable multipart recording without manifest write access", () => {
  const objects = objectNames({
    ...STUDY_CLAIMS,
    class_id: "CLASS-A",
    student_code: "S001",
    upload_id: "upload_001",
  }, "webm", true);
  const policy = JSON.parse(rolePolicy("cyber-game", objects));
  const actions = policy.Statement[0].Action;
  assert.ok(actions.includes("oss:InitiateMultipartUpload"));
  assert.ok(actions.includes("oss:UploadPart"));
  assert.ok(actions.includes("oss:CompleteMultipartUpload"));
  assert.ok(actions.includes("oss:AbortMultipartUpload"));
  assert.ok(policy.Statement[0].Resource.every((value) => !value.endsWith("/manifest.json")));
});

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
    ...STUDY_CLAIMS,
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
  const manifest = JSON.parse(await fs.readFile(path.join(
    mockRoot, "studies", "godot-v1", "CLASS-5A", "active", "S001", "upload_001", "manifest.json"
  ), "utf8"));
  assert.equal(manifest.status, "complete");
  assert.equal(manifest.condition, "active");
});

test("Coze proxy authenticates the student and preserves a signed conversation", async (context) => {
  const mockRoot = await fs.mkdtemp(path.join(os.tmpdir(), "cyber-coze-"));
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
    cozeApiToken: "test-token",
    cozeBotId: "7649339604520697891",
    aiLevelPrompts: TEST_LEVEL_PROMPTS,
    aiPromptsConfigured: true,
    aiPromptConfigError: "",
  };
  const calls = [];
  let statusChecks = 0;
  const coze = {
    configured: true,
    async startChat(input) {
      calls.push({ operation: "start", ...input });
      return {
        chatId: `750000000000000000${calls.length + 1}`,
        conversationId: input.conversationId || "7500000000000000001",
        status: "created",
      };
    },
    async getChatResult(input) {
      calls.push({ operation: "status", ...input });
      statusChecks += 1;
      if (statusChecks === 1) return { status: "in_progress" };
      return { status: "completed", reply: "先观察巡逻路线。" };
    },
  };
  const server = createApp({ config, cloud: createCloudAdapter(config), coze }).listen(0, "127.0.0.1");
  await new Promise((resolve) => server.once("listening", resolve));
  context.after(() => server.close());
  const base = `http://127.0.0.1:${server.address().port}`;
  const ticket = createTicket({
    ...STUDY_CLAIMS,
    class_id: "CLASS-5A",
    student_code: "S001",
    upload_id: "upload_001",
    exp: Math.floor(Date.now() / 1000) + 3600,
  }, config.linkSecret);

  const firstResponse = await fetch(`${base}/api/coze/chat`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Origin: "http://127.0.0.1:4173" },
    body: JSON.stringify({
      ticket,
      level_id: "spinner_race",
      trigger: "repeated_failure",
      message: "我卡住了",
      state: { checkpoint: 2, obstacle_hits: 3, falls: 1, remaining_time: 42, answer: "secret" },
    }),
  });
  assert.equal(firstResponse.status, 200);
  const first = await firstResponse.json();
  assert.equal(first.status, "pending");
  assert.ok(first.poll);
  assert.match(calls[0].userId, /^web_[a-f0-9]{24}$/);
  assert.doesNotMatch(calls[0].userId, /upload_001/);
  assert.equal(calls[0].conversationId, "");
  assert.match(calls[0].message, /第二关隐藏教学档案/);
  assert.match(calls[0].message, /"checkpoint":2/);
  assert.doesNotMatch(calls[0].message, /answer/);

  const statusResponse = await fetch(`${base}/api/coze/chat/status`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Origin: "http://127.0.0.1:4173" },
    body: JSON.stringify({ ticket, level_id: "spinner_race", poll: first.poll }),
  });
  assert.equal(statusResponse.status, 200);
  const waiting = await statusResponse.json();
  assert.equal(waiting.status, "pending");
  assert.equal(waiting.poll, first.poll);

  const completedResponse = await fetch(`${base}/api/coze/chat/status`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Origin: "http://127.0.0.1:4173" },
    body: JSON.stringify({ ticket, level_id: "spinner_race", poll: first.poll }),
  });
  assert.equal(completedResponse.status, 200);
  const completed = await completedResponse.json();
  assert.equal(completed.status, "completed");
  assert.equal(completed.reply, "先观察巡逻路线。");
  assert.ok(completed.session);

  const secondResponse = await fetch(`${base}/api/coze/chat`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Origin: "http://127.0.0.1:4173" },
    body: JSON.stringify({
      ticket,
      level_id: "spinner_race",
      trigger: "manual",
      message: "然后呢",
      state: { checkpoint: 2, obstacle_hits: 3, falls: 1, remaining_time: 40 },
      session: completed.session,
    }),
  });
  assert.equal(secondResponse.status, 200);
  assert.equal(calls[3].conversationId, "7500000000000000001");

  const last = completed.session.slice(-1);
  const tamperedSession = `${completed.session.slice(0, -1)}${last === "a" ? "b" : "a"}`;
  const tamperedResponse = await fetch(`${base}/api/coze/chat`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Origin: "http://127.0.0.1:4173" },
    body: JSON.stringify({
      ticket,
      level_id: "spinner_race",
      trigger: "manual",
      message: "非法续接",
      state: {},
      session: tamperedSession,
    }),
  });
  assert.equal(tamperedResponse.status, 400);

  const crossLevelResponse = await fetch(`${base}/api/coze/chat`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Origin: "http://127.0.0.1:4173" },
    body: JSON.stringify({
      ticket,
      level_id: "data_chip_hunt",
      trigger: "manual",
      message: "继续提示",
      state: { chips: 3, falls: 1, remaining_time: 40 },
      session: completed.session,
    }),
  });
  assert.equal(crossLevelResponse.status, 400);
  assert.equal((await crossLevelResponse.json()).code, "agent_session_level_mismatch");

  const passiveTicket = createTicket({
    ...STUDY_CLAIMS,
    condition: "passive",
    class_id: "CLASS-5A",
    student_code: "S002",
    upload_id: "upload_002",
    exp: Math.floor(Date.now() / 1000) + 3600,
  }, config.linkSecret);
  const forbiddenAutomaticResponse = await fetch(base + "/api/coze/chat", {
    method: "POST",
    headers: { "Content-Type": "application/json", Origin: "http://127.0.0.1:4173" },
    body: JSON.stringify({
      ticket: passiveTicket,
      level_id: "spinner_race",
      trigger: "idle",
      message: "自动提示",
      state: { checkpoint: 1 },
    }),
  });
  assert.equal(forbiddenAutomaticResponse.status, 403);
  assert.equal((await forbiddenAutomaticResponse.json()).code, "agent_condition_forbidden");
});
