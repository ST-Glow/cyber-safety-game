'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { createSqliteStore } = require('../src/classroom/store');
const { Lesson1TrialService, CONSENT } = require('../src/lesson1-trial');
const { EXPERIMENT, LEVEL } = require('../src/lesson1-experiment');
const secret = 'two-class-test-secret-with-more-than-32-characters';
const body = (class_id = 'g7-01', extra = {}) => ({ class_id, student_name: '技术测试生', run_id: `lesson1-${crypto.randomUUID()}`, segment_id: crypto.randomUUID(), client_key: crypto.randomBytes(32).toString('hex'), consent_version: CONSENT, experiment_version: EXPERIMENT, ...extra });
async function fixture(t) { const store = await createSqliteStore(':memory:'); t.after(() => store.close()); let now = Date.now(); return { store, service: new Lesson1TrialService(store, secret, () => now, { enabled: true, round: 'pilot-test' }), advance: ms => { now += ms; } }; }
test('server assigns the two classes, ignores forged condition, and locks assignment on renew', async t => {
  const { service } = await fixture(t);
  for (const [classId, expected] of [['g7-01', 'proactive'], ['g7-06', 'reactive']]) {
    const input = body(classId, { condition: expected === 'proactive' ? 'reactive' : 'proactive' });
    const issued = await service.session(input);
    assert.equal(issued.claims.condition, expected); assert.equal(issued.experiment.version, EXPERIMENT);
    service.experiment.round = 'next-round';
    assert.equal((await service.session(input, '', true)).experiment.round, 'pilot-test');
    service.experiment.round = 'pilot-test';
    await assert.rejects(service.metadata({ ...issued.claims, condition: 'passive' }), /owner_mismatch/);
  }
  await assert.rejects(service.session(body('g7-02')), /entry_required/);
});
test('old upload sessions and device checks keep their labels and cannot call AI', async t => {
  const { service } = await fixture(t); service.experiment.enabled = false;
  const input = body('g7-16'); delete input.experiment_version;
  const old = await service.session(input); service.experiment.enabled = true;
  assert.equal((await service.session(input, '', true)).claims.condition, 'passive');
  const check = await service.session(body('g7-01', { activity_type: 'device_check_30s' }));
  assert.equal(check.claims.condition, 'passive'); assert.equal((await service.metadata(check.claims)).activity_type, 'device_check_30s');
  for (const assignment of [old, check]) await assert.rejects(service.authorizeAgent(assignment.claims, { level_id: LEVEL }), /upload_ticket_only/);
});
test('other class is restricted to device checks, retains the submitted name, and cannot use AI', async t => {
  const { service } = await fixture(t);
  const input = body('g7-other', { student_name: '检测测试生', activity_type: 'device_check_30s' });
  const check = await service.session(input);
  const metadata = await service.metadata(check.claims);
  assert.equal(metadata.student_name, '检测测试生');
  assert.equal(metadata.class_name, '其他班级');
  assert.equal(metadata.activity_type, 'device_check_30s');
  assert.equal(check.claims.class_id, 'g7-other');
  assert.equal(check.claims.condition, 'passive');
  assert.equal(check.experiment, undefined);
  assert.equal((await service.session(input, '', true)).claims.upload_id, check.claims.upload_id);
  await assert.rejects(service.authorizeAgent(check.claims, { level_id: LEVEL }), /upload_ticket_only/);
  await assert.rejects(service.session(body('g7-other')), /class_invalid/);
  await assert.rejects(service.session(body('g7-02', { activity_type: 'device_check_30s' })), /class_invalid/);
  service.experiment.enabled = false;
  await assert.rejects(service.session(body('g7-other')), /class_invalid/);
});

