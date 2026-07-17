"use strict";

const crypto = require("node:crypto");

const MAX_WAIT_MS = 45000;
const POLL_INTERVAL_MS = 250;
const REQUEST_TIMEOUT_MS = 15000;
const COZE_API_BASE_URL = "https://api.coze.cn";
const OAUTH_TOKEN_PATH = "/api/permission/oauth2/token";
const OAUTH_TOKEN_TTL_SECONDS = 86399;
const OAUTH_RENEWAL_MARGIN_SECONDS = 300;
const JWT_ASSERTION_TTL_SECONDS = 600;
const FINISHED_STATUSES = new Set(["completed", "failed", "requires_action", "canceled"]);

function wait(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function createCozeError(code, details = "") {
  const error = new Error(code);
  error.code = code;
  error.details = details;
  return error;
}

function encodeJson(value) {
  return Buffer.from(JSON.stringify(value), "utf8").toString("base64url");
}

function normalizePrivateKey(value) {
  return String(value || "").replaceAll("\\n", "\n").trim();
}

function createJwtAssertion(config, nowSeconds = Math.floor(Date.now() / 1000)) {
  const header = {
    alg: "RS256",
    typ: "JWT",
    kid: config.cozeOauthPublicKeyId,
  };
  const payload = {
    iss: config.cozeOauthClientId,
    aud: "api.coze.cn",
    iat: nowSeconds,
    exp: nowSeconds + JWT_ASSERTION_TTL_SECONDS,
    jti: crypto.randomUUID(),
  };
  const unsigned = `${encodeJson(header)}.${encodeJson(payload)}`;
  let signature;
  try {
    signature = crypto.sign("RSA-SHA256", Buffer.from(unsigned), normalizePrivateKey(config.cozeOauthPrivateKey)).toString("base64url");
  } catch {
    throw createCozeError("coze_oauth_private_key_invalid");
  }
  return `${unsigned}.${signature}`;
}

function createCozeAdapter(config) {
  const oauthConfigured = Boolean(
    config.cozeOauthClientId
    && config.cozeOauthPublicKeyId
    && config.cozeOauthPrivateKey
  );
  const patConfigured = Boolean(config.cozeApiToken);
  const authMode = oauthConfigured ? "jwt_oauth" : patConfigured ? "pat" : "none";
  const configured = Boolean(config.cozeBotId && authMode !== "none");
  let oauthCache = { token: "", expiresAt: 0 };
  let oauthRequest = null;

  async function issueOauthAccessToken() {
    const assertion = createJwtAssertion(config);
    let response;
    try {
      response = await fetch(`${COZE_API_BASE_URL}${OAUTH_TOKEN_PATH}`, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${assertion}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
          duration_seconds: OAUTH_TOKEN_TTL_SECONDS,
        }),
        signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
      });
    } catch (error) {
      throw createCozeError(error.name === "TimeoutError" ? "coze_timeout" : "coze_oauth_network_error");
    }

    const payload = await response.json().catch(() => ({}));
    const accessToken = String(payload.access_token || "");
    if (!response.ok || !accessToken) {
      throw createCozeError("coze_oauth_failed", payload.error_message || payload.error || `HTTP ${response.status}`);
    }
    const expiresIn = Number(payload.expires_in);
    const ttl = Number.isFinite(expiresIn) && expiresIn > 0
      ? Math.min(expiresIn, OAUTH_TOKEN_TTL_SECONDS)
      : OAUTH_TOKEN_TTL_SECONDS;
    oauthCache = {
      token: accessToken,
      expiresAt: Math.floor(Date.now() / 1000) + ttl,
    };
    return accessToken;
  }

  async function getAccessToken() {
    if (authMode === "pat") return config.cozeApiToken;
    if (authMode !== "jwt_oauth") throw createCozeError("coze_not_configured");
    const nowSeconds = Math.floor(Date.now() / 1000);
    if (oauthCache.token && oauthCache.expiresAt - nowSeconds > OAUTH_RENEWAL_MARGIN_SECONDS) {
      return oauthCache.token;
    }
    if (!oauthRequest) {
      oauthRequest = issueOauthAccessToken().finally(() => {
        oauthRequest = null;
      });
    }
    return oauthRequest;
  }

  async function performRequest(path, options, accessToken) {
    let response;
    try {
      response = await fetch(`${COZE_API_BASE_URL}${path}`, {
        method: options.method || "GET",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: options.body ? JSON.stringify(options.body) : undefined,
        signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
      });
    } catch (error) {
      throw createCozeError(error.name === "TimeoutError" ? "coze_timeout" : "coze_network_error");
    }
    const payload = await response.json().catch(() => ({}));
    return { response, payload };
  }

  async function request(path, options = {}) {
    let accessToken = await getAccessToken();
    let result = await performRequest(path, options, accessToken);
    if (result.response.status === 401 && authMode === "jwt_oauth") {
      oauthCache = { token: "", expiresAt: 0 };
      accessToken = await getAccessToken();
      result = await performRequest(path, options, accessToken);
    }
    if (!result.response.ok || result.payload.code !== 0) {
      throw createCozeError("coze_upstream_error", result.payload.msg || `HTTP ${result.response.status}`);
    }
    return result.payload.data;
  }

  async function startChat({ message, conversationId, userId }) {
    if (!configured) throw createCozeError("coze_not_configured");
    const conversationQuery = conversationId ? `?conversation_id=${encodeURIComponent(conversationId)}` : "";
    const created = await request(`/v3/chat${conversationQuery}`, {
      method: "POST",
      body: {
        bot_id: config.cozeBotId,
        user_id: userId,
        auto_save_history: true,
        stream: false,
        additional_messages: [{
          role: "user",
          content: message,
          content_type: "text",
        }],
      },
    });

    return {
      chatId: created.id,
      conversationId: created.conversation_id,
      status: created.status,
    };
  }

  async function getChatResult({ chatId, conversationId }) {
    if (!configured) throw createCozeError("coze_not_configured");
    const result = await request(`/v3/chat/retrieve?conversation_id=${encodeURIComponent(conversationId)}&chat_id=${encodeURIComponent(chatId)}`);

    if (!FINISHED_STATUSES.has(result.status)) {
      return { status: result.status || "in_progress" };
    }

    if (result.status !== "completed") {
      throw createCozeError("coze_chat_failed", result.last_error?.msg || result.status);
    }

    const messages = await request(`/v3/chat/message/list?conversation_id=${encodeURIComponent(conversationId)}&chat_id=${encodeURIComponent(chatId)}`);
    const answer = [...messages].reverse().find((item) => item.role === "assistant" && item.type === "answer");
    const reply = String(answer?.content || "").trim();
    if (!reply) throw createCozeError("coze_empty_response");

    return { status: "completed", reply };
  }

  async function chat({ message, conversationId, userId }) {
    const created = await startChat({ message, conversationId, userId });

    const deadline = Date.now() + MAX_WAIT_MS;
    let result = { status: created.status };
    while (true) {
      if (Date.now() >= deadline) throw createCozeError("coze_timeout");
      if (!FINISHED_STATUSES.has(result.status)) await wait(POLL_INTERVAL_MS);
      result = await getChatResult({ chatId: created.chatId, conversationId: created.conversationId });
      if (result.status === "completed") break;
    }

    return {
      conversationId: created.conversationId,
      reply: result.reply,
    };
  }

  return { configured, authMode, botId: config.cozeBotId, startChat, getChatResult, chat };
}

module.exports = { createCozeAdapter, createCozeError, createJwtAssertion };
