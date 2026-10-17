const clone = value => JSON.parse(JSON.stringify(value));

function simplifiedSnapshot(state) {
  return {
    phase: state.phase,
    missionStatus: state.missionStatus,
    taskVersion: state.task_version,
    progress: clone(state.progress),
    packetAreas: state.packets ? Object.fromEntries(Object.values(state.packets).map(packet => [packet.id, packet.area])) : undefined,
    nodeOccupancy: state.nodes ? Object.fromEntries(Object.entries(state.nodes).map(([id, node]) => [id, node.occupancy ?? node.status])) : undefined,
    reassemblyStatus: state.reassembly?.status ?? null
  };
}

export const MISSION_STATUS = Object.freeze({
  PLAYING: 'playing',
  SUCCESS: 'success',
  TIMEOUT: 'timeout',
  ENDED: 'ended'
});

export function elapsed(state, now = Date.now()) {
  return Math.max(0, state.accumulated_ms + (state.ended_at === null ? Math.max(0, now - state.segment_started_at) : 0));
}

export function makeRunId() {
  return globalThis.crypto?.randomUUID?.() || 'run-' + Date.now() + '-' + Math.random().toString(16).slice(2);
}

export function record(state, type, detail = {}, now = Date.now()) {
  const difficultyDuration = state.difficultyState?.active && state.difficultyState.startedAt !== null
    ? Math.max(0, now - state.difficultyState.startedAt)
    : 0;
  const objectIds = [detail.object_id, detail.packet_id && 'packet-' + detail.packet_id, detail.target_id]
    .filter(Boolean);
  const event = {
    seq: state.next_event++,
    at: now,
    elapsed_ms: elapsed(state, now),
    type: String(type),
    detail: clone(detail),
    timestamp: now,
    elapsedTime: elapsed(state, now),
    lessonId: state.meta?.curriculum_lesson_id || state.meta?.task_id || null,
    phase: state.phase,
    agentMode: state.agentMode || null,
    eventType: String(type),
    objectIds,
    difficultyType: state.difficultyState?.type || null,
    difficultyDuration,
    recommendationId: state.lastRecommendation?.id || null,
    stateSnapshot: simplifiedSnapshot(state)
  };
  state.events.push(event);
  if (state.events.length > 2000) {
    state.events.shift();
    state.dropped_events++;
  }
  return event;
}

export function setFeedback(state, tone, title, text, now = Date.now()) {
  state.feedback = { tone, title, text };
  record(state, 'task_feedback', { tone, title, text }, now);
}

export function createMissionState(config, now = Date.now(), runId = makeRunId()) {
  const data = typeof config.createInitialData === 'function' ? config.createInitialData() : {};
  const state = {
    meta: { ...config.meta },
    run_id: runId,
    started_at: now,
    segment_started_at: now,
    accumulated_ms: 0,
    ended_at: null,
    phase: config.stages?.[0]?.id || 'tutorial',
    missionStatus: MISSION_STATUS.PLAYING,
    elapsed_ms: 0,
    selectedCard: null,
    selectedObject: null,
    selectedTarget: null,
    progress: { arrived: 0, total: 0, step: 0 },
    mistakes: 0,
    helpUsage: 0,
    task_version: 0,
    undo: [],
    events: [],
    next_event: 1,
    dropped_events: 0,
    reminder_seen: false,
    overtime_seen: false,
    feedback: {
      tone: 'info',
      title: '第一步',
      text: config.intro?.firstStep || '选择一张行动卡，再点击场景中的目标。'
    },
    ...data
  };
  record(state, 'session_started', { task_id: config.meta.task_id, mode: 'campus_tabletop_card_game' }, now);
  return state;
}

export function checkpoint(state) {
  const copy = clone(state);
  for (const key of ['undo', 'events', 'next_event', 'dropped_events', 'started_at', 'segment_started_at', 'accumulated_ms', 'ended_at', 'run_id', 'meta']) {
    delete copy[key];
  }
  return copy;
}

