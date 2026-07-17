(() => {
  "use strict";

  const sdkUrl = "https://lf-cdn.coze.cn/obj/unpkg/flow-platform/chat-app-sdk/1.2.0-beta.19/libs/cn/index.js";
  const agentConfig = {
    botId: "7649339604520697891",
    title: "五年级助思老师",
    tokenEndpoint: window.CYBER_COZE_CONFIG?.tokenEndpoint || "",
  };

  let sdkLoadPromise = null;
  let chatClient = null;
  let initialized = false;
  let openMethodName = "";

  function getSdkRoots() {
    const roots = [];
    const knownRoot = document.getElementById("coze-web-chat");
    if (knownRoot) roots.push(knownRoot);

    Array.from(document.body.children).forEach((child) => {
      if (!(child instanceof HTMLElement)) return;
      if (child.id === "app") return;
      if (child.id && child.id.startsWith("semi-image-preview")) return;
      if (child.tagName !== "DIV") return;
      if (child.closest("#agentOverlay")) return;
      roots.push(child);
    });

    return Array.from(new Set(roots));
  }

  function markClientDebug() {
    if (!chatClient) return;
    const ownKeys = Object.keys(chatClient);
    const protoKeys = Object.getOwnPropertyNames(Object.getPrototypeOf(chatClient) || {});
    document.documentElement.dataset.cozeClientKeys = Array.from(new Set([...ownKeys, ...protoKeys])).join(",");
    document.documentElement.dataset.cozeOpenMethod = openMethodName || "";
  }

  function callLikelyOpenMethod() {
    if (!chatClient) return false;
    const methodNames = [
      "open",
      "show",
      "showChat",
      "openChat",
      "toggle",
      "toggleChat",
      "expand",
      "showPanel",
    ];

    for (const name of methodNames) {
      if (typeof chatClient[name] !== "function") continue;
      try {
        chatClient[name]();
        openMethodName = name;
        markClientDebug();
        return true;
      } catch {
        // Try the next known method name.
      }
    }

    markClientDebug();
    return false;
  }

  function setFallback(message, state = "loading") {
    const fallback = document.getElementById("agentFallback");
    if (!fallback) return;
    fallback.textContent = message;
    fallback.dataset.state = state;
  }

  function loadSdk() {
    if (window.CozeWebSDK?.WebChatClient) {
      return Promise.resolve();
    }
    if (sdkLoadPromise) {
      return sdkLoadPromise;
    }

    sdkLoadPromise = new Promise((resolve, reject) => {
      const existing = document.querySelector(`script[src="${sdkUrl}"]`);
      if (existing) {
        existing.addEventListener("load", resolve, { once: true });
        existing.addEventListener("error", () => reject(new Error("Coze SDK failed to load")), { once: true });
        return;
      }

      const script = document.createElement("script");
      script.src = sdkUrl;
      script.async = true;
      script.onload = resolve;
      script.onerror = () => reject(new Error("Coze SDK failed to load"));
      document.head.appendChild(script);

      window.setTimeout(() => {
        if (!window.CozeWebSDK?.WebChatClient) {
          reject(new Error("Coze SDK load timeout"));
        }
      }, 12000);
    });

    return sdkLoadPromise;
  }

  async function getAgentToken() {
    if (!agentConfig.tokenEndpoint) {
      throw new Error("coze_token_endpoint_not_configured");
    }
    const response = await fetch(agentConfig.tokenEndpoint, { credentials: "omit" });
    const payload = await response.json().catch(() => ({}));
    if (!response.ok || !payload.token) {
      throw new Error(payload.message || "coze_token_request_failed");
    }
    return payload.token;
  }

  function moveSdkNodeIntoDrawer() {
    const mount = document.getElementById("cozeAgentMount");
    const chatNodes = getSdkRoots();
    if (!mount || chatNodes.length === 0) return false;

    chatNodes.forEach((chatNode) => {
      if (chatNode.parentElement !== mount) {
        mount.appendChild(chatNode);
      }
      chatNode.classList.add("coze-agent-embedded");
    });

    return chatNodes.some((node) => {
      const text = (node.textContent || "").trim();
      return text.length > 0 || Boolean(node.querySelector("button, iframe, input, textarea, [role='button'], [role='textbox']"));
    });
  }

  function hasSdkRoot() {
    const mount = document.getElementById("cozeAgentMount");
    if (!mount) return false;
    return Boolean(mount.querySelector(".coze-agent-embedded"));
  }

  function hasVisibleChatSurface() {
    const mount = document.getElementById("cozeAgentMount");
    if (!mount) return false;
    const roots = Array.from(mount.querySelectorAll(".coze-agent-embedded"));
    return roots.some((node) => {
      const text = (node.textContent || "").trim();
      return text.length > 0 || Boolean(node.querySelector("button, iframe, input, textarea, [role='button'], [role='textbox']"));
    });
  }

  function markMissingSurface() {
    if (hasVisibleChatSurface()) {
      setFallback("守护助手已接入。可以在这里提问，也可以点击上方继续游戏。", "ready");
      return;
    }

    if (hasSdkRoot()) {
      setFallback("智能体 SDK 已接入，但聊天窗口还没有展开。请检查该智能体的发布配置或网络权限。", "error");
      return;
    }

    setFallback("智能体加载失败，请检查网络后继续游戏。行为日志仍会正常保存。", "error");
  }

  function clickLikelyLauncher() {
    const mount = document.getElementById("cozeAgentMount");
    if (!mount) return false;

    const candidates = [
      "#coze-web-chat button",
      "#coze-web-chat [role='button']",
      "#coze-web-chat .chat-button",
      "#coze-web-chat .coze-chat-button",
    ];

    for (const selector of candidates) {
      const button = mount.querySelector(selector);
      if (button instanceof HTMLElement) {
        button.click();
        return true;
      }
    }
    return false;
  }

  function arrangeSdkInDrawer(attempt = 0) {
    const moved = moveSdkNodeIntoDrawer();
    callLikelyOpenMethod();
    const clicked = clickLikelyLauncher();

    if (moved || hasVisibleChatSurface()) {
      setFallback("守护助手已接入。可以在这里提问，也可以点击上方继续游戏。", "ready");
    }

    if ((!moved || !clicked) && attempt < 24) {
      window.setTimeout(() => arrangeSdkInDrawer(attempt + 1), 250);
    } else if (!hasVisibleChatSurface()) {
      markMissingSurface();
    }
  }

  async function open() {
    setFallback("正在接入守护助手，请稍等。", "loading");
    let hardTimeoutId = 0;

    try {
      await Promise.race([
        loadSdk(),
        new Promise((_, reject) => {
          hardTimeoutId = window.setTimeout(() => {
            reject(new Error("Coze SDK load timeout"));
          }, 12000);
        }),
      ]);
      window.clearTimeout(hardTimeoutId);

      if (!window.CozeWebSDK?.WebChatClient) {
        throw new Error("Coze SDK is unavailable");
      }

      if (!initialized) {
        const token = await getAgentToken();
        chatClient = new window.CozeWebSDK.WebChatClient({
          config: {
            bot_id: agentConfig.botId,
          },
          componentProps: {
            title: agentConfig.title,
          },
          auth: {
            type: "token",
            token,
            onRefreshToken: getAgentToken,
          },
        });
        initialized = true;
        markClientDebug();
      }

      arrangeSdkInDrawer();

      return { ok: true, reused: Boolean(chatClient) };
    } catch (error) {
      window.clearTimeout(hardTimeoutId);
      sdkLoadPromise = null;
      setFallback("智能体加载失败，请检查网络后继续游戏。行为日志仍会正常保存。", "error");
      return { ok: false, error: error.message };
    }
  }

  function close() {
    setFallback("守护助手已暂停。下次停滞时会再次接入。", "idle");
  }

  window.CyberSafetyCozeAgent = {
    open,
    close,
  };

  document.documentElement.dataset.cozeAgentModule = "ready";
})();
