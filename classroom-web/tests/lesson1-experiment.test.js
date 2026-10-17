import test from 'node:test';
import assert from 'node:assert/strict';
import { ExperimentScaffold } from '../src/experiment-scaffold.js';
import { lesson1Scope } from '../prototypes/lesson1-card-table/experiment-support.mjs';
import { createCardTaskEngine } from '../prototypes/card-task-engine/core.mjs';
import { lesson1Adapter } from '../prototypes/card-task-engine/adapters/lesson1.mjs';
test('lesson 1 scope follows real progress and keeps knowledge distinct', () => {
  const state = createCardTaskEngine(lesson1Adapter).createState();
  assert.equal(lesson1Scope(state).id, 'network:early:connect');
  state.data.challenges[0].terminalConnected = true;
  assert.equal(lesson1Scope(state).id, 'network:early:link');
  state.data.knowledge.current = 0; state.data.knowledge.checkpoints[0].status = 'active';
  assert.deepEqual(lesson1Scope(state), { id: 'knowledge:0', kind: 'quiz', eligible: true, objective: '用刚才的观察检验概念和解释之间的关系' });
  state.data.knowledge.checkpoints[0].status = 'completed'; assert.equal(lesson1Scope(state).eligible, false);
});
test('same activity gets proactive idle support and reactive two-error support', () => {
  const active = new ExperimentScaffold({ condition: 'proactive' }), reactive = new ExperimentScaffold({ condition: 'reactive' });
  for (const helper of [active, reactive]) helper.setScope({ id: 'network:early:connect' });
  active.tick(14, true); assert.equal(active.pending, null); active.tick(1, true); assert.equal(active.pending.trigger_reason, 'idle');
  reactive.tick(30, true); assert.equal(reactive.pending, null);
  reactive.failure('invalid_action'); assert.equal(reactive.pending, null); reactive.failure('invalid_action'); assert.ok(reactive.pending);
  const before = active.count; active.open(); assert.equal(active.count, before);
});
