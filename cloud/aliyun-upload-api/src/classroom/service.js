"use strict";
const crypto = require("node:crypto");
const { promisify } = require("node:util");
const { createTicket, verifyTicket } = require("../auth");
const { identity, checkEntry, installExperiment, CONDITIONS } = require("./experiment");
const scrypt = promisify(crypto.scrypt);
const STAGES = ["ai_training_ground", "spinner_race", "data_chip_hunt", "signal_bomb_survival"];
const SPECIALISTS = ["level_2_puzzle", "level_3_matching", "level_4_image_judgment"];
const TOP = ["level_1_party_campaign", ...SPECIALISTS];
const CATALOG = Object.freeze([
  { id: "color_sky", name: "晴空蓝", slot: "color", value: "70d5ee", price: 100 },
  { id: "color_mint", name: "薄荷绿", slot: "color", value: "72ddbd", price: 100 },
  { id: "color_lilac", name: "葡萄紫", slot: "color", value: "b6a1ee", price: 100 },
  { id: "color_sun", name: "阳光黄", slot: "color", value: "ffda76", price: 100 },
  { id: "hat_crown", name: "星星王冠", slot: "hat", value: "crown", price: 300 },
  { id: "hat_cap", name: "探险小帽", slot: "hat", value: "cap", price: 300 },
  { id: "hat_party", name: "派对尖帽", slot: "hat", value: "party", price: 300 },
]);
class ClassroomError extends Error {
  constructor(code, status = 400) { super(code); this.code = code; this.status = status; }
}
const fail = (code, status) => { throw new ClassroomError(code, status); };
const digest = value => crypto.createHash("sha256").update(String(value)).digest("hex");
const id = () => crypto.randomUUID();
function cleanId(value) { if (!/^[A-Za-z0-9_-]{1,64}$/.test(String(value || ""))) fail("invalid_id"); return String(value); }
function passwordRule(value, minimum = 10) { if (typeof value !== "string" || value.length < minimum || value.length > 128) fail("password_length"); }
async function hashPassword(value, minimum = 10) { passwordRule(value, minimum); const salt = crypto.randomBytes(16).toString("hex"); return `${salt}:${(await scrypt(value, salt, 64)).toString("hex")}`; }
function studentPassword() { const alphabet = "23456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz"; return Array.from({ length: 6 }, () => alphabet[crypto.randomInt(alphabet.length)]).join(""); }
async function matches(value, stored) {
  const [salt, expected] = stored.split(":");
  const actual = await scrypt(String(value).slice(0, 128), salt, 64);
  return crypto.timingSafeEqual(actual, Buffer.from(expected, "hex"));
}
function publicAccount(a) { return { id: a.id, username: a.username, role: a.role, class_id: a.class_id, student_code: a.student_code, must_change_password: a.must_change_password, enabled: a.enabled, ...identity(a) }; }
function blankProgress(account, lesson) { return { id: `${account.id}_${lesson.id}`, account_id: account.id, lesson_id: lesson.id, completed: {}, stage_results: {}, quiz_responses: {}, specialist_scores: {}, revision: 0 }; }

