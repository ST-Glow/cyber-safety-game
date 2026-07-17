"use strict";

const express = require("express");
const { verifyTicket, createAgentSession, verifyAgentSession } = require("./auth");
const { loadConfig } = require("./config");
const { createCloudAdapter, objectNames, objectPrefix } = require("./cloud");
const { createCozeAdapter } = require("./coze");

const LIMITS = {
  events: { max: 10 * 1024 * 1024, types: ["application/x-ndjson", "application/jsonl", "application/octet-stream"] },
  summary: { max: 1024 * 1024, types: ["application/json", "application/octet-stream"] },
  recording: { max: 512 * 1024 * 1024, types: ["video/mp4", "video/webm", "application/json", "application/octet-stream"] },
};

function errorResponse(response, status, code, message = code) {
  response.status(status).json({ code, message });
}

function validateFile(info, key) {
  const rules = LIMITS[key];
  if (!info.exists) throw new Error(`${key}_missing`);
  if (!Number.isFinite(info.bytes) || info.bytes <= 0 || info.bytes > rules.max) throw new Error(`${key}_size_invalid`);
  const contentType = String(info.contentType || "").toLowerCase().split(";")[0];
  if (contentType && !rules.types.includes(contentType)) throw new Error(`${key}_content_type_invalid`);
}

function bearerTicket(request) {
  const header = String(request.headers.authorization || "");
  return header.startsWith("Bearer ") ? header.slice(7) : "";
}

function createRateLimiter({ limit = 12, windowMs = 5 * 60 * 1000 } = {}) {
  const buckets = new Map();
  return function consume(key, now = Date.now()) {
    const recent = (buckets.get(key) || []).filter((timestamp) => now - timestamp < windowMs);
    if (recent.length >= limit) return false;
    recent.push(now);
    buckets.set(key, recent);
    if (buckets.size > 1000) {
      for (const [bucketKey, timestamps] of buckets) {
        if (timestamps.every((timestamp) => now - timestamp >= windowMs)) buckets.delete(bucketKey);
      }
    }
    return true;
  };
}

