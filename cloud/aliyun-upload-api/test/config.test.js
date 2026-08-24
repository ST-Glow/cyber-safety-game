"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const { loadConfig } = require("../src/config");

test("Hong Kong STS endpoint is accepted for Function Compute", () => {
  const config = loadConfig({
    UPLOAD_LINK_SECRET: "test-secret-at-least-32-characters-long",
    ALLOWED_ORIGINS: "https://st-glow.github.io",
    MOCK_OSS_ROOT: "../../mock-oss",
    STS_ENDPOINT: "https://sts.cn-hongkong.aliyuncs.com/",
  });

  assert.equal(config.stsEndpoint, "https://sts.cn-hongkong.aliyuncs.com");
});

test("non-Alibaba STS endpoints are rejected outside mock mode", () => {
  assert.throws(() => loadConfig({
    UPLOAD_LINK_SECRET: "test-secret-at-least-32-characters-long",
    ALLOWED_ORIGINS: "https://st-glow.github.io",
    OSS_REGION: "oss-cn-hangzhou",
    OSS_BUCKET: "cyber-game",
    OSS_UPLOAD_ROLE_ARN: "acs:ram::1234567890123456:role/upload-role",
    STS_ENDPOINT: "https://untrusted.example.com",
  }), /STS_ENDPOINT/);
});

test("Coze credentials require an explicit new Bot ID", () => {
  assert.throws(() => loadConfig({
    UPLOAD_LINK_SECRET: "test-secret-at-least-32-characters-long",
    ALLOWED_ORIGINS: "https://st-glow.github.io",
    MOCK_OSS_ROOT: "../../mock-oss",
    COZE_JWT_OAUTH_CLIENT_ID: "new-client",
  }), /COZE_BOT_ID/);
});
