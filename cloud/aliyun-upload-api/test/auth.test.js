"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const { createTicket, verifyTicket } = require("../src/auth");

const secret = "test-secret-at-least-16-characters";
const claims = { class_id: "CLASS-5A", student_code: "S001", upload_id: "upload_001", exp: 2000000000 };

test("creates and verifies a scoped ticket", () => {
  const ticket = createTicket(claims, secret);
  assert.deepEqual(verifyTicket(ticket, secret, 1900000000), { v: 1, ...claims });
});

test("rejects a modified ticket", () => {
  const ticket = createTicket(claims, secret);
  const modified = `${ticket.slice(0, -1)}x`;
  assert.throws(() => verifyTicket(modified, secret, 1900000000), /ticket_signature_invalid/);
});

test("rejects expired and unsafe identifiers", () => {
  const ticket = createTicket({ ...claims, exp: 100 }, secret);
  assert.throws(() => verifyTicket(ticket, secret, 101), /ticket_expired/);
  assert.throws(() => createTicket({ ...claims, student_code: "../S001" }, secret), /student_code_invalid/);
});
