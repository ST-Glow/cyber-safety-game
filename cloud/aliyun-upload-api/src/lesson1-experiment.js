'use strict';
const crypto = require('node:crypto');
const express = require('express');
const { verifyTicket } = require('./auth');
const EXPERIMENT = 'lesson1-two-class-v1';
const LEVEL = 'g7_internet_l01';
const CLASSES = [{ class_id: 'g7-01', name: '初一1班' }, { class_id: 'g7-06', name: '初一6班' }];
const fail = (code, status = 403) => { throw Object.assign(Error(code), { code, status }); };
const safe = value => /^[A-Za-z0-9_.:-]{1,120}$/.test(value || '') && value !== '__proto__' && !Object.hasOwn(Object.prototype, value);
const scopeValid = value => /^network:(early|protocol|mesh):(connect|connect_b|link|test|fault|repair|retest)$/.test(value || '') || /^knowledge:[012]$/.test(value || '');
function experimentConfig() { return { enabled: process.env.LESSON1_EXPERIMENT_ENABLED === 'true', round: process.env.LESSON1_EXPERIMENT_ROUND_ID || 'lesson1-pilot-20261016' }; }
async function context(service, claims) {
  const metadata = await service.metadata(claims);
  if (!service.experiment.enabled || metadata?.experiment_version !== EXPERIMENT || metadata.activity_type !== 'lesson1_game') fail('trial_upload_ticket_only');
  const identity = [metadata.class_id, metadata.student_name, metadata.experiment_round, LEVEL];
  const hash = crypto.createHmac('sha256', service.secret).update(JSON.stringify(identity)).digest('hex');
  return { metadata, key: 'lesson1_scaffold:' + hash };
}
function initial() { return { kind: 'lesson1_scaffold', scopes: {}, shown: 0, cooldown: 0, cooldown_at: 0, clients: {}, invitations: {}, requests: {}, revision: 0 }; }
async function scaffoldState(service, claims, body) {
  const { key } = await context(service, claims), now = service.clock();
  return service.store.transaction(async tx => {
    const state = await tx.get('settings', key) || initial();
    if (body.events) {
      if (!safe(body.client_id) || !Array.isArray(body.events) || body.events.length > 100) fail('invalid_scaffold_events', 400);
      if (!state.clients[body.client_id] && Object.keys(state.clients).length >= 200) fail('scaffold_client_limit', 409);
      const cursor = state.clients[body.client_id] ||= { seq: 0, hashes: {} };
      for (const event of body.events) {
        if (!Number.isInteger(event.seq) || event.seq < 1 || !scopeValid(event.scope_id)) fail('invalid_scaffold_event', 400);
        const fingerprint = crypto.createHash('sha256').update(JSON.stringify(event)).digest('hex');
        if (event.seq <= cursor.seq) { if (cursor.hashes[event.seq] && cursor.hashes[event.seq] !== fingerprint) fail('scaffold_event_conflict', 409); continue; }
        if (event.seq !== cursor.seq + 1) fail('scaffold_event_gap', 409);
        const scope = state.scopes[event.scope_id] ||= { failed: false, failures: 0, errors: 0, shown_failure: 0, hint_count: 0 };
        if (event.type === 'scope') state.last_scope = event.scope_id;
        else if (event.type === 'failure') { scope.failed = true; scope.failures++; scope.errors++; }
        else if (event.type === 'progress' || event.type === 'success') { scope.declined = false; if (event.type === 'success') scope.errors = 0; }
        else if (event.type === 'cooldown') {
          const floor = Math.max(0, state.cooldown - Math.max(0, now - state.cooldown_at) / 1000);
          state.cooldown = Math.max(floor, Math.min(state.cooldown, Number(event.remaining) || 0)); state.cooldown_at = now;
        } else if (event.type === 'shown') {
          if (!safe(event.scaffold_id) || event.family !== claims.condition) fail('scaffold_condition_forbidden');
          if (!state.invitations[event.scaffold_id]) {
            if (state.shown >= 3) fail('scaffold_quota_reached', 409);
            if (state.cooldown > 0) fail('scaffold_cooldown', 409);
            if (claims.condition === 'proactive' && (scope.failed || scope.declined)) fail('scaffold_condition_forbidden');
            if (claims.condition === 'reactive' && (scope.errors < 2 || (!scope.remind && scope.failures <= scope.shown_failure))) fail('scaffold_threshold_not_met', 409);
            const allowed = claims.condition === 'proactive' ? ['idle', 'no_progress'] : ['repeated_failure', 'repeated_strategy', 'quiz_error'];
            if (!allowed.includes(event.trigger_reason)) fail('scaffold_condition_forbidden');
            state.shown++;
            state.invitations[event.scaffold_id] = { scope: event.scope_id, trigger: event.trigger_reason, previous_shown_failure: scope.shown_failure };
            scope.shown_failure = scope.failures; scope.remind = false;
          } else if (state.invitations[event.scaffold_id].scope !== event.scope_id || state.invitations[event.scaffold_id].cancelled) fail('scaffold_event_conflict', 409);
        } else if (event.type === 'displayed' || event.type === 'unshown') {
          const invite = state.invitations[event.scaffold_id];
          if (!invite || invite.scope !== event.scope_id) fail('invitation_not_found');
          if (event.type === 'displayed') { if (invite.cancelled) fail('invitation_cancelled', 409); invite.displayed = true; }
          else if (!invite.displayed && !invite.choice && !invite.cancelled) {
            invite.cancelled = true; state.shown = Math.max(0, state.shown - 1); scope.shown_failure = invite.previous_shown_failure;
          }
        } else if (event.type === 'decision') {
          if (!['accepted', 'rejected', 'dismissed', 'closed'].includes(event.choice)) fail('invalid_scaffold_event', 400);
          const invite = state.invitations[event.scaffold_id];
          if (event.choice !== 'closed' && (!invite || invite.scope !== event.scope_id)) fail('invitation_not_found');
          if (invite) { invite.choice = event.choice; invite.displayed = true; }
          scope.remind = event.choice === 'dismissed'; if (event.choice === 'rejected') scope.declined = true;
          state.cooldown = 30; state.cooldown_at = now;
        } else if (event.type === 'request') {
          if (!safe(event.scaffold_id) || !['manual', 'idle', 'no_progress', 'repeated_failure', 'repeated_strategy', 'quiz_error'].includes(event.trigger_reason)) fail('invalid_agent_request', 400);
          if (event.trigger_reason !== 'manual') {
            const invite = state.invitations[event.scaffold_id];
            if (!invite || invite.scope !== event.scope_id || invite.trigger !== event.trigger_reason || invite.choice !== 'accepted') fail('agent_invitation_required');
          }
          state.requests[event.scaffold_id] = { scope: event.scope_id, trigger: event.trigger_reason };
          if (Object.keys(state.requests).length > 200) fail('agent_request_limit', 429);
        } else if (event.type === 'hint') {
          if (!state.requests[event.scaffold_id]) fail('agent_request_required');
          scope.hint_count++; scope.last_hint = { scope_id: event.scope_id, scaffold_id: event.scaffold_id, trigger_reason: event.trigger_reason, trigger_family: event.trigger_family, hint_count: scope.hint_count };
        } else fail('invalid_scaffold_event', 400);
        cursor.seq = event.seq; cursor.hashes[event.seq] = fingerprint; state.revision++;
      }
      for (const sequence of Object.keys(cursor.hashes)) if (Number(sequence) < cursor.seq - 200) delete cursor.hashes[sequence];
      await tx.put('settings', key, state);
    }
    return { state, acknowledged: state.clients[body.client_id]?.seq || 0 };
  });
}
async function authorizeAgent(service, claims, body, polling) {
  const { key, metadata } = await context(service, claims);
  if (body.level_id !== LEVEL) fail('agent_level_invalid', 400);
  if (polling) return;
  return service.store.transaction(async tx => {
    const state = await tx.get('settings', key) || initial();
    const permit = state.requests[body.scaffold_id];
    if (!permit || permit.scope !== body.state?.scope_id || permit.trigger !== body.trigger || state.last_scope !== permit.scope) fail('agent_request_required');
    const now = service.clock();
    state.ai_calls = (state.ai_calls || []).filter(time => time > now - 300000);
    if (state.ai_calls.length >= 12) fail('coze_rate_limited', 429);
    state.ai_calls.push(now); await tx.put('settings', key, state); return metadata;
  });
}
function mountExperiment(app, getService, secret) {
  app.get('/api/lesson1/trial/config', async (_req, res) => {
    res.setHeader('Cache-Control', 'no-store'); const config = experimentConfig();
    res.json({ experiment_enabled: config.enabled, experiment_version: EXPERIMENT, experiment_round: config.round, classes: CLASSES, data_phase: 'pilot' });
  });
  app.post('/api/lesson1/trial/scaffold', express.json({ limit: '64kb' }), async (req, res) => {
    res.setHeader('Cache-Control', 'no-store');
    try { res.json(await (await getService()).scaffold(verifyTicket(req.body.ticket, secret), req.body)); }
    catch (error) { res.status(error.status || 400).json({ code: error.code || 'scaffold_unavailable' }); }
  });
}
module.exports = { EXPERIMENT, LEVEL, CLASSES, experimentConfig, mountExperiment, scaffoldState, authorizeAgent };
