"use strict";

const crypto = require("node:crypto");

function uploadErrorResponse(response, error, { phase, status, log = console.error }) {
  const safeCode = value => /^[A-Za-z][A-Za-z0-9_.-]{0,95}$/.test(String(value || "")) ? String(value) : "";
  const safeId = value => /^[A-Za-z0-9-]{8,80}$/.test(String(value || "")) ? String(value) : "";
  const code = safeCode(error.code) || safeCode(error.message) || "upload_service_failed";
  const diagnosticId = crypto.randomUUID();
  const upstreamStatus = Number(error.status || error.statusCode || error.entry?.response?.statusCode || 0);
  const details = {
    event: "upload_request_failed",
    diagnostic_id: diagnosticId,
    code,
    phase,
    upstream_status: Number.isInteger(upstreamStatus) ? upstreamStatus : 0,
    requestId: safeId(error.requestId || error.data?.RequestId || error.res?.headers?.["x-oss-request-id"]),
  };
  // SDK messages, stacks, URLs and request objects may include signed parameters. Log only these fields.
  log(JSON.stringify(details));
  response.status(status).json({ code, message: code, ...details });
}

module.exports = { uploadErrorResponse };