export function pushCheckpoint(state) {
  state.undo.push(checkpoint(state));
  if (state.undo.length > 50) state.undo.shift();
}

export function restoreCheckpoint(state, previous) {
  const lifecycle = {
    undo: state.undo,
    events: state.events,
    next_event: state.next_event,
    dropped_events: state.dropped_events,
    started_at: state.started_at,
    segment_started_at: state.segment_started_at,
    accumulated_ms: state.accumulated_ms,
    ended_at: state.ended_at,
    run_id: state.run_id,
    meta: state.meta
  };
  Object.assign(state, clone(previous), lifecycle);
}

export function tick(state, config, now = Date.now()) {
  if (state.ended_at !== null || state.missionStatus !== MISSION_STATUS.PLAYING) return;
  state.elapsed_ms = elapsed(state, now);
  const reminderMs = config.reminderMs ?? Math.max(0, (config.timeLimitMs || 300000) - 45000);
  if (state.elapsed_ms >= reminderMs && !state.reminder_seen) {
    state.reminder_seen = true;
    record(state, 'wrap_reminder_shown', { strict_cutoff: false }, now);
  }
  if (state.elapsed_ms >= (config.timeLimitMs || 300000) && !state.overtime_seen) {
    state.overtime_seen = true;
    state.missionStatus = MISSION_STATUS.TIMEOUT;
    state.phase = 'timeout';
    record(state, 'target_time_exceeded', { strict_cutoff: false }, now);
    setFeedback(state, 'warn', '时间到了，但你可以收尾', '这是柔性结束：你仍然可以完成最后一步或主动结束。', now);
  }
}

export function end(state, config, now = Date.now()) {
  if (state.ended_at !== null) return false;
  tick(state, config, now);
  state.elapsed_ms = elapsed(state, now);
  state.ended_at = now;
  if (state.missionStatus === MISSION_STATUS.PLAYING) state.missionStatus = MISSION_STATUS.ENDED;
  record(state, 'session_ended', { status: state.missionStatus }, now);
  return true;
}

export function resume(state, now = Date.now()) {
  if (state.ended_at === null) return false;
  state.segment_started_at = now;
  state.ended_at = null;
  if (state.missionStatus === MISSION_STATUS.ENDED || state.missionStatus === MISSION_STATUS.TIMEOUT) state.missionStatus = MISSION_STATUS.PLAYING;
  record(state, 'session_resumed', {}, now);
  return true;
}

export function snapshot(state, config, now = Date.now()) {
  return {
    kind: 'candy-card-game.v2',
    task_id: config.meta.task_id,
    content_version: config.meta.content_version,
    saved_at: now,
    elapsed_at_save_ms: elapsed(state, now),
    state: clone(state)
  };
}

export function restore(input, config, now = Date.now()) {
  const state = input?.state;
  if (input?.kind !== 'candy-card-game.v2' || input.task_id !== config.meta.task_id || input.content_version !== config.meta.content_version || !state) {
    throw new Error('牌桌存档与当前课程版本不兼容。');
  }
  if (!Number.isFinite(input.saved_at) || !Number.isFinite(input.elapsed_at_save_ms) || input.elapsed_at_save_ms < 0 || typeof state.run_id !== 'string' || !Array.isArray(state.events) || !Array.isArray(state.undo) || !state.meta || state.meta.task_id !== config.meta.task_id || state.meta.content_version !== config.meta.content_version) {
    throw new Error('牌桌存档结构无效，当前进度未被替换。');
  }
  const restored = clone(state);
  const away = state.ended_at === null ? Math.max(0, now - input.saved_at) : 0;
  restored.accumulated_ms = input.elapsed_at_save_ms + away;
  restored.segment_started_at = now;
  restored.ended_at = null;
  return restored;
}

export function reset(config, now = Date.now(), runId = makeRunId()) {
  return createMissionState(config, now, runId);
}
