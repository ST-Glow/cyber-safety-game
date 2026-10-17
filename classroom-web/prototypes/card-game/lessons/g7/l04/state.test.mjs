import test from 'node:test';
import assert from 'node:assert/strict';
import { createCardActionSystem } from '../../../core/action-system.mjs';
import { LESSON4_CONFIG, LESSON4_PHASES } from './config.mjs';
import { ADAPTIVE_COOLDOWN_MS, ADAPTIVE_DIFFICULTY_MS } from '../../../agent/adaptive-triggered-policy.mjs';
import { applyAction, attemptReassembly, createState, elapsed, help, legalTargets, packetizeAnnouncement, requestAgentHelp, restore, snapshot, tick, undo, validateWin } from './state.mjs';

const move = (state, objectId, targetId, now) => {
  const result = applyAction(state, 'forward', objectId, targetId, now);
  assert.equal(result.ok, true, state.feedback?.text);
  return result;
};
const packetize = (state, now = 10) => {
  const result = packetizeAnnouncement(state, now);
  assert.equal(result.ok, true, state.feedback?.text);
};
const playableState = () => {
  const state = createState(0, 'playable');
  assert.equal(applyAction(state, 'forward', 'whole-announcement', 'node-a', 10).ok, false);
  packetize(state, 20);
  return state;
};
const completeRoutes = state => {
  move(state, 'packet-01', 'node-a', 30);
  move(state, 'packet-02', 'node-a', 40);
  move(state, 'packet-03', 'node-b', 50);
  move(state, 'packet-04', 'node-c', 60);
  move(state, 'packet-01', 'node-b', 70);
  move(state, 'packet-02', 'node-c', 80);
  move(state, 'packet-03', 'receiver', 90);
  move(state, 'packet-01', 'receiver', 100);
  move(state, 'packet-04', 'receiver', 110);
  move(state, 'packet-02', 'receiver', 120);
};

test('initial state is a whole announcement and only forwarding can expose the capacity problem', () => {
  const state = createState(0, 'opening');
  assert.equal(state.phase, LESSON4_PHASES.WHOLE_DATA_BLOCKED);
  assert.equal(state.tutorialStage, 0);
  assert.deepEqual(Object.keys(state.packets), []);
  assert.equal(state.wholeAnnouncement.status, 'intact');
  assert.deepEqual(legalTargets(state, 'forward').map(item => item.id), ['whole-announcement']);
  assert.equal(legalTargets(state, 'packetize').length, 0);
  assert.equal(legalTargets(state, 'reassemble')[0]?.disabledReason, '还有数据包没有到达。');
  const before = JSON.stringify(state);
  const result = applyAction(state, 'forward', 'whole-announcement', 'node-a', 10);
  assert.equal(result.ok, false);
  assert.equal(state.phase, LESSON4_PHASES.PACKETIZATION);
  assert.equal(JSON.stringify(state.packets), JSON.stringify(JSON.parse(before).packets));
  assert.match(state.feedback.text, /太大|分包/);
});

test('packetization creates four real packets and unlocks forwarding', () => {
  const state = createState(0, 'packetize');
  applyAction(state, 'forward', 'whole-announcement', 'node-a', 10);
  packetize(state, 20);
  assert.equal(state.phase, LESSON4_PHASES.FORWARDING);
  assert.equal(state.progress.total, 4);
  assert.deepEqual(Object.keys(state.packets), ['01', '02', '03', '04']);
  assert.equal(state.packets['03'].area, 'sender');
  assert.equal(LESSON4_CONFIG.cards.length, 3);
  assert.deepEqual(LESSON4_CONFIG.cards.map(card => card.id), ['packetize', 'forward', 'reassemble']);
});

test('card action system preserves card → object → target', () => {
  const state = playableState();
  const system = createCardActionSystem({ config: LESSON4_CONFIG, legalTargets, applyAction });
  assert.equal(system.selectCard(state, 'forward', 30).ok, true);
  assert.equal(system.selectObject(state, 'packet-03', 31).ok, true);
  assert.equal(system.selectTarget(state, 'node-b', 32).ok, true);
  assert.equal(system.executeAction(state, 33).ok, true);
  assert.equal(state.packets['03'].area, 'node-b');
  assert.equal(state.selectedCard, null);
});

test('capacity and fixed congestion change legal routes without randomness', () => {
  const state = playableState();
  move(state, 'packet-01', 'node-a', 30);
  move(state, 'packet-02', 'node-a', 40);
  assert.equal(state.routes['node-a-receiver'].status, 'congested');
  assert.equal(state.nodes['node-a'].status, 'congested');
  const targets = legalTargets(state, 'forward', 'packet-01');
  assert.equal(targets.find(item => item.id === 'receiver').disabledReason.includes('拥堵'), true);
  assert.equal(targets.some(item => item.id === 'node-b'), true);
  assert.equal(targets.some(item => item.id === 'node-c'), true);
});

