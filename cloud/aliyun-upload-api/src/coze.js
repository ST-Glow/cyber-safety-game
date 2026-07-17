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

function createCozeError(code, details = "", diagnosticId = "") {
  const error = new Error(code);
  error.code = code;
  error.details = details;
  error.diagnosticId = diagnosticId;
  return error;
}

function logCozeEvent(diagnosticId, event, fields = {}, level = "log") {
  if (!diagnosticId) return;
  const record = JSON.stringify({
    event,
    diagnostic_id: diagnosticId,
    ...fields,
  });
  const writer = typeof console[level] === "function" ? console[level] : console.log;
  writer.call(console, record);
}

function safePrivateKeyInfo(value) {
  const raw = String(value || "");
  const normalized = normalizePrivateKey(raw);
  const pemType = normalized.match(/-----BEGIN ([^-]+)-----/)?.[1] || "unknown";
  return {
    raw_length: raw.length,
    normalized_length: normalized.length,
    pem_type: pemType,
    normalized_lines: normalized ? normalized.split(/\r?\n/).length : 0,
  };
}

function providerLogId(response) {
  return String(
    response.headers.get("x-tt-logid")
      || response.headers.get("x-request-id")
      || response.headers.get("x-trace-id")
      || "",
  ).slice(0, 120);
}

function encodeJson(value) {
  return Buffer.from(JSON.stringify(value), "utf8").toString("base64url");
}

