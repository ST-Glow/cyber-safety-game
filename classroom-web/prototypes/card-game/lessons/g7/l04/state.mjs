import LESSON4_CONFIG, { LESSON4_PHASES } from './config.mjs';
import {
  MISSION_STATUS,
  createMissionState,
  elapsed,
  end as endMission,
  pushCheckpoint,
  record,
  restore as restoreMission,
  restoreCheckpoint,
  resume as resumeMission,
  setFeedback,
  snapshot as snapshotMission,
  tick as tickMission
} from '../../../core/mission-state.mjs';
import { clearDifficulty, ensureAgentState, markMeaningfulProgress } from '../../../agent/adaptive-triggered-policy.mjs';
import { detectDifficulty } from './difficulty-rules.mjs';
import { createAgentTriggerPolicy } from '../../../agent/agent-trigger-policy.mjs';

const packetNumber = id => String(id).replace(/^packet-/, '').padStart(2, '0');
const packetId = id => packetNumber(id);
const packet = (state, id) => state.packets[packetId(id)] || null;
const areaPackets = (state, area) => Object.values(state.packets).filter(item => item.area === area);
const areaFull = (state, area) => areaPackets(state, area).length >= (state.nodes[area]?.capacity || 0);
const isActive = state => state.ended_at === null && state.missionStatus !== MISSION_STATUS.SUCCESS && state.missionStatus !== MISSION_STATUS.ENDED;
const target = (type, id, label, disabledReason = null) => disabledReason ? { type, id, label, disabledReason } : { type, id, label };

export { elapsed, LESSON4_PHASES };

function initialData() {
  return {
    wholeAnnouncement: { id: 'whole-announcement', text: '图书馆公告', status: 'intact', size: 'large', packetized: false },
    packets: {},
    nodes: Object.fromEntries(Object.entries(LESSON4_CONFIG.nodeCapacities).map(([id, capacity]) => [id, { id, capacity, status: id === 'receiver' ? 'waiting' : 'ready' }])),
    routes: Object.fromEntries(LESSON4_CONFIG.routes.map(route => [route.id, { ...route, status: 'open' }])),
    arrivalOrder: [],
    reassembly: { status: 'locked', draft: null, sourceVersion: null, stale: false, revision: 0, expectedIds: LESSON4_CONFIG.packetDefinitions.map(definition => definition.id), selectedOrder: [], attempts: 0, lastAttempt: null },
    tutorialStage: 0,
    completed: false,
    phase: LESSON4_PHASES.WHOLE_DATA_BLOCKED,
    phaseStartedAt: 0,
    lastMeaningfulProgressAt: 0,
    meaningfulProgressSeq: 0,
    invalidActionStreak: 0,
    invalidHistory: [],
    agentMode: 'adaptive_triggered',
    difficultyState: { active: false, type: null, startedAt: null, lastUpdatedAt: null, evidence: [], recommendationTriggered: false, adviceLevel: 1 },
    autoInterventionCount: 0,
    agentCooldownUntil: 0,
    lastRecommendation: null
  };
}

function setPhase(state, phase, now) {
  if (state.phase === phase) return false;
  const previous = state.phase;
  state.phase = phase;
  state.phaseStartedAt = now;
  record(state, 'phase_change', { from: previous, to: phase }, now);
  return true;
}

export function createState(now = Date.now(), runIdOrOptions, maybeOptions = {}) {
  const options = typeof runIdOrOptions === 'object' ? runIdOrOptions : maybeOptions;
  const runId = typeof runIdOrOptions === 'string' ? runIdOrOptions : options.runId;
  const state = createMissionState(LESSON4_CONFIG, now, runId);
  Object.assign(state, initialData());
  state.phaseStartedAt = now;
  state.lastMeaningfulProgressAt = now;
  state.progress = { arrived: 0, total: 0, step: 0 };
  state.feedback = { tone: 'info', title: '第一步', text: LESSON4_CONFIG.intro.firstStep };
  ensureAgentState(state, options.agentMode || 'adaptive_triggered');
  record(state, 'agent_mode_set', { agent_mode: state.agentMode }, now);
  record(state, 'mission_start', {}, now);
  return state;
}

