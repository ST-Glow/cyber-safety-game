"use strict";

const crypto = require("node:crypto");
const express = require("express");
const { createTicket } = require("./auth");
const { createMysqlStore } = require("./classroom/store");

const VERSION = "lesson1-student-trial-v1";
const CONSENT = "lesson1-tab-recording-v1";
const { EXPERIMENT, experimentConfig, mountExperiment, scaffoldState, authorizeAgent } = require('./lesson1-experiment');
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const fail = (code, status = 400) => { throw Object.assign(new Error(code), { code, status }); };
const digest = value => crypto.createHash("sha256").update(value).digest("hex");

class Lesson1TrialService {
  constructor(store, secret, clock = Date.now, experiment = experimentConfig()) { this.store = store; this.secret = secret; this.clock = clock; this.experiment = experiment; }
  async session(body, address = "", renew = false) {
    const segment = String(body.segment_id || "");
    const key = String(body.client_key || "");
    if (!UUID.test(segment) || !/^[a-f0-9]{64}$/.test(key)) fail("trial_session_invalid");
    const now = this.clock();
    const record = await this.store.transaction(async tx => {
      const id = `lesson1_trial:${segment}`;
      const existing = await tx.get("settings", id);
      if (existing) {
        if (existing.client_key_hash !== digest(key)) fail("trial_session_owner_mismatch", 403);
        if (now - existing.created_at > 30 * 86400000) fail("trial_session_expired", 410);
        if (!renew && (body.run_id !== existing.run_id || body.class_id !== existing.class_id
          || String(body.student_name || "").normalize("NFC").trim().replace(/\s+/gu, " ") !== existing.student_name)) fail("trial_session_conflict", 409);
        return existing;
      }
      if (renew) fail("trial_session_not_found", 404);
      const deviceCheck = body.activity_type === 'device_check_30s';
      if (!/^g7-(0[1-9]|1[0-6])$/.test(body.class_id || "") && !(deviceCheck && body.class_id === 'g7-other')) fail("trial_class_invalid");
      const name = String(body.student_name || "").normalize("NFC").trim().replace(/\s+/gu, " ");
      if (!name || name.length > 32 || !/\p{L}/u.test(name) || /[<>\p{Cc}\p{Cf}]/u.test(name)) fail("trial_name_invalid");
      if (!String(body.run_id || "").startsWith("lesson1-") || !UUID.test(String(body.run_id).slice(8))) fail("trial_run_invalid");
      if (body.consent_version !== CONSENT) fail("trial_consent_required");
      if (body.activity_type && !['device_check_30s', 'lesson1_game'].includes(body.activity_type)) fail('trial_activity_invalid');
      let assignment = {};
      if (deviceCheck) {
        if (!['g7-01', 'g7-06', 'g7-other'].includes(body.class_id)) fail('trial_class_invalid');
      } else if (this.experiment.enabled) {
        const condition = { 'g7-01': 'proactive', 'g7-06': 'reactive' }[body.class_id];
        if (!condition || body.experiment_version !== EXPERIMENT) fail('experiment_entry_required', 409);
        assignment = { condition, experiment_version: EXPERIMENT, scaffold_policy_version: 'timing-v2', experiment_round: this.experiment.round, data_phase: 'pilot' };
      } else if (body.experiment_version) fail('experiment_not_enabled', 503);
      // Shared school NATs can start a class together; limits apply across FC instances.
      const window = Math.floor(now / 600000);
      const rateId = `lesson1_rate:${window}:${crypto.createHmac("sha256", this.secret).update(address).digest("hex").slice(0, 32)}`;
      const rate = await tx.get("settings", rateId) || { kind: "lesson1_trial_rate", count: 0, created_at: now };
      if (rate.count >= 240) fail("trial_rate_limited", 429);
      rate.count++;
      await tx.put("settings", rateId, rate);
      const created = {
        kind: "lesson1_trial_session", segment_id: segment, run_id: body.run_id,
        class_id: body.class_id, class_name: body.class_id === 'g7-other' ? '其他班级' : `七年级${Number(body.class_id.slice(3))}班`, student_name: name,
        identity_source: "self_reported_trial", consent_version: CONSENT, consent_at: now,
        client_key_hash: digest(key), created_at: now, upload_id: crypto.randomUUID(),
        student_code: `T_${crypto.randomBytes(12).toString("hex")}`,
        activity_type: deviceCheck ? 'device_check_30s' : 'lesson1_game', ...assignment,
      };
      await tx.put("settings", id, created);
      await tx.put("settings", `lesson1_upload:${created.upload_id}`, { kind: "lesson1_trial_upload", session_id: id });
      return created;
    });
    const claims = { study_version: VERSION, condition: record.condition || "passive", class_id: record.class_id,
      ...(record.scaffold_policy_version ? { scaffold_policy_version: record.scaffold_policy_version, data_phase: record.data_phase } : {}),
      student_code: record.student_code, upload_id: record.upload_id, exp: Math.floor(now / 1000) + 900 };
    return { ticket: createTicket(claims, this.secret), claims, segment_id: record.segment_id,
      ...(record.experiment_version ? { experiment: { condition: record.condition, version: record.experiment_version, round: record.experiment_round, policy: record.scaffold_policy_version, data_phase: record.data_phase } } : {}) };
  }
  async metadata(claims) {
    if (claims.study_version !== VERSION) return null;
    return this.store.transaction(async tx => {
      const link = await tx.get("settings", `lesson1_upload:${claims.upload_id}`);
      const record = link && await tx.get("settings", link.session_id);
      if (!record || record.class_id !== claims.class_id || record.student_code !== claims.student_code || (record.condition || 'passive') !== claims.condition) fail("trial_session_owner_mismatch", 403);
      const { segment_id, run_id, class_id, class_name, student_name, identity_source, consent_version, consent_at } = record;
      return { segment_id, run_id, class_id, class_name, student_name, identity_source, consent_version, consent_at,
        activity_type: record.activity_type || 'lesson1_game', condition: record.condition || 'passive',
        ...(record.experiment_version ? { experiment_version: record.experiment_version, experiment_round: record.experiment_round, scaffold_policy_version: record.scaffold_policy_version, data_phase: record.data_phase } : {}) };
    });
  }
  scaffold(claims, body) { return scaffoldState(this, claims, body); }
  authorizeAgent(claims, body, polling = false) { return authorizeAgent(this, claims, body, polling); }
}

function mountLesson1Trial(app, { config, service, enabled = process.env.LESSON1_TRIAL_ENABLED === "true" } = {}) {
  let pending;
  const getService = async () => {
    if (service) return service;
    if (!enabled) fail("trial_not_enabled", 503);
    pending ||= createMysqlStore().then(store => new Lesson1TrialService(store, config.linkSecret)).catch(error => { pending = null; throw error; });
    return pending;
  };
  mountExperiment(app, getService, config.linkSecret);
  for (const [path, renew] of [["/api/lesson1/trial/sessions", false], ["/api/lesson1/trial/renew", true]]) {
    app.post(path, express.json({ limit: "4kb" }), async (req, res) => {
      res.setHeader("Cache-Control", "no-store");
      try { res.json(await (await getService()).session(req.body || {}, req.ip || "", renew)); }
      catch (error) { res.status(error.status || 503).json({ code: error.code || "trial_storage_unavailable" }); }
    });
  }
  return { metadata: async claims => claims.study_version === VERSION ? (await getService()).metadata(claims) : null,
    authorizeAgent: async (claims, body, polling) => (await getService()).authorizeAgent(claims, body, polling) };
}

module.exports = { VERSION, CONSENT, Lesson1TrialService, mountLesson1Trial };
