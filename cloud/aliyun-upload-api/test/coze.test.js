"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const { createCozeAdapter } = require("../src/coze");

test("Coze adapter calls the official China API and returns only the final answer", async (context) => {
  const originalFetch = global.fetch;
  const calls = [];
  const replies = [
    { code: 0, data: { id: "chat_1", conversation_id: "conversation_1", status: "created" } },
    { code: 0, data: { id: "chat_1", conversation_id: "conversation_1", status: "completed" } },
    { code: 0, data: [
      { role: "assistant", type: "verbose", content: "internal details" },
      { role: "assistant", type: "answer", content: "先观察巡逻路线。" },
    ] },
  ];
  global.fetch = async (url, options) => {
    calls.push({ url: String(url), options });
    const payload = replies.shift();
    return new Response(JSON.stringify(payload), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  };
  context.after(() => { global.fetch = originalFetch; });

  const adapter = createCozeAdapter({
    cozeApiToken: "server-only-token",
    cozeBotId: "7649339604520697891",
  });
  const result = await adapter.chat({
    message: "给我提示",
    conversationId: "",
    userId: "web_upload_001",
  });

  assert.deepEqual(result, { conversationId: "conversation_1", reply: "先观察巡逻路线。" });
  assert.equal(calls.length, 3);
  assert.equal(calls[0].url, "https://api.coze.cn/v3/chat");
  assert.equal(calls[0].options.headers.Authorization, "Bearer server-only-token");
  assert.equal(JSON.parse(calls[0].options.body).stream, false);
  assert.match(calls[1].url, /\/v3\/chat\/retrieve\?/);
  assert.match(calls[2].url, /\/v3\/chat\/message\/list\?/);
});

test("Coze adapter stays disabled when server credentials are missing", async () => {
  const adapter = createCozeAdapter({ cozeApiToken: "", cozeBotId: "" });
  assert.equal(adapter.configured, false);
  await assert.rejects(() => adapter.chat({ message: "test", conversationId: "", userId: "test" }), /coze_not_configured/);
});