function reject(state, code, title, text, now, detail = {}) {
  state.mistakes++;
  noteInvalidAction(state, code, detail, now);
  setFeedback(state, 'warn', title, text, now);
  record(state, 'action_invalid', { code, ...detail }, now);
  return { ok: false, code, title, text, feedback: state.feedback };
}

export function noteInvalidAction(state, code, detail = {}, now = Date.now()) {
  state.invalidActionStreak = (state.invalidActionStreak || 0) + 1;
  state.invalidHistory ||= [];
  state.invalidHistory.push({ code, ...detail, at: now, progressSeq: state.meaningfulProgressSeq });
  state.invalidHistory = state.invalidHistory.slice(-12);
}

function route(state, from, to) {
  return Object.values(state.routes).find(item => item.from === from && item.to === to) || null;
}

function packetTargets(state, action, objectId = null) {
  const id = objectId ? packetId(objectId) : null;
  if (!id) {
    const candidates = Object.values(state.packets).filter(item => item.area !== 'receiver');
    return candidates.map(item => target('packet', 'packet-' + item.id, item.id + ' · ' + item.text));
  }
  const item = packet(state, id);
  if (!item || item.area === 'receiver') return [];
  if (item.area === 'sender') {
    return ['node-a', 'node-b', 'node-c'].map(area => target('node', area, area.replace('node-', '节点 ').toUpperCase(), state.nodes[area].status === 'congested' ? '这个节点正在拥堵，请观察其他有空位的站点。' : areaFull(state, area) ? '这个节点已经没有空位。' : null));
  }
  if (['node-a', 'node-b', 'node-c'].includes(item.area)) {
    const link = route(state, item.area, 'receiver');
    const result = [target('receiver', 'receiver', '图书馆公告屏', link?.status === 'congested' ? '这条出口正在拥堵，请先选择另一个有空位的节点。' : null)];
    if (item.area === 'node-a' && link?.status === 'congested') {
      result.push(...['node-b', 'node-c'].map(area => target('node', area, area.replace('node-', '节点 ').toUpperCase(), areaFull(state, area) ? '这个节点已经没有空位。' : null)));
    }
    return result;
  }
  return [];
}

function objectTargets(state, action, objectId = null) {
  if (action === 'packetize') {
    if (!objectId) return [target('announcement', 'whole-announcement', '图书馆公告')];
    return objectId === 'whole-announcement' ? [target('announcement', 'whole-announcement', '图书馆公告')] : [];
  }
  if (action === 'forward' || action === 'reroute') {
    if (!objectId) {
      if (!state.wholeAnnouncement.packetized) return [target('announcement', 'whole-announcement', '图书馆公告')];
      return packetTargets(state, action);
    }
    if (objectId === 'whole-announcement') {
      return ['node-a', 'node-b', 'node-c'].map(area => target('node', area, area.replace('node-', '节点 ').toUpperCase()));
    }
    return packetTargets(state, action, objectId);
  }
  if (action === 'reassemble') {
    return [target('receiver', 'receiver', '图书馆公告屏', state.arrivalOrder.length < 4 ? '还有数据包没有到达。' : null)];
  }
  return [];
}

export function legalTargets(state, action, objectId = null) {
  if (!isActive(state)) return [];
  if (action === 'packetize' && state.wholeAnnouncement.status !== 'blocked') return [];
  if (action === 'reassemble' && !['ready', 'sorting'].includes(state.reassembly.status)) return objectTargets(state, action, objectId);
  return objectTargets(state, action, objectId);
}

export function selectableObjects(state, action) {
  return legalTargets(state, action, null).filter(item => !item.disabledReason).map(item => item.id);
}

