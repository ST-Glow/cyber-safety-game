import test from 'node:test';
import assert from 'node:assert/strict';
import { createCardTaskEngine, elapsed } from './core.mjs';
import { lesson9Adapter } from './adapters/lesson9.mjs';
import { lesson17Adapter } from './adapters/lesson17.mjs';
import { lesson27Adapter } from './adapters/lesson27.mjs';

const run = (engine, state, action, objectId, targetId, now) => engine.applyAction(state, action, objectId, targetId, now).ok;
const targetIds = (engine, state, action, objectId = null) => engine.legalTargets(state, action, objectId).map(item => item.id);

test('lesson 9 exposes descriptive targets and completes a loss/retransmit route', () => {
  const engine = createCardTaskEngine(lesson9Adapter); const state = engine.createState(0, 'l9-route-a');
  const targets = engine.legalTargets(state, 'reliable');
  assert.deepEqual(targets.map(item => item.id), ['file', 'live']);
  assert.equal(targets[0].type, 'application'); assert.equal(targets[0].label, '科技节海报文件');
  assert.ok(targets[1].disabledReason);
  assert.equal(run(engine, state, 'reliable', 'file', 'file', 10), true);
  assert.equal(run(engine, state, 'realtime', 'live', 'live', 20), true);
  assert.equal(run(engine, state, 'assign-port', 'file', 'port-file', 30), true);
  assert.equal(run(engine, state, 'assign-port', 'live', 'port-live', 40), true);
  assert.equal(run(engine, state, 'simulate-loss', 'file', 'file', 50), true);
  assert.equal(state.data.applications.file.recovered, false);
  assert.equal(run(engine, state, 'reliable', 'file', 'file', 60), true);
  assert.equal(run(engine, state, 'simulate-loss', 'live', 'live', 70), true);
  assert.equal(run(engine, state, 'submit', null, 'decision-board', 80), true);
  assert.equal(engine.validateWin(state), true);
  assert.ok(state.data.evidence.some(item => item.type === 'loss_detected'));
  assert.ok(state.data.evidence.some(item => item.type === 'loss_recovered'));
  assert.equal(state.data.applications.live.dropped_frames > 0, true);
  assert.equal(run(engine, state, 'reliable', 'file', 'file', 90), true);
  assert.equal(state.completed, false);
  assert.equal(state.data.decision.stale, true);
  assert.equal(engine.validateWin(state), false);
});

test('lesson 9 supports a second order and rejects port conflicts without mutation', () => {
  const engine = createCardTaskEngine(lesson9Adapter); const state = engine.createState(0, 'l9-route-b');
  assert.equal(run(engine, state, 'assign-port', 'file', 'port-file', 10), true);
  const beforeConflict = JSON.stringify(state.data);
  assert.equal(run(engine, state, 'assign-port', 'live', 'port-file', 20), false);
  assert.equal(JSON.stringify(state.data), beforeConflict);
  assert.equal(run(engine, state, 'assign-port', 'live', 'port-live', 30), true);
  assert.equal(run(engine, state, 'realtime', 'live', 'live', 40), true);
  assert.equal(run(engine, state, 'simulate-loss', 'live', 'live', 50), true);
  assert.equal(run(engine, state, 'reliable', 'file', 'file', 60), true);
  assert.equal(run(engine, state, 'simulate-loss', 'file', 'file', 70), true);
  assert.equal(run(engine, state, 'reliable', 'file', 'file', 80), true);
  assert.equal(run(engine, state, 'submit', null, 'decision-board', 90), true);
  assert.equal(engine.validateWin(state), true);
});

test('lesson 9 wrong protocol target is disabled and preserves state', () => {
  const engine = createCardTaskEngine(lesson9Adapter); const state = engine.createState();
  const before = JSON.stringify(state.data);
  const result = engine.applyAction(state, 'realtime', 'file', 'file', 10);
  assert.equal(result.ok, false); assert.equal(JSON.stringify(state.data), before); assert.match(state.feedback.text, /可靠传输/);
});

