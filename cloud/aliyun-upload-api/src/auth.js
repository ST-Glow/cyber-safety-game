"use strict";

const crypto = require("node:crypto");

const SAFE_ID = /^[A-Za-z0-9_-]{1,48}$/;

function assertSafeId(value, field) {
  if (!SAFE_ID.test(String(value || ""))) {
    const error = new Error(`${field}_invalid`);
    error.code = `${field}_invalid`;
    throw error;
  }
  return String(value);
}

function encodePayload(payload) {
  return Buffer.from(JSON.stringify(payload), "utf8").toString("base64url");
}

function sign(encodedPayload, secret) {
  return crypto.createHmac("sha256", secret).update(encodedPayload).digest("base64url");
}

function createTicket(claims, secret) {
  if (!secret || secret.length < 16) throw new Error("link_secret_too_short");
  const payload = {
    v: 1,
    class_id: assertSafeId(claims.class_id, "class_id"),
    student_code: assertSafeId(claims.student_code, "student_code"),
    upload_id: assertSafeId(claims.upload_id, "upload_id"),
    exp: Number(claims.exp),
  };
  if (!Number.isFinite(payload.exp)) throw new Error("expiry_invalid");
  const encoded = encodePayload(payload);
  return `${encoded}.${sign(encoded, secret)}`;
}

function verifyTicket(ticket, secret, nowSeconds = Math.floor(Date.now() / 1000)) {
  if (!secret || secret.length < 16) throw new Error("link_secret_not_configured");
  const [encoded, providedSignature, extra] = String(ticket || "").split(".");
  if (!encoded || !providedSignature || extra) throw new Error("ticket_malformed");
  const expectedSignature = sign(encoded, secret);
  const expected = Buffer.from(expectedSignature);
  const provided = Buffer.from(providedSignature);
  if (expected.length !== provided.length || !crypto.timingSafeEqual(expected, provided)) {
    throw new Error("ticket_signature_invalid");
  }
  let payload;
  try {
    payload = JSON.parse(Buffer.from(encoded, "base64url").toString("utf8"));
  } catch {
    throw new Error("ticket_payload_invalid");
  }
  if (payload.v !== 1) throw new Error("ticket_version_unsupported");
  payload.class_id = assertSafeId(payload.class_id, "class_id");
  payload.student_code = assertSafeId(payload.student_code, "student_code");
  payload.upload_id = assertSafeId(payload.upload_id, "upload_id");
  if (!Number.isFinite(payload.exp) || payload.exp < nowSeconds) throw new Error("ticket_expired");
  return payload;
}

module.exports = { createTicket, verifyTicket, assertSafeId };