function packetize(state, now) {
  pushCheckpoint(state);
  state.wholeAnnouncement.status = 'packetized';
  state.wholeAnnouncement.packetized = true;
  state.packets = Object.fromEntries(LESSON4_CONFIG.packetDefinitions.map(definition => [definition.id, {
    id: definition.id,
    text: definition.text,
    color: definition.color,
    area: 'sender',
    status: 'ready',
    path: ['sender']
  }]));
  state.progress.total = 4;
  state.task_version++;
  setPhase(state, LESSON4_PHASES.FORWARDING, now);
  state.tutorialStage = 2;
  for (const item of Object.values(state.packets)) record(state, 'packet_created', { packet_id: item.id, group_id: 'library-announcement' }, now);
  markMeaningfulProgress(state, 'packetized', { packet_ids: Object.keys(state.packets) }, now, record);
  setFeedback(state, 'success', '公告已拆成4个数据包', '现在用“转发”让它们经过校园节点。', now);
  return { ok: true, versioned: true, checkpointed: true, action: 'packetize', eventType: 'action_executed', detail: { packet_count: 4 } };
}

function markCongestion(state, now) {
  if (areaPackets(state, 'node-a').length >= 2 && state.routes['node-a-receiver'].status === 'open') {
    state.routes['node-a-receiver'].status = 'congested';
    state.nodes['node-a'].status = 'congested';
    setPhase(state, LESSON4_PHASES.CONGESTION, now);
    record(state, 'congestion_started', { route_id: 'node-a-receiver', node_id: 'node-a' }, now);
    return true;
  }
  return false;
}

function movePacket(state, item, to, action, now) {
  const from = item.area;
  pushCheckpoint(state);
  item.area = to;
  item.status = to === 'receiver' ? 'arrived' : 'stored';
  item.path.push(to);
  state.task_version++;
  state.progress.step++;
  if (to === 'receiver' && !state.arrivalOrder.includes(item.id)) state.arrivalOrder.push(item.id);
  state.progress.arrived = state.arrivalOrder.length;
  if (state.nodes[from]) state.nodes[from].status = from === 'node-a' && state.routes['node-a-receiver'].status === 'congested' ? 'congested' : 'ready';
  if (state.nodes[to]) state.nodes[to].status = to === 'receiver' ? 'receiving' : 'occupied';
  const congestionStarted = markCongestion(state, now);
  record(state, 'packet_moved', { packet_id: item.id, from, to, path: [...item.path] }, now);
  if (to.startsWith('node-')) record(state, 'node_entered', { packet_id: item.id, node_id: to }, now);
  if (from.startsWith('node-')) record(state, 'node_left', { packet_id: item.id, node_id: from }, now);
  if (to === 'receiver') record(state, 'packet_delivered', { packet_id: item.id, arrival_order: [...state.arrivalOrder] }, now);
  if (state.progress.arrived === state.progress.total) {
    setPhase(state, LESSON4_PHASES.REASSEMBLY, now);
    state.tutorialStage = 6;
    state.reassembly.status = 'ready';
    const inOrder = state.arrivalOrder.join('') === '01020304';
    setFeedback(state, 'success', inOrder ? '包都到了，检查后重组公告' : '包都到了，但公告还是乱的', '到达顺序是 ' + state.arrivalOrder.join(' / ') + '。使用“重组”检查编号。', now);
  } else if (congestionStarted) {
    state.tutorialStage = 4;
    setFeedback(state, 'warn', 'A 站出现拥堵', '出口暂不可用。观察容量，选择其他可达站点。', now);
  } else if (to.startsWith('node-')) {
    setPhase(state, state.phase === LESSON4_PHASES.CONGESTION ? LESSON4_PHASES.CONGESTION : LESSON4_PHASES.FORWARDING, now);
    setFeedback(state, 'info', item.id + ' 已缓存', '包先停在节点里，下一步还可以继续转发。', now);
  } else {
    setPhase(state, LESSON4_PHASES.DELIVERY, now);
    setFeedback(state, 'success', item.id + ' 已送达公告屏', '节点 ' + from.replace('node-', '').toUpperCase() + ' → 公告屏；到达顺序已经记录。', now);
  }
  markMeaningfulProgress(state, 'packet_moved', { packet_id: item.id, from, to }, now, record);
  const recommendation = state.lastRecommendation;
  if (recommendation && state.recommendationViews?.[recommendation.id] && now - recommendation.createdAt <= 30000 &&
      recommendation.suggestedCardId === 'forward' && recommendation.suggestedPacketIds.includes(item.id) && recommendation.suggestedTargetIds.includes(to)) {
    record(state, 'recommendation_followed_candidate', { candidateMatch: true, packet_id: item.id, target_id: to }, now);
  }
  return { ok: true, versioned: true, checkpointed: true, action, eventType: 'action_executed', detail: { packet_id: item.id, from, to, congestion_started: congestionStarted } };
}

