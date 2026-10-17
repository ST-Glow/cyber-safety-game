import test from 'node:test';
import assert from 'node:assert/strict';
import { CARD_TASK_ADAPTERS, createCardTaskEngine, getCardTaskAdapter } from '../prototypes/card-task-engine/index.mjs';

test('card task registry keeps lesson 4 as a reference and exposes the pilot adapters', () => {
  assert.deepEqual(Object.keys(CARD_TASK_ADAPTERS), ['lesson1', 'lesson4', 'lesson9', 'lesson17', 'lesson27']);
  assert.equal(getCardTaskAdapter('lesson4').implementation, 'classroom-web/prototypes/lesson4-card-table/model.mjs');
  for (const id of ['lesson1', 'lesson9', 'lesson17', 'lesson27']) {
    const adapter = getCardTaskAdapter(id);
    assert.ok(adapter.meta.task_id);
    assert.ok(adapter.actions.length >= 5);
    const engine = createCardTaskEngine(adapter);
    const state = engine.createState(0, `registry-${id}`);
    assert.equal(state.meta.curriculum_lesson_id, adapter.meta.curriculum_lesson_id);
    assert.ok(engine.legalTargets(state, adapter.actions[0].id).length >= 0);
  }
});
