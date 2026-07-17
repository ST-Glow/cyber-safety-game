(() => {
  "use strict";

  const GAME_WIDTH = 1280;
  const GAME_HEIGHT = 720;
  const WORLD = { x: 44, y: 108, w: 846, h: 506 };
  const IDLE_STAGES = [12, 24, 36];
  const SHIELD_DURATION_MS = 2500;
  const SHIELD_COOLDOWN_MS = 6000;

  const canvas = document.getElementById("gameCanvas");
  const ctx = canvas.getContext("2d");
  const screenOverlay = document.getElementById("screenOverlay");
  const screenKicker = document.getElementById("screenKicker");
  const screenTitle = document.getElementById("screenTitle");
  const screenText = document.getElementById("screenText");
  const codeRow = document.getElementById("codeRow");
  const studentCodeInput = document.getElementById("studentCode");
  const quizBox = document.getElementById("quizBox");
  const screenActions = document.getElementById("screenActions");
  const primaryAction = document.getElementById("primaryAction");
  const terminalPanel = document.getElementById("terminalPanel");
  const terminalKicker = document.getElementById("terminalKicker");
  const terminalQuestion = document.getElementById("terminalQuestion");
  const terminalOptions = document.getElementById("terminalOptions");
  const agentOverlay = document.getElementById("agentOverlay");
  const agentKicker = document.getElementById("agentKicker");
  const closeAgent = document.getElementById("closeAgent");
  const agentChoiceGate = document.getElementById("agentChoiceGate");
  const agentNeedHelp = document.getElementById("agentNeedHelp");
  const agentTryAgain = document.getElementById("agentTryAgain");
  const cozeAgentMount = document.getElementById("cozeAgentMount");
  const agentFallback = document.getElementById("agentFallback");
  const toastRack = document.getElementById("toastRack");
  const assistantBubble = document.getElementById("assistantBubble");
  const idleCountdown = document.getElementById("idleCountdown");
  const hudPhase = document.getElementById("hudPhase");
  const hudTitle = document.getElementById("hudTitle");
  const hudShield = document.getElementById("hudShield");
  const hudLevel = document.getElementById("hudLevel");
  const hudClues = document.getElementById("hudClues");
  const hudRisks = document.getElementById("hudRisks");
  const uploadPanel = document.getElementById("uploadPanel");
  const uploadStatusIcon = document.getElementById("uploadStatusIcon");
  const uploadStatusTitle = document.getElementById("uploadStatusTitle");
  const uploadStatusText = document.getElementById("uploadStatusText");
  const uploadProgressBar = document.getElementById("uploadProgressBar");
  const uploadProgressText = document.getElementById("uploadProgressText");
  const uploader = window.CyberSafetyUploader;

  const assetPaths = {
    player: "assets/player.png",
    assistant: "assets/assistant.png",
    clue: "assets/clue.png",
    risk: "assets/risk.png",
    terminal: "assets/terminal.png",
    reward: "assets/reward.png",
    map: "assets/training-base-map.png",
    patrol: "assets/patrol-bot.png",
  };

  const images = {};
  const imageReady = {};

  const levels = [
    {
      title: "隐私核心护送行动",
      short: "护送行动",
      goal: "依次收集三枚隐私密钥，避开巡逻机器人，把隐私核心送到安全终端。",
      start: { x: 155, y: 535 },
      terminal: { x: 806, y: 172 },
      clues: [
        { x: 286, y: 465, text: "密钥一：真实姓名和学校不能随意公开。" },
        { x: 510, y: 345, text: "密钥二：验证码是账号钥匙，不能告诉任何人。" },
        { x: 704, y: 238, text: "密钥三：照片背景也可能暴露位置。" },
      ],
      patrols: [
        {
          text: "风险巡逻：陌生网友诱导",
          speed: 88,
          points: [{ x: 335, y: 370 }, { x: 610, y: 260 }],
        },
        {
          text: "风险巡逻：假客服催促",
          speed: 104,
          points: [{ x: 470, y: 500 }, { x: 750, y: 385 }],
        },
      ],
      obstacles: [
        { x: 330, y: 185, w: 126, h: 72 },
        { x: 520, y: 390, w: 136, h: 76 },
        { x: 690, y: 286, w: 108, h: 72 },
      ],
      question: "陌生网友说送你游戏皮肤，同时索要验证码和家庭地址。最安全的做法是？",
      options: ["拒绝提供，退出对话并告诉家长或老师", "只给验证码，不给地址", "用同学的信息换取礼物"],
      correct: 0,
      hint: "验证码、地址和他人的信息都不能用来交换礼物。先停止对话，再向可信的大人求助。",
    },
  ];

  const state = {
    screen: "welcome",
    sessionId: "",
    studentCode: "",
    startedAt: "",
    endedAt: "",
    events: [],
    levelIndex: 0,
    level: null,
    player: { x: 155, y: 535 },
    checkpoint: { x: 155, y: 535 },
    keys: new Set(),
    score: 100,
    stars: 0,
    shieldActiveUntil: 0,
    shieldCooldownUntil: 0,
    shieldUses: 0,
    shieldBlocks: 0,
    invulnerableUntil: 0,
    hitFlashUntil: 0,
    shakeUntil: 0,
    consecutiveRiskContacts: 0,
    patrolDetections: 0,
    particles: [],
    missionStartedAt: 0,
    missionCompletedAt: 0,
    clicks: 0,
    errors: 0,
    levelsCompleted: 0,
    totalClues: 0,
    totalRisks: 0,
    totalDistance: 0,
    idleEpisodes: 0,
    agentOpens: 0,
    agentHelpChoices: 0,
    agentRetryChoices: 0,
    lastActivityAt: performance.now(),
    idleStage: 0,
    agentVisible: false,
    agentChoicePending: false,
    agentTriggerSeconds: 0,
    agentTriggerReason: "idle",
    lastAgentClosedAt: 0,
    interventionRecoverySeconds: [],
    lastMoveSampleAt: 0,
    lastMoveSamplePos: { x: 130, y: 480 },
    terminalCooldownUntil: 0,
    recordingChunks: [],
    recordingBlob: null,
    recorder: null,
    recordingStream: null,
    recordingMode: "not_started",
    recordingMime: "",
    recordingExtension: "webm",
    recordingProfile: "not_started",
    recordingStarted: false,
    recordingReadyPromise: null,
    resolveRecordingReady: null,
    assetLoadComplete: false,
    finalSummary: null,
    uploadPending: false,
    uploadSucceeded: false,
    uploadRetryTimer: 0,
  };

  function createSessionId() {
    const date = new Date();
    const pad = (value) => String(value).padStart(2, "0");
    const stamp = [
      date.getFullYear(),
      pad(date.getMonth() + 1),
      pad(date.getDate()),
      "_",
      pad(date.getHours()),
      pad(date.getMinutes()),
      pad(date.getSeconds()),
    ].join("");
    const random = Math.random().toString(16).slice(2, 10);
    return `${stamp}_${random}`;
  }

  function loadImages() {
    Object.entries(assetPaths).forEach(([key, src]) => {
      const img = new Image();
      img.onload = () => {
        imageReady[key] = true;
      };
      img.onerror = () => {
        imageReady[key] = false;
        showToast(`素材没有加载成功：${src}`, "warn");
      };
      img.src = src;
      images[key] = img;
    });
    setTimeout(() => {
      state.assetLoadComplete = true;
    }, 900);
  }

  function logEvent(type, data = {}) {
    const now = new Date();
    const event = {
      time_iso: now.toISOString(),
      session_id: state.sessionId || "not_started",
      student_code: state.studentCode || "not_set",
      phase: state.screen,
      level_index: state.levelIndex + 1,
      event_type: type,
      ...data,
    };
    state.events.push(event);
    persistSnapshot();
  }

  function persistSnapshot() {
    if (!state.sessionId) return;
    try {
      localStorage.setItem(
        `cyber_safety_session_${state.sessionId}`,
        JSON.stringify({ summary: buildSummary(false), events: state.events })
      );
    } catch {
      // Browser storage can be unavailable or full. The explicit download still works.
    }
  }

  function notifyActivity(source, shouldLog = false) {
    const now = performance.now();
    state.lastActivityAt = now;
    state.idleStage = 0;
    if (state.lastAgentClosedAt > 0 && source !== "agent_closed") {
      const recoverySeconds = Math.max(0, (now - state.lastAgentClosedAt) / 1000);
      state.interventionRecoverySeconds.push(recoverySeconds);
      state.lastAgentClosedAt = 0;
      logEvent("intervention_recovered", {
        source,
        recovery_seconds: Number(recoverySeconds.toFixed(2)),
      });
    }
    if (shouldLog) {
      logEvent("activity", { source });
    }
  }

  function setAssistant(text, subtitle = "") {
    assistantBubble.textContent = text;
    if (subtitle) {
      idleCountdown.textContent = subtitle;
    }
  }

  function showToast(message, kind = "info", ms = 2600) {
    const toast = document.createElement("div");
    toast.className = `toast ${kind}`;
    toast.textContent = message;
    toastRack.appendChild(toast);
    setTimeout(() => {
      toast.style.opacity = "0";
      toast.style.transform = "translateY(8px)";
      setTimeout(() => toast.remove(), 180);
    }, ms);
  }

  function updateHud() {
    const level = levels[state.levelIndex];
    hudPhase.textContent = phaseLabel();
    hudTitle.textContent = level && state.screen !== "welcome" ? level.title : "隐私核心护送行动";
    hudShield.textContent = `得分 ${state.score}`;
    hudLevel.textContent = state.screen === "end" ? `${state.stars} 星通关` : "护送进行中";
    const clueCount = state.level ? state.level.clues.filter((item) => item.collected).length : 0;
    const clueTotal = state.level ? state.level.clues.length : 0;
    hudClues.textContent = `密钥 ${clueCount}/${clueTotal || 3}`;
    const now = performance.now();
    if (now < state.shieldActiveUntil) {
      hudRisks.textContent = `护盾 ${Math.max(0, (state.shieldActiveUntil - now) / 1000).toFixed(1)}s`;
    } else if (now < state.shieldCooldownUntil) {
      hudRisks.textContent = `冷却 ${Math.ceil((state.shieldCooldownUntil - now) / 1000)}s`;
    } else {
      hudRisks.textContent = "空格：护盾就绪";
    }
  }

  function phaseLabel() {
    if (state.screen === "welcome") return "准备";
    if (state.screen === "complete") return "任务完成";
    if (state.screen === "end") return "完成";
    if (state.screen === "terminal") return "最终决策";
    return "潜行护送";
  }

  function startSession() {
    const assignment = uploader?.getAssignment?.() || { valid: false, studentCode: "" };
    const uploadDisabledForTest = new URLSearchParams(window.location.search).get("upload") === "off";
    if (!uploadDisabledForTest && !uploader?.isConfigured?.()) {
      showToast("云端保存尚未配置，请老师联系部署人员。", "danger", 5200);
      return;
    }
    if (!uploadDisabledForTest && !assignment.valid) {
      showToast("这个实验链接无效或缺少学生编号，请让老师重新打开专属链接。", "danger", 5600);
      return;
    }

    const code = assignment.studentCode || `DEMO-${Math.random().toString(36).slice(2, 6).toUpperCase()}`;
    studentCodeInput.value = code;

    state.sessionId = createSessionId();
    state.studentCode = code;
    state.startedAt = new Date().toISOString();
    state.screen = "game";
    notifyActivity("start");
    logEvent("session_started", {
      app: "web-game",
      mode: uploadDisabledForTest ? "teacher_demo" : "student_experiment",
      privacy_note: "anonymous_code_only_no_camera_no_microphone",
    });
    startGameRecording();
    startLevel(0);
  }

  function cloneLevel(level) {
    return {
      ...level,
      clues: level.clues.map((item, index) => ({ ...item, index, collected: false, pulse: 0 })),
      patrols: level.patrols.map((item, index) => ({
        ...item,
        index,
        x: item.points[0].x,
        y: item.points[0].y,
        targetIndex: 1,
        contactCooldownUntil: 0,
        detected: false,
      })),
      obstacles: level.obstacles.map((item) => ({ ...item })),
    };
  }

  function startLevel(index) {
    const level = cloneLevel(levels[index]);
    state.levelIndex = index;
    state.level = level;
    state.player.x = level.start.x;
    state.player.y = level.start.y;
    state.checkpoint = { ...level.start };
    state.missionStartedAt = performance.now();
    state.lastMoveSamplePos = { ...state.player };
    state.terminalCooldownUntil = 0;
    state.screen = "game";
    screenOverlay.classList.remove("visible");
    terminalPanel.classList.add("hidden");
    notifyActivity("level_started");
    setAssistant(level.goal, "12 秒无有效操作会自动接入智能体");
    logEvent("level_started", {
      level_id: index + 1,
      level_title: level.title,
      player_x: Math.round(state.player.x),
      player_y: Math.round(state.player.y),
    });
    showToast(`${level.short}开始：按空格开启护盾。`, "info", 3400);
    updateHud();
  }

  function openTerminal() {
    const now = performance.now();
    if (now < state.terminalCooldownUntil) return;

    const collected = state.level.clues.filter((item) => item.collected).length;
    if (collected < state.level.clues.length) {
      state.terminalCooldownUntil = now + 1800;
      logEvent("terminal_locked", {
        clue_count: collected,
        clue_total: state.level.clues.length,
      });
      showToast("安全终端未解锁：还需要隐私密钥。", "warn");
      setAssistant("沿着发光路径继续前进。密钥必须按顺序收集，必要时按空格开启护盾。", "终端未解锁");
      return;
    }

    state.screen = "terminal";
    terminalPanel.classList.remove("hidden");
    terminalKicker.textContent = "最终安全决策";
    terminalQuestion.textContent = state.level.question;
    terminalOptions.innerHTML = "";
    state.level.options.forEach((option, index) => {
      const button = document.createElement("button");
      button.className = "option-button";
      button.type = "button";
      button.textContent = option;
      button.addEventListener("click", () => answerTerminal(index));
      terminalOptions.appendChild(button);
    });
    notifyActivity("terminal_opened", true);
    logEvent("terminal_opened", {
      level_id: state.levelIndex + 1,
      clue_count: collected,
    });
    setAssistant("隐私核心已接入安全终端。完成最后一次安全判断即可通关。", "正在进行最终决策");
    updateHud();
  }

  function answerTerminal(index) {
    notifyActivity("terminal_answer", true);
    const correct = index === state.level.correct;
    logEvent("terminal_answer", {
      level_id: state.levelIndex + 1,
      selected_index: index,
      selected_text: state.level.options[index],
      correct,
    });

    const buttons = [...terminalOptions.querySelectorAll("button")];
    buttons.forEach((button, i) => {
      button.disabled = true;
      if (i === state.level.correct) button.classList.add("correct");
      if (i === index && !correct) button.classList.add("wrong");
    });

    if (!correct) {
      state.errors += 1;
      state.score = Math.max(0, state.score - 5);
      setAssistant(state.level.hint, "答错了也没关系，可以再试一次");
      showToast(state.level.hint, "warn");
      logEvent("wrong_attempt", {
        level_id: state.levelIndex + 1,
        hint: state.level.hint,
      });
      setTimeout(() => {
        terminalOptions.innerHTML = "";
        state.level.options.forEach((option, optionIndex) => {
          const button = document.createElement("button");
          button.className = "option-button";
          button.type = "button";
          button.textContent = option;
          button.addEventListener("click", () => answerTerminal(optionIndex));
          terminalOptions.appendChild(button);
        });
      }, 900);
      updateHud();
      return;
    }

    state.levelsCompleted += 1;
    state.missionCompletedAt = performance.now();
    const missionSeconds = (state.missionCompletedAt - state.missionStartedAt) / 1000;
    const timePenalty = Math.max(0, Math.floor((missionSeconds - 90) / 20) * 2);
    state.score = Math.max(0, state.score - timePenalty);
    state.stars = state.score >= 85 ? 3 : state.score >= 65 ? 2 : 1;
    logEvent("level_completed", {
      level_id: state.levelIndex + 1,
      score: state.score,
      stars: state.stars,
      move_distance: Math.round(state.totalDistance),
    });
    logEvent("mission_completed", {
      mission_seconds: Number(missionSeconds.toFixed(2)),
      score: state.score,
      stars: state.stars,
      risk_contacts: state.totalRisks,
      wrong_attempts: state.errors,
    });
    logEvent("demo_score", {
      base_score: 100,
      risk_penalty: state.totalRisks * 10,
      wrong_answer_penalty: state.errors * 5,
      time_penalty: timePenalty,
      final_score: state.score,
      stars: state.stars,
    });
    spawnCelebration();
    state.screen = "complete";
    showToast(`${state.stars} 星通关！隐私核心已安全送达。`, "info", 4200);
    setAssistant("护送完成！你成功识别了诱导、验证码和位置暴露风险。", `${state.stars} 星任务评价`);
    terminalPanel.classList.add("hidden");

    setTimeout(() => {
      finishSession();
    }, 1800);
  }

  async function finishSession() {
    if (state.screen === "end") return;
    state.screen = "end";
    state.endedAt = new Date().toISOString();
    state.uploadPending = true;
    showEndScreen();
    setUploadStatus("working", "正在整理游戏录像", "请不要关闭页面，录像生成后会自动保存到云端。", 0);
    await stopGameRecordingAndWait();
    state.finalSummary = buildSummary(true);
    logEvent("session_completed", state.finalSummary);
    state.finalSummary = buildSummary(true);
    showEndScreen();
    await beginAutomaticUpload();
  }

  function showEndScreen() {
    const summary = state.finalSummary || buildSummary(true);
    screenOverlay.classList.add("visible");
    codeRow.classList.add("hidden");
    quizBox.classList.add("hidden");
    terminalPanel.classList.add("hidden");
    screenKicker.textContent = "任务完成 · 数据自动保存";
    screenTitle.textContent = `${summary.stars} 星护送成功`;
    screenText.innerHTML = [
      `匿名编号：${escapeHtml(state.studentCode)}`,
      `最终得分：${summary.final_score}/100，任务评价：${summary.stars} 星`,
      `密钥：${summary.total_clues_collected}/3，风险接触：${summary.total_risk_contacts}，护盾使用：${summary.shield_use_count}`,
      `巡逻发现：${summary.patrol_detection_count}，智能体介入：${summary.agent_open_count}`,
    ].join("<br>");

    screenActions.innerHTML = "";
    uploadPanel.classList.remove("hidden");
    updateHud();
  }

  function setUploadStatus(status, title, message, progress = 0) {
    uploadPanel.classList.remove("hidden");
    uploadPanel.dataset.state = status;
    uploadStatusTitle.textContent = title;
    uploadStatusText.textContent = message;
    const percent = Math.max(0, Math.min(100, Math.round(progress * 100)));
    uploadProgressBar.style.width = `${percent}%`;
    uploadProgressText.textContent = `${percent}%`;
    const icons = { working: "☁", success: "✓", warning: "!", error: "!" };
    uploadStatusIcon.textContent = icons[status] || "☁";
  }

  function uploadFileLabel(file) {
    if (file === "events") return "行为序列";
    if (file === "summary") return "实验总结";
    return "游戏录像";
  }

  function handleUploadProgress(update) {
    if (update.phase === "uploading") {
      setUploadStatus("working", `正在上传${uploadFileLabel(update.file)}`, "数据会直接保存到老师的私有云空间。", update.progress || 0);
      return;
    }
    if (update.phase === "verifying") {
      setUploadStatus("working", "正在检查文件完整性", "三份文件全部确认后才会显示保存成功。", 1);
      return;
    }
    if (update.phase === "retry_wait") {
      const seconds = Math.max(1, Math.round((update.delayMs || 0) / 1000));
      setUploadStatus("warning", "网络不稳定，正在自动重试", `${seconds} 秒后继续上传，不需要学生操作。`, uploadProgressBar.style.width ? Number.parseFloat(uploadProgressBar.style.width) / 100 : 0);
    }
  }

  function buildUploadBundle() {
    return {
      sessionId: state.sessionId,
      studentCode: state.studentCode,
      summary: state.finalSummary || buildSummary(true),
      eventsText: toJsonl(state.events),
      recordingBlob: state.recordingBlob,
      recordingExtension: state.recordingExtension,
      recordingMime: state.recordingMime,
    };
  }

  async function beginAutomaticUpload() {
    const uploadDisabledForTest = new URLSearchParams(window.location.search).get("upload") === "off";
    if (uploadDisabledForTest) {
      state.uploadPending = false;
      showTeacherFallbackActions(false);
      setUploadStatus("warning", "测试模式未启用云端保存", "这些下载按钮只用于开发测试，正式学生链接不会显示。", 0);
      return;
    }

    try {
      const result = await uploader.queueAndUpload(buildUploadBundle(), handleUploadProgress);
      renderUploadComplete(result);
    } catch (error) {
      renderUploadFailure(error);
    }
  }

  function renderUploadComplete(result) {
    window.clearTimeout(state.uploadRetryTimer);
    state.uploadPending = false;
    state.uploadSucceeded = result?.status !== "saved_with_warning";
    screenActions.innerHTML = "";
    if (result?.status === "saved_with_warning") {
      setUploadStatus("warning", "日志和总结已保存", "本次录像没有生成，请把这个提示告诉老师。", 1);
      return;
    }
    setUploadStatus("success", "保存成功，可以关闭页面", "行为序列、实验总结和游戏录像都已安全上传。", 1);
  }

  function renderUploadFailure(error) {
    state.uploadPending = true;
    screenActions.innerHTML = "";
    setUploadStatus("error", "暂时没有保存成功，请叫老师", `系统会继续自动重试。错误：${error?.message || "网络连接失败"}`, 0);
    addAction("老师：立即重试", retryPendingUpload);
    addAction("老师：下载本地备份", async () => {
      try {
        await uploader.downloadPendingBackup();
      } catch {
        downloadCurrentSessionBackup();
      }
    }, "secondary");
    scheduleBackgroundRetry();
  }

  async function retryPendingUpload() {
    window.clearTimeout(state.uploadRetryTimer);
    screenActions.innerHTML = "";
    setUploadStatus("working", "正在重新连接云端", "请保持页面打开。", 0);
    try {
      const resumed = await uploader.resumePending(handleUploadProgress);
      if (!resumed) throw new Error("没有找到可恢复的本地数据");
      renderUploadComplete(resumed.result);
    } catch (error) {
      renderUploadFailure(error);
    }
  }

  function scheduleBackgroundRetry() {
    window.clearTimeout(state.uploadRetryTimer);
    const delay = Number(window.CYBER_UPLOAD_CONFIG?.backgroundRetryMs || 60000);
    state.uploadRetryTimer = window.setTimeout(retryPendingUpload, delay);
  }

  function downloadCurrentSessionBackup() {
    downloadFile(`session_${state.sessionId}.jsonl`, toJsonl(state.events), "application/x-ndjson");
    window.setTimeout(() => {
      downloadFile(`summary_${state.sessionId}.json`, JSON.stringify(state.finalSummary || buildSummary(true), null, 2), "application/json");
    }, 180);
    if (state.recordingBlob) {
      window.setTimeout(() => downloadBlob(`recording_${state.sessionId}.${state.recordingExtension}`, state.recordingBlob), 360);
    }
  }

  function showTeacherFallbackActions(includeRetry = true) {
    screenActions.innerHTML = "";
    if (includeRetry) addAction("老师：立即重试", retryPendingUpload);
    addAction("老师：下载行为日志", () => downloadFile(`session_${state.sessionId}.jsonl`, toJsonl(state.events), "application/x-ndjson"), "secondary");
    addAction("老师：下载实验总结", () => downloadFile(`summary_${state.sessionId}.json`, JSON.stringify(state.finalSummary || buildSummary(true), null, 2), "application/json"), "secondary");
    if (state.recordingBlob) {
      addAction(`老师：下载录像 ${state.recordingExtension.toUpperCase()}`, () => downloadBlob(`recording_${state.sessionId}.${state.recordingExtension}`, state.recordingBlob), "secondary");
    }
  }

  function addAction(label, handler, type = "primary") {
    const button = document.createElement("button");
    button.className = type === "primary" ? "primary-action" : "secondary-action";
    button.type = "button";
    button.textContent = label;
    button.addEventListener("click", handler);
    screenActions.appendChild(button);
  }

  function buildSummary(final) {
    const recoveryAverage = state.interventionRecoverySeconds.length > 0
      ? state.interventionRecoverySeconds.reduce((sum, value) => sum + value, 0) / state.interventionRecoverySeconds.length
      : null;
    const missionSeconds = state.missionStartedAt > 0
      ? ((state.missionCompletedAt || performance.now()) - state.missionStartedAt) / 1000
      : 0;
    return {
      schema_version: 1,
      session_id: state.sessionId,
      student_code: state.studentCode,
      started_at: state.startedAt,
      ended_at: final ? state.endedAt || new Date().toISOString() : state.endedAt,
      pretest_score: null,
      pretest_removed: true,
      posttest_score: null,
      posttest_removed: true,
      clicks: state.clicks,
      wrong_attempts: state.errors,
      levels_completed: state.levelsCompleted,
      total_clues_collected: state.totalClues,
      total_risk_contacts: state.totalRisks,
      total_move_distance: Math.round(state.totalDistance),
      final_score: state.score,
      stars: state.stars,
      mission_seconds: Number(missionSeconds.toFixed(2)),
      shield_use_count: state.shieldUses,
      shield_block_count: state.shieldBlocks,
      patrol_detection_count: state.patrolDetections,
      idle_episode_count: state.idleEpisodes,
      agent_open_count: state.agentOpens,
      agent_help_choice_count: state.agentHelpChoices,
      agent_retry_choice_count: state.agentRetryChoices,
      intervention_recovery_seconds: recoveryAverage === null ? null : Number(recoveryAverage.toFixed(2)),
      recording_available: Boolean(state.recordingBlob || state.recordingStarted),
      recording_mode: state.recordingMode,
      recording_mime: state.recordingMime,
      recording_extension: state.recordingExtension,
      recording_profile: state.recordingProfile,
      recording_bytes: state.recordingBlob ? state.recordingBlob.size : null,
      data_minimization: "anonymous_code_only_no_name_no_camera_no_microphone",
    };
  }

  function toJsonl(events) {
    return events.map((item) => JSON.stringify(item)).join("\n") + "\n";
  }

  function downloadFile(filename, text, type) {
    const blob = new Blob([text], { type });
    downloadBlob(filename, blob);
  }

  function downloadBlob(filename, blob) {
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }

  function escapeHtml(value) {
    return String(value)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#039;");
  }

  function createCompatibleRecorder(stream) {
    const profiles = [
      { mime: "video/mp4;codecs=avc1.42E01E", extension: "mp4", name: "mp4_h264_baseline" },
      { mime: "video/mp4;codecs=avc1.424028", extension: "mp4", name: "mp4_h264_level4" },
      { mime: "video/mp4", extension: "mp4", name: "mp4_browser_default" },
      { mime: "video/webm;codecs=vp8", extension: "webm", name: "webm_vp8" },
      { mime: "video/webm", extension: "webm", name: "webm_browser_default" },
    ];

    for (const profile of profiles) {
      if (!MediaRecorder.isTypeSupported(profile.mime)) continue;
      try {
        const recorder = new MediaRecorder(stream, {
          mimeType: profile.mime,
          videoBitsPerSecond: 4_000_000,
        });
        return { recorder, profile };
      } catch {
        // A browser may report support but still lack an encoder for this stream.
      }
    }

    throw new Error("no_compatible_recording_profile");
  }

  function beginMediaRecorder(stream, mode) {
    const { recorder, profile } = createCompatibleRecorder(stream);
    const mime = recorder.mimeType || profile.mime;
    state.recordingChunks = [];
    state.recordingReadyPromise = new Promise((resolve) => {
      state.resolveRecordingReady = resolve;
    });
    recorder.ondataavailable = (event) => {
      if (event.data && event.data.size > 0) {
        state.recordingChunks.push(event.data);
      }
    };
    recorder.onstop = () => {
      state.recordingBlob = new Blob(state.recordingChunks, { type: mime });
      logEvent("recording_ready", {
        bytes: state.recordingBlob.size,
        mime,
        mode: state.recordingMode,
        profile: state.recordingProfile,
      });
      state.resolveRecordingReady?.(state.recordingBlob);
      state.resolveRecordingReady = null;
    };
    recorder.start(1000);
    state.recorder = recorder;
    state.recordingStream = stream;
    state.recordingStarted = true;
    state.recordingMode = mode;
    state.recordingMime = mime;
    state.recordingExtension = profile.extension;
    state.recordingProfile = profile.name;
    logEvent("recording_started", {
      mode,
      mime,
      extension: profile.extension,
      profile: profile.name,
      video_bits_per_second: recorder.videoBitsPerSecond,
      audio: false,
    });
  }

  async function startGameRecording() {
    if (state.recordingStarted) return;
    if (new URLSearchParams(window.location.search).get("recording") === "off") {
      state.recordingMode = "disabled_for_test";
      state.recordingProfile = "disabled_for_test";
      logEvent("recording_unavailable", { reason: "disabled_by_query_parameter" });
      return;
    }
    if (!window.MediaRecorder) {
      state.recordingMode = "unavailable";
      logEvent("recording_unavailable", { reason: "mediarecorder_not_supported" });
      showToast("当前浏览器不支持录像，行为日志仍会保存。", "warn");
      return;
    }

    if (navigator.mediaDevices?.getDisplayMedia) {
      try {
        const stream = await navigator.mediaDevices.getDisplayMedia({
          video: {
            displaySurface: "browser",
            frameRate: { ideal: 12, max: 15 },
          },
          audio: false,
          preferCurrentTab: true,
          selfBrowserSurface: "include",
          surfaceSwitching: "exclude",
          monitorTypeSurfaces: "exclude",
        });
        const videoTrack = stream.getVideoTracks()[0];
        if (!videoTrack) throw new Error("screen_capture_has_no_video_track");
        beginMediaRecorder(stream, "current_tab_capture");
        videoTrack.addEventListener("ended", () => {
          if (state.recorder?.state !== "inactive") {
            state.recorder.stop();
            logEvent("recording_share_stopped_by_user", { mode: state.recordingMode });
          }
        });
        showToast("完整游戏界面正在录制，不包含声音。", "info", 3200);
        return;
      } catch (error) {
        logEvent("recording_permission_or_capture_failed", {
          reason: error.name || "display_capture_failed",
          message: error.message,
          fallback: "canvas_capture",
        });
        showToast("未启用标签页录制，已改用基础游戏画面录像。", "warn", 3600);
      }
    }

    startCanvasRecording();
  }

  function startCanvasRecording() {
    if (state.recordingStarted) return;
    if (!canvas.captureStream) {
      state.recordingMode = "unavailable";
      logEvent("recording_unavailable", {
        reason: "canvas_capture_not_supported",
      });
      showToast("当前浏览器不支持录像，行为日志仍会保存。", "warn");
      return;
    }

    try {
      const stream = canvas.captureStream(12);
      beginMediaRecorder(stream, "canvas_capture_fallback");
    } catch (error) {
      state.recordingMode = "unavailable";
      logEvent("recording_error", { message: error.message });
      showToast("录像启动失败，行为日志不受影响。", "warn");
    }
  }

  async function stopGameRecordingAndWait() {
    if (state.recorder && state.recorder.state !== "inactive") {
      try {
        state.recorder.stop();
        logEvent("recording_stopped", { mode: state.recordingMode });
      } catch (error) {
        logEvent("recording_stop_error", { message: error.message });
      }
    }
    if (state.recordingReadyPromise) {
      await Promise.race([
        state.recordingReadyPromise,
        new Promise((resolve) => window.setTimeout(resolve, 15000)),
      ]);
    }
    if (state.recordingStream) {
      state.recordingStream.getTracks().forEach((track) => track.stop());
      state.recordingStream = null;
    }
    return state.recordingBlob;
  }

  function showAgentOverlay(stageSeconds, triggerReason = "idle") {
    if (state.agentVisible) return;
    state.agentVisible = true;
    state.agentChoicePending = true;
    state.agentTriggerSeconds = stageSeconds;
    state.agentTriggerReason = triggerReason;
    state.agentOpens += 1;
    agentKicker.textContent = triggerReason === "risk_contacts" ? "连续遇到隐私风险" : `${stageSeconds} 秒无操作`;
    agentChoiceGate.classList.remove("hidden");
    cozeAgentMount.classList.add("hidden");
    agentFallback.classList.add("hidden");
    closeAgent.disabled = true;
    closeAgent.textContent = "请先选择";
    agentOverlay.classList.remove("hidden");
    window.requestAnimationFrame(() => agentOverlay.classList.add("visible"));
    setAssistant(
      triggerReason === "risk_contacts"
        ? "连续两次碰到巡逻风险。可以请守护助手给出路线提示。"
        : "你停了一会儿。请在右侧选择需要提示，还是自己再试一次。",
      "等待学生选择"
    );
    if (triggerReason === "idle") {
      logEvent("idle_or_stuck_episode", {
        idle_seconds: stageSeconds,
        detection_basis: "no_effective_game_activity",
      });
    }
    logEvent("agent_overlay_opened", {
      mode: "right_drawer_choice_gate",
      agent_source: "grade5_zhusi_sdk",
      idle_seconds: stageSeconds,
      trigger_reason: triggerReason,
    });
  }

  function handleAgentChoice(choice) {
    if (!state.agentVisible || !state.agentChoicePending) return;
    state.agentChoicePending = false;
    if (choice === "need_help") {
      state.agentHelpChoices += 1;
    } else {
      state.agentRetryChoices += 1;
    }
    closeAgent.disabled = false;
    closeAgent.textContent = "继续游戏";
    logEvent("agent_gate_choice", {
      choice,
      idle_seconds: state.agentTriggerSeconds,
      trigger_reason: state.agentTriggerReason,
      level_id: state.levelIndex + 1,
    });

    if (choice === "try_again") {
      setAssistant("好的，再观察巡逻路线。等待机器人远离，必要时按空格开启护盾。", "选择自己再试");
      hideAgentOverlay("try_again");
      return;
    }

    agentChoiceGate.classList.add("hidden");
    cozeAgentMount.classList.remove("hidden");
    agentFallback.classList.remove("hidden");
    setAssistant("助思智能体正在接入。你可以描述自己卡在哪里。", "正在接入智能体");
    logEvent("agent_sdk_requested", {
      mode: "right_drawer_sdk",
      agent_source: "grade5_zhusi_sdk",
    });

    if (window.CyberSafetyCozeAgent?.open) {
      window.CyberSafetyCozeAgent.open().then((result) => {
        if (!result?.ok) {
          logEvent("agent_sdk_load_failed", {
            mode: "right_drawer_sdk",
            agent_source: "grade5_zhusi_sdk",
            reason: result?.error || "unknown",
          });
        }
      });
    } else {
      logEvent("agent_sdk_load_failed", {
        mode: "right_drawer_sdk",
        agent_source: "grade5_zhusi_sdk",
        reason: "agent_module_missing",
      });
    }
  }

  function hideAgentOverlay(reason = "continue_game") {
    if (!state.agentVisible) return;
    if (state.agentChoicePending) {
      showToast("请先选择需要提示，还是自己再试一次。", "warn");
      return;
    }
    state.agentVisible = false;
    agentOverlay.classList.remove("visible");
    window.setTimeout(() => {
      if (!state.agentVisible) {
        agentOverlay.classList.add("hidden");
      }
    }, 260);
    if (window.CyberSafetyCozeAgent?.close) {
      window.CyberSafetyCozeAgent.close();
    }
    notifyActivity("agent_closed", true);
    state.lastAgentClosedAt = performance.now();
    logEvent("agent_overlay_closed", { reason });
    setAssistant("继续护送隐私核心。跟随发光路径收集下一枚密钥。", "已回到游戏");
  }

  function checkIdle(now) {
    const activePhase = state.screen === "game" || state.screen === "terminal";
    if (!activePhase) {
      idleCountdown.textContent = state.screen === "welcome" ? "正在等待演示开始" : "任务已完成";
      return;
    }

    if (state.agentVisible) {
      idleCountdown.textContent = "智能体正在接入";
      return;
    }

    const idleSeconds = Math.floor((now - state.lastActivityAt) / 1000);
    const nextStage = IDLE_STAGES[state.idleStage] || IDLE_STAGES[IDLE_STAGES.length - 1];
    const remaining = Math.max(0, nextStage - idleSeconds);
    idleCountdown.textContent = `停滞检测：${remaining} 秒后自动介入`;

    if (idleSeconds >= nextStage) {
      state.idleStage += 1;
      if (nextStage === IDLE_STAGES[0]) {
        state.idleEpisodes += 1;
        showAgentOverlay(nextStage, "idle");
      } else {
        logEvent("idle_stage_reached", {
          idle_seconds: nextStage,
          detection_basis: "no_effective_game_activity",
        });
        setAssistant(
          nextStage === IDLE_STAGES[1]
            ? "观察机器人来回巡逻的节奏，等它离开路线后再前进。"
            : "按空格可以开启短暂护盾，再沿发光路径前进。",
          `${nextStage} 秒停滞提示`
        );
      }
    }
  }

  function updateGame(dt, now) {
    if (state.screen !== "game" || state.agentVisible) return;

    updatePatrols(dt, now);

    const direction = { x: 0, y: 0 };
    if (state.keys.has("ArrowLeft") || state.keys.has("KeyA")) direction.x -= 1;
    if (state.keys.has("ArrowRight") || state.keys.has("KeyD")) direction.x += 1;
    if (state.keys.has("ArrowUp") || state.keys.has("KeyW")) direction.y -= 1;
    if (state.keys.has("ArrowDown") || state.keys.has("KeyS")) direction.y += 1;

    const length = Math.hypot(direction.x, direction.y);
    if (length > 0) {
      direction.x /= length;
      direction.y /= length;
      const speed = 245;
      const oldX = state.player.x;
      const oldY = state.player.y;
      const nextX = clamp(oldX + direction.x * speed * dt, WORLD.x + 32, WORLD.x + WORLD.w - 32);
      const nextY = clamp(oldY + direction.y * speed * dt, WORLD.y + 38, WORLD.y + WORLD.h - 34);
      if (!collidesWithObstacle(nextX, oldY)) state.player.x = nextX;
      if (!collidesWithObstacle(state.player.x, nextY)) state.player.y = nextY;
      const moved = Math.hypot(state.player.x - oldX, state.player.y - oldY);
      if (moved > 0.1) {
        state.totalDistance += moved;
        notifyActivity("player_moved");
        maybeLogMoveSample(now);
      }
    }

    collectClues();
    if (distance(state.player, state.level.terminal) < 58) {
      openTerminal();
    }
  }

  function collidesWithObstacle(x, y) {
    const radius = 25;
    return state.level.obstacles.some((obstacle) => {
      const closestX = clamp(x, obstacle.x, obstacle.x + obstacle.w);
      const closestY = clamp(y, obstacle.y, obstacle.y + obstacle.h);
      return Math.hypot(x - closestX, y - closestY) < radius;
    });
  }

  function activateShield(now = performance.now()) {
    if (state.screen !== "game" || state.agentVisible) return;
    if (now < state.shieldActiveUntil) return;
    if (now < state.shieldCooldownUntil) {
      showToast(`护盾还需 ${Math.ceil((state.shieldCooldownUntil - now) / 1000)} 秒冷却。`, "warn", 1500);
      return;
    }
    state.shieldActiveUntil = now + SHIELD_DURATION_MS;
    state.shieldCooldownUntil = now + SHIELD_COOLDOWN_MS;
    state.shieldUses += 1;
    notifyActivity("shield_activated", true);
    logEvent("shield_activated", {
      duration_seconds: SHIELD_DURATION_MS / 1000,
      cooldown_seconds: SHIELD_COOLDOWN_MS / 1000,
      player_x: Math.round(state.player.x),
      player_y: Math.round(state.player.y),
    });
    spawnBurst(state.player.x, state.player.y, "#52d9ff", 18);
    setAssistant("隐私护盾已开启！现在可以安全穿过巡逻机器人的侦测区。", "护盾生效 2.5 秒");
    showToast("隐私护盾启动！", "info", 1800);
  }

  function updatePatrols(dt, now) {
    state.level.patrols.forEach((patrol) => {
      const target = patrol.points[patrol.targetIndex];
      const dx = target.x - patrol.x;
      const dy = target.y - patrol.y;
      const length = Math.hypot(dx, dy);
      if (length < 5) {
        patrol.targetIndex = patrol.targetIndex === 0 ? 1 : 0;
      } else {
        const step = Math.min(length, patrol.speed * dt);
        patrol.x += (dx / length) * step;
        patrol.y += (dy / length) * step;
      }

      const playerDistance = distance(state.player, patrol);
      const isDetected = playerDistance < 112;
      if (isDetected && !patrol.detected) {
        patrol.detected = true;
        state.patrolDetections += 1;
        logEvent("patrol_detected", {
          patrol_id: patrol.index + 1,
          patrol_text: patrol.text,
          distance: Math.round(playerDistance),
          player_x: Math.round(state.player.x),
          player_y: Math.round(state.player.y),
        });
      } else if (!isDetected && playerDistance > 132) {
        patrol.detected = false;
      }

      if (playerDistance < 48 && now >= patrol.contactCooldownUntil) {
        handlePatrolContact(patrol, now);
      }
    });
  }

  function handlePatrolContact(patrol, now) {
    patrol.contactCooldownUntil = now + 2200;
    if (now < state.shieldActiveUntil) {
      state.shieldBlocks += 1;
      logEvent("shield_blocked", {
        patrol_id: patrol.index + 1,
        patrol_text: patrol.text,
        player_x: Math.round(state.player.x),
        player_y: Math.round(state.player.y),
      });
      spawnBurst(state.player.x, state.player.y, "#ffd166", 22);
      showToast("护盾成功挡住风险！", "info", 1700);
      return;
    }
    if (now < state.invulnerableUntil) return;

    state.totalRisks += 1;
    state.consecutiveRiskContacts += 1;
    state.score = Math.max(0, state.score - 10);
    state.invulnerableUntil = now + 2500;
    state.hitFlashUntil = now + 900;
    state.shakeUntil = now + 500;
    notifyActivity("risk_contacted", true);
    logEvent("risk_contacted", {
      level_id: 1,
      risk_index: patrol.index,
      risk_text: patrol.text,
      score_after: state.score,
      checkpoint_x: Math.round(state.checkpoint.x),
      checkpoint_y: Math.round(state.checkpoint.y),
    });
    spawnBurst(state.player.x, state.player.y, "#ff6b6b", 28);
    state.player.x = state.checkpoint.x;
    state.player.y = state.checkpoint.y;
    setAssistant("被巡逻机器人发现了。已返回最近检查点，观察路线或按空格开启护盾。", "风险接触，扣 10 分");
    showToast("隐私核心被发现，返回检查点！", "danger", 2600);

    if (state.consecutiveRiskContacts >= 2) {
      state.consecutiveRiskContacts = 0;
      showAgentOverlay(0, "risk_contacts");
    }
  }

  function maybeLogMoveSample(now) {
    if (now - state.lastMoveSampleAt < 1500) return;
    state.lastMoveSampleAt = now;
    const from = state.lastMoveSamplePos;
    const sampleDistance = Math.hypot(state.player.x - from.x, state.player.y - from.y);
    state.lastMoveSamplePos = { ...state.player };
    logEvent("player_move_sample", {
      player_x: Math.round(state.player.x),
      player_y: Math.round(state.player.y),
      sample_distance: Math.round(sampleDistance),
    });
  }

  function collectClues() {
    const clue = state.level.clues.find((item) => !item.collected);
    if (!clue || distance(state.player, clue) >= 54) return;

    clue.collected = true;
    clue.pulse = 1;
    state.totalClues += 1;
    state.checkpoint = { x: clue.x, y: clue.y };
    state.consecutiveRiskContacts = 0;
    notifyActivity("clue_collected", true);
    logEvent("clue_collected", {
      level_id: 1,
      clue_index: clue.index,
      clue_text: clue.text,
      player_x: Math.round(state.player.x),
      player_y: Math.round(state.player.y),
    });
    logEvent("checkpoint_reached", {
      checkpoint_index: clue.index + 1,
      checkpoint_x: Math.round(clue.x),
      checkpoint_y: Math.round(clue.y),
    });
    spawnBurst(clue.x, clue.y, "#ffd166", 24);
    const remaining = state.level.clues.filter((item) => !item.collected).length;
    setAssistant(clue.text, remaining > 0 ? `检查点已保存，还差 ${remaining} 枚密钥` : "安全终端已解锁");
    showToast(remaining > 0 ? `获得隐私密钥 ${clue.index + 1}/3` : "三枚密钥集齐，前往安全终端！");
    updateHud();
  }

  function render(now) {
    drawStageBackground(now);
    ctx.save();
    if (now < state.shakeUntil) {
      ctx.translate(Math.sin(now * 0.08) * 5, Math.cos(now * 0.11) * 4);
    }
    if (state.level) drawWorld(now);
    else drawAttractWorld(now);
    ctx.restore();
    drawParticles(now);

    if (now < state.hitFlashUntil) {
      const alpha = ((state.hitFlashUntil - now) / 900) * 0.24;
      ctx.save();
      ctx.fillStyle = `rgba(255, 78, 92, ${alpha})`;
      ctx.fillRect(WORLD.x, WORLD.y, WORLD.w, WORLD.h);
      ctx.restore();
    }
    updateHud();
  }

  function drawStageBackground(now) {
    ctx.fillStyle = "#dff7f2";
    ctx.fillRect(0, 0, GAME_WIDTH, GAME_HEIGHT);

    ctx.save();
    ctx.globalAlpha = 0.28;
    ctx.fillStyle = "#89ddd0";
    for (let i = 0; i < 26; i += 1) {
      const x = (i * 191 + now * 0.01) % (GAME_WIDTH + 80) - 40;
      const y = 88 + ((i * 67) % 600);
      ctx.beginPath();
      ctx.arc(x, y, i % 3 === 0 ? 5 : 3, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.restore();
  }

  function drawAttractWorld(now) {
    drawMapFrame();
    drawMapBackdrop();
    drawGlow(758, 228, 58, "rgba(64, 196, 255, 0.25)");
    drawTerminal({ x: 758, y: 228 }, now, 0.55);
    drawAsset("patrol", 586, 308, 78, now, 0.9);
    drawAsset("clue", 430, 390, 74, now, 1);
    drawAsset("reward", 235, 457, 48, now, 1);
    drawAsset("player", 270, 430, 86, now, 1);
  }

  function drawWorld(now) {
    drawMapFrame();
    drawMapBackdrop();
    drawLevelRoute(now);
    drawObstacles();

    state.level.clues.forEach((clue) => {
      const nextClue = state.level.clues.find((item) => !item.collected);
      const isCurrent = nextClue === clue;
      if (!clue.collected) {
        drawGlow(clue.x, clue.y, isCurrent ? 58 : 42, isCurrent ? "rgba(255, 201, 48, 0.42)" : "rgba(120, 155, 170, 0.18)");
        drawAsset("clue", clue.x, clue.y, isCurrent ? 70 : 58, now, isCurrent ? 1 : 0.38);
        drawNumberBadge(clue.index + 1, clue.x + 27, clue.y - 30, isCurrent);
      } else {
        drawCollectedMark(clue.x, clue.y);
      }
    });

    state.level.patrols.forEach((patrol) => {
      drawPatrol(patrol, now);
    });

    drawTerminal(state.level.terminal, now, state.level.clues.every((item) => item.collected) ? 1 : 0.72);
    drawPrivacyCore(now);
    drawPlayer(now);

    if (state.screen === "complete") {
      ctx.save();
      roundedRectPath(WORLD.x + 196, WORLD.y + 190, 454, 112, 8);
      ctx.fillStyle = "rgba(255, 255, 255, 0.94)";
      ctx.fill();
      ctx.strokeStyle = "#28b99a";
      ctx.lineWidth = 4;
      ctx.stroke();
      ctx.fillStyle = "#153e53";
      ctx.font = "900 34px Microsoft YaHei, sans-serif";
      ctx.textAlign = "center";
      ctx.fillText("隐私核心安全送达！", WORLD.x + WORLD.w / 2, WORLD.y + 238);
      ctx.fillStyle = "#17806c";
      ctx.font = "800 20px Microsoft YaHei, sans-serif";
      ctx.fillText(`${state.stars} 星评价 · 得分 ${state.score}`, WORLD.x + WORLD.w / 2, WORLD.y + 274);
      ctx.restore();
    }
  }

  function drawMapFrame() {
    ctx.save();
    roundedRectPath(WORLD.x - 5, WORLD.y - 5, WORLD.w + 10, WORLD.h + 10, 8);
    ctx.fillStyle = "rgba(255, 255, 255, 0.94)";
    ctx.fill();
    ctx.strokeStyle = "rgba(37, 139, 126, 0.32)";
    ctx.lineWidth = 2;
    ctx.stroke();
    ctx.restore();
  }

  function drawMapBackdrop() {
    ctx.save();
    ctx.beginPath();
    ctx.rect(WORLD.x, WORLD.y, WORLD.w, WORLD.h);
    ctx.clip();
    if (imageReady.map) {
      const image = images.map;
      const sourceAspect = image.width / image.height;
      const targetAspect = WORLD.w / WORLD.h;
      let sx = 0;
      let sy = 0;
      let sw = image.width;
      let sh = image.height;
      if (sourceAspect > targetAspect) {
        sw = image.height * targetAspect;
        sx = (image.width - sw) / 2;
      } else {
        sh = image.width / targetAspect;
        sy = (image.height - sh) / 2;
      }
      ctx.drawImage(image, sx, sy, sw, sh, WORLD.x, WORLD.y, WORLD.w, WORLD.h);
    } else {
      ctx.fillStyle = "#bcebd7";
      ctx.fillRect(WORLD.x, WORLD.y, WORLD.w, WORLD.h);
    }
    ctx.fillStyle = "rgba(255, 255, 255, 0.06)";
    ctx.fillRect(WORLD.x, WORLD.y, WORLD.w, WORLD.h);
    ctx.restore();
  }

  function drawLevelRoute(now) {
    const points = [state.level.start, ...state.level.clues, state.level.terminal];
    ctx.save();
    ctx.lineWidth = 11;
    ctx.lineJoin = "round";
    ctx.strokeStyle = "rgba(255, 255, 255, 0.72)";
    ctx.beginPath();
    points.forEach((point, index) => {
      if (index === 0) ctx.moveTo(point.x, point.y);
      else ctx.lineTo(point.x, point.y);
    });
    ctx.stroke();

    ctx.lineWidth = 5;
    ctx.strokeStyle = "rgba(21, 177, 145, 0.84)";
    ctx.setLineDash([12, 14]);
    ctx.lineDashOffset = -now * 0.04;
    ctx.beginPath();
    points.forEach((point, index) => {
      if (index === 0) ctx.moveTo(point.x, point.y);
      else ctx.lineTo(point.x, point.y);
    });
    ctx.stroke();
    ctx.restore();
  }

  function drawObstacles() {
    ctx.save();
    state.level.obstacles.forEach((obstacle, index) => {
      roundedRectPath(obstacle.x, obstacle.y, obstacle.w, obstacle.h, 8);
      ctx.fillStyle = index % 2 === 0 ? "rgba(36, 129, 145, 0.28)" : "rgba(72, 151, 104, 0.3)";
      ctx.fill();
      ctx.strokeStyle = "rgba(255, 255, 255, 0.82)";
      ctx.lineWidth = 3;
      ctx.stroke();
      ctx.fillStyle = "rgba(17, 92, 103, 0.78)";
      ctx.fillRect(obstacle.x + 12, obstacle.y + 15, obstacle.w - 24, 8);
      ctx.fillRect(obstacle.x + 12, obstacle.y + obstacle.h - 23, obstacle.w - 24, 8);
    });
    ctx.restore();
  }

  function drawPatrol(patrol, now) {
    const detectedAlpha = patrol.detected ? 0.26 + Math.sin(now * 0.012) * 0.06 : 0.1;
    ctx.save();
    ctx.strokeStyle = patrol.detected ? "rgba(255, 72, 86, 0.68)" : "rgba(255, 134, 92, 0.36)";
    ctx.lineWidth = patrol.detected ? 3 : 2;
    ctx.setLineDash([8, 9]);
    ctx.beginPath();
    ctx.moveTo(patrol.points[0].x, patrol.points[0].y);
    ctx.lineTo(patrol.points[1].x, patrol.points[1].y);
    ctx.stroke();
    ctx.setLineDash([]);
    ctx.fillStyle = `rgba(255, 72, 86, ${detectedAlpha})`;
    ctx.strokeStyle = patrol.detected ? "rgba(255, 72, 86, 0.8)" : "rgba(255, 134, 92, 0.45)";
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.arc(patrol.x, patrol.y, 112, 0, Math.PI * 2);
    ctx.fill();
    ctx.stroke();
    ctx.restore();
    drawAsset("patrol", patrol.x, patrol.y, patrol.detected ? 78 : 70, now, 1);
    if (patrol.detected) drawNumberBadge("!", patrol.x + 30, patrol.y - 34, false, true);
  }

  function drawPrivacyCore(now) {
    const coreX = state.player.x - 36;
    const coreY = state.player.y + 27;
    ctx.save();
    ctx.strokeStyle = "rgba(62, 212, 184, 0.86)";
    ctx.lineWidth = 4;
    ctx.setLineDash([6, 7]);
    ctx.lineDashOffset = -now * 0.035;
    ctx.beginPath();
    ctx.moveTo(coreX, coreY);
    ctx.lineTo(state.player.x - 8, state.player.y + 8);
    ctx.stroke();
    ctx.restore();
    drawGlow(coreX, coreY, 34, "rgba(255, 218, 72, 0.34)");
    drawAsset("reward", coreX, coreY, 48, now, 1);
  }

  function drawPlayer(now) {
    const active = now < state.shieldActiveUntil;
    const flashing = now < state.invulnerableUntil && Math.floor(now / 120) % 2 === 0;
    if (active) {
      ctx.save();
      ctx.strokeStyle = "rgba(46, 207, 255, 0.92)";
      ctx.lineWidth = 7;
      ctx.beginPath();
      ctx.arc(state.player.x, state.player.y, 49 + Math.sin(now * 0.012) * 4, 0, Math.PI * 2);
      ctx.stroke();
      ctx.strokeStyle = "rgba(255, 224, 92, 0.88)";
      ctx.lineWidth = 3;
      ctx.beginPath();
      ctx.arc(state.player.x, state.player.y, 58 + Math.cos(now * 0.01) * 3, 0, Math.PI * 2);
      ctx.stroke();
      ctx.restore();
    }
    drawAsset("player", state.player.x, state.player.y, 78, now, flashing ? 0.35 : 1);
  }

  function drawNumberBadge(value, x, y, current = false, danger = false) {
    ctx.save();
    ctx.fillStyle = danger ? "#ff4856" : current ? "#ffc930" : "#7896a5";
    ctx.strokeStyle = "#ffffff";
    ctx.lineWidth = 3;
    ctx.beginPath();
    ctx.arc(x, y, 17, 0, Math.PI * 2);
    ctx.fill();
    ctx.stroke();
    ctx.fillStyle = danger ? "#ffffff" : "#17364a";
    ctx.font = "900 18px Microsoft YaHei, sans-serif";
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.fillText(String(value), x, y + 1);
    ctx.restore();
  }

  function drawAsset(name, x, y, size, now, alpha = 1) {
    const bob = Math.sin(now * 0.004 + x * 0.01) * 4;
    ctx.save();
    ctx.globalAlpha = alpha;
    if (imageReady[name]) {
      ctx.drawImage(images[name], x - size / 2, y - size / 2 + bob, size, size);
    } else {
      ctx.fillStyle = name === "risk" || name === "patrol" ? "#ff6b6b" : name === "clue" ? "#ffd166" : "#52d9ff";
      ctx.beginPath();
      ctx.arc(x, y + bob, size * 0.35, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.restore();
  }

  function drawTerminal(point, now, alpha) {
    drawGlow(point.x, point.y, 52, alpha > 0.9 ? "rgba(82, 217, 255, 0.26)" : "rgba(120, 130, 145, 0.18)");
    drawAsset("terminal", point.x, point.y, 82, now, alpha);
  }

  function drawCollectedMark(x, y) {
    ctx.save();
    ctx.fillStyle = "rgba(99, 245, 199, 0.18)";
    ctx.strokeStyle = "rgba(99, 245, 199, 0.7)";
    ctx.lineWidth = 3;
    ctx.beginPath();
    ctx.arc(x, y, 20, 0, Math.PI * 2);
    ctx.fill();
    ctx.stroke();
    ctx.strokeStyle = "#63f5c7";
    ctx.lineWidth = 4;
    ctx.beginPath();
    ctx.moveTo(x - 9, y);
    ctx.lineTo(x - 2, y + 8);
    ctx.lineTo(x + 12, y - 11);
    ctx.stroke();
    ctx.restore();
  }

  function drawGlow(x, y, radius, color) {
    ctx.save();
    const gradient = ctx.createRadialGradient(x, y, 0, x, y, radius);
    gradient.addColorStop(0, color);
    gradient.addColorStop(1, "rgba(0, 0, 0, 0)");
    ctx.fillStyle = gradient;
    ctx.beginPath();
    ctx.arc(x, y, radius, 0, Math.PI * 2);
    ctx.fill();
    ctx.restore();
  }

  function spawnBurst(x, y, color, count = 18) {
    const now = performance.now();
    for (let index = 0; index < count; index += 1) {
      const angle = (Math.PI * 2 * index) / count + Math.random() * 0.28;
      const speed = 55 + Math.random() * 125;
      state.particles.push({
        x,
        y,
        color,
        vx: Math.cos(angle) * speed,
        vy: Math.sin(angle) * speed - 28,
        born: now,
        life: 560 + Math.random() * 520,
        size: 3 + Math.random() * 6,
        square: Math.random() > 0.48,
      });
    }
  }

  function spawnCelebration() {
    const terminal = state.level?.terminal || { x: WORLD.x + WORLD.w / 2, y: WORLD.y + WORLD.h / 2 };
    spawnBurst(terminal.x, terminal.y, "#ffd54a", 42);
    spawnBurst(terminal.x - 90, terminal.y + 55, "#38d7b4", 30);
    spawnBurst(terminal.x + 62, terminal.y + 72, "#4cb7ff", 30);
  }

  function drawParticles(now) {
    state.particles = state.particles.filter((particle) => now - particle.born < particle.life);
    ctx.save();
    ctx.beginPath();
    ctx.rect(WORLD.x, WORLD.y, WORLD.w, WORLD.h);
    ctx.clip();
    state.particles.forEach((particle) => {
      const elapsed = (now - particle.born) / 1000;
      const progress = (now - particle.born) / particle.life;
      const x = particle.x + particle.vx * elapsed;
      const y = particle.y + particle.vy * elapsed + 125 * elapsed * elapsed;
      ctx.globalAlpha = Math.max(0, 1 - progress);
      ctx.fillStyle = particle.color;
      if (particle.square) {
        ctx.fillRect(x - particle.size / 2, y - particle.size / 2, particle.size, particle.size);
      } else {
        ctx.beginPath();
        ctx.arc(x, y, particle.size / 2, 0, Math.PI * 2);
        ctx.fill();
      }
    });
    ctx.restore();
  }

  function roundedRectPath(x, y, width, height, radius) {
    const r = Math.min(radius, width / 2, height / 2);
    ctx.beginPath();
    ctx.moveTo(x + r, y);
    ctx.lineTo(x + width - r, y);
    ctx.quadraticCurveTo(x + width, y, x + width, y + r);
    ctx.lineTo(x + width, y + height - r);
    ctx.quadraticCurveTo(x + width, y + height, x + width - r, y + height);
    ctx.lineTo(x + r, y + height);
    ctx.quadraticCurveTo(x, y + height, x, y + height - r);
    ctx.lineTo(x, y + r);
    ctx.quadraticCurveTo(x, y, x + r, y);
    ctx.closePath();
  }

  function clamp(value, min, max) {
    return Math.max(min, Math.min(max, value));
  }

  function distance(a, b) {
    return Math.hypot(a.x - b.x, a.y - b.y);
  }

  let lastFrame = performance.now();
  function loop(now) {
    const dt = Math.min(0.035, (now - lastFrame) / 1000);
    lastFrame = now;
    updateGame(dt, now);
    checkIdle(now);
    render(now);
    requestAnimationFrame(loop);
  }

  function prepareAssignmentUi() {
    const assignment = uploader?.getAssignment?.();
    if (!assignment?.valid) return;
    studentCodeInput.value = assignment.studentCode;
    screenText.innerHTML = [
      `你的匿名编号是：<strong>${escapeHtml(assignment.studentCode)}</strong>` ,
      "完成任务后，行为序列、实验总结和游戏录像会自动保存。",
      "看到“保存成功，可以关闭页面”之前，请不要关闭网页。",
    ].join("<br>");
    primaryAction.textContent = "开始护送并自动保存";
  }

  async function resumePendingOnLoad() {
    if (!uploader?.isConfigured?.()) return;
    try {
      const record = await uploader.getPendingForAssignment();
      if (!record || record.status === "complete") return;
      state.sessionId = record.sessionId;
      state.studentCode = record.studentCode;
      state.startedAt = record.summary?.started_at || record.createdAt;
      state.endedAt = record.summary?.ended_at || record.createdAt;
      state.finalSummary = record.summary || null;
      state.recordingExtension = record.recordingExtension || "webm";
      state.recordingMime = record.recordingMime || "video/webm";
      state.screen = "end";
      state.uploadPending = true;
      showEndScreen();
      setUploadStatus("working", "发现尚未完成的本地数据", "正在从上次中断的位置继续上传。", 0);
      await retryPendingUpload();
    } catch (error) {
      if (state.screen === "end") renderUploadFailure(error);
    }
  }

  primaryAction.addEventListener("click", startSession);
  closeAgent.addEventListener("click", () => hideAgentOverlay("continue_game"));
  agentNeedHelp.addEventListener("click", () => handleAgentChoice("need_help"));
  agentTryAgain.addEventListener("click", () => handleAgentChoice("try_again"));

  document.addEventListener("pointerdown", (event) => {
    state.clicks += 1;
    const target = event.target;
    const tag = target && target.tagName ? target.tagName.toLowerCase() : "unknown";
    if (!agentOverlay.contains(target)) {
      notifyActivity("pointer_down");
    }
    if (state.sessionId) {
      logEvent("click", {
        tag,
        id: target && target.id ? target.id : "",
        class_name: target && target.className ? String(target.className).slice(0, 80) : "",
      });
    }
  });

  window.addEventListener("keydown", (event) => {
    if (["ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight", "Space"].includes(event.code)) {
      event.preventDefault();
    }
    state.keys.add(event.code);
    if (event.code === "Space" && !event.repeat) {
      activateShield();
    }
    if (state.screen === "game" || state.screen === "terminal") {
      notifyActivity("key_down");
    }
  });

  window.addEventListener("keyup", (event) => {
    state.keys.delete(event.code);
  });

  window.addEventListener("beforeunload", (event) => {
    if (state.sessionId && state.screen !== "end") {
      logEvent("session_abandoned", buildSummary(false));
    }
    if (state.uploadPending || uploader?.hasPending?.()) {
      event.preventDefault();
      event.returnValue = "";
    }
  });

  prepareAssignmentUi();
  loadImages();
  updateHud();
  resumePendingOnLoad();
  requestAnimationFrame(loop);
})();