function startReassembly(state, now) {
  if (state.arrivalOrder.length !== 4) return reject(state, 'not_all_arrived', '还不能重组', '先让4个数据包都到达公告屏。', now);
  if (state.reassembly.status === 'sorting') return { ok: true, action: 'reassemble', detail: { already_started: true } };
  pushCheckpoint(state);
  state.reassembly.status = 'sorting';
  state.reassembly.selectedOrder = [];
  setPhase(state, LESSON4_PHASES.REASSEMBLY, now);
  markMeaningfulProgress(state, 'reassembly_started', {}, now, record);
  record(state, 'reassembly_started', { arrival_order: [...state.arrivalOrder] }, now);
  setFeedback(state, 'info', '开始重组', '观察编号，按你的判断依次点选数据包。', now);
  return { ok: true, versioned: true, checkpointed: true, action: 'reassemble', eventType: 'action_executed' };
}

export function selectReassemblyOrder(state, order, now = Date.now()) {
  if (!isActive(state) || state.reassembly.status !== 'sorting' || !Array.isArray(order)) return false;
  const normalized = order.map(packetNumber);
  if (new Set(normalized).size !== normalized.length || normalized.some(id => !state.packets[id] || state.packets[id].area !== 'receiver')) return false;
  const score = value => { let n = 0; while (value[n] && value[n] === state.reassembly.expectedIds[n]) n++; return n; };
  if (JSON.stringify(normalized) === JSON.stringify(state.reassembly.selectedOrder)) return false;
  pushCheckpoint(state);
  const previous = score(state.reassembly.selectedOrder);
  state.reassembly.selectedOrder = normalized;
  state.task_version++;
  record(state, 'reassembly_order_changed', { order: normalized }, now);
  if (score(normalized) > previous) markMeaningfulProgress(state, 'reassembly_improved', {}, now, record);
  return true;
}