function normalizePrivateKey(value) {
  let normalized = String(value || "")
    .replaceAll("\\r\\n", "\n")
    .replaceAll("\\n", "\n")
    .trim();

  if (
    normalized.length >= 2
    && ((normalized.startsWith('"') && normalized.endsWith('"'))
      || (normalized.startsWith("'") && normalized.endsWith("'")))
  ) {
    normalized = normalized.slice(1, -1).trim();
  }

  const pem = normalized.match(/-----BEGIN (RSA PRIVATE KEY|PRIVATE KEY)-----([\s\S]*?)-----END \1-----/);
  if (!pem) return normalized;

  const body = pem[2].replace(/\s+/g, "");
  if (!body) return normalized;
  const lines = body.match(/.{1,64}/g) || [];
  return `-----BEGIN ${pem[1]}-----\n${lines.join("\n")}\n-----END ${pem[1]}-----`;
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

  async function issueOauthAccessToken(diagnosticId) {
    logCozeEvent(diagnosticId, "coze_oauth_exchange_started", { auth_mode: authMode });
    let assertion;
    try {
      assertion = createJwtAssertion(config);
    } catch (error) {
      error.diagnosticId = diagnosticId;
      logCozeEvent(
        diagnosticId,
        "coze_oauth_jwt_sign_failed",
        safePrivateKeyInfo(config.cozeOauthPrivateKey),
        "error",
      );
      throw error;
    }
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
      const code = error.name === "TimeoutError" ? "coze_timeout" : "coze_oauth_network_error";
      logCozeEvent(diagnosticId, "coze_oauth_exchange_network_failed", { code }, "error");
      throw createCozeError(code, "", diagnosticId);
    }

    const payload = await response.json().catch(() => ({}));
    const accessToken = String(payload.access_token || "");
    logCozeEvent(diagnosticId, "coze_oauth_exchange_response", {
      http_status: response.status,
      provider_code: String(payload.code ?? payload.error ?? ""),
      provider_log_id: providerLogId(response),
      access_token_received: Boolean(accessToken),
    }, response.ok && accessToken ? "log" : "error");
    if (!response.ok || !accessToken) {
      throw createCozeError(
        "coze_oauth_failed",
        payload.error_message || payload.msg || payload.error || `HTTP ${response.status}`,
        diagnosticId,
      );
    }
    const expiresIn = Number(payload.expires_in);
    const ttl = Number.isFinite(expiresIn) && expiresIn > 0
      ? Math.min(expiresIn, OAUTH_TOKEN_TTL_SECONDS)
      : OAUTH_TOKEN_TTL_SECONDS;
    oauthCache = {
      token: accessToken,
      expiresAt: Math.floor(Date.now() / 1000) + ttl,
    };
    logCozeEvent(diagnosticId, "coze_oauth_token_cached", { expires_in_seconds: ttl });
    return accessToken;
  }

  async function getAccessToken(diagnosticId) {
    if (authMode === "pat") return config.cozeApiToken;
    if (authMode !== "jwt_oauth") throw createCozeError("coze_not_configured", "", diagnosticId);
    const nowSeconds = Math.floor(Date.now() / 1000);
    if (oauthCache.token && oauthCache.expiresAt - nowSeconds > OAUTH_RENEWAL_MARGIN_SECONDS) {
      logCozeEvent(diagnosticId, "coze_oauth_token_cache_hit", {
        remaining_seconds: oauthCache.expiresAt - nowSeconds,
      });
      return oauthCache.token;
    }
    if (!oauthRequest) {
      oauthRequest = issueOauthAccessToken(diagnosticId).finally(() => {
        oauthRequest = null;
      });
    }
    return oauthRequest;
  }

  async function performRequest(path, options, accessToken, diagnosticId, operation) {
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
      const code = error.name === "TimeoutError" ? "coze_timeout" : "coze_network_error";
      logCozeEvent(diagnosticId, "coze_api_network_failed", { operation, code }, "error");
      throw createCozeError(code, "", diagnosticId);
    }
    const payload = await response.json().catch(() => ({}));
    logCozeEvent(diagnosticId, "coze_api_response", {
      operation,
      http_status: response.status,
      provider_code: String(payload.code ?? ""),
      provider_log_id: providerLogId(response),
    }, response.ok && payload.code === 0 ? "log" : "error");
    return { response, payload };
  }

  async function request(path, options = {}, diagnosticId = "", operation = "unknown") {
    let accessToken = await getAccessToken(diagnosticId);
    let result = await performRequest(path, options, accessToken, diagnosticId, operation);
    if (result.response.status === 401 && authMode === "jwt_oauth") {
      logCozeEvent(diagnosticId, "coze_api_unauthorized_retry", { operation });
      oauthCache = { token: "", expiresAt: 0 };
      accessToken = await getAccessToken(diagnosticId);
      result = await performRequest(path, options, accessToken, diagnosticId, operation);
    }
    if (!result.response.ok || result.payload.code !== 0) {
      throw createCozeError(
        "coze_upstream_error",
        result.payload.msg || `HTTP ${result.response.status}`,
        diagnosticId,
      );
    }
    return result.payload.data;
  }

  async function startChat({ message, conversationId, userId, diagnosticId = "" }) {
    if (!configured) throw createCozeError("coze_not_configured", "", diagnosticId);
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
    }, diagnosticId, "chat_create");

    return {
      chatId: created.id,
      conversationId: created.conversation_id,
      status: created.status,
    };
  }

  async function getChatResult({ chatId, conversationId, diagnosticId = "" }) {
    if (!configured) throw createCozeError("coze_not_configured", "", diagnosticId);
    const result = await request(
      `/v3/chat/retrieve?conversation_id=${encodeURIComponent(conversationId)}&chat_id=${encodeURIComponent(chatId)}`,
      {},
      diagnosticId,
      "chat_retrieve",
    );

    if (!FINISHED_STATUSES.has(result.status)) {
      return { status: result.status || "in_progress" };
    }

    if (result.status !== "completed") {
      throw createCozeError("coze_chat_failed", result.last_error?.msg || result.status, diagnosticId);
    }

    const messages = await request(
      `/v3/chat/message/list?conversation_id=${encodeURIComponent(conversationId)}&chat_id=${encodeURIComponent(chatId)}`,
      {},
      diagnosticId,
      "chat_message_list",
    );
    const answer = [...messages].reverse().find((item) => item.role === "assistant" && item.type === "answer");
    const reply = String(answer?.content || "").trim();
    if (!reply) throw createCozeError("coze_empty_response", "", diagnosticId);

    return { status: "completed", reply };
  }

  async function chat({ message, conversationId, userId, diagnosticId = "" }) {
    const created = await startChat({ message, conversationId, userId, diagnosticId });

    const deadline = Date.now() + MAX_WAIT_MS;
    let result = { status: created.status };
    while (true) {
      if (Date.now() >= deadline) throw createCozeError("coze_timeout", "", diagnosticId);
      if (!FINISHED_STATUSES.has(result.status)) await wait(POLL_INTERVAL_MS);
      result = await getChatResult({
        chatId: created.chatId,
        conversationId: created.conversationId,
        diagnosticId,
      });
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
