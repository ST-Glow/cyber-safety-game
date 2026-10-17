"use strict";
const crypto = require('node:crypto');
const { isKnownLevelId } = require('../agent-context');
const POLICY = 'timing-v2';
const STUDY = 'classroom-timing-v1';
const CONDITIONS = new Set(['proactive', 'reactive']);
const entry = condition => condition === 'proactive' ? '/classroom/a/' : condition === 'reactive' ? '/classroom/b/' : '/classroom/native/';
const hash = value => crypto.createHash('sha256').update(String(value)).digest('hex');
const identity = account => ({ condition: account.condition || 'passive', study_version: account.study_version || '', scaffold_policy_version: account.scaffold_policy_version || '', entry_path: entry(account.condition) });
function error(code, status = 400) { throw Object.assign(new Error(code), { code, status }); }
const safeMapKey = (value, pattern) => typeof value === 'string' && pattern.test(value) && value !== 'prototype' && !Object.hasOwn(Object.prototype, value);
function checkEntry(account, requested) { if (CONDITIONS.has(account.condition) && requested !== account.condition) error('experiment_entry_mismatch', 409); }
function installExperiment(ClassroomService) {
  Object.assign(ClassroomService.prototype, {
    async teacherClass(tx, teacher, requested) {
      const classId = requested || teacher.class_id;
      if (![teacher.class_id, ...(teacher.managed_class_ids || [])].includes(classId)) error('forbidden', 403);
      const meta = await tx.get('settings', 'class_meta:' + classId);
      if (meta && meta.owner_teacher_id !== teacher.id) error('forbidden', 403);
      return { ...teacher, class_id: classId };
    },
    async classes(token) {
      return this.store.transaction(async tx => {
        const teacher = await this.authenticated(tx, token, 'teacher');
        return Promise.all([...new Set([teacher.class_id, ...(teacher.managed_class_ids || [])])].map(async class_id =>
          await tx.get('settings', 'class_meta:' + class_id) || { class_id, name: class_id, condition: 'legacy', entry_path: '/classroom/native/' }));
      });
    },
    async createClass(token, body) {
      if (!CONDITIONS.has(body.condition) || typeof body.name !== 'string' || !body.name.trim() || body.name.length > 60 || !/^[\w-]{1,64}$/.test(body.request_id || '')) error('invalid_class');
      return this.store.transaction(async tx => {
        const teacher = await this.authenticated(tx, token, 'teacher');
        const class_id = 'C_' + hash(teacher.id + ':' + body.request_id).slice(0, 24);
        const key = 'class_meta:' + class_id, previous = await tx.get('settings', key);
        if (previous) { if (previous.name !== body.name.trim() || previous.condition !== body.condition) error('request_conflict', 409); return previous; }
        const sameCondition = (await tx.list('settings', { kind: 'experiment_class', owner_teacher_id: teacher.id })).find(c => c.study_version === STUDY && c.condition === body.condition);
        if (sameCondition) error('experiment_class_exists', 409);
        const meta = { kind: 'experiment_class', class_id, name: body.name.trim(), owner_teacher_id: teacher.id, condition: body.condition, study_version: STUDY, scaffold_policy_version: POLICY, entry_path: entry(body.condition), created_at: this.clock() };
        teacher.managed_class_ids = [...new Set([...(teacher.managed_class_ids || []), class_id])];
        await tx.put('accounts', teacher.id, teacher); await tx.put('settings', key, meta); return meta;
      });
    },
    async scaffoldState(token, body, write = false) {
      if (!isKnownLevelId(body.level_id) || body.level_id === 'digcomp_hub' || !/^[\w-]{1,100}$/.test(body.lesson_id || '')) error('invalid_scaffold_context');
      return this.store.transaction(async tx => {
        const account = await this.authenticated(tx, token, 'student');
        if (!CONDITIONS.has(account.condition)) error('experiment_required', 403);
        const lesson = await tx.get('lessons', body.lesson_id);
        if (!lesson || lesson.class_id !== account.class_id) error('forbidden', 403);
        const key = 'scaffold:' + hash(account.id + ':' + lesson.id + ':' + body.level_id);
        const state = await tx.get('settings', key) || { kind: 'scaffold_state', account_id: account.id, class_id: account.class_id, lesson_id: lesson.id, level_id: body.level_id, ...identity(account), scopes: {}, shown: 0, cooldown: 0, safety_errors: 0, revision: 0, clients: {} };
        if (lesson.experiment?.data_phase) state.data_phase = lesson.experiment.data_phase;
        if (write) {
          if (!Array.isArray(body.events) || body.events.length > 100 || !safeMapKey(body.client_id, /^[\w-]{1,64}$/)) error('invalid_scaffold_events');
          if (!state.clients[body.client_id] && Object.keys(state.clients).length >= 100) error('scaffold_session_limit', 409);
          let last = state.clients[body.client_id] || 0;
          state.fingerprints ||= {};
          const fingerprints = state.fingerprints[body.client_id] ||= {};
          for (const event of body.events) {
            if (!event || !Number.isInteger(event.seq) || event.seq < 1) error('invalid_scaffold_event');
            const fingerprint = hash(JSON.stringify(Object.fromEntries(Object.entries(event).sort(([a], [b]) => a.localeCompare(b)))));
            if (fingerprints[event.seq] && fingerprints[event.seq] !== fingerprint) error('scaffold_event_conflict', 409);
            if (event.seq <= last) continue;
            if (event.seq !== last + 1) error('scaffold_event_gap', 409);
            if (!event || !['scope','failure','success','progress','shown','decision','cooldown','hint'].includes(event.type) || !safeMapKey(event.scope_id, /^[\w:.-]{1,120}$/)) error('invalid_scaffold_event');
            if (!state.scopes[event.scope_id] && Object.keys(state.scopes).length >= 300) error('scaffold_scope_limit', 409);
            const scope = state.scopes[event.scope_id] ||= { failed: false, failures: 0, errors: 0, shown_failure: 0, hint_count: 0 };
            if (event.type === 'scope') state.last_scope = event.scope_id;
            if (event.type === 'failure') { scope.failed = true; scope.failures++; scope.errors++; if (event.safety) state.safety_errors++; }
            if (event.type === 'success') { scope.errors = 0; if (event.safety) state.safety_errors = 0; }
            if (event.type === 'progress' || event.type === 'success') scope.declined = false;
            if (event.type === 'shown') {
              if (!safeMapKey(event.scaffold_id, /^[\w-]{1,120}$/)) error('invalid_scaffold_event');
              state.invitation_ids ||= {};
              const priorScope = state.invitation_ids[event.scaffold_id];
              if (priorScope && priorScope !== event.scope_id) error('scaffold_event_conflict', 409);
              const repeated = priorScope === event.scope_id || scope.last_invitation === event.scaffold_id;
              if (!repeated) {
                if (state.shown >= 3) error('scaffold_quota_reached', 409);
                const family = account.condition === 'proactive' ? 'proactive' : 'reactive';
                if (event.family !== family || (family === 'proactive' && scope.failed)) error('scaffold_condition_forbidden', 403);
                if (family === 'proactive' && scope.declined) error('scaffold_evidence_unchanged', 409);
                if (family === 'reactive' && (event.safety ? state.safety_errors : scope.errors) < 2) error('scaffold_threshold_not_met', 409);
                if (family === 'reactive' && !scope.remind && scope.failures <= scope.shown_failure) error('scaffold_evidence_unchanged', 409);
                if (state.cooldown > 0) error('scaffold_cooldown', 409);
                state.shown++; state.invitation_ids[event.scaffold_id] = event.scope_id;
                scope.shown_failure = scope.failures; scope.last_invitation = event.scaffold_id;
                scope.remind = false; scope.last_family = family; scope.last_reason = String(event.reason || event.trigger_reason || '').slice(0, 80);
              }
            }
            if (event.type === 'decision') {
              if (!['accepted','rejected','dismissed','closed'].includes(event.choice)) error('invalid_scaffold_event');
              state.cooldown = 30; scope.remind = event.choice === 'dismissed'; scope.last_decision = event.choice;
              if (event.choice === 'rejected') scope.declined = true;
            }
            if (event.type === 'cooldown' && Number.isFinite(event.remaining)) state.cooldown = Math.max(0, Math.min(state.cooldown, event.remaining));
            if (event.type === 'hint') {
              scope.hint_count++;
              scope.last_hint = { scope_id: event.scope_id, scaffold_id: String(event.scaffold_id || '').slice(0,120), trigger_reason: String(event.trigger_reason || 'manual').slice(0,80), trigger_family: String(event.trigger_family || 'manual').slice(0,40), hint_count: scope.hint_count, scaffold_policy_version: account.scaffold_policy_version || POLICY };
            }
            state.revision++; last = event.seq; fingerprints[last] = fingerprint;
          }
          for (const seq of Object.keys(fingerprints)) if (Number(seq) < last - 200) delete fingerprints[seq];
          state.clients[body.client_id] = last; await tx.put('settings', key, state);
        }
        return { state, acknowledged: state.clients[body.client_id] || 0 };
      });
    },
  });
}
module.exports = { POLICY, STUDY, CONDITIONS, entry, identity, checkEntry, installExperiment };