export function attemptReassembly(state, order, now = Date.now()) {
  if (!isActive(state) || !Array.isArray(order)) return { ok: false, code: 'mission_closed' };
  if (state.reassembly.status !== 'sorting') return reject(state, 'reassembly_not_started', '还没开始重组', '先选择“重组”行动卡。', now);
  const normalized = order.map(packetNumber);
  const expected = [...state.reassembly.expectedIds];
  state.reassembly.attempts++;
  state.reassembly.lastAttempt = normalized;
  record(state, 'reassembly_attempt', { order: normalized, expected }, now);
  if (normalized.length !== expected.length || normalized.some((id, index) => id !== expected[index])) {
    setFeedback(state, 'warn', '顺序好像还不对', '看看每个包上的编号，再试一次。', now);
    noteInvalidAction(state, 'wrong_reassembly_order', {}, now);
    return { ok: false, code: 'wrong_reassembly_order', feedback: state.feedback };
  }
  pushCheckpoint(state);
  const ordered = normalized.map(id => state.packets[id].text);
  state.reassembly.status = 'complete';
  state.reassembly.selectedOrder = expected;
  state.reassembly.draft = { receivedIds: [...state.arrivalOrder], ordered, missing: [], message: ordered.join('') };
  state.reassembly.sourceVersion = state.task_version;
  state.reassembly.stale = false;
  state.reassembly.revision++;
  state.tutorialStage = 7;
  setPhase(state, LESSON4_PHASES.SUCCESS, now);
  state.completed = true;
  state.missionStatus = MISSION_STATUS.SUCCESS;
  markMeaningfulProgress(state, 'reassembled', { order: expected }, now, record);
  setFeedback(state, 'success', '公告屏亮起', '恢复后的通知是“' + ordered.join('') + '”。', now);
  record(state, 'mission_success', { message: ordered.join(''), arrival_order: [...state.arrivalOrder] }, now);
  return { ok: true, complete: true, versioned: true, checkpointed: true, action: 'reassemble', detail: { message: ordered.join('') } };
}

export function applyAction(state, action, objectId = null, targetId = null, now = Date.now()) {
  if (!isActive(state)) return reject(state, 'mission_closed', '这局已经结束', '可以点击“再来一局”重新处理事件。', now);
  const normalizedAction = action === 'reroute' ? 'forward' : action;
  const targets = legalTargets(state, normalizedAction, objectId);
  const selected = targets.find(item => item.id === targetId);
  if (!selected) return reject(state, 'illegal_target', '这里还不能走', '请选择当前高亮的对象和目标。', now, { action, objectId, targetId });
  if (normalizedAction === 'forward' && objectId === 'whole-announcement' && !state.wholeAnnouncement.packetized) {
    pushCheckpoint(state);
    state.wholeAnnouncement.status = 'blocked';
    setPhase(state, LESSON4_PHASES.PACKETIZATION, now);
    state.tutorialStage = 1;
    markMeaningfulProgress(state, 'capacity_discovered', {}, now, record);
    setFeedback(state, 'info', '这份公告太大，节点装不下', '公告留在发送站。试试刚解锁的“分包”。', now);
    return { ok: false, committed: true, code: 'whole_data_blocked', feedback: state.feedback };
  }
  if (selected.disabledReason) {
    if (action === 'forward' && objectId === 'whole-announcement') {
      state.wholeAnnouncement.status = 'blocked';
      setPhase(state, LESSON4_PHASES.PACKETIZATION, now);
      state.tutorialStage = 1;
    }
    return reject(state, 'disabled_target', '这个目标暂时不能用', selected.disabledReason, now, { action, objectId, targetId });
  }
  if (normalizedAction === 'packetize') return packetize(state, now);
  if (normalizedAction === 'reassemble') return startReassembly(state, now);
  const item = packet(state, objectId);
  if (!item) return reject(state, 'missing_object', '先选择一个数据包', '行动卡需要作用在具体的数据包上。', now);
  return movePacket(state, item, targetId, action, now);
}

export function packetizeAnnouncement(state, now = Date.now()) {
  return applyAction(state, 'packetize', 'whole-announcement', 'whole-announcement', now);
}

export function reassemble(state, orderOrNow = null, now = Date.now()) {
  if (Array.isArray(orderOrNow)) return attemptReassembly(state, orderOrNow, now);
  return applyAction(state, 'reassemble', null, 'receiver', typeof orderOrNow === 'number' ? orderOrNow : now);
}