test('lesson 17 invalidates old preview, re-previews and exports offline HTML', () => {
  const engine = createCardTaskEngine(lesson17Adapter); const state = engine.createState(0, 'l17-test');
  assert.equal(run(engine, state, 'set-heading', 'heading', 'heading', 10), true);
  assert.equal(run(engine, state, 'add-paragraph', 'intro', 'intro', 20), true);
  assert.equal(run(engine, state, 'set-section', 'section', 'section', 30), true);
  assert.equal(run(engine, state, 'preview', null, 'preview', 40), true);
  assert.equal(state.data.preview.revision, state.data.revision);
  assert.equal(state.data.preview.srcdoc, state.data.preview.html);
  assert.equal(run(engine, state, 'set-heading', 'heading', 'heading', 50), true);
  assert.equal(state.data.preview.stale, true);
  assert.equal(run(engine, state, 'publish', null, 'publish', 60), false);
  assert.equal(run(engine, state, 'preview', null, 'preview', 70), true);
  assert.equal(run(engine, state, 'publish', null, 'publish', 80), true);
  assert.equal(engine.validateWin(state), true);
  assert.equal(engine.artifact(state).mime, 'text/html;charset=utf-8');
  assert.match(engine.artifact(state).text, /<section>/);
  assert.equal(run(engine, state, 'set-heading', 'heading', 'heading', 90), true);
  assert.equal(state.completed, false);
  assert.equal(state.data.preview.stale, true);
  assert.equal(engine.validateWin(state), false);
});

test('lesson 17 preview target explains incomplete structure and cannot publish a form-like state', () => {
  const engine = createCardTaskEngine(lesson17Adapter); const state = engine.createState();
  const previewTarget = engine.legalTargets(state, 'preview')[0];
  assert.match(previewTarget.disabledReason, /h1/);
  const before = JSON.stringify(state.data);
  assert.equal(run(engine, state, 'publish', null, 'publish'), false);
  assert.equal(JSON.stringify(state.data), before);
  assert.equal(state.data.published_flag, false);
});

test('lesson 17 accepts a second valid construction order', () => {
  const engine = createCardTaskEngine(lesson17Adapter); const state = engine.createState(0, 'l17-route-b');
  assert.equal(run(engine, state, 'set-section', 'section', 'section', 10), true);
  assert.equal(run(engine, state, 'add-paragraph', 'intro', 'intro', 20), true);
  assert.equal(run(engine, state, 'set-heading', 'heading', 'heading', 30), true);
  assert.equal(run(engine, state, 'preview', null, 'preview', 40), true);
  assert.equal(run(engine, state, 'publish', null, 'publish', 50), true);
  assert.equal(engine.validateWin(state), true);
});

test('lesson 27 requires explicit risk identification and supports a delivered route', () => {
  const engine = createCardTaskEngine(lesson27Adapter); const state = engine.createState(0, 'l27-delivered');
  assert.equal(run(engine, state, 'review', null, 'risk-board', 10), false);
  assert.equal(run(engine, state, 'identify-risk', null, 'risk-board', 20), true);
  assert.equal(state.data.identified, true);
  assert.equal(run(engine, state, 'redact', 'profile', 'profile', 30), true);
  assert.equal(run(engine, state, 'replace', 'photo', 'photo', 40), true);
  assert.equal(run(engine, state, 'remove', 'qr', 'qr', 50), true);
  assert.equal(run(engine, state, 'review', null, 'risk-board', 60), true);
  assert.equal(state.data.risk.level, 'low');
  assert.equal(run(engine, state, 'deliver', null, 'advocacy', 70), true);
  assert.equal(state.data.outcome, 'delivered');
  assert.equal(engine.validateWin(state), true);
  assert.equal(run(engine, state, 'narrow-audience', 'photo', 'photo', 80), true);
  assert.equal(state.completed, false);
  assert.equal(state.data.reviewed, false);
  assert.equal(engine.validateWin(state), false);
});

test('lesson 27 supports safe-stop and rejects narrowing a high-sensitivity field', () => {
  const engine = createCardTaskEngine(lesson27Adapter); const state = engine.createState(0, 'l27-safe-stop');
  run(engine, state, 'identify-risk', null, 'risk-board', 10);
  const before = JSON.stringify(state.data);
  assert.equal(run(engine, state, 'narrow-audience', 'profile', 'profile', 20), false);
  assert.equal(JSON.stringify(state.data), before);
  assert.equal(run(engine, state, 'redact', 'profile', 'profile', 30), true);
  assert.equal(run(engine, state, 'narrow-audience', 'photo', 'photo', 40), true);
  assert.equal(run(engine, state, 'hold', 'qr', 'qr', 50), true);
  assert.equal(run(engine, state, 'review', null, 'risk-board', 60), true);
  assert.equal(state.data.audience_preview.find(item => item.id === 'photo').audience, 'classmates');
  assert.equal(run(engine, state, 'deliver', null, 'advocacy', 70), true);
  assert.equal(state.data.outcome, 'safe_stopped');
  assert.equal(state.data.objects.qr.shared, false);
  assert.equal(engine.validateWin(state), true);
});