class ClassroomService {
  constructor(store, options = {}) {
    this.store = store; this.clock = options.clock || Date.now;
    this.options = { lessonReward: 100, completionBonus: 100, studyVersion: "digcomp-v1", legacyStudyVersion: "digcomp-v1", openRegistration: true, ...options };
    this.catalog = CATALOG.map(item => ({ ...item, price: options.prices?.[item.id] ?? item.price }));
    if (![this.options.lessonReward, this.options.completionBonus, ...this.catalog.map(x => x.price)].every(x => Number.isInteger(x) && x >= 0 && x <= 100000)) throw new Error("invalid_classroom_prices");
  }
  async bootstrap(username, password, classId = "CLASS01") {
    cleanId(username); cleanId(classId); const hash = await hashPassword(password);
    return this.store.transaction(async tx => {
      const teachers = await tx.list("accounts", { role: "teacher" });
      if (teachers.length) fail("teacher_already_exists", 409);
      const account = { id: id(), username, role: "teacher", class_id: classId, student_code: "", password: hash, enabled: true, must_change_password: false, balance: 0, auth_version: 1 };
      await tx.put("accounts", account.id, account);
      return publicAccount(account);
    });
  }
  async login(username, password, teacher = false) {
    if (typeof username !== "string" || typeof password !== "string" || password.length > 128) fail("invalid_login", 401);
    const account = await this.store.transaction(async tx => {
      const key = `login_${digest(username)}`;
      const bucket = await tx.get("settings", key) || { times: [] };
      bucket.times = bucket.times.filter(time => this.clock() - time < 60000);
      if (bucket.times.length >= 15) fail("login_rate_limited", 429);
      bucket.times.push(this.clock());
      await tx.put("settings", key, bucket);
      return (await tx.list("accounts", { username }))[0];
    });
    // Same expensive hash for unknown names; no account enumeration response.
    const valid = await matches(password, account?.password || `${"0".repeat(32)}:${"0".repeat(128)}`);
    if (!valid || !account?.enabled || (account.role === "teacher") !== teacher) fail("invalid_login", 401);
    const token = crypto.randomBytes(32).toString("base64url");
    return this.store.transaction(async tx => {
      const current = await tx.get("accounts", account.id);
      if (!current.enabled || current.password !== account.password) fail("invalid_login", 401);
      const session = { id: digest(token), account_id: account.id, auth_version: current.auth_version, expires: this.clock() + 8 * 3600000 };
      await tx.put("sessions", session.id, session);
      return { token, account: publicAccount(current) };
    });
  }
  async registrationClass(tx) {
    if (!this.options.openRegistration) fail("registration_closed", 403);
    const classes = [...new Set((await tx.list("accounts", { role: "teacher", enabled: true })).map(a => a.class_id))];
    const selected = this.options.registrationClassId || (classes.length === 1 ? classes[0] : "");
    if (!selected || !classes.includes(selected)) fail("registration_unavailable", 503);
    return selected;
  }
  async register(body) {
    const username = typeof body.username === "string" ? body.username.trim() : "";
    if (!/^[A-Za-z0-9][A-Za-z0-9_-]{2,23}$/.test(username)) fail("invalid_username");
    passwordRule(body.password, 6);
    const requestId = cleanId(body.request_id), operationKey = `register_${digest(requestId)}`;
    const before = await this.store.transaction(async tx => {
      const classId = await this.registrationClass(tx);
      // Shared across FC instances. Reserve before doing an expensive password hash.
      const key = "public_registration_rate", bucket = await tx.get("settings", key) || { times: [] };
      bucket.times = bucket.times.filter(time => this.clock() - time < 10 * 60000);
      if (bucket.times.length >= 240) fail("registration_rate_limited", 429);
      bucket.times.push(this.clock()); await tx.put("settings", key, bucket);
      const operation = await tx.get("settings", operationKey);
      const existing = (await tx.list("accounts")).find(a => a.username.toLowerCase() === username.toLowerCase());
      return { classId, operation, existing };
    });
    if (before.operation) {
      if (before.existing?.id !== before.operation.account_id || before.existing.username !== username || !before.existing.enabled || !await matches(body.password, before.existing.password)) fail("request_conflict", 409);
      return { account: publicAccount(before.existing), duplicate: true };
    }
    if (before.existing) fail("username_exists", 409);
    const hash = await hashPassword(body.password, 6);
    const outcome = await this.store.transaction(async tx => {
      const classId = await this.registrationClass(tx);
      if (classId !== before.classId) fail("registration_unavailable", 503);
      const operation = await tx.get("settings", operationKey);
      if (operation) return { retryAccount: await tx.get("accounts", operation.account_id) };
      if ((await tx.list("accounts")).some(a => a.username.toLowerCase() === username.toLowerCase())) fail("username_exists", 409);
      // Role, class, balance and research identity are server-owned, never copied from body.
      const account = { id: id(), username, password: hash, class_id: classId, student_code: `S_${crypto.randomBytes(8).toString("hex")}`, role: "student", enabled: true, must_change_password: false, balance: 0, auth_version: 1, condition: "passive", registration_source: "self", created_at: this.clock() };
      await tx.put("accounts", account.id, account);
      await tx.put("settings", operationKey, { account_id: account.id });
      return { account: publicAccount(account), duplicate: false };
    });
    if (outcome.retryAccount) {
      const account = outcome.retryAccount;
      if (account.username !== username || !account.enabled || !await matches(body.password, account.password)) fail("request_conflict", 409);
      return { account: publicAccount(account), duplicate: true };
    }
    return outcome;
  }
  async authenticated(tx, token, role, allowPassword = false) {
    const session = await tx.get("sessions", digest(token));
    if (!session || session.expires <= this.clock()) fail("login_required", 401);
    const account = await tx.get("accounts", session.account_id);
    if (!account?.enabled || account.auth_version !== session.auth_version) fail("login_required", 401);
    if (role && account.role !== role) fail("forbidden", 403);
    if (account.must_change_password && !allowPassword) fail("password_change_required", 403);
    return account;
  }
  async logout(token) { return this.store.transaction(tx => tx.remove("sessions", digest(token))); }
  async changePassword(token, oldPassword, newPassword) {
    const before = await this.store.transaction(tx => this.authenticated(tx, token, null, true));
    if (!await matches(oldPassword, before.password)) fail("invalid_password", 403);
    if (oldPassword === newPassword) fail("new_password_required");
    const hash = await hashPassword(newPassword, before.role === "student" ? 6 : 10);
    await this.store.transaction(async tx => {
      const account = await this.authenticated(tx, token, null, true);
      if (account.password !== before.password) fail("login_required", 401);
      account.password = hash; account.must_change_password = false; account.auth_version++;
      await tx.put("accounts", account.id, account);
    });
    return { login_again: true };
  }
  async snapshot(tx, a) {
    const settings = await tx.get("settings", a.class_id);
    const lesson = settings?.active_lesson ? await tx.get("lessons", settings.active_lesson) : null;
    const progress = lesson ? (await tx.get("progress", `${a.id}_${lesson.id}`) || blankProgress(a, lesson)) : null;
    const inventory = await tx.get("inventory", a.id) || { owned: [], equipped: { color: "", hat: "" } };
    return { account: publicAccount(a), lesson, progress, balance: a.balance, ...inventory, catalog: this.catalog, rewards: { task: this.options.lessonReward, all: this.options.completionBonus } };
  }
  async me(token) { return this.store.transaction(async tx => this.snapshot(tx, await this.authenticated(tx, token, "student"))); }
  async startRun(token, body) {
    const level = cleanId(body.level_id);
    if (![...STAGES, ...SPECIALISTS].includes(level)) fail("unknown_level");
    const requestId = cleanId(body.request_id);
    return this.store.transaction(async tx => {
      const a = await this.authenticated(tx, token, "student");
      checkEntry(a, body.entry_condition);
      const snapshot = await this.snapshot(tx, a);
      if (!snapshot.lesson || snapshot.lesson.id !== body.lesson_id) fail("lesson_changed", 409);
      const runId = digest(`${a.id}:${requestId}`);
      const previous = await tx.get("runs", runId);
      if (previous) {
        if (previous.lesson_id !== body.lesson_id || previous.level_id !== level || previous.practice !== (body.practice === true)) fail("request_conflict", 409);
        return { run: previous, snapshot };
      }
      if (STAGES.includes(level) && body.practice !== true) {
        for (const prior of STAGES.slice(0, STAGES.indexOf(level))) if (!snapshot.progress.stage_results[prior]) fail("previous_stage_required", 409);
      }
      const run = { id: runId, account_id: a.id, lesson_id: body.lesson_id, level_id: level, practice: body.practice === true, started_at: this.clock(), expires_at: this.clock() + 4 * 3600000, submitted: false, experiment: { ...identity(a), ...(snapshot.lesson.experiment?.data_phase ? { data_phase: snapshot.lesson.experiment.data_phase } : {}) } };
      await tx.put("runs", run.id, run);
      return { run, snapshot };
    });
  }
  validateResult(run, body) {
    const r = body.result;
    if (!r || typeof r !== "object" || Array.isArray(r) || typeof r.success !== "boolean") fail("invalid_result");
    if (!Number.isFinite(r.elapsed_seconds) || r.elapsed_seconds < 0 || r.elapsed_seconds > 14400 || r.elapsed_seconds * 1000 > this.clock() - run.started_at + 15000) fail("invalid_elapsed");
    if (JSON.stringify(body).length > 50000) fail("result_too_large");
    if (r.success) {
      if (run.level_id === "level_2_puzzle" && ![9, 16, 25].includes(r.piece_count)) fail("invalid_completion");
      if (run.level_id === "level_3_matching" && r.correct_count !== 10) fail("invalid_completion");
      if (run.level_id === "level_4_image_judgment" && (r.reviewed_count !== 10 || !Number.isFinite(r.risk) || r.risk < 0 || r.risk >= 100)) fail("invalid_completion");
      if (run.level_id === "data_chip_hunt" && r.collected_count !== 12) fail("invalid_completion");
      if (run.level_id === "spinner_race" && r.checkpoints_reached !== 4) fail("invalid_completion");
      if (run.level_id === "signal_bomb_survival" && r.elapsed_seconds < 59) fail("invalid_completion");
    }
    return structuredClone(r);
  }
  async completeRun(token, body) {
    const runId = String(body.run_id || "");
    return this.store.transaction(async tx => {
      const a = await this.authenticated(tx, token, "student");
      const run = await tx.get("runs", runId);
      if (!run || run.account_id !== a.id) fail("run_not_found", 404);
      const fingerprint = digest(JSON.stringify({ result: body.result, learning: body.learning }));
      if (run.submitted) {
        if (run.fingerprint !== fingerprint) fail("result_conflict", 409);
        return { saved: true, duplicate: true, awarded: run.awarded, lesson_id: run.lesson_id, snapshot: await this.snapshot(tx, a) };
      }
      if (run.expires_at < this.clock()) fail("run_expired", 409);
      const result = this.validateResult(run, body);
      const lesson = await tx.get("lessons", run.lesson_id);
      const p = await tx.get("progress", `${a.id}_${run.lesson_id}`) || blankProgress(a, lesson);
      let awarded = 0;
      if (!run.practice) {
        // Merge only first quiz responses. Never accept a client wallet or whole save.
        const learning = body.learning || {};
        for (const [key, value] of Object.entries(learning.quiz_responses || {})) {
          if (/^[a-zA-Z0-9_-]{1,100}$/.test(key) && !p.quiz_responses[key] && value && /^area_[1-5]$/.test(value.area_id) && typeof value.correct === "boolean") p.quiz_responses[key] = value;
        }
        if (result.success) {
          const target = STAGES.includes(run.level_id) ? "level_1_party_campaign" : run.level_id;
          if (STAGES.includes(run.level_id) && !p.stage_results[run.level_id]) p.stage_results[run.level_id] = result;
          const done = target !== "level_1_party_campaign" || STAGES.every(stage => p.stage_results[stage]);
          if (done && !p.completed[target]) {
            p.completed[target] = { ...result, success: true };
            const allowed = { level_2_puzzle: ["area_5"], level_3_matching: ["area_1", "area_3"], level_4_image_judgment: ["area_2", "area_4"] }[target] || [];
            for (const area of allowed) {
              const score = learning.specialist_scores?.[area];
              if (Number.isFinite(score) && score >= 0 && score <= 100) p.specialist_scores[area] = score;
            }
            awarded += await this.reward(tx, a, `${p.id}_${target}`, this.options.lessonReward, run.lesson_id, target);
            if (TOP.every(key => p.completed[key])) awarded += await this.reward(tx, a, `${p.id}_all`, this.options.completionBonus, run.lesson_id, "all_complete");
          }
        }
        p.revision++;
        await tx.put("progress", p.id, p);
      }
      await tx.put("attempts", run.id, { id: run.id, account_id: a.id, lesson_id: run.lesson_id, level_id: run.level_id, practice: run.practice, experiment: run.experiment, result, completed_at: this.clock() });
      run.submitted = true; run.fingerprint = fingerprint; run.awarded = awarded;
      await tx.put("runs", run.id, run);
      await tx.put("accounts", a.id, a);
      return { saved: true, awarded, lesson_id: run.lesson_id, snapshot: await this.snapshot(tx, a) };
    });
  }
  async reward(tx, account, key, amount, lessonId, reason) {
    if (await tx.get("ledger", key)) return 0;
    account.balance += amount;
    await tx.put("ledger", key, { id: key, account_id: account.id, lesson_id: lessonId, amount, reason, created_at: this.clock() });
    return amount;
  }
  async purchase(token, itemId) {
    const item = this.catalog.find(x => x.id === itemId);
    if (!item) fail("unknown_item");
    return this.store.transaction(async tx => {
      const a = await this.authenticated(tx, token, "student");
      const inventory = await tx.get("inventory", a.id) || { owned: [], equipped: { color: "", hat: "" } };
      if (!inventory.owned.includes(item.id)) {
        if (a.balance < item.price) fail("insufficient_points", 409);
        a.balance -= item.price; inventory.owned.push(item.id);
        await tx.put("accounts", a.id, a);
        await tx.put("inventory", a.id, inventory);
        await tx.put("ledger", `${a.id}_buy_${item.id}`, { id: `${a.id}_buy_${item.id}`, account_id: a.id, amount: -item.price, reason: "purchase", item_id: item.id, created_at: this.clock() });
      }
      return this.snapshot(tx, a);
    });
  }
  async equip(token, slot, itemId) {
    if (!["color", "hat"].includes(slot)) fail("invalid_slot");
    return this.store.transaction(async tx => {
      const a = await this.authenticated(tx, token, "student");
      const inventory = await tx.get("inventory", a.id) || { owned: [], equipped: { color: "", hat: "" } };
      if (itemId && (!inventory.owned.includes(itemId) || !this.catalog.some(x => x.id === itemId && x.slot === slot))) fail("item_not_owned", 403);
      inventory.equipped[slot] = itemId || "";
      await tx.put("inventory", a.id, inventory);
      return this.snapshot(tx, a);
    });
  }
  async batchStudents(token, count, prefix, classId) {
    if (!Number.isInteger(count) || count < 1 || count > 60) fail("invalid_count");
    if (!/^[A-Za-z][A-Za-z0-9_-]{0,20}$/.test(prefix || "")) fail("invalid_prefix");
    await this.store.transaction(async tx => this.teacherClass(tx, await this.authenticated(tx, token, "teacher"), classId));
    const accounts = [];
    for (let i = 1; i <= count; i++) {
      const password = studentPassword();
      accounts.push({ username: `${prefix}${String(i).padStart(3, "0")}`, initial_password: password, password: await hashPassword(password, 6) });
    }
    return this.store.transaction(async tx => {
      const teacher = await this.teacherClass(tx, await this.authenticated(tx, token, "teacher"), classId);
      const meta = await tx.get("settings", "class_meta:" + teacher.class_id);
      const existing = await tx.list("accounts");
      if (accounts.some(a => existing.some(e => e.username === a.username))) fail("username_exists", 409);
      for (const item of accounts) {
        const account = { id: id(), username: item.username, password: item.password, class_id: teacher.class_id, student_code: `S_${crypto.randomBytes(8).toString("hex")}`, role: "student", enabled: true, must_change_password: true, balance: 0, auth_version: 1, condition: meta?.condition || "passive", study_version: meta?.study_version || "", scaffold_policy_version: meta?.scaffold_policy_version || "" };
        await tx.put("accounts", account.id, account);
      }
      return accounts.map(({ username, initial_password }) => ({ username, initial_password, class_id: teacher.class_id, class_name: meta?.name || teacher.class_id, condition: meta?.condition || "passive", entry_path: identity({ condition: meta?.condition }).entry_path }));
    });
  }
  async manageStudent(token, accountId, action) {
    const password = action === "reset_password" ? studentPassword() : "";
    const hash = password ? await hashPassword(password, 6) : "";
    return this.store.transaction(async tx => {
      const teacher = await this.authenticated(tx, token, "teacher");
      const a = await tx.get("accounts", accountId);
      if (!a || a.role !== "student" || ![teacher.class_id, ...(teacher.managed_class_ids || [])].includes(a.class_id)) fail("student_not_found", 404);
      if (action === "reset_password") { a.password = hash; a.must_change_password = true; }
      else if (action === "disable") a.enabled = false;
      else if (action === "enable") a.enabled = true;
      else fail("unknown_action");
      a.auth_version++;
      await tx.put("accounts", a.id, a);
      return { account: publicAccount(a), ...(password ? { initial_password: password } : {}) };
    });
  }
  async lesson(token, action, title, requestId, targetLesson = "", classId, dataPhase) {
    cleanId(requestId);
    return this.store.transaction(async tx => {
      const owner = await this.authenticated(tx, token, "teacher");
      const teacher = await this.teacherClass(tx, owner, classId);
      const operationId = `lessonop_${digest(`${teacher.id}:${teacher.class_id}:${requestId}`)}`;
      const priorOperation = await tx.get("settings", operationId) || (teacher.class_id === owner.class_id ? await tx.get("settings", `lessonop_${digest(`${teacher.id}:${requestId}`)}`) : null);
      if (priorOperation) {
        if (priorOperation.action !== action || priorOperation.target !== targetLesson || (action === "open" && dataPhase && priorOperation.result?.experiment?.data_phase && priorOperation.result.experiment.data_phase !== dataPhase)) fail("request_conflict", 409);
        return priorOperation.result;
      }
      const settings = await tx.get("settings", teacher.class_id) || {};
      if (action === "open") {
        if (typeof title !== "string" || !title.trim() || title.length > 60) fail("invalid_title");
        const lessonId = digest(`${teacher.class_id}:${requestId}`);
        const prior = await tx.get("lessons", lessonId);
        if (prior) return prior;
        if (settings.active_lesson) fail("close_current_lesson", 409);
        const meta = await tx.get("settings", "class_meta:" + teacher.class_id);
        if (meta && dataPhase && !["pilot", "formal"].includes(dataPhase)) fail("invalid_data_phase");
        const lesson = { id: lessonId, class_id: teacher.class_id, title: title.trim(), opened_at: this.clock(), closed_at: null, ...(meta ? { experiment: { condition: meta.condition, study_version: meta.study_version, scaffold_policy_version: meta.scaffold_policy_version, data_phase: dataPhase || "pilot" } } : {}) };
        await tx.put("lessons", lesson.id, lesson);
        await tx.put("settings", teacher.class_id, { active_lesson: lesson.id });
        await tx.put("settings", operationId, { action, target: targetLesson, result: lesson });
        return lesson;
      }
      if (action !== "close") fail("unknown_action");
      if (targetLesson && settings.active_lesson && settings.active_lesson !== targetLesson) fail("lesson_changed", 409);
      if (settings.active_lesson) {
        const current = await tx.get("lessons", settings.active_lesson);
        current.closed_at = this.clock(); await tx.put("lessons", current.id, current);
        await tx.put("settings", teacher.class_id, { active_lesson: "" });
      }
      await tx.put("settings", operationId, { action, target: targetLesson, result: { closed: true } });
      return { closed: true };
    });
  }
  async dashboard(token, classId) {
    const data = await this.store.transaction(async tx => {
      const teacher = await this.teacherClass(tx, await this.authenticated(tx, token, "teacher"), classId);
      const students = await tx.list("accounts", { role: "student", class_id: teacher.class_id });
      const studentsIds = new Set(students.map(x => x.id));
      return { teacher: publicAccount(teacher), students: students.map(a => ({ ...publicAccount(a), balance: a.balance })), lessons: await tx.list("lessons", { class_id: teacher.class_id }), active_lesson: (await tx.get("settings", teacher.class_id))?.active_lesson || "", progress: (await tx.list("progress")).filter(x => studentsIds.has(x.account_id)), ledger: (await tx.list("ledger")).filter(x => studentsIds.has(x.account_id)), attempts: (await tx.list("attempts")).filter(x => studentsIds.has(x.account_id)), scaffolds: (await tx.list("settings", { kind: "scaffold_state" })).filter(x => studentsIds.has(x.account_id)).map(({ clients, fingerprints, ...record }) => record) };
    });
    const classes = await this.classes(token);
    return { ...data, classes, class_meta: classes.find(c => c.class_id === data.teacher.class_id), rewards: { task: this.options.lessonReward, all: this.options.completionBonus }, catalog: this.catalog };
  }
  async studyTicket(token, resumeUploadId = "", entryCondition, resumeTicket = "") {
    return this.store.transaction(async tx => {
      const a = await this.authenticated(tx, token, "student");
      const previous = resumeUploadId ? await tx.get("settings", `study_${String(resumeUploadId).slice(0, 80)}`) : null;
      if (resumeUploadId && (!previous || previous.account_id !== a.id)) fail("upload_not_found", 404);
      if (!previous) checkEntry(a, entryCondition);
      const lessonId = previous?.lesson_id || (await tx.get("settings", a.class_id))?.active_lesson;
      if (!lessonId) fail("no_active_lesson", 409);
      const uploadId = previous?.upload_id || id();
      let assignment = previous?.assignment;
      let legacyIdentityRecovered = previous?.legacy_identity_recovered;
      if (previous && !assignment) {
        // Expiry may lapse; the original signature and account/upload binding must still verify.
        if (resumeTicket) {
          try { assignment = verifyTicket(resumeTicket, this.options.linkSecret, 0); } catch { fail("resume_identity_invalid", 403); }
          if (assignment.upload_id !== uploadId || assignment.student_code !== a.student_code) fail("resume_identity_invalid", 403);
          legacyIdentityRecovered = "original_signed_ticket";
        } else {
          // Released Godot clients only send the upload id. These legacy accounts cannot
          // change groups/classes through this API; never apply this fallback to experiments.
          const oldLesson = await tx.get("lessons", lessonId);
          if (!["active", "passive"].includes(a.condition || "passive") || oldLesson?.class_id !== a.class_id) fail("resume_identity_required", 409);
          assignment = { study_version: this.options.legacyStudyVersion, condition: a.condition || "passive", class_id: oldLesson.class_id, student_code: a.student_code, upload_id: uploadId };
          legacyIdentityRecovered = "legacy_account_and_lesson";
        }
      }
      const lesson = await tx.get("lessons", lessonId);
      assignment ||= { study_version: a.study_version || this.options.studyVersion, condition: a.condition || "passive", class_id: a.class_id, student_code: a.student_code, upload_id: uploadId, ...(a.scaffold_policy_version ? { scaffold_policy_version: a.scaffold_policy_version } : {}), ...(lesson?.experiment?.data_phase ? { data_phase: lesson.experiment.data_phase } : {}) };
      const claims = { ...assignment, exp: Math.floor(this.clock() / 1000) + 4 * 3600 };
      const ticket = createTicket(claims, this.options.linkSecret);
      await tx.put("settings", `study_${uploadId}`, { account_id: a.id, lesson_id: lessonId, upload_id: uploadId, assignment, ...(legacyIdentityRecovered ? { legacy_identity_recovered: legacyIdentityRecovered } : {}), expires_at: claims.exp * 1000 });
      return { ticket, claims, lesson_id: lessonId, entry_path: identity(a).entry_path };
    });
  }
}
installExperiment(ClassroomService);
module.exports = { ClassroomService, ClassroomError, STAGES, SPECIALISTS, TOP, CATALOG };
