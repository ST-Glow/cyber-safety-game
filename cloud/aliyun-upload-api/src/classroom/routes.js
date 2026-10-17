"use strict";
const express = require("express");
const path = require("node:path");
const { ClassroomService } = require("./service");
const { createMysqlStore } = require("./store");

function mountClassroom(app, options = {}) {
  if (!options.service && process.env.CLASSROOM_ENABLED !== "true") return;
  let servicePromise;
  function service() {
    if (options.service) return Promise.resolve(options.service);
    if (!servicePromise) servicePromise = createMysqlStore().then(store => new ClassroomService(store, {
      linkSecret: process.env.UPLOAD_LINK_SECRET,
      studyVersion: process.env.CLASSROOM_STUDY_VERSION || "digcomp-v1",
      lessonReward: Number(process.env.CLASSROOM_TASK_REWARD || 100),
      completionBonus: Number(process.env.CLASSROOM_ALL_REWARD || 100),
      prices: JSON.parse(process.env.CLASSROOM_PRICES_JSON || "{}"),
      openRegistration: process.env.CLASSROOM_OPEN_REGISTRATION !== "false",
      registrationClassId: process.env.CLASSROOM_REGISTRATION_CLASS_ID || "",
    })).catch(error => { servicePromise = null; throw error; });
    return servicePromise;
  }
  const router = express.Router();
  router.use(express.json({ limit: "64kb" }));
  router.use((_request, response, next) => { response.setHeader("Cache-Control", "no-store"); next(); });
  const buckets = new Map();
  const route = (method, url, call) => router[method](url, async (request, response) => {
    const token = String(request.headers.authorization || "").replace(/^Bearer /, "");
    try {
      if (url === "/auth/login") {
        const key = String(request.body?.username || "").slice(0, 64);
        const now = Date.now();
        const recent = (buckets.get(key) || []).filter(t => now - t < 60000);
        if (recent.length >= 15) return response.status(429).json({ code: "login_rate_limited" });
        recent.push(now); buckets.set(key, recent);
        if (buckets.size > 2000) for (const [name, times] of buckets) if (now - times.at(-1) >= 60000) buckets.delete(name);
      }
      const result = await call(await service(), token, request.body || {}, request);
      response.json(result ?? { ok: true });
    } catch (error) {
      const status = error.status || 503;
      console.error(JSON.stringify({ event: "classroom_request_failed", path: url, status, code: error.code || "storage_unavailable" }));
      response.status(status).json({ code: error.code || "storage_unavailable" });
    }
  });
  route("post", "/auth/login", (s, _t, b) => s.login(b.username, b.password, b.teacher === true));
  route("post", "/auth/register", (s, _t, b) => s.register(b));
  route("post", "/auth/logout", (s, t) => s.logout(t));
  route("post", "/auth/password", (s, t, b) => s.changePassword(t, b.old_password, b.new_password));
  route("get", "/me", (s, t) => s.me(t));
  route("post", "/runs/start", (s, t, b) => s.startRun(t, b));
  route("post", "/runs/complete", (s, t, b) => s.completeRun(t, b));
  route("post", "/shop/purchase", (s, t, b) => s.purchase(t, b.item_id));
  route("post", "/shop/equip", (s, t, b) => s.equip(t, b.slot, b.item_id));
  route("post", "/study/ticket", (s, t, b) => s.studyTicket(t, b.resume_upload_id, b.entry_condition, b.resume_ticket));
  route("get", "/teacher/classes", (s, t) => s.classes(t));
  route("post", "/teacher/classes", (s, t, b) => s.createClass(t, b));
  route("get", "/study/scaffold/state", (s, t, _b, r) => s.scaffoldState(t, r.query));
  route("post", "/study/scaffold/events", (s, t, b) => s.scaffoldState(t, b, true));
  route("get", "/teacher/dashboard", (s, t, _b, r) => s.dashboard(t, r.query.class_id));
  route("post", "/teacher/students", (s, t, b) => s.batchStudents(t, b.count, b.prefix, b.class_id));
  route("post", "/teacher/students/:id", (s, t, b, r) => s.manageStudent(t, r.params.id, b.action));
  route("post", "/teacher/lessons", (s, t, b) => s.lesson(t, b.action, b.title, b.request_id, b.lesson_id, b.class_id, b.data_phase));
  app.use("/api/classroom", router);
  app.use("/classroom", express.static(path.join(__dirname, "../../public/classroom"), {
    setHeaders(response) {
      response.setHeader("Cache-Control", "no-store");
      response.setHeader("X-Content-Type-Options", "nosniff");
      response.setHeader("Content-Security-Policy", "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; frame-ancestors 'none'; base-uri 'none'; form-action 'self'");
    },
  }));
}
module.exports = { mountClassroom };