test('generic undo and hardened snapshot restore preserve adapter data and evidence', () => {
  const engine = createCardTaskEngine(lesson27Adapter); const state = engine.createState(100, 'save-test');
  run(engine, state, 'identify-risk', null, 'risk-board', 200);
  run(engine, state, 'redact', 'profile', 'profile', 300);
  const snapshot = engine.snapshot(state, 500);
  const restored = engine.restore(snapshot, 1000);
  assert.equal(restored.data.objects.profile.redacted, true);
  assert.equal(elapsed(restored, 1000), 400);
  assert.equal(engine.undo(restored, 1100), true);
  assert.equal(restored.data.objects.profile.redacted, false);
  assert.throws(() => engine.restore({ ...snapshot, elapsed_at_save_ms: -1 }, 1000), /时间/);
  assert.throws(() => engine.restore({ ...snapshot, action_schema: [] }, 1000), /行动卡版本/);
  assert.throws(() => engine.restore({ ...snapshot, state: { ...snapshot.state, completed: true } }, 1000), /胜利条件/);
});

test('each pilot adapter restores its own evidence and course data', () => {
  const cases = [
    [lesson9Adapter, (engine, state) => run(engine, state, 'reliable', 'file', 'file', 10), item => item.type === 'transport_selected'],
    [lesson17Adapter, (engine, state) => run(engine, state, 'set-heading', 'heading', 'heading', 10), item => item.type === 'html_structure'],
    [lesson27Adapter, (engine, state) => run(engine, state, 'identify-risk', null, 'risk-board', 10), item => item.type === 'risk_identified']
  ];
  for (const [adapter, action, evidenceCheck] of cases) {
    const engine = createCardTaskEngine(adapter);
    const state = engine.createState(0, 'evidence-' + adapter.meta.curriculum_lesson_id);
    assert.equal(action(engine, state), true);
    const snapshot = engine.snapshot(state, 100);
    const restored = engine.restore(snapshot, 200);
    assert.ok(restored.data.evidence.some(evidenceCheck));
    assert.equal(restored.events.some(event => event.type === 'session_loaded'), true);
  }
});

test('course validators reject structurally inconsistent snapshots', () => {
  const l9 = createCardTaskEngine(lesson9Adapter);
  const s9 = l9.createState();
  const snap9 = l9.snapshot(s9, 10);
  const bad9 = JSON.parse(JSON.stringify(snap9));
  bad9.state.data.port_cards[1].id = bad9.state.data.port_cards[0].id;
  assert.throws(() => l9.restore(bad9, 20), /课程对象/);

  const l17 = createCardTaskEngine(lesson17Adapter);
  const s17 = l17.createState();
  const snap17 = l17.snapshot(s17, 10);
  const bad17 = JSON.parse(JSON.stringify(snap17));
  bad17.state.data.preview.revision = 99;
  assert.throws(() => l17.restore(bad17, 20), /课程对象/);

  const l27 = createCardTaskEngine(lesson27Adapter);
  const s27 = l27.createState();
  const snap27 = l27.snapshot(s27, 10);
  const bad27 = JSON.parse(JSON.stringify(snap27));
  bad27.state.data.risk.revision = 99;
  assert.throws(() => l27.restore(bad27, 20), /课程对象/);
});

test('legal target descriptors include type, id, label and disabled reason', () => {
  const engine = createCardTaskEngine(lesson27Adapter); const state = engine.createState();
  for (const action of lesson27Adapter.actions) {
    for (const item of engine.legalTargets(state, action.id)) {
      assert.equal(typeof item.type, 'string'); assert.equal(typeof item.id, 'string'); assert.equal(typeof item.label, 'string');
      if (item.disabledReason) assert.equal(typeof item.disabledReason, 'string');
    }
  }
});
