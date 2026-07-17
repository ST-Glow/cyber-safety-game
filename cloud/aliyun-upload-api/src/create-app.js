"use strict";

const express = require("express");
const { verifyTicket } = require("./auth");
const { loadConfig } = require("./config");
const { createCloudAdapter, objectNames, objectPrefix } = require("./cloud");

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

function createApp(options = {}) {
  const config = options.config || loadConfig();
  const cloud = options.cloud || createCloudAdapter(config);
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
    response.json({ ok: true, mode: cloud.mode, time: new Date().toISOString() });
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

module.exports = { createApp, validateFile };
