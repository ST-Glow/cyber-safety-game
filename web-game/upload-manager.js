(() => {
  "use strict";

  const DB_NAME = "cyber-safety-upload-v1";
  const STORE_NAME = "sessions";
  const DB_VERSION = 1;
  const config = window.CYBER_UPLOAD_CONFIG || {};
  let pendingInMemory = false;
  let activeRecord = null;

  function normalizeBaseUrl(value) {
    return String(value || "").trim().replace(/\/+$/, "");
  }

  function isConfigured() {
    const apiBaseUrl = normalizeBaseUrl(config.apiBaseUrl);
    return Boolean(config.enabled && apiBaseUrl && !apiBaseUrl.includes("__UPLOAD_API_BASE_URL__"));
  }

  function parseTicketPayload(ticket) {
    try {
      const payloadPart = String(ticket || "").split(".")[0];
      if (!payloadPart) return null;
      const base64 = payloadPart.replace(/-/g, "+").replace(/_/g, "/");
      const padded = base64.padEnd(Math.ceil(base64.length / 4) * 4, "=");
      const binary = atob(padded);
      const bytes = Uint8Array.from(binary, (character) => character.charCodeAt(0));
      return JSON.parse(new TextDecoder().decode(bytes));
    } catch {
      return null;
    }
  }

  function getAssignment() {
    const params = new URLSearchParams(window.location.search);
    const ticket = params.get("ticket") || "";
    const ticketPayload = parseTicketPayload(ticket);
    const queryStudent = (params.get("student") || "").trim().toUpperCase();
    const studentCode = String(ticketPayload?.student_code || queryStudent || "").trim().toUpperCase();
    return {
      ticket,
      ticketPayload,
      studentCode,
      classId: String(ticketPayload?.class_id || "").trim(),
      uploadId: String(ticketPayload?.upload_id || "").trim(),
      valid: Boolean(ticket && ticketPayload && studentCode),
    };
  }

  function openDatabase() {
    return new Promise((resolve, reject) => {
      if (!window.indexedDB) {
        reject(new Error("indexeddb_unavailable"));
        return;
      }
      const request = indexedDB.open(DB_NAME, DB_VERSION);
      request.onupgradeneeded = () => {
        const database = request.result;
        if (!database.objectStoreNames.contains(STORE_NAME)) {
          database.createObjectStore(STORE_NAME, { keyPath: "id" });
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
        const store = transaction.objectStore(STORE_NAME);
        let request;
        try {
          request = operation(store);
        } catch (error) {
          reject(error);
          return;
        }
        request.onsuccess = () => resolve(request.result);
        request.onerror = () => reject(request.error || new Error("indexeddb_request_failed"));
      });
    } finally {
      database.close();
    }
  }

  function saveRecord(record) {
    pendingInMemory = true;
    activeRecord = record;
    return withStore("readwrite", (store) => store.put(record));
  }

  async function loadRecord(id) {
    if (!id) return null;
    const record = await withStore("readonly", (store) => store.get(id));
    if (record) {
      pendingInMemory = record.status !== "complete";
      activeRecord = record;
    }
    return record || null;
  }

  async function deleteRecord(id) {
    await withStore("readwrite", (store) => store.delete(id));
    if (activeRecord?.id === id) activeRecord = null;
    pendingInMemory = false;
  }

  function sleep(milliseconds) {
    return new Promise((resolve) => window.setTimeout(resolve, milliseconds));
  }

  async function apiRequest(path, body) {
    const response = await fetch(`${normalizeBaseUrl(config.apiBaseUrl)}${path}`, {
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
    if (!response.ok) {
      const error = new Error(payload.message || payload.code || `api_${response.status}`);
      error.code = payload.code || `api_${response.status}`;
      throw error;
    }
    return payload;
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
    const initial = credentialFields(payload);
    return new window.OSS({
      region: payload.region,
      bucket: payload.bucket,
      authorizationV4: true,
      secure: true,
      ...initial,
      refreshSTSToken: async () => credentialFields(await requestCredentials(record)),
      refreshSTSTokenInterval: 5 * 60 * 1000,
    });
  }

  function putWithProgress(url, blob, ticket, onProgress) {
    return new Promise((resolve, reject) => {
      const request = new XMLHttpRequest();
      request.open("PUT", url, true);
      request.setRequestHeader("Content-Type", blob.type || "application/octet-stream");
      request.setRequestHeader("Authorization", `Bearer ${ticket}`);
      request.upload.onprogress = (event) => {
        if (event.lengthComputable) onProgress(event.loaded / event.total);
      };
      request.onload = () => {
        if (request.status >= 200 && request.status < 300) {
          onProgress(1);
          resolve();
        } else {
          reject(new Error(`mock_upload_${request.status}`));
        }
      };
      request.onerror = () => reject(new Error("mock_upload_network_error"));
      request.send(blob);
    });
  }

  async function persistProgress(record) {
    try {
      await saveRecord(record);
    } catch {
      activeRecord = record;
      pendingInMemory = true;
    }
  }

  async function uploadOneReal(client, record, fileKey, blob, objectName, onProgress) {
    if (record.uploaded[fileKey]) {
      onProgress(1);
      return;
    }
    if (fileKey === "recording" && blob.size >= Number(config.multipartThresholdBytes || 20 * 1024 * 1024)) {
      const result = await client.multipartUpload(objectName, blob, {
        parallel: Number(config.multipartParallel || 3),
        partSize: Number(config.multipartPartSizeBytes || 5 * 1024 * 1024),
        checkpoint: record.checkpoints[fileKey] || undefined,
        progress: async (progress, checkpoint) => {
          record.checkpoints[fileKey] = checkpoint || null;
          onProgress(progress);
          await persistProgress(record);
        },
        headers: { "Content-Type": blob.type || "application/octet-stream" },
      });
      record.etags[fileKey] = result?.res?.headers?.etag || result?.etag || "";
    } else {
      const result = await client.put(objectName, blob, {
        headers: { "Content-Type": blob.type || "application/octet-stream" },
      });
      record.etags[fileKey] = result?.res?.headers?.etag || result?.etag || "";
      onProgress(1);
    }
    record.uploaded[fileKey] = true;
    record.checkpoints[fileKey] = null;
    await persistProgress(record);
  }

  async function uploadAttempt(record, report) {
    const credentialPayload = await requestCredentials(record);
    if (credentialPayload.status === "already_completed") {
      return { status: "complete", alreadyCompleted: true };
    }

    const entries = [
      ["events", record.eventsBlob, 0.05],
      ["summary", record.summaryBlob, 0.05],
      ["recording", record.recordingBlob || record.recordingStatusBlob, 0.90],
    ];
    const progressByFile = { events: record.uploaded.events ? 1 : 0, summary: record.uploaded.summary ? 1 : 0, recording: record.uploaded.recording ? 1 : 0 };
    const emitProgress = (fileKey, stage) => {
      progressByFile[fileKey] = stage;
      const overall = entries.reduce((sum, [key, , weight]) => sum + progressByFile[key] * weight, 0);
      report({ phase: "uploading", file: fileKey, progress: overall });
    };

    if (credentialPayload.mode === "mock") {
      for (const [fileKey, blob] of entries) {
        if (record.uploaded[fileKey]) {
          emitProgress(fileKey, 1);
          continue;
        }
        const url = credentialPayload.upload_urls?.[fileKey];
        if (!url) throw new Error(`missing_mock_url_${fileKey}`);
        await putWithProgress(url, blob, record.ticket, (progress) => emitProgress(fileKey, progress));
        record.uploaded[fileKey] = true;
        await persistProgress(record);
      }
    } else {
      const client = createOssClient(credentialPayload, record);
      for (const [fileKey, blob] of entries) {
        const objectName = credentialPayload.objects?.[fileKey];
        if (!objectName) throw new Error(`missing_object_name_${fileKey}`);
        await uploadOneReal(client, record, fileKey, blob, objectName, (progress) => emitProgress(fileKey, progress));
      }
    }

    report({ phase: "verifying", progress: 1 });
    return completeUpload(record);
  }

  async function uploadWithRetry(record, report = () => {}) {
    const delays = Array.isArray(config.retryDelaysMs) ? config.retryDelaysMs : [0, 2000, 5000, 15000, 30000];
    let lastError = null;
    for (let attempt = 0; attempt < delays.length; attempt += 1) {
      if (delays[attempt] > 0) {
        report({ phase: "retry_wait", attempt: attempt + 1, delayMs: delays[attempt], error: lastError });
        await sleep(delays[attempt]);
      }
      try {
        record.status = "uploading";
        record.lastAttemptAt = new Date().toISOString();
        await persistProgress(record);
        const result = await uploadAttempt(record, report);
        record.status = result.status === "saved_with_warning" ? "warning" : "complete";
        record.completedAt = new Date().toISOString();
        await persistProgress(record);
        if (record.status === "complete" || record.status === "warning") {
          await deleteRecord(record.id);
        }
        return result;
      } catch (error) {
        lastError = error;
        record.status = "pending";
        record.lastError = error.message;
        await persistProgress(record);
      }
    }
    throw lastError || new Error("upload_failed");
  }

  async function queueAndUpload(bundle, report) {
    const assignment = getAssignment();
    if (!isConfigured()) throw new Error("upload_not_configured");
    if (config.requireSignedTicket && !assignment.valid) throw new Error("signed_ticket_required");

    const recordingStatus = bundle.recordingBlob ? null : {
      session_id: bundle.sessionId,
      status: "recording_unavailable",
      recording_mode: bundle.summary.recording_mode,
      recorded_at: new Date().toISOString(),
    };
    const record = {
      id: assignment.uploadId || bundle.sessionId,
      sessionId: bundle.sessionId,
      studentCode: bundle.studentCode,
      ticket: assignment.ticket,
      summary: bundle.summary,
      eventsBlob: new Blob([bundle.eventsText], { type: "application/x-ndjson" }),
      summaryBlob: new Blob([JSON.stringify(bundle.summary, null, 2)], { type: "application/json" }),
      recordingBlob: bundle.recordingBlob || null,
      recordingStatusBlob: recordingStatus ? new Blob([JSON.stringify(recordingStatus, null, 2)], { type: "application/json" }) : null,
      recordingExtension: bundle.recordingBlob ? bundle.recordingExtension : "json",
      recordingMime: bundle.recordingBlob ? bundle.recordingMime : "application/json",
      uploaded: { events: false, summary: false, recording: false },
      checkpoints: {},
      etags: {},
      status: "pending",
      createdAt: new Date().toISOString(),
    };
    await saveRecord(record);
    return uploadWithRetry(record, report);
  }

  async function resumePending(report) {
    const assignment = getAssignment();
    const id = assignment.uploadId;
    if (!id) return null;
    const record = await loadRecord(id);
    if (!record || record.status === "complete") return null;
    return { record, result: await uploadWithRetry(record, report) };
  }

  async function getPendingForAssignment() {
    const assignment = getAssignment();
    if (!assignment.uploadId) return null;
    try {
      return await loadRecord(assignment.uploadId);
    } catch {
      return activeRecord?.id === assignment.uploadId ? activeRecord : null;
    }
  }

  function downloadBlob(filename, blob) {
    if (!blob) return;
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = filename;
    document.body.appendChild(anchor);
    anchor.click();
    anchor.remove();
    window.setTimeout(() => URL.revokeObjectURL(url), 1000);
  }

  async function downloadPendingBackup() {
    const record = (await getPendingForAssignment()) || activeRecord;
    if (!record) throw new Error("pending_record_not_found");
    downloadBlob(`session_${record.sessionId}.jsonl`, record.eventsBlob);
    await sleep(180);
    downloadBlob(`summary_${record.sessionId}.json`, record.summaryBlob);
    await sleep(180);
    const recordingName = record.recordingBlob
      ? `recording_${record.sessionId}.${record.recordingExtension}`
      : `recording-status_${record.sessionId}.json`;
    downloadBlob(recordingName, record.recordingBlob || record.recordingStatusBlob);
  }

  window.CyberSafetyUploader = Object.freeze({
    isConfigured,
    getAssignment,
    queueAndUpload,
    resumePending,
    getPendingForAssignment,
    downloadPendingBackup,
    hasPending: () => pendingInMemory,
  });
})();
