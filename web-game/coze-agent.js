(() => {
  "use strict";

  const config = {
    apiBaseUrl: String(window.CYBER_UPLOAD_CONFIG?.apiBaseUrl || "").replace(/\/$/, ""),
    ticket: new URLSearchParams(window.location.search).get("ticket") || "",
    title: "助思智能体",
  };

  let initialized = false;
  let sending = false;
  let session = "";
  let messages = null;
  let input = null;
  let submitButton = null;

  function setFallback(message, state = "loading") {
    const fallback = document.getElementById("agentFallback");
    if (!fallback) return;
    fallback.textContent = message;
    fallback.dataset.state = state;
    fallback.classList.remove("hidden");
  }

  function hideFallback() {
    document.getElementById("agentFallback")?.classList.add("hidden");
  }

  function addMessage(role, text, options = {}) {
    if (!messages) return null;
    const bubble = document.createElement("div");
    bubble.className = `coze-proxy-message ${role}`;
    if (options.pending) bubble.classList.add("pending");
    bubble.textContent = text;
    messages.appendChild(bubble);
    messages.scrollTop = messages.scrollHeight;
    return bubble;
  }

  function errorMessage(code) {
    const messagesByCode = {
      coze_not_configured: "智能体服务尚未完成配置，请联系教师。",
      coze_rate_limited: "提问有些频繁，请稍等一会儿再试。",
      ticket_expired: "这个课堂链接已经过期，请向教师领取新链接。",
      ticket_malformed: "当前不是有效的课堂专属链接。",
      ticket_signature_invalid: "当前课堂链接无效，请向教师重新领取。",
      origin_not_allowed: "当前网站地址未获智能体服务授权。",
      coze_message_invalid: "问题需要控制在 800 个字符以内。",
    };
    return messagesByCode[code] || "智能体暂时无法回答，请稍后再试。";
  }

  async function sendMessage(rawMessage) {
    const message = String(rawMessage || "").trim();
    if (!message || sending) return;
    if (message.length > 800) {
      addMessage("system", "问题需要控制在 800 个字符以内。");
      return;
    }

    sending = true;
    submitButton.disabled = true;
    input.disabled = true;
    addMessage("user", message);
    input.value = "";
    const pending = addMessage("assistant", "正在思考…", { pending: true });

    try {
      const response = await fetch(`${config.apiBaseUrl}/api/coze/chat`, {
        method: "POST",
        credentials: "omit",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ ticket: config.ticket, message, session: session || undefined }),
      });
      const payload = await response.json().catch(() => ({}));
      pending?.remove();
      if (!response.ok || !payload.reply) {
        addMessage("system", errorMessage(payload.code));
        window.dispatchEvent(new CustomEvent("cyber-agent-response", { detail: { ok: false, code: payload.code || "request_failed" } }));
        return;
      }
      session = payload.session || session;
      addMessage("assistant", payload.reply);
      window.dispatchEvent(new CustomEvent("cyber-agent-response", { detail: { ok: true } }));
    } catch {
      pending?.remove();
      addMessage("system", "网络连接失败。请检查网络后再试，游戏进度不会受到影响。");
      window.dispatchEvent(new CustomEvent("cyber-agent-response", { detail: { ok: false, code: "network_error" } }));
    } finally {
      sending = false;
      submitButton.disabled = false;
      input.disabled = false;
      input.focus();
    }
  }

  function addSuggestion(container, label, message) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "coze-proxy-suggestion";
    button.textContent = label;
    button.addEventListener("click", () => sendMessage(message));
    container.appendChild(button);
  }

  function initialize() {
    if (initialized) return;
    const mount = document.getElementById("cozeAgentMount");
    if (!mount) throw new Error("agent_mount_missing");

    const shell = document.createElement("section");
    shell.className = "coze-proxy-chat";

    const header = document.createElement("header");
    header.className = "coze-proxy-header";
    const title = document.createElement("strong");
    title.textContent = config.title;
    const privacy = document.createElement("span");
    privacy.textContent = "由扣子提供回答 · 请勿输入姓名、电话等个人信息";
    header.append(title, privacy);

    messages = document.createElement("div");
    messages.className = "coze-proxy-messages";
    messages.setAttribute("role", "log");
    messages.setAttribute("aria-live", "polite");

    const suggestions = document.createElement("div");
    suggestions.className = "coze-proxy-suggestions";
    addSuggestion(suggestions, "给我一个提示", "我在当前游戏关卡卡住了。请只给我一个简短提示，不要直接公布答案。");
    addSuggestion(suggestions, "讲讲隐私保护", "请结合这个网络安全游戏，用清楚、简洁的话提醒我保护个人信息时最重要的做法。");

    const form = document.createElement("form");
    form.className = "coze-proxy-form";
    input = document.createElement("textarea");
    input.rows = 2;
    input.maxLength = 800;
    input.placeholder = "说说你卡在哪里……";
    input.setAttribute("aria-label", "向助思智能体提问");
    submitButton = document.createElement("button");
    submitButton.type = "submit";
    submitButton.textContent = "发送";
    form.append(input, submitButton);
    form.addEventListener("submit", (event) => {
      event.preventDefault();
      sendMessage(input.value);
    });
    input.addEventListener("keydown", (event) => {
      if (event.key === "Enter" && !event.shiftKey) {
        event.preventDefault();
        form.requestSubmit();
      }
    });

    shell.append(header, messages, suggestions, form);
    mount.replaceChildren(shell);
    addMessage("assistant", "你好，我是助思智能体。你可以告诉我卡在哪里，我会尽量只给提示，不直接替你完成任务。");
    initialized = true;
  }

  async function open() {
    try {
      if (!config.apiBaseUrl || config.apiBaseUrl.includes("__UPLOAD_API_BASE_URL__")) {
        throw new Error("agent_api_not_configured");
      }
      if (!config.ticket) throw new Error("signed_ticket_missing");
      initialize();
      hideFallback();
      window.setTimeout(() => input?.focus(), 80);
      return { ok: true, mode: "server_proxy" };
    } catch (error) {
      const message = error.message === "signed_ticket_missing"
        ? "请使用教师发放的课堂专属链接进入，才能使用智能体。"
        : "智能体服务尚未配置完成，请联系教师。";
      setFallback(message, "error");
      return { ok: false, error: error.message };
    }
  }

  function close() {
    input?.blur();
  }

  window.CyberSafetyCozeAgent = { open, close };
  document.documentElement.dataset.cozeAgentModule = "server-proxy-ready";
})();
