"use strict";

const { parseLevelPrompts } = require("./agent-context");

function parseOrigins(value) {
  return String(value || "http://127.0.0.1:4173,http://localhost:4173")
    .split(",")
    .map((item) => item.trim().replace(/\/$/, ""))
    .filter(Boolean);
}

function loadConfig(environment = process.env) {
  const levelPromptConfig = parseLevelPrompts(environment.AI_LEVEL_PROMPTS_JSON);
  const config = {
    linkSecret: environment.UPLOAD_LINK_SECRET || "",
    allowedOrigins: parseOrigins(environment.ALLOWED_ORIGINS),
    ossRegion: environment.OSS_REGION || "",
    ossBucket: environment.OSS_BUCKET || "",
    ossRoleArn: environment.OSS_UPLOAD_ROLE_ARN || "",
    ossInternal: environment.OSS_INTERNAL === "true",
    stsEndpoint: String(environment.STS_ENDPOINT || "https://sts.cn-hangzhou.aliyuncs.com").replace(/\/$/, ""),
    mockRoot: environment.MOCK_OSS_ROOT || "",
    publicBaseUrl: String(environment.PUBLIC_BASE_URL || "").replace(/\/$/, ""),
    cozeApiToken: environment.COZE_API_TOKEN || "",
    cozeBotId: environment.COZE_BOT_ID || "",
    cozeOauthClientId: environment.COZE_JWT_OAUTH_CLIENT_ID || "",
    cozeOauthPublicKeyId: environment.COZE_JWT_OAUTH_PUBLIC_KEY_ID || "",
    cozeOauthPrivateKey: environment.COZE_JWT_OAUTH_PRIVATE_KEY || "",
    aiLevelPrompts: levelPromptConfig.prompts,
    aiPromptsConfigured: levelPromptConfig.configured,
    aiPromptConfigError: levelPromptConfig.error,
  };
  validateConfig(config);
  return config;
}

function validateConfig(config) {
  if (String(config.linkSecret || "").length < 32) {
    throw new Error("UPLOAD_LINK_SECRET must contain at least 32 characters");
  }
  if (!Array.isArray(config.allowedOrigins) || config.allowedOrigins.length === 0) {
    throw new Error("ALLOWED_ORIGINS must contain at least one exact origin");
  }
  if (!config.mockRoot) {
    for (const [key, value] of [
      ["OSS_REGION", config.ossRegion],
      ["OSS_BUCKET", config.ossBucket],
      ["OSS_UPLOAD_ROLE_ARN", config.ossRoleArn],
    ]) {
      if (!value) throw new Error(`${key} is required outside local mock mode`);
    }
    if (!/^https:\/\/sts(?:[.-][a-z0-9-]+)*\.aliyuncs\.com$/i.test(config.stsEndpoint)) {
      throw new Error("STS_ENDPOINT must be an Alibaba Cloud STS HTTPS endpoint");
    }
  }
  const cozeCredentialConfigured = Boolean(config.cozeApiToken || config.cozeOauthPrivateKey || config.cozeOauthClientId || config.cozeOauthPublicKeyId);
  if (cozeCredentialConfigured && !config.cozeBotId) {
    throw new Error("COZE_BOT_ID is required when Coze credentials are configured");
  }
  return config;
}

module.exports = { loadConfig, validateConfig };
