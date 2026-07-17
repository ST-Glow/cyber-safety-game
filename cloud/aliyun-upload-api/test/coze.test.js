"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
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
  const adapter = createCozeAdapter({ cozeApiToken: "", cozeBotId: "", cozeOauthClientId: "", cozeOauthPublicKeyId: "", cozeOauthPrivateKey: "" });
  assert.equal(adapter.configured, false);
  await assert.rejects(() => adapter.chat({ message: "test", conversationId: "", userId: "test" }), /coze_not_configured/);
});

test("JWT OAuth token is generated once and reused until its renewal window", async (context) => {
  const originalFetch = global.fetch;
  const { privateKey } = crypto.generateKeyPairSync("rsa", { modulusLength: 2048 });
  const calls = [];
  let chatNumber = 0;
  global.fetch = async (url, options) => {
    const target = String(url);
    calls.push({ url: target, options });
    if (target.endsWith("/api/permission/oauth2/token")) {
      return new Response(JSON.stringify({ access_token: "oauth-access-token", expires_in: 86399 }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }
    if (target.includes("/v3/chat/message/list")) {
      return new Response(JSON.stringify({ code: 0, data: [{ role: "assistant", type: "answer", content: "A safe hint" }] }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }
    chatNumber += 1;
    return new Response(JSON.stringify({
      code: 0,
      data: { id: `chat_${chatNumber}`, conversation_id: `conversation_${chatNumber}`, status: "completed" },
    }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  };
  context.after(() => { global.fetch = originalFetch; });

  const adapter = createCozeAdapter({
    cozeApiToken: "old-pat-is-not-used",
    cozeBotId: "7647799189921284146",
    cozeOauthClientId: "1167033540105",
    cozeOauthPublicKeyId: "public-key-id",
    cozeOauthPrivateKey: privateKey.export({ type: "pkcs8", format: "pem" }),
  });
  assert.equal(adapter.authMode, "jwt_oauth");
  assert.equal(adapter.botId, "7647799189921284146");

  await adapter.chat({ message: "first", conversationId: "", userId: "web_1" });
  await adapter.chat({ message: "second", conversationId: "", userId: "web_2" });

  const tokenCalls = calls.filter((call) => call.url.endsWith("/api/permission/oauth2/token"));
  assert.equal(tokenCalls.length, 1);
  const assertion = tokenCalls[0].options.headers.Authorization.slice("Bearer ".length);
  const [headerPart, payloadPart] = assertion.split(".");
  const header = JSON.parse(Buffer.from(headerPart, "base64url").toString("utf8"));
  const payload = JSON.parse(Buffer.from(payloadPart, "base64url").toString("utf8"));
  assert.equal(header.kid, "public-key-id");
  assert.equal(payload.iss, "1167033540105");
  assert.equal(payload.aud, "api.coze.cn");
  assert.equal(payload.exp - payload.iat, 600);
  assert.equal(JSON.parse(tokenCalls[0].options.body).duration_seconds, 86399);

  const chatCalls = calls.filter((call) => call.url.includes("/v3/chat") && !call.url.includes("message/list"));
  assert.equal(chatCalls.length, 2);
  assert.equal(chatCalls[0].options.headers.Authorization, "Bearer oauth-access-token");
  assert.equal(JSON.parse(chatCalls[0].options.body).bot_id, "7647799189921284146");
});
