// Course-agnostic card-task loop. Adapters own course objects and rules;
// the engine owns target contracts, history, evidence and safe persistence.

const clone = value => JSON.parse(JSON.stringify(value));
const makeRunId = () => globalThis.crypto?.randomUUID?.()
  || `run-${Date.now()}-${Math.random().toString(16).slice(2)}`;
const finite = value => Number.isFinite(value);
const nonNegative = value => finite(value) && value >= 0;
const integer = value => Number.isInteger(value) && value >= 0;

export function makeTarget(type, id, label, disabledReason = null, meta = undefined) {
  if (!type || id === undefined || id === null || !label) throw new TypeError('Target descriptors need type, id and label.');
  const target = { type: String(type), id: String(id), label: String(label) };
  if (disabledReason) target.disabledReason = String(disabledReason);
  if (meta !== undefined) target.meta = clone(meta);
  return Object.freeze(target);
}

function normalizeTarget(raw) {
  if (typeof raw === 'string' || typeof raw === 'number') return makeTarget('object', raw, String(raw));
  if (!raw || typeof raw !== 'object') throw new TypeError('legalTargets() must return target descriptors.');
  return makeTarget(raw.type, raw.id, raw.label, raw.disabledReason, raw.meta);
}

export const elapsed = (state, now = Date.now()) => Math.max(0,
  state.accumulated_ms + (state.ended_at === null ? Math.max(0, now - state.segment_started_at) : 0));

export function record(state, type, detail = {}, now = Date.now()) {
  const event = { seq: state.next_event++, at: now, elapsed_ms: elapsed(state, now), type: String(type), detail: clone(detail) };
  state.events.push(event);
  if (state.events.length > 2000) { state.events.shift(); state.dropped_events++; }
  return event;
}

function checkpoint(state) {
  return clone({ phase: state.phase, task_version: state.task_version, completed: state.completed, error_count: state.error_count, feedback: state.feedback, data: state.data });
}
function restoreCheckpoint(state, previous) { Object.assign(state, clone(previous)); }
function setFeedback(state, tone, title, text) { state.feedback = { tone, title, text }; }

function invalidResult(state, result, now, detail = {}) {
  state.error_count++;
  setFeedback(state, result?.tone || 'warn', result?.title || '这张牌现在不能用', result?.text || '请重新查看当前对象和目标。');
  record(state, 'invalid_action', { code: result?.code || 'invalid_action', action: detail.action, object_id: detail.objectId, target_id: detail.targetId, ...(result?.detail || {}) }, now);
  return { ok: false, code: result?.code || 'invalid_action', feedback: state.feedback };
}

function validateAdapter(adapter) {
  if (!adapter?.meta?.task_id || !adapter.meta.content_version) throw new TypeError('Card task adapters require meta.task_id and meta.content_version.');
  if (!Array.isArray(adapter.actions) || !adapter.actions.length) throw new TypeError(`Card task adapter ${adapter.meta.task_id} must declare actions.`);
  const ids = new Set();
  for (const action of adapter.actions) {
    if (!action?.id || !action.title || ids.has(action.id)) throw new TypeError('Every card task action needs a unique id and title.');
    ids.add(action.id);
  }
  if (typeof adapter.createInitialState !== 'function' || typeof adapter.legalTargets !== 'function' || typeof adapter.applyAction !== 'function') throw new TypeError(`Card task adapter ${adapter.meta.task_id} needs createInitialState(), legalTargets() and applyAction().`);
  if (typeof adapter.validateState !== 'function' || typeof adapter.validateWin !== 'function') throw new TypeError(`Card task adapter ${adapter.meta.task_id} needs validateState() and validateWin().`);
}

function actionSchema(adapter) { return adapter.actions.map(action => ({ id: String(action.id), title: String(action.title), purpose: String(action.purpose || '') })); }
function validateEvents(events) {
  if (!Array.isArray(events) || events.length > 2000) return false;
  let previous = 0;
  return events.every(event => {
    const valid = integer(event?.seq) && event.seq > previous && finite(event.at) && nonNegative(event.elapsed_ms) && typeof event.type === 'string' && event.detail && typeof event.detail === 'object';
    previous = event?.seq || previous;
    return valid;
  });
}
function validCheckpoint(item) {
  return item && typeof item === 'object' && typeof item.phase === 'string' && integer(item.task_version) && typeof item.completed === 'boolean' && integer(item.error_count) && item.feedback && item.data && typeof item.data === 'object';
}