function createApp(options = {}) {
  const config = options.config || loadConfig();
  const cloud = options.cloud || createCloudAdapter(config);
  const coze = options.coze || createCozeAdapter(config);
  const consumeAgentQuota = options.consumeAgentQuota || createRateLimiter();
  const app = express();
  app.disable("x-powered-by");

  app.use((request, response, next) => {
    const origin = String(request.headers.origin || "").replace(/\/$/, "");
    if (origin && !config.allowedOrigins.includes(origin)) {
      errorResponse(response, 403, "origin_not_allowed");
      return;
    }
    if (origin) response.setHeader("Access-Control-Allow-Origin", origin);
    response.setHeader("Vary", "Origin");
    response.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization");
    response.setHeader("Access-Control-Allow-Methods", "GET, POST, PUT, OPTIONS");
    if (request.method === "OPTIONS") {
      response.status(204).end();
      return;
    }
    next();
  });

  app.get("/api/health", (request, response) => {
    response.json({
      ok: true,
      mode: cloud.mode,
      coze_configured: coze.configured,
      coze_auth_mode: coze.authMode || "custom",
      coze_bot_id: coze.botId || config.cozeBotId,
      time: new Date().toISOString(),
    });
  });

  if (cloud.mode === "mock") {
    app.put("/api/mock-upload/:uploadId/:fileName", express.raw({ type: "*/*", limit: "512mb" }), async (request, response) => {
      try {
        const claims = verifyTicket(bearerTicket(request), config.linkSecret);
        if (claims.upload_id !== request.params.uploadId) throw new Error("upload_id_mismatch");
        const allowed = new Set(["session.jsonl", "summary.json", "recording.mp4", "recording.webm", "recording-status.json"]);
        if (!allowed.has(request.params.fileName)) throw new Error("file_name_not_allowed");
        const name = `${objectPrefix(claims)}/${request.params.fileName}`;
        await cloud.writeObject(name, request.body, request.headers["content-type"] || "application/octet-stream");
        response.status(201).json({ ok: true });
      } catch (error) {
        errorResponse(response, 400, error.message);
      }
    });
  }

  const json = express.json({ limit: "64kb" });

  app.post("/api/coze/chat", json, async (request, response) => {
    try {
      const body = request.body || {};
      const claims = verifyTicket(body.ticket, config.linkSecret);
      const message = String(body.message || "").trim();
      if (!message || message.length > 800) {
        errorResponse(response, 400, "coze_message_invalid", "问题内容应为 1 至 800 个字符");
        return;
      }
      if (!coze.configured) {
        errorResponse(response, 503, "coze_not_configured", "智能体服务尚未完成配置");
        return;
      }
      if (!consumeAgentQuota(claims.upload_id)) {
        errorResponse(response, 429, "coze_rate_limited", "提问过于频繁，请稍后再试");
        return;
      }

      let conversationId = "";
      if (body.session) {
        const session = verifyAgentSession(body.session, config.linkSecret, claims.upload_id);
        conversationId = session.conversation_id;
      }

      const result = await coze.chat({
        message,
        conversationId,
        userId: `web_${claims.upload_id}`,
      });
      const session = createAgentSession({
        upload_id: claims.upload_id,
        conversation_id: result.conversationId,
        exp: claims.exp,
      }, config.linkSecret);
      response.json({ reply: result.reply, session });
    } catch (error) {
      const code = error.code || error.message || "coze_request_failed";
      const status = code === "ticket_expired" || code === "agent_session_expired" ? 401
        : code.startsWith("ticket_") || code.startsWith("agent_session_") || code === "conversation_id_invalid" ? 400
          : code === "coze_not_configured" ? 503
            : 502;
      const message = status === 502 ? "智能体暂时无法回答，请稍后重试" : code;
      errorResponse(response, status, code, message);
    }
  });

  app.post("/api/upload/credentials", json, async (request, response) => {
    try {
      const claims = verifyTicket(request.body.ticket, config.linkSecret);
      const recordingAvailable = request.body.recording_available !== false;
      const objects = objectNames(claims, request.body.recording_extension, recordingAvailable);
      const manifest = await cloud.head(objects.manifest);
      if (manifest.exists) {
        response.json({ status: "already_completed" });
        return;
      }
      if (cloud.mode === "mock") {
        const base = config.publicBaseUrl || `${request.protocol}://${request.get("host")}`;
        const fileName = (name) => name.slice(name.lastIndexOf("/") + 1);
        response.json({
          mode: "mock",
          objects,
          upload_urls: {
            events: `${base}/api/mock-upload/${claims.upload_id}/${fileName(objects.events)}`,
            summary: `${base}/api/mock-upload/${claims.upload_id}/${fileName(objects.summary)}`,
            recording: `${base}/api/mock-upload/${claims.upload_id}/${fileName(objects.recording)}`,
          },
        });
        return;
      }
      const credentials = await cloud.assumeRole(claims, objects);
      response.json({ mode: "oss", region: config.ossRegion, bucket: config.ossBucket, objects, credentials });
    } catch (error) {
      const status = error.message === "ticket_expired" ? 401 : 400;
      errorResponse(response, status, error.message);
    }
  });

  app.post("/api/upload/complete", json, async (request, response) => {
    try {
      const claims = verifyTicket(request.body.ticket, config.linkSecret);
      const recordingAvailable = request.body.recording_available !== false;
      const objects = objectNames(claims, request.body.recording_extension, recordingAvailable);
      const [events, summary, recording] = await Promise.all([
        cloud.head(objects.events),
        cloud.head(objects.summary),
        cloud.head(objects.recording),
      ]);
      validateFile(events, "events");
      validateFile(summary, "summary");
      validateFile(recording, "recording");
      const status = recordingAvailable ? "complete" : "saved_with_warning";
      const manifest = {
        schema_version: 1,
        status,
        class_id: claims.class_id,
        student_code: claims.student_code,
        upload_id: claims.upload_id,
        completed_at: new Date().toISOString(),
        files: {
          events: { name: objects.events, bytes: events.bytes, etag: events.etag },
          summary: { name: objects.summary, bytes: summary.bytes, etag: summary.etag },
          recording: { name: objects.recording, bytes: recording.bytes, etag: recording.etag },
        },
      };
      await cloud.writeManifest(objects.manifest, manifest);
      response.json({ status, files: manifest.files });
    } catch (error) {
      errorResponse(response, 409, error.message);
    }
  });

  app.use((request, response) => errorResponse(response, 404, "not_found"));
  return app;
}

module.exports = { createApp, validateFile, createRateLimiter };
