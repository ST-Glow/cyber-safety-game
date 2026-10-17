import test from 'node:test';
import assert from 'node:assert/strict';
import {
  activateKnowledge,
  attemptKnowledgePair,
  createKnowledgeState,
  dismissKnowledge,
  KNOWLEDGE_CHECKPOINTS,
  selectKnowledgeConcept,
  validateKnowledgeState
} from './adapters/lesson1-knowledge.mjs';

test('knowledge checkpoint shuffles, records a wrong attempt, then completes both pairs', () => {
  const knowledge = createKnowledgeState();
  assert.equal(activateKnowledge(knowledge, 0, () => 0), true);
  assert.equal(knowledge.current, 0);
  assert.equal(knowledge.checkpoints[0].order.length, 4);
  assert.equal(new Set(knowledge.checkpoints[0].order).size, 4);

  selectKnowledgeConcept(knowledge, 'single-point');
  const wrong = attemptKnowledgePair(knowledge, 'central-structure');
  assert.equal(wrong.correct, false);
  assert.equal(knowledge.checkpoints[0].matched.length, 0);
  assert.equal(knowledge.checkpoints[0].attempts.length, 1);
  const first = attemptKnowledgePair(knowledge, 'single-point');
  assert.equal(first.correct, true);

  selectKnowledgeConcept(knowledge, 'central-structure');
  const second = attemptKnowledgePair(knowledge, 'central-structure');
  assert.equal(second.correct, true);
  assert.equal(knowledge.checkpoints[0].status, 'completed');
  assert.equal(knowledge.evidence.filter(item => item.type === 'knowledge_pair_attempted').length, 3);
  assert.equal(knowledge.evidence.some(item => item.type === 'knowledge_match_completed'), true);
  assert.equal(dismissKnowledge(knowledge).ok, true);
  assert.equal(knowledge.current, null);
  assert.equal(validateKnowledgeState(knowledge, 1), true);
});

test('knowledge checkpoint can be skipped without fabricating a match', () => {
  const knowledge = createKnowledgeState();
  activateKnowledge(knowledge, 1, () => .5);
  selectKnowledgeConcept(knowledge, 'communication-protocol');
  const skipped = dismissKnowledge(knowledge, 'escape');
  assert.equal(skipped.events[0].type, 'knowledge_match_skipped');
  assert.equal(knowledge.checkpoints[1].status, 'skipped');
  assert.deepEqual(knowledge.checkpoints[1].matched, []);
  assert.equal(knowledge.evidence.at(-1).reason, 'escape');
  assert.equal(validateKnowledgeState(knowledge, 2), true);
});

test('knowledge state rejects a forged completion', () => {
  const knowledge = createKnowledgeState();
  activateKnowledge(knowledge, 0, () => .2);
  knowledge.checkpoints[0].status = 'completed';
  knowledge.checkpoints[0].matched = KNOWLEDGE_CHECKPOINTS[0].pairs.map(pair => pair.id);
  assert.equal(validateKnowledgeState(knowledge, 1), false);
});