export function createCardTaskEngine(adapter) {
  validateAdapter(adapter);
  const actionIds = new Set(adapter.actions.map(action => action.id));
  const schema = actionSchema(adapter);
  const engine = {
    adapter,
    createState(now = Date.now(), runId = makeRunId()) {
      const state = {
        meta: { ...adapter.meta }, run_id: runId, started_at: now, segment_started_at: now, accumulated_ms: 0, ended_at: null,
        phase: 'ready', task_version: 0, completed: false, error_count: 0, undo: [], events: [], next_event: 1, dropped_events: 0,
        reminder_seen: false, overtime_seen: false, feedback: clone(adapter.initialFeedback || { tone: 'info', title: '开始任务', text: adapter.meta.task_title || '选择一张行动卡开始。' }),
        data: clone(adapter.createInitialState({ now, runId }))
      };
      if (!adapter.validateState(state)) throw new Error('Adapter created an invalid initial state.');
      adapter.onCreate?.(state, { now, record: (type, detail) => record(state, type, detail, now) });
      record(state, 'session_started', { task_id: adapter.meta.task_id, mode: 'card_task', evidence_type: adapter.meta.evidence_type || 'course_state' }, now);
      return state;
    },
    legalTargets(state, action, objectId = null) {
      if (state.ended_at !== null || !actionIds.has(action)) return [];
      return (adapter.legalTargets(state, action, objectId) || []).map(normalizeTarget);
    },
    selectableObjects(state, action) {
      if (state.ended_at !== null) return [];
      return typeof adapter.selectableObjects === 'function' ? [...(adapter.selectableObjects(state, action) || [])] : [];
    },
    actionHint(state, action, objectId = null) { return adapter.actionHint?.(state, action, objectId) || ''; },
    applyAction(state, action, objectId = null, targetId = null, now = Date.now()) {
      if (state.ended_at !== null) return invalidResult(state, { code: 'session_ended', title: '本次体验已结束', text: '请重新开始或恢复一局新的体验。' }, now, { action, objectId, targetId });
      if (!actionIds.has(action)) return invalidResult(state, { code: 'unknown_action', title: '这张行动卡不存在', text: '当前课程没有这张牌。' }, now, { action, objectId, targetId });
      const targets = engine.legalTargets(state, action, objectId);
      const selected = targets.find(target => target.id === String(targetId));
      if (!selected) return invalidResult(state, { code: 'illegal_target', title: '目标不在这张牌的规则内', text: `请从${targets.map(target => target.label).join('、') || '当前可用目标'}中选择。` }, now, { action, objectId, targetId });
      if (selected.disabledReason) return invalidResult(state, { code: 'disabled_target', title: '这个目标暂时不能处理', text: selected.disabledReason, detail: { reason: selected.disabledReason } }, now, { action, objectId, targetId });
      const before = checkpoint(state);
      let result;
      try {
        result = adapter.applyAction(state, action, objectId, String(targetId), { now, legalTargets: (a, o = null) => engine.legalTargets(state, a, o), selectableObjects: a => engine.selectableObjects(state, a), actionHint: (a, o = null) => engine.actionHint(state, a, o), setFeedback: (tone, title, text) => setFeedback(state, tone, title, text) });
      } catch (error) {
        restoreCheckpoint(state, before);
        return invalidResult(state, { code: 'adapter_error', title: '行动没有完成', text: '课程对象暂时无法处理这张牌。', detail: { message: error.message } }, now, { action, objectId, targetId });
      }
      if (!result?.ok) { restoreCheckpoint(state, before); return invalidResult(state, result || { code: 'invalid_action' }, now, { action, objectId, targetId }); }
      state.undo.push(before);
      if (state.undo.length > 50) state.undo.shift();
      if (result.changed !== false) {
        state.task_version++;
        adapter.invalidateDerived?.(state, { action, objectId, targetId, result, taskVersion: state.task_version });
      }
      if (result.phase) state.phase = result.phase;
      if (result.complete) { state.completed = true; state.phase = result.phase || 'completed'; }
      else if (result.changed !== false) {
        state.completed = false;
        if (state.phase === 'completed') state.phase = 'in_progress';
      }
      if (result.feedback) setFeedback(state, result.feedback.tone, result.feedback.title, result.feedback.text);
      record(state, result.eventType || `action_${action}`, { action, object_id: objectId, target_id: targetId, ...result.detail }, now);
      return { ...result, ok: true, task_version: state.task_version };
    },
    undo(state, now = Date.now()) {
      if (state.ended_at !== null || !state.undo.length) return false;
      restoreCheckpoint(state, state.undo.pop());
      setFeedback(state, 'info', '已撤销上一张行动卡', '对象和任务状态回到上一步，可以换一条路线继续。');
      record(state, 'operation_undone', {}, now);
      return true;
    },
    snapshot(state, now = Date.now()) {
      return { kind: 'candy-card-task-engine.v1', task_id: adapter.meta.task_id, content_version: adapter.meta.content_version, saved_at: now, elapsed_at_save_ms: elapsed(state, now), action_schema: clone(schema), state: clone(state) };
    },
    restore(input, now = Date.now()) {
      const state = input?.state;
      if (input?.kind !== 'candy-card-task-engine.v1' || input.task_id !== adapter.meta.task_id || input.content_version !== adapter.meta.content_version || !state) throw new Error('备份格式、课程版本或任务状态不兼容，当前进度未被替换。');
      if (!finite(input.saved_at) || !nonNegative(input.elapsed_at_save_ms) || JSON.stringify(input.action_schema) !== JSON.stringify(schema)) throw new Error('备份的时间或行动卡版本不兼容，当前进度未被替换。');
      if (state.meta?.task_id !== adapter.meta.task_id || state.meta?.content_version !== adapter.meta.content_version || typeof state.run_id !== 'string' || !finite(state.started_at) || !finite(state.segment_started_at) || !nonNegative(state.accumulated_ms) || (state.ended_at !== null && !finite(state.ended_at)) || typeof state.phase !== 'string' || !integer(state.task_version) || typeof state.completed !== 'boolean' || !integer(state.error_count) || !Array.isArray(state.undo) || !state.undo.every(validCheckpoint) || !validateEvents(state.events) || !integer(state.next_event) || !integer(state.dropped_events) || !state.data) throw new Error('备份格式、课程版本或任务状态不兼容，当前进度未被替换。');
      if (!adapter.validateState(state)) throw new Error('备份中的课程对象状态无法通过适配器校验，当前进度未被替换。');
      if (state.completed && !adapter.validateWin(state)) throw new Error('备份声称已经完成，但课程对象证据并不满足胜利条件，当前进度未被替换。');
      const restored = clone(state);
      restored.accumulated_ms = input.elapsed_at_save_ms; restored.segment_started_at = now; restored.ended_at = null; restored.feedback = restored.feedback || clone(adapter.initialFeedback);
      adapter.onRestore?.(restored, { now });
      record(restored, 'session_loaded', { source: 'snapshot' }, now);
      return restored;
    },
    artifact(state) { return adapter.artifact?.(state) || null; },
    validateWin(state) { return Boolean(state.completed && adapter.validateWin(state)); },
    tick(state, now = Date.now()) { if (state.ended_at !== null) return; const duration = adapter.meta.duration_ms || 300000; if (elapsed(state, now) >= duration && !state.overtime_seen) { state.overtime_seen = true; record(state, 'target_time_exceeded', { strict_cutoff: false }, now); } },
    end(state, now = Date.now()) { if (state.ended_at !== null) return false; engine.tick(state, now); state.accumulated_ms = elapsed(state, now); state.ended_at = now; record(state, 'session_ended', { completed: engine.validateWin(state) }, now); return true; },
    resume(state, now = Date.now()) { if (state.ended_at === null) return false; state.segment_started_at = now; state.ended_at = null; record(state, 'session_resumed', {}, now); return true; }
  };
  return Object.freeze(engine);
}
