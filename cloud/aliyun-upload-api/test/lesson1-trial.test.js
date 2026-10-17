"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const { createSqliteStore } = require("../src/classroom/store");
const { Lesson1TrialService, VERSION, CONSENT } = require("../src/lesson1-trial");
const { verifyTicket } = require("../src/auth");
const secret = "lesson1-trial-test-secret-at-least-32";
const request = () => ({ run_id: `lesson1-${crypto.randomUUID()}`, segment_id: crypto.randomUUID(), client_key: crypto.randomBytes(32).toString("hex"), class_id: "g7-16", student_name: "试玩测试生", consent_version: CONSENT });

test("trial issues scoped tickets idempotently, renews only the owner and separates same-name sessions", async () => {
  const store = await createSqliteStore(":memory:");
  try {
    let now = Date.now();
    const service = new Lesson1TrialService(store, secret, () => now);
    const body = request();
    const first = await service.session(body, "school");
    const again = await service.session(body, "school");
    assert.deepEqual(first, again);
    assert.equal(verifyTicket(first.ticket, secret).study_version, VERSION);
    assert.equal(first.claims.class_id, "g7-16");
    assert.ok(!JSON.stringify(first).includes(body.student_name));
    const metadata = await service.metadata(first.claims);
    assert.equal(metadata.student_name, body.student_name);
    assert.equal(metadata.run_id, body.run_id);
    assert.equal(metadata.identity_source, "self_reported_trial");
    assert.ok(!JSON.stringify(metadata).includes(body.client_key));
    await assert.rejects(service.session({ ...body, client_key: "0".repeat(64) }, "school", true), /owner_mismatch/);
    await assert.rejects(service.session({ ...body, class_id: "g7-01" }, "school"), /conflict/);
    now += 1800000;
    const renewed = await service.session(body, "school", true);
    assert.equal(renewed.claims.upload_id, first.claims.upload_id);
    assert.ok(renewed.claims.exp > first.claims.exp);
    const other = await service.session(request(), "school");
    assert.notEqual(other.claims.student_code, first.claims.student_code);
    await assert.rejects(service.metadata({ ...first.claims, student_code: other.claims.student_code }), /owner_mismatch/);
    now += 31 * 86400000;
    await assert.rejects(service.session(body, "school", true), /expired/);
  } finally { store.close(); }
});

test("trial validates class, consent and names; shared-school starts are limited across service instances", async () => {
  const store = await createSqliteStore(":memory:");
  try {
    const now = 1800000000000;
    const one = new Lesson1TrialService(store, secret, () => now);
    const two = new Lesson1TrialService(store, secret, () => now);
    for (const patch of [{ class_id: "g7-17" }, { student_name: "<script>" }, { student_name: "123" }, { run_id: "../other" }, { consent_version: "" }]) {
      await assert.rejects(one.session({ ...request(), ...patch }, "school"));
    }
    for (let i = 0; i < 240; i++) await (i % 2 ? one : two).session(request(), "school");
    await assert.rejects(two.session(request(), "school"), /rate_limited/);
    assert.ok(await two.session(request(), "different-school"));
  } finally { store.close(); }
});
