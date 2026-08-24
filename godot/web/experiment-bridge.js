(() => {
  "use strict";

  const DB_NAME = "ai-training-ground-study-v2";
  const STORE_NAME = "sessions";
  const config = window.GODOT_EXPERIMENT_CONFIG || {};
  const conditions = new Set(["active", "passive"]);
  const state = {
    consent: config.productionMode ? "pending" : "accepted",
    assignment: parseAssignment(),
    sessionId: "",
    events: [],
    recorder: null,
    stream: null,
    chunks: [],
    recordingBlob: null,
    recordingMime: "",
    recordingExtension: "webm",
    recordingStatus: "not_started",
    stopPromise: null,
    stopResolve: null,
    activeRecord: null,
    uploadStarted: false,
  };

  function decodeTicketPayload(ticket) {
    try {
      const encoded = String(ticket || "").split(".")[0];
      if (!encoded) return null;
      const base64 = encoded.replace(/-/g, "+").replace(/_/g, "/");
      const padded = base64.padEnd(Math.ceil(base64.length / 4) * 4, "=");
      const bytes = Uint8Array.from(atob(padded), (character) => character.charCodeAt(0));
      return JSON.parse(new TextDecoder().decode(bytes));
    } catch {
      return null;
    }
  }

  function parseAssignment() {
    const params = new URLSearchParams(window.location.search);
    const ticket = params.get("ticket") || "";
    const payload = decodeTicketPayload(ticket);
    const valid = Boolean(
      ticket
      && payload
      && payload.v === 2
      && conditions.has(payload.condition)
      && payload.study_version
      && payload.class_id
      && payload.student_code
      && payload.upload_id
      && Number(payload.exp || 0) > Math.floor(Date.now() / 1000)
    );
    return {
      valid,
      ticket,
      study_version: valid ? String(payload.study_version) : "",
      condition: valid ? String(payload.condition) : "unassigned",
      class_id: valid ? String(payload.class_id) : "",
      student_code: valid ? String(payload.student_code) : "",
      upload_id: valid ? String(payload.upload_id) : "",
      expires_at: valid ? Number(payload.exp || 0) : 0,
    };
  }

  function apiBases() {
    return [config.primaryApiBaseUrl, config.fallbackApiBaseUrl]
      .map((value) => String(value || "").trim().replace(/\/+$/, ""))
      .filter((value, index, values) => value && values.indexOf(value) === index);
  }

  async function apiRequest(path, body) {
    let lastError = null;
    for (const base of apiBases()) {
      try {
        const response = await fetch(base + path, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(body),
        });
        let payload = {};
        try {
          payload = await response.json();
        } catch {
          payload = {};
        }
        if (response.ok) return { ...payload, api_base_url: base };
        const error = new Error(payload.message || payload.code || "api_" + response.status);
        error.code = payload.code || "api_" + response.status;
        error.status = response.status;
        if (response.status < 500) throw error;
        lastError = error;
      } catch (error) {
        if (Number(error.status || 0) > 0 && Number(error.status) < 500) throw error;
        lastError = error;
      }
    }
    throw lastError || new Error("api_unavailable");
  }

  function openDatabase() {
    return new Promise((resolve, reject) => {
      if (!window.indexedDB) {
        reject(new Error("indexeddb_unavailable"));
        return;
      }
      const request = indexedDB.open(DB_NAME, 1);
      request.onupgradeneeded = () => {
        if (!request.result.objectStoreNames.contains(STORE_NAME)) {
          request.result.createObjectStore(STORE_NAME, { keyPath: "id" });
        }
      };
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error || new Error("indexeddb_open_failed"));
    });
  }

  async function withStore(mode, operation) {
    const database = await openDatabase();
    try {
      return await new Promise((resolve, reject) => {
        const transaction = database.transaction(STORE_NAME, mode);
        const request = operation(transaction.objectStore(STORE_NAME));
        request.onsuccess = () => resolve(request.result);
        request.onerror = () => reject(request.error || new Error("indexeddb_request_failed"));
      });
    } finally {
      database.close();
    }
  }

  async function saveRecord(record) {
    state.activeRecord = record;
    try {
      await withStore("readwrite", (store) => store.put(record));
    } catch (error) {
      record.persistence_error = String(error.message || error);
    }
  }

  async function loadRecord(id) {
    if (!id) return null;
    try {
      return (await withStore("readonly", (store) => store.get(id))) || null;
    } catch {
      return null;
    }
  }

  async function deleteRecord(id) {
    try {
      await withStore("readwrite", (store) => store.delete(id));
    } catch {
      // A completed server manifest is authoritative even if local cleanup fails.
    }
    if (state.activeRecord && state.activeRecord.id === id) state.activeRecord = null;
  }

  function emptyCollectionRecord(metadata) {
    return {
      id: state.assignment.upload_id || metadata.session_id,
      ticket: state.assignment.ticket,
      assignment: { ...state.assignment, ticket: undefined },
      sessionId: metadata.session_id,
      events: [],
      status: "collecting",
      createdAt: new Date().toISOString(),
      uploaded: { events: false, summary: false, recording: false },
      checkpoints: {},
    };
  }

  async function beginSession(metadataJson) {
    if (state.consent !== "accepted" || (config.productionMode && !state.assignment.valid)) return false;
    const metadata = parseJson(metadataJson);
    state.sessionId = String(metadata.session_id || "");
    state.events = [];
    state.activeRecord = emptyCollectionRecord(metadata);
    await saveRecord(state.activeRecord);
    return true;
  }

  async function appendEvent(eventJson) {
    if (state.consent !== "accepted" || !state.activeRecord) return false;
    const event = parseJson(eventJson);
    if (!event || typeof event !== "object") return false;
    state.events.push(event);
    state.activeRecord.events = state.events.slice();
    state.activeRecord.updatedAt = new Date().toISOString();
    await saveRecord(state.activeRecord);
    return true;
  }

  function parseJson(value) {
    try {
      return typeof value === "string" ? JSON.parse(value) : value || {};
    } catch {
      return {};
    }
  }

  function chooseRecorder(stream) {
    const profiles = [
      { mime: "video/webm;codecs=vp9", name: "webm_vp9" },
      { mime: "video/webm;codecs=vp8", name: "webm_vp8" },
      { mime: "video/webm", name: "webm_default" },
    ];
    for (const profile of profiles) {
      if (!MediaRecorder.isTypeSupported(profile.mime)) continue;
      try {
        return {
          recorder: new MediaRecorder(stream, {
            mimeType: profile.mime,
            videoBitsPerSecond: Number(config.recordingBitsPerSecond || 2500000),
          }),
          profile,
        };
      } catch {
        // Try the next supported profile.
      }
    }
    throw new Error("no_compatible_recording_profile");
  }

  function startRecording() {
    if (!config.productionMode || state.recorder || state.recordingStatus === "recording") return;
    if (!window.MediaRecorder) {
      state.recordingStatus = "mediarecorder_unavailable";
      return;
    }
    const canvas = document.getElementById("canvas");
    if (!canvas || typeof canvas.captureStream !== "function") {
      state.recordingStatus = "canvas_capture_unavailable";
      return;
    }
    try {
      state.stream = canvas.captureStream(Number(config.recordingFps || 30));
      const selected = chooseRecorder(state.stream);
      state.recorder = selected.recorder;
      state.recordingMime = selected.recorder.mimeType || selected.profile.mime;
      state.recordingStatus = "recording";
      state.chunks = [];
      state.stopPromise = new Promise((resolve) => {
        state.stopResolve = resolve;
      });
      state.recorder.ondataavailable = (event) => {
        if (event.data && event.data.size > 0) state.chunks.push(event.data);
      };
      state.recorder.onerror = () => {
        state.recordingStatus = "recording_error";
      };
      state.recorder.onstop = () => {
        state.recordingBlob = state.chunks.length
          ? new Blob(state.chunks, { type: state.recordingMime || "video/webm" })
          : null;
        state.recordingStatus = state.recordingBlob ? "ready" : "empty";
        state.stream?.getTracks().forEach((track) => track.stop());
        state.stopResolve?.(state.recordingBlob);
      };
      state.recorder.start(2000);
    } catch (error) {
      state.recordingStatus = String(error.message || "recording_start_failed");
      state.stream?.getTracks().forEach((track) => track.stop());
    }
  }

  async function stopRecording() {
    if (!state.recorder || state.recorder.state === "inactive") return state.recordingBlob;
    state.recorder.stop();
    return state.stopPromise;
  }

  function toJsonl(events) {
    return events.map((event) => JSON.stringify(event)).join("\n") + "\n";
  }

  function summarizeAssistantEvents(events) {
    const counts = {
      eligible: 0,
      triggered: 0,
      invitations_shown: 0,
      accepted: 0,
      rejected: 0,
      dismissed: 0,
      manual_opened: 0,
    };
    const triggerReasons = {};
    for (const event of events) {
      const name = String(event.event_name || "");
      if (name === "scaffold_eligible") counts.eligible += 1;
      if (name === "scaffold_triggered") counts.triggered += 1;
      if (name === "scaffold_invitation_shown") counts.invitations_shown += 1;
      if (name === "scaffold_accepted") counts.accepted += 1;
      if (name === "scaffold_rejected") counts.rejected += 1;
      if (name === "scaffold_dismissed") counts.dismissed += 1;
      if (name === "support_started" && String(event.payload?.trigger_reason || "") === "manual") counts.manual_opened += 1;
      const reason = String(event.payload?.trigger_reason || "");
      if (reason) triggerReasons[reason] = Number(triggerReasons[reason] || 0) + 1;
    }
    return { ...counts, trigger_reasons: triggerReasons };
  }

  async function finalizeCampaign(summaryJson) {
    if (state.uploadStarted || state.consent !== "accepted" || !state.activeRecord) return false;
    state.uploadStarted = true;
    setUploadStatus("正在整理实验数据与录像…", "working");
    await new Promise((resolve) => window.setTimeout(resolve, 750));
    await stopRecording();
    const campaignSummary = parseJson(summaryJson);
    const summary = {
      schema_version: 2,
      study_version: state.assignment.study_version || String(config.studyVersion || "godot-v1"),
      condition: state.assignment.condition,
      session_id: state.sessionId,
      class_id: state.assignment.class_id,
      student_code: state.assignment.student_code,
      upload_id: state.assignment.upload_id,
      build_version: String(config.buildVersion || "development"),
      completed_at: new Date().toISOString(),
      browser: navigator.userAgent,
      consent: "accepted",
      recording_mode: "godot_canvas",
      recording_status: state.recordingStatus,
      recording_mime: state.recordingMime,
      recording_bytes: state.recordingBlob ? state.recordingBlob.size : 0,
      assistant_interactions: summarizeAssistantEvents(state.events),
      upload_status_at_packaging: "pending_manifest_confirmation",
      campaign: campaignSummary,
    };
    const recordingStatus = {
      schema_version: 2,
      session_id: state.sessionId,
      status: "recording_unavailable",
      reason: state.recordingStatus,
      recorded_at: new Date().toISOString(),
    };
    const record = {
      ...state.activeRecord,
      summary,
      eventsBlob: new Blob([toJsonl(state.events)], { type: "application/x-ndjson" }),
      summaryBlob: new Blob([JSON.stringify(summary, null, 2)], { type: "application/json" }),
      recordingBlob: state.recordingBlob,
      recordingStatusBlob: state.recordingBlob ? null : new Blob([JSON.stringify(recordingStatus, null, 2)], { type: "application/json" }),
      recordingExtension: state.recordingBlob ? "webm" : "json",
      status: "pending",
      finalizedAt: new Date().toISOString(),
    };
    await saveRecord(record);
    try {
      await uploadWithRetry(record);
      return true;
    } catch (error) {
      state.uploadStarted = false;
      showUploadFailure(record, error);
      return false;
    }
  }

  async function requestCredentials(record) {
    return apiRequest("/api/upload/credentials", {
      ticket: record.ticket,
      recording_extension: record.recordingExtension,
      recording_available: Boolean(record.recordingBlob),
    });
  }

  async function completeUpload(record) {
    return apiRequest("/api/upload/complete", {
      ticket: record.ticket,
      recording_extension: record.recordingExtension,
      recording_available: Boolean(record.recordingBlob),
    });
  }

  function credentialFields(payload) {
    const credentials = payload.credentials || payload.Credentials || {};
    return {
      accessKeyId: credentials.accessKeyId || credentials.AccessKeyId,
      accessKeySecret: credentials.accessKeySecret || credentials.AccessKeySecret,
      stsToken: credentials.stsToken || credentials.SecurityToken,
    };
  }

  function createOssClient(payload, record) {
    if (!window.OSS) throw new Error("oss_sdk_unavailable");
    return new window.OSS({
      region: payload.region,
      bucket: payload.bucket,
      authorizationV4: true,
      secure: true,
      ...credentialFields(payload),
      refreshSTSToken: async () => credentialFields(await requestCredentials(record)),
      refreshSTSTokenInterval: 5 * 60 * 1000,
    });
  }

  async function persistProgress(record) {
    record.updatedAt = new Date().toISOString();
    await saveRecord(record);
  }

  async function uploadReal(client, record, key, blob, objectName) {
    if (record.uploaded[key]) return;
    if (key === "recording" && blob.size >= Number(config.multipartThresholdBytes || 20 * 1024 * 1024)) {
      await client.multipartUpload(objectName, blob, {
        parallel: Number(config.multipartParallel || 3),
        partSize: Number(config.multipartPartSizeBytes || 5 * 1024 * 1024),
        checkpoint: record.checkpoints[key] || undefined,
        progress: async (progress, checkpoint) => {
          record.checkpoints[key] = checkpoint || null;
          setUploadStatus("正在上传录像 " + Math.round(progress * 100) + "%", "working");
          await persistProgress(record);
        },
        headers: { "Content-Type": blob.type || "application/octet-stream" },
      });
    } else {
      await client.put(objectName, blob, {
        headers: { "Content-Type": blob.type || "application/octet-stream" },
      });
    }
    record.uploaded[key] = true;
    record.checkpoints[key] = null;
    await persistProgress(record);
  }

  function putMock(url, blob, ticket) {
    return fetch(url, {
      method: "PUT",
      headers: {
        "Content-Type": blob.type || "application/octet-stream",
        Authorization: "Bearer " + ticket,
      },
      body: blob,
    }).then((response) => {
      if (!response.ok) throw new Error("mock_upload_" + response.status);
    });
  }

  async function uploadAttempt(record) {
    const credentials = await requestCredentials(record);
    if (credentials.status === "already_completed") return { status: "complete" };
    const files = {
      events: record.eventsBlob,
      summary: record.summaryBlob,
      recording: record.recordingBlob || record.recordingStatusBlob,
    };
    if (credentials.mode === "mock") {
      for (const key of Object.keys(files)) {
        if (record.uploaded[key]) continue;
        await putMock(credentials.upload_urls[key], files[key], record.ticket);
        record.uploaded[key] = true;
        await persistProgress(record);
      }
    } else {
      const client = createOssClient(credentials, record);
      for (const key of Object.keys(files)) {
        setUploadStatus(key === "recording" ? "正在上传游戏录像…" : "正在上传实验数据…", "working");
        await uploadReal(client, record, key, files[key], credentials.objects[key]);
      }
    }
    setUploadStatus("正在核验云端文件…", "working");
    return completeUpload(record);
  }

  async function uploadWithRetry(record) {
    const delays = [0, 2000, 5000, 15000, 30000];
    let lastError = null;
    for (let index = 0; index < delays.length; index += 1) {
      if (delays[index]) await new Promise((resolve) => window.setTimeout(resolve, delays[index]));
      try {
        record.status = "uploading";
        await persistProgress(record);
        const result = await uploadAttempt(record);
        record.status = result.status === "saved_with_warning" ? "warning" : "complete";
        record.completedAt = new Date().toISOString();
        await persistProgress(record);
        showUploadSuccess(result.status);
        await deleteRecord(record.id);
        return result;
      } catch (error) {
        lastError = error;
        record.status = "pending";
        record.lastError = String(error.message || error);
        await persistProgress(record);
      }
    }
    throw lastError || new Error("upload_failed");
  }

  async function resumePending() {
    if (!config.productionMode || !state.assignment.valid) return;
    const record = await loadRecord(state.assignment.upload_id);
    if (!record || !record.eventsBlob || !record.summaryBlob || record.status === "complete") return;
    state.activeRecord = record;
    setUploadStatus("发现未完成的上传，正在自动续传…", "working");
    try {
      await uploadWithRetry(record);
    } catch (error) {
      showUploadFailure(record, error);
    }
  }

  function downloadBlob(name, blob) {
    if (!blob) return;
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = name;
    document.body.appendChild(anchor);
    anchor.click();
    anchor.remove();
    window.setTimeout(() => URL.revokeObjectURL(url), 1000);
  }

  function downloadBackup(record) {
    downloadBlob("session_" + record.sessionId + ".jsonl", record.eventsBlob);
    window.setTimeout(() => downloadBlob("summary_" + record.sessionId + ".json", record.summaryBlob), 200);
    window.setTimeout(() => downloadBlob(
      "recording_" + record.sessionId + "." + record.recordingExtension,
      record.recordingBlob || record.recordingStatusBlob
    ), 400);
  }

  function ensureStatusNode() {
    let node = document.getElementById("study-upload-status");
    if (!node) {
      node = document.createElement("div");
      node.id = "study-upload-status";
      node.className = "study-status";
      document.body.appendChild(node);
    }
    return node;
  }

  function setUploadStatus(message, kind) {
    const node = ensureStatusNode();
    node.className = "study-status " + kind;
    node.textContent = message;
  }

  function showUploadSuccess(status) {
    const message = status === "saved_with_warning"
      ? "实验数据已保存，录像不可用。现在可以关闭页面。"
      : "实验数据和录像已保存成功，现在可以关闭页面。";
    const overlay = document.createElement("div");
    overlay.className = "study-overlay";
    overlay.innerHTML = '<section class="study-card success"><h1>保存成功</h1><p>' + message + '</p></section>';
    document.body.appendChild(overlay);
    setUploadStatus("云端保存完成", "success");
  }

  function showUploadFailure(record, error) {
    setUploadStatus("上传尚未完成，请保持页面开启", "error");
    let overlay = document.getElementById("study-upload-error");
    if (!overlay) {
      overlay = document.createElement("div");
      overlay.id = "study-upload-error";
      overlay.className = "study-overlay";
      overlay.innerHTML = '<section class="study-card error"><h1>暂时无法保存</h1><p class="error-message"></p><div class="study-actions"><button data-action="retry">重新上传</button><button data-action="backup">教师备份下载</button></div></section>';
      overlay.querySelector('[data-action="retry"]').addEventListener("click", async () => {
        overlay.remove();
        try {
          await uploadWithRetry(record);
        } catch (retryError) {
          showUploadFailure(record, retryError);
        }
      });
      overlay.querySelector('[data-action="backup"]').addEventListener("click", () => downloadBackup(record));
      document.body.appendChild(overlay);
    }
    overlay.querySelector(".error-message").textContent = "错误：" + String(error.message || error) + "。系统会保留本地副本，可重试或由教师下载备份。";
  }

  function addStudyStyles() {
    const style = document.createElement("style");
    style.textContent = [
      ".study-overlay{position:fixed;inset:0;z-index:10000;display:grid;place-items:center;background:rgba(4,12,30,.92);font-family:'Microsoft YaHei',sans-serif;color:#eef8ff}",
      ".study-card{width:min(620px,calc(100vw - 48px));box-sizing:border-box;padding:34px 38px;border:1px solid #45ded1;border-radius:24px;background:#102748;box-shadow:0 24px 80px rgba(0,0,0,.45)}",
      ".study-card h1{margin:0 0 18px;font-size:30px}.study-card p{line-height:1.75;color:#cfe3f4}.study-card ul{padding-left:22px;line-height:1.8;color:#dcebf7}",
      ".study-actions{display:flex;gap:12px;margin-top:24px}.study-actions button{flex:1;padding:13px 18px;border:0;border-radius:12px;background:#45ded1;color:#082034;font-size:16px;font-weight:700;cursor:pointer}",
      ".study-actions button.secondary{background:#314a6c;color:#fff}.study-card.success{border-color:#65e6a3}.study-card.error{border-color:#ff8f8f}",
      ".study-status{position:fixed;left:18px;bottom:18px;z-index:9000;padding:10px 14px;border-radius:10px;background:#183453;color:#fff;font:14px 'Microsoft YaHei',sans-serif;box-shadow:0 8px 24px rgba(0,0,0,.3)}",
      ".study-status.success{background:#176b4c}.study-status.error{background:#8d3333}",
    ].join("");
    document.head.appendChild(style);
  }

  function showConsent() {
    if (!config.productionMode) return;
    const overlay = document.createElement("div");
    overlay.id = "study-consent";
    overlay.className = "study-overlay";
    const userAgent = navigator.userAgent || "";
    const supportedDesktopBrowser = !/Mobile|Android|iPhone|iPad/i.test(userAgent) && /(Chrome|Chromium|Edg)\//i.test(userAgent);
    if (!supportedDesktopBrowser) {
      state.consent = "unsupported";
      overlay.innerHTML = '<section class="study-card error"><h1>浏览器不受支持</h1><p>本实验仅支持电脑最新版 Chrome 或 Edge。当前页面不会录屏或采集数据。</p></section>';
      document.body.appendChild(overlay);
      return;
    }
    if (!state.assignment.valid) {
      state.consent = "invalid";
      overlay.innerHTML = '<section class="study-card error"><h1>实验链接无效</h1><p>请使用教师发放的完整个人链接进入。当前页面不会录屏或采集数据。</p></section>';
      document.body.appendChild(overlay);
      return;
    }
    overlay.innerHTML = '<section class="study-card"><h1>参与说明与知情同意</h1><p>本活动研究 AI 学习提示对游戏闯关的帮助。若同意参与，系统会记录匿名游戏操作、答题与提示交互，并只录制本游戏画布。</p><ul><li>不录制麦克风、摄像头、桌面或其他标签页</li><li>不采集真实姓名、手机号或账号信息</li><li>数据仅用于研究与教学改进，默认保存 12 个月</li><li>可通过匿名编号向研究者申请删除</li></ul><div class="study-actions"><button data-action="accept">我已阅读并同意参与</button><button class="secondary" data-action="decline">不同意并退出</button></div></section>';
    overlay.querySelector('[data-action="accept"]').addEventListener("click", () => {
      state.consent = "accepted";
      overlay.remove();
      startRecording();
    });
    overlay.querySelector('[data-action="decline"]').addEventListener("click", () => {
      state.consent = "declined";
      overlay.innerHTML = '<section class="study-card"><h1>已退出实验</h1><p>本页面不会录屏、记录操作或上传数据。现在可以关闭页面。</p></section>';
    });
    document.body.appendChild(overlay);
  }

  window.addEventListener("beforeunload", (event) => {
    const record = state.activeRecord;
    if (record && ["pending", "uploading"].includes(record.status)) {
      event.preventDefault();
      event.returnValue = "";
    }
  });

  addStudyStyles();
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", () => {
      showConsent();
      window.setTimeout(resumePending, 500);
    }, { once: true });
  } else {
    showConsent();
    window.setTimeout(resumePending, 500);
  }

  window.GodotExperimentBridge = Object.freeze({
    isProduction: () => Boolean(config.productionMode),
    getAssignment: () => ({ ...state.assignment, ticket: undefined }),
    getConsentStatus: () => state.consent,
    beginSession,
    appendEvent,
    finalizeCampaign,
    resumePending,
  });
})();