test('two valid route choices create different arrival orders and paths', () => {
  const first = playableState();
  completeRoutes(first);
  assert.deepEqual(first.arrivalOrder, ['03', '01', '04', '02']);
  assert.equal(first.packets['01'].path.includes('node-b'), true);
  const second = playableState();
  move(second, 'packet-01', 'node-a', 30);
  move(second, 'packet-02', 'node-b', 40);
  move(second, 'packet-03', 'node-c', 50);
  move(second, 'packet-04', 'node-a', 60);
  move(second, 'packet-01', 'node-c', 70);
  move(second, 'packet-02', 'receiver', 80);
  move(second, 'packet-03', 'receiver', 90);
  move(second, 'packet-04', 'node-b', 100);
  move(second, 'packet-01', 'receiver', 110);
  move(second, 'packet-04', 'receiver', 120);
  assert.notDeepEqual(first.arrivalOrder, second.arrivalOrder);
  assert.notDeepEqual(first.packets['01'].path, second.packets['01'].path);
});

test('only exact reassembly order completes the mission', () => {
  const state = playableState();
  completeRoutes(state);
  assert.equal(state.phase, LESSON4_PHASES.REASSEMBLY);
  assert.equal(applyAction(state, 'reassemble', null, 'receiver', 130).ok, true);
  assert.equal(state.reassembly.status, 'sorting');
  assert.equal(attemptReassembly(state, ['02', '01', '03', '04'], 140).ok, false);
  assert.equal(validateWin(state), false);
  assert.equal(attemptReassembly(state, ['01', '02', '03', '04'], 150).ok, true);
  assert.equal(validateWin(state), true);
  assert.equal(state.reassembly.draft.message, '图书馆周五开放阅读角');
});

test('undo and snapshot restore preserve custom lesson state', () => {
  const state = playableState();
  move(state, 'packet-01', 'node-a', 30);
  const saved = snapshot(state, 40);
  const restored = restore(saved, 500);
  assert.equal(restored.packets['01'].area, 'node-a');
  assert.equal(elapsed(restored, 500), 500);
  assert.equal(undo(restored, 510), true);
  assert.equal(restored.packets['01'].area, 'sender');
  assert.equal(restored.phase, LESSON4_PHASES.FORWARDING);
  assert.equal(restored.tutorialStage, 2);
});

test('help events and recommendation modes stay isolated', () => {
  const state = createState(0, { runId: 'help', agentMode: 'user_requested' });
  help(state, 'operation_help', 10);
  assert.equal(state.events.some(event => event.type === 'operation_help'), true);
  assert.equal(state.agentMode, 'user_requested');
  assert.equal(state.lastRecommendation, null);
  const recommendation = requestAgentHelp(state, 20);
  assert.ok(recommendation.id);
  assert.equal(state.lastRecommendation.triggerReason, 'user_requested');
  const adaptive = createState(0, { runId: 'adaptive', agentMode: 'adaptive_triggered' });
  applyAction(adaptive, 'forward', 'whole-announcement', 'node-a', 1);
  tick(adaptive, 21_000);
  assert.equal(adaptive.lastRecommendation, null);
  assert.equal(adaptive.difficultyState.active, true);
});

test('adaptive trigger needs a continuous 20 seconds, clears on progress, and respects cooldown/cap', () => {
  const state = playableState();
  tick(state, 5_000);
  assert.equal(state.lastRecommendation, null);
  tick(state, 25_000);
  assert.equal(state.lastRecommendation, null);
  tick(state, 44_000);
  assert.equal(state.lastRecommendation, null);
  tick(state, 45_000);
  assert.ok(state.difficultyState.active);
  assert.ok(state.lastRecommendation);
  const recommendationId = state.lastRecommendation.id;
  const before = JSON.stringify({ packets: state.packets, areas: state.nodes, version: state.task_version });
  tick(state, 67_000);
  assert.equal(state.lastRecommendation.id, recommendationId);
  assert.equal(JSON.stringify({ packets: state.packets, areas: state.nodes, version: state.task_version }), before);
  assert.equal(state.autoInterventionCount, 1);
  state.lastMeaningfulProgressAt = 70_000;
  state.invalidActionStreak = 0;
  tick(state, 70_001);
  assert.equal(state.difficultyState.active, false);
  tick(state, 100_000);
  assert.equal(state.agentCooldownUntil, 0);
  state.invalidActionStreak = 2;
  tick(state, 100_001);
  tick(state, 121_001);
  assert.equal(state.autoInterventionCount, 2);
  state.invalidActionStreak = 0;
  state.lastMeaningfulProgressAt = 130_000;
  tick(state, 130_001);
  state.invalidActionStreak = 2;
  tick(state, 320_001);
  tick(state, 350_001);
  assert.equal(state.autoInterventionCount, 3);
  state.invalidActionStreak = 2;
  tick(state, 380_001);
  assert.equal(state.autoInterventionCount, 3);
  assert.equal(ADAPTIVE_DIFFICULTY_MS, 20_000);
  assert.equal(ADAPTIVE_COOLDOWN_MS, 30_000);
});

