import test from 'node:test';
import assert from 'node:assert/strict';
import { createCardTaskEngine } from './core.mjs';
import { lesson1Adapter } from './adapters/lesson1.mjs';

const run = (engine, state, action, objectId, targetId, now) => engine.applyAction(state, action, objectId, targetId, now);

test('lesson 1 completes the early-network challenge and exposes its limitation', () => {
  const engine = createCardTaskEngine(lesson1Adapter); const state = engine.createState(0, 'l1-early');
  assert.deepEqual(engine.legalTargets(state, 'connect-device').map(item => item.id), ['early-terminal']);
  assert.equal(run(engine, state, 'connect-device', 'early-terminal', 'early-terminal', 10).ok, true);
  assert.equal(run(engine, state, 'establish-connection', 'early-central-link', 'early-central-link', 20).ok, true);
  assert.equal(run(engine, state, 'run-test', 'early-communication-test', 'early-communication-test', 30).ok, true);
  assert.equal(run(engine, state, 'run-test', 'early-central-fault', 'early-central-fault', 40).ok, true);
  const failed = run(engine, state, 'run-test', 'early-communication-test', 'early-communication-test', 50);
  assert.equal(failed.ok, true); assert.equal(state.data.challengeIndex, 1);
  assert.ok(state.data.evidence.some(item => item.type === 'central_failure'));
});

test('lesson 1 requires common protocol before communication can recover', () => {
  const engine = createCardTaskEngine(lesson1Adapter); const state = engine.createState();
  const before = engine.applyAction(state, 'configure-protocol', 'protocol-bridge', 'protocol-bridge', 1);
  assert.equal(before.ok, false); assert.match(before.feedback.text, /当前早期|先/);
  run(engine, state, 'connect-device', 'early-terminal', 'early-terminal', 2);
  run(engine, state, 'establish-connection', 'early-central-link', 'early-central-link', 3);
  run(engine, state, 'run-test', 'early-communication-test', 'early-communication-test', 4);
  run(engine, state, 'run-test', 'early-central-fault', 'early-central-fault', 5);
  run(engine, state, 'run-test', 'early-communication-test', 'early-communication-test', 6);
  run(engine, state, 'connect-device', 'protocol-network-a', 'protocol-network-a', 7);
  run(engine, state, 'connect-device', 'protocol-network-b', 'protocol-network-b', 8);
  run(engine, state, 'establish-connection', 'protocol-bridge', 'protocol-bridge', 9);
  const failed = run(engine, state, 'run-test', 'protocol-bridge', 'protocol-bridge', 10);
  assert.equal(failed.ok, true); assert.equal(state.data.challenges[1].communication, 'failed_protocol_mismatch');
  assert.match(engine.legalTargets(state, 'run-test')[0].disabledReason, /配置相同协议/);
  assert.equal(run(engine, state, 'configure-protocol', 'protocol-bridge', 'protocol-bridge', 11).ok, true);
  assert.equal(run(engine, state, 'run-test', 'protocol-bridge', 'protocol-bridge', 12).ok, true);
  assert.equal(state.data.challengeIndex, 2);
});

test('lesson 1 completes mesh redundancy and showcases Chinese innovation milestones', () => {
  const engine = createCardTaskEngine(lesson1Adapter); const state = engine.createState();
  const actions = [
    ['connect-device', 'early-terminal', 1], ['establish-connection', 'early-central-link', 2], ['run-test', 'early-communication-test', 3], ['run-test', 'early-central-fault', 4], ['run-test', 'early-communication-test', 5],
    ['connect-device', 'protocol-network-a', 6], ['connect-device', 'protocol-network-b', 7], ['establish-connection', 'protocol-bridge', 8], ['run-test', 'protocol-bridge', 9], ['configure-protocol', 'protocol-bridge', 10], ['run-test', 'protocol-bridge', 11],
    ['connect-device', 'mesh-node', 12], ['establish-connection', 'mesh-main-line', 13], ['run-test', 'mesh-main-line', 14], ['run-test', 'mesh-fault-switch', 15], ['add-backup-route', 'mesh-backup-line', 16]
  ];
  for (const [action, id, now] of actions) assert.equal(run(engine, state, action, id, id, now).ok, true, state.feedback.text);
  const final = run(engine, state, 'run-test', 'mesh-backup-line', 'mesh-backup-line', 17);
  assert.equal(final.ok, true); assert.equal(engine.validateWin(state), true); assert.equal(state.data.showcase.items[0].year, '1987'); assert.equal(state.data.showcase.items[1].year, '1994'); assert.match(state.data.showcase.items[2].text, /5G/);
});

test('lesson 1 rejects illegal or disabled targets without mutating course data', () => {
  const engine = createCardTaskEngine(lesson1Adapter); const state = engine.createState();
  const before = JSON.stringify(state.data);
  const result = run(engine, state, 'run-test', 'early-communication-test', 'early-communication-test', 1);
  assert.equal(result.ok, false); assert.equal(JSON.stringify(state.data), before); assert.match(state.feedback.text, /先建立/);
  const disabled = engine.legalTargets(state, 'add-backup-route')[0]; assert.ok(disabled.disabledReason);
});