test('reactive waits for two errors; proactive refuses an invitation after a scope error', async t => {
  const { service } = await fixture(t);
  for (const [classId, family] of [['g7-01', 'proactive'], ['g7-06', 'reactive']]) {
    const { claims } = await service.session(body(classId)); const client_id = crypto.randomUUID(), scope_id = 'network:early:connect';
    await service.scaffold(claims, { client_id, events: [{ seq: 1, type: 'scope', scope_id }, { seq: 2, type: 'failure', scope_id }] });
    await assert.rejects(service.scaffold(claims, { client_id, events: [{ seq: 3, type: 'shown', scope_id, family, trigger_reason: family === 'proactive' ? 'idle' : 'repeated_failure', scaffold_id: crypto.randomUUID() }] }), family === 'proactive' ? /condition_forbidden/ : /threshold_not_met/);
    if (family === 'reactive') {
      const reply = await service.scaffold(claims, { client_id, events: [{ seq: 3, type: 'failure', scope_id }, { seq: 4, type: 'shown', scope_id, family, trigger_reason: 'repeated_failure', scaffold_id: crypto.randomUUID() }] });
      assert.equal(reply.state.shown, 1);
    }
  }
});
test('quota is shared across runs, capture segments, service instances, and matching checkpoints', async t => {
  const f = await fixture(t), { claims } = await f.service.session(body()), client_id = crypto.randomUUID(); let seq = 0;
  const send = events => f.service.scaffold(claims, { client_id, events: events.map(event => ({ ...event, seq: ++seq })) });
  for (let i = 0; i < 3; i++) {
    const scope_id = `knowledge:${i}`, scaffold_id = crypto.randomUUID();
    await send([{ type: 'scope', scope_id }, { type: 'shown', scope_id, family: 'proactive', trigger_reason: 'no_progress', scaffold_id }, { type: 'decision', scope_id, choice: 'dismissed', scaffold_id }]);
    f.advance(31000); await send([{ type: 'cooldown', scope_id, remaining: 0 }]);
  }
  const next = new Lesson1TrialService(f.store, secret, undefined, { enabled: true, round: 'pilot-test' });
  const anotherRun = await next.session(body());
  const state = await next.scaffold(anotherRun.claims, {}); assert.equal(state.state.shown, 3);
  await assert.rejects(next.scaffold(anotherRun.claims, { client_id: crypto.randomUUID(), events: [{ seq: 1, type: 'shown', scope_id: 'network:mesh:repair', family: 'proactive', trigger_reason: 'idle', scaffold_id: crypto.randomUUID() }] }), /quota_reached/);
  assert.equal((await next.scaffold((await next.session(body('g7-06'))).claims, {})).state.shown, 0);
});
test('AI needs a registered matching request and cannot reuse another scope or forge a trigger', async t => {
  const { service } = await fixture(t), { claims } = await service.session(body()); const scope_id = 'knowledge:0', scaffold_id = crypto.randomUUID(), client_id = crypto.randomUUID();
  await service.scaffold(claims, { client_id, events: [{ seq: 1, type: 'scope', scope_id }, { seq: 2, type: 'request', scope_id, scaffold_id, trigger_reason: 'manual' }] });
  const input = { level_id: LEVEL, scaffold_id, trigger: 'manual', state: { scope_id } };
  await service.authorizeAgent(claims, input);
  await assert.rejects(service.authorizeAgent(claims, { ...input, trigger: 'idle' }), /request_required/);
  await assert.rejects(service.authorizeAgent(claims, { ...input, state: { scope_id: 'knowledge:1' } }), /request_required/);
  await assert.rejects(service.authorizeAgent(claims, { ...input, level_id: 'ai_training_ground' }), /level_invalid/);
  for (let i = 0; i < 11; i++) await service.authorizeAgent(claims, input);
  await assert.rejects(service.authorizeAgent(claims, input), /rate_limited/);
});
test('an invitation cancelled before display releases its reservation, displayed invitations remain counted', async t => {
  const { service } = await fixture(t), { claims } = await service.session(body()); const scope_id = 'network:early:connect', client_id = crypto.randomUUID(), scaffold_id = crypto.randomUUID();
  await service.scaffold(claims, { client_id, events: [{ seq: 1, type: 'scope', scope_id }, { seq: 2, type: 'shown', scope_id, family: 'proactive', trigger_reason: 'idle', scaffold_id }, { seq: 3, type: 'unshown', scope_id, scaffold_id }] });
  assert.equal((await service.scaffold(claims, {})).state.shown, 0);
  const next = crypto.randomUUID();
  await service.scaffold(claims, { client_id, events: [{ seq: 4, type: 'shown', scope_id, family: 'proactive', trigger_reason: 'idle', scaffold_id: next }, { seq: 5, type: 'displayed', scope_id, scaffold_id: next }, { seq: 6, type: 'unshown', scope_id, scaffold_id: next }] });
  assert.equal((await service.scaffold(claims, {})).state.shown, 1);
});
