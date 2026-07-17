"use strict";

const MAX_WAIT_MS = 45000;
const POLL_INTERVAL_MS = 250;
const REQUEST_TIMEOUT_MS = 15000;
const COZE_API_BASE_URL = "https://api.coze.cn";
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

function createCozeAdapter(config) {
  const configured = Boolean(config.cozeApiToken && config.cozeBotId);

  async function request(path, options = {}) {
    let response;
    try {
      response = await fetch(`${COZE_API_BASE_URL}${path}`, {
        method: options.method || "GET",
        headers: {
          Authorization: `Bearer ${config.cozeApiToken}`,
          "Content-Type": "application/json",
        },
        body: options.body ? JSON.stringify(options.body) : undefined,
        signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
      });
    } catch (error) {
      throw createCozeError(error.name === "TimeoutError" ? "coze_timeout" : "coze_network_error");
    }
    const payload = await response.json().catch(() => ({}));
    if (!response.ok || payload.code !== 0) {
      throw createCozeError("coze_upstream_error", payload.msg || `HTTP ${response.status}`);
    }
    return payload.data;
  }

  async function chat({ message, conversationId, userId }) {
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

    const deadline = Date.now() + MAX_WAIT_MS;
    let result = created;
    while (!FINISHED_STATUSES.has(result.status)) {
      if (Date.now() >= deadline) throw createCozeError("coze_timeout");
      await wait(POLL_INTERVAL_MS);
      result = await request(`/v3/chat/retrieve?conversation_id=${encodeURIComponent(created.conversation_id)}&chat_id=${encodeURIComponent(created.id)}`);
    }

    if (result.status !== "completed") {
      throw createCozeError("coze_chat_failed", result.last_error?.msg || result.status);
    }

    const messages = await request(`/v3/chat/message/list?conversation_id=${encodeURIComponent(created.conversation_id)}&chat_id=${encodeURIComponent(created.id)}`);
    const answer = [...messages].reverse().find((item) => item.role === "assistant" && item.type === "answer");
    const reply = String(answer?.content || "").trim();
    if (!reply) throw createCozeError("coze_empty_response");

    return {
      conversationId: created.conversation_id,
      reply,
    };
  }

  return { configured, chat };
}

module.exports = { createCozeAdapter, createCozeError };
