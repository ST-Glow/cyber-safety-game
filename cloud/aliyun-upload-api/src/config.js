"use strict";

function parseOrigins(value) {
  return String(value || "http://127.0.0.1:4173,http://localhost:4173")
    .split(",")
    .map((item) => item.trim().replace(/\/$/, ""))
    .filter(Boolean);
}

function loadConfig(environment = process.env) {
  const config = {
    linkSecret: environment.UPLOAD_LINK_SECRET || "",
    allowedOrigins: parseOrigins(environment.ALLOWED_ORIGINS),
    ossRegion: environment.OSS_REGION || "",
    ossBucket: environment.OSS_BUCKET || "",
    ossRoleArn: environment.OSS_UPLOAD_ROLE_ARN || "",
    ossInternal: environment.OSS_INTERNAL === "true",
    mockRoot: environment.MOCK_OSS_ROOT || "",
    publicBaseUrl: String(environment.PUBLIC_BASE_URL || "").replace(/\/$/, ""),
    cozeApiToken: environment.COZE_API_TOKEN || "",
    cozeBotId: "7647799189921284146",
    cozeOauthClientId: environment.COZE_JWT_OAUTH_CLIENT_ID || "1167033540105",
    cozeOauthPublicKeyId: environment.COZE_JWT_OAUTH_PUBLIC_KEY_ID || "HzkdmJpFJHuubOaaG3C6bmAjC0oLY6vX2AgtVz5X4ho",
    cozeOauthPrivateKey: environment.COZE_JWT_OAUTH_PRIVATE_KEY || "",
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
  }
  return config;
}

module.exports = { loadConfig, validateConfig };