export function undo(state, now = Date.now()) {
  if (state.ended_at !== null || !state.undo.length) return false;
  const previous = state.undo.pop();
  const agent = { agentMode: state.agentMode, autoInterventionCount: state.autoInterventionCount, agentCooldownUntil: state.agentCooldownUntil, lastRecommendation: state.lastRecommendation, recommendationViews: state.recommendationViews, lastRecommendationProgressSeq: state.lastRecommendationProgressSeq };
  clearDifficulty(state, now, 'undo', record);
  restoreCheckpoint(state, previous);
  Object.assign(state, agent);
  state.lastMeaningfulProgressAt = now;
  state.phaseStartedAt = now;
  state.difficultyState = { active: false, type: null, startedAt: null, lastUpdatedAt: now, evidence: [], recommendationTriggered: false, adviceLevel: 1 };
  setFeedback(state, 'info', '已撤销上一张行动卡', '路线和数据包回到上一步，可以换一条路线继续。', now);
  record(state, 'operation_undone', {}, now);
  return true;
}

export function validateWin(state) {
  return Boolean(state.missionStatus === MISSION_STATUS.SUCCESS && state.completed && state.arrivalOrder.length === 4 && new Set(state.arrivalOrder).size === 4 &&
    Object.values(state.packets).length === 4 && Object.values(state.packets).every(p => p.area === 'receiver') &&
    state.reassembly.status === 'complete' && state.reassembly.selectedOrder.join('') === '01020304' &&
    state.reassembly.draft?.message === state.reassembly.selectedOrder.map(id => state.packets[id]?.text || '').join(''));
}

export function help(state, kind = 'operation_help', now = Date.now()) {
  const messages = {
    operation_help: '先选择一张行动卡，再点击地图中的目标。',
    task_feedback: state.routes['node-a-receiver'].status === 'congested' ? 'A站已经满了，看看旁边还有没有空的位置。' : '节点会先缓存数据包，再把它转发到下一站。',
    metacognitive_prompt: '你的目标是让所有数据包都到达。现在还有哪些路线可用？'
  };
  state.helpUsage++;
  record(state, kind, { text: messages[kind] || messages.operation_help, usage: state.helpUsage }, now);
  setFeedback(state, 'info', kind === 'metacognitive_prompt' ? '想一想再行动' : '值班提示', messages[kind] || messages.operation_help, now);
  return { type: kind, text: messages[kind] || messages.operation_help };
}

export function requestAgentHelp(state, now = Date.now()) {
  return policyFor(state).request(state, now);
}

function policyFor(state) {
  return createAgentTriggerPolicy(state.agentMode, { config: LESSON4_CONFIG, detectDifficulty, legalTargets, record });
}

export function tick(state, now = Date.now()) {
  tickMission(state, LESSON4_CONFIG, now);
  if (state.missionStatus === MISSION_STATUS.TIMEOUT && state.phase !== LESSON4_PHASES.TIMEOUT_SOFT) {
    state.phase = LESSON4_PHASES.TIMEOUT_SOFT;
    record(state, 'soft_timeout', { strict_cutoff: false }, now);
  }
  policyFor(state).tick(state, now);
}

export function end(state, now = Date.now()) {
  state.phaseBeforeEnd = state.phase;
  const ended = endMission(state, LESSON4_CONFIG, now);
  if (ended) state.phase = LESSON4_PHASES.ENDED;
  return ended;
}

export function resume(state, now = Date.now()) {
  const resumed = resumeMission(state, now);
  if (resumed) setPhase(state, state.phaseBeforeEnd || LESSON4_PHASES.FORWARDING, now);
  return resumed;
}

export function snapshot(state, now = Date.now()) {
  return snapshotMission(state, LESSON4_CONFIG, now);
}

export function restore(input, now = Date.now()) {
  const result = restoreMission(input, LESSON4_CONFIG, now);
  if (!result.wholeAnnouncement || !result.nodes || !result.routes || !Array.isArray(result.arrivalOrder) || !result.reassembly || !result.difficultyState) throw new Error('第4课存档对象不完整。');
  ensureAgentState(result, result.agentMode || 'adaptive_triggered');
  return result;
}

export function resetLevel(now = Date.now(), runId, options = {}) {
  return createState(now, { runId, ...options });
}

