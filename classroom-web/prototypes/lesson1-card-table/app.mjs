import { elapsed, record, createCardTaskEngine } from './core.mjs';
import { lesson1Adapter } from './adapters/lesson1.mjs';
import { activateKnowledge, attemptKnowledgePair, dismissKnowledge, selectKnowledgeConcept } from './adapters/lesson1-knowledge.mjs';
import { createVisualGameShell } from './visual-game-shell.mjs';
import { createNetworkLessonScene } from './network-lesson-scene.mjs';
import { createLesson1Tour } from './tour.mjs';
import { createKnowledgeDialog } from './knowledge-dialog.mjs';
import { createStudentEntry } from './student-entry.mjs';
import { createTrialStudy } from './trial-study.mjs';
import { studentStorageKey, belongsToStudent } from './student-session.mjs';
import LESSON1_CONFIG from './config.mjs';
import { recommendLesson1 } from './agent.mjs';
import { loadExperimentConfig, createExperimentSupport } from './experiment-support.mjs';

try { await loadExperimentConfig(); }
catch (error) { document.querySelector('#app').textContent = error.message; throw error; }

const root = document.querySelector('#app');
const engine = createCardTaskEngine(lesson1Adapter);
let participant = null;
let studentEntry = null;
let trialStudy = null;
let support = null;
let cloudReady = false;
let state = engine.createState(Date.now(), `lesson1-${Date.now()}`);
state.recommendationViews = {};
let started = false;
let selectedCard = null;
let agentUi = { open: false, why: false, bubble: false, highlightIds: [], successDismissed: false };
let lastProgressVersion = state.task_version;
let lastProgressAt = Date.now();
let seenRecommendationId = null;
let highlightTimer = null;
let tour = null;
let knowledgeDialog = null;
let pausedElapsed = null;
let pauseStartedAt = null;
let saveMessage = '';
const MAX_PROACTIVE_TUTORIAL_HINTS = 2;
const LINK_MACHINE_ALIASES = Object.freeze({
  'early-terminal': 'early-central-link',
  'early-central-fault': 'early-central-link',
  'protocol-network-a': 'protocol-bridge',
  'protocol-network-b': 'protocol-bridge',
  'mesh-node': 'mesh-main-line',
  'mesh-receiver': 'mesh-main-line'
});

function pauseExperienceClock() {
  if (started && pausedElapsed === null) {
    pauseStartedAt = Date.now();
    pausedElapsed = elapsed(state, pauseStartedAt);
  }
}

// Keep the engine's clock consistent with the paused UI before writing events
// or snapshots. Paused reading time must not reappear after a refresh.
function syncPausedClock(now = Date.now()) {
  if (pausedElapsed === null) return;
  state.accumulated_ms = pausedElapsed;
  state.segment_started_at = now;
  state.elapsed_ms = pausedElapsed;
}

function resumeExperienceClock() {
  if (pausedElapsed === null) return;
  const now = Date.now();
  syncPausedClock(now);
  if (pauseStartedAt !== null) lastProgressAt += now - pauseStartedAt;
  pausedElapsed = null;
  pauseStartedAt = null;
}

function recordKnowledgeEvents(events, now = Date.now()) {
  syncPausedClock(now);
  for (const event of events || []) record(state, event.type, event.detail || {}, now);
}

function saveSnapshot(slot = 'session') {
  if (!participant || !started) return false;
  const now = Date.now();
  syncPausedClock(now);
  try {
    if (support?.enabled) state.experiment_support = support.snapshot();
    const snapshot = JSON.stringify(engine.snapshot(state, now));
    localStorage.setItem(studentStorageKey(participant, slot), snapshot);
    // Keep each run when a student restarts; the latest session is a resume pointer.
    localStorage.setItem(studentStorageKey(participant, `run:${state.run_id}`), snapshot);
    saveMessage = '进度已保存在本机，填写相同班级和姓名可继续。';
    return true;
  } catch {
    saveMessage = '当前浏览器无法保存进度；仍可继续本次游戏。';
    return false;
  }
}

function persistSession() {
  if (started && participant) {
    saveSnapshot();
    trialStudy?.observe(engine.snapshot(state, Date.now()));
  }
}

function restoreStudentSnapshot(raw) {
  const snapshot = JSON.parse(raw);
  if (!belongsToStudent(snapshot, participant)) throw new Error('存档属于另一位学生。');
  return engine.restore(snapshot, Date.now());
}

function restoreSession() {
  try {
    const raw = localStorage.getItem(studentStorageKey(participant));
    if (!raw) return;
    const snapshot = JSON.parse(raw);
    const restored = restoreStudentSnapshot(raw);
    // An explicitly ended run stays ended; the engine's manual restore path
    // remains available in the menu when the student wants to resume it.
    if (snapshot.state.ended_at !== null) return;
    state = restored;
    state.participant = { ...participant };
    state.recommendationViews ||= {};
    started = true;
    lastProgressVersion = state.task_version;
    lastProgressAt = Date.now();
    saveMessage = '已恢复本机进度。';
  } catch {
    saveMessage = '旧进度无法恢复，本次从新游戏开始。';
  }
}

function activateKnowledgeCheckpoint(index) {
  if (!activateKnowledge(state.data.knowledge, index)) return;
  state.data.revision++;
  pauseExperienceClock();
}

function openKnowledgeIfNeeded() {
  if (!knowledgeDialog || !state.data?.knowledge) return;
  if (trialStudy?.enabled && !cloudReady) return;
  if (state.data.knowledge.current !== null) pauseExperienceClock();
  knowledgeDialog.render(state.data.knowledge, state.run_id, saveMessage);
}

function startGame() {
  if (started || !participant) return;
  started = true;
  const now = Date.now();
  state.started_at = now;
  state.segment_started_at = now;
  lastProgressAt = now;
  state.feedback = { tone: 'info', title: '第一步：让终端接入网络', text: '选择“接入设备”，再点击早期网络里的终端。' };
  persistSession();
  render();
}

function freshStudentRun() {
  const now = Date.now();
  state = engine.createState(now, `lesson1-${crypto.randomUUID()}`);
  state.recommendationViews = {};
  state.participant = participant ? { ...participant } : null;
  if (participant) record(state, 'student_identified', { ...participant }, now);
  selectedCard = null;
  pausedElapsed = null;
  pauseStartedAt = null;
  clearTimeout(highlightTimer);
  seenRecommendationId = null;
  lastProgressVersion = state.task_version;
  lastProgressAt = now;
  agentUi = { open: false, why: false, bubble: false, highlightIds: [], successDismissed: false, menuOpen: false };
}

async function enterAsStudent(student) {
  participant = student;
  started = false;
  saveMessage = '';
  freshStudentRun();
  restoreSession();
  cloudReady = !trialStudy.enabled;
  if (trialStudy.enabled && started) pauseExperienceClock();
  render();
  if (trialStudy.enabled) {
    cloudReady = await trialStudy.enter(student, engine.snapshot(state, Date.now()));
    if (!cloudReady) { await callbacks.onStudentChange(); return; }
    if (started && state.data.knowledge.current === null && !state.completed) resumeExperienceClock();
    render();
  }
  if (!started) tour.open({ welcome: true });
}

const callbacks = {
  onSelectCard(id) {
    if (!started || state.completed || state.ended_at !== null || knowledgeDialog?.isOpen() || tour?.isOpen() || trialStudy?.busy()) return;
    const targets = engine.legalTargets(state, id);
    const card = LESSON1_CONFIG.cards.find(item => item.id === id);
    selectedCard = id;
    support?.activity({ card: id });
    const hasSuggestedTarget = targets.some(item => !item.disabledReason);
    state.feedback = {
      tone: 'info',
      title: `${card.label}已拿起`,
      text: hasSuggestedTarget
        ? `${card.description}。高亮对象是一个可能目标，也可以试试其他对象，看反馈再判断。`
        : `${card.description}。这张牌也可以先试试，点击场景中的对象查看反馈。`
    };
    render();
  },
  onObject(id) {
    if (!started || state.completed || state.ended_at !== null || knowledgeDialog?.isOpen() || tour?.isOpen() || trialStudy?.busy()) return;
    if (!selectedCard) {
      state.feedback = { tone: 'info', title: '先选一张行动卡', text: '从底部牌桌开始，再点击场景里的设备或线路。' };
      render();
      return;
    }
    const targetId = selectedCard === 'establish-connection' ? (LINK_MACHINE_ALIASES[id] || id) : id;
    if (!support?.allowSubmission(`${selectedCard}:${targetId}`)) return;
    const attemptedCard = selectedCard;
    const previousChallenge = state.data.challengeIndex;
    const result = engine.applyAction(state, selectedCard, targetId, targetId, Date.now());
    if (result.ok) selectedCard = null;
    if (result.ok && state.data.challengeIndex > previousChallenge) {
      activateKnowledgeCheckpoint(previousChallenge);
    }
    // Support events persist immediately. Open the review checkpoint first so
    // a winning action cannot seal the recording before the final review.
    support?.outcome(result.ok, `${attemptedCard}:${targetId}`);
    persistSession();
    render();
  },
  onUndo() {
    if (knowledgeDialog?.isOpen()) return;
    resumeExperienceClock();
    if (engine.undo(state, Date.now())) {
      selectedCard = null;
      lastProgressAt = Date.now();
      agentUi.menuOpen = false;
      persistSession();
      render();
    }
  },
  async onRestart() {
    if (!participant) return;
    persistSession();
    support?.close(); await support?.flush().catch(() => {}); support?.reset();
    await trialStudy.finish('restarted');
    freshStudentRun();
    started = false;
    cloudReady = !trialStudy.enabled;
    render();
    if (trialStudy.enabled) cloudReady = await trialStudy.enter(participant, engine.snapshot(state, Date.now()));
    if (cloudReady) startGame();
    else await callbacks.onStudentChange();
  },
  async onStudentChange() {
    persistSession();
    support?.close(); await support?.flush().catch(() => {}); support?.reset();
    await trialStudy.finish('student_changed');
    started = false;
    cloudReady = false;
    participant = null;
    freshStudentRun();
    tour.close();
    render();
    studentEntry.open();
  },
  onSave() {
    const saved = saveSnapshot('backup');
    state.feedback = saved
      ? { tone: 'info', title: '本机进度已保存', text: '这局的网络状态、匹配进度和观察记录已经保存在当前浏览器。' }
      : { tone: 'warn', title: '进度未能保存', text: saveMessage };
    agentUi.menuOpen = false;
    render();
  },
  async onLoad() {
    let raw;
    try { raw = localStorage.getItem(studentStorageKey(participant, 'backup')); } catch { raw = null; }
    if (!raw) state.feedback = { tone: 'info', title: '还没有本机存档', text: '完成几步行动后再保存一次。' };
    else {
      try {
        const restored = restoreStudentSnapshot(raw);
        await trialStudy.finish('backup_restored');
        pausedElapsed = null; pauseStartedAt = null;
        state = restored; state.recommendationViews ||= {}; state.data.proactiveHintsShown ||= 0;
        selectedCard = null; started = true; agentUi.successDismissed = false;
        lastProgressAt = Date.now(); lastProgressVersion = state.task_version;
        if (state.data.knowledge.current !== null || state.completed) pauseExperienceClock();
        state.feedback = { tone: 'success', title: '牌桌已恢复', text: '继续观察当前网络结构。' };
        persistSession();
        if (trialStudy.enabled) {
          pauseExperienceClock(); cloudReady = false;
          cloudReady = await trialStudy.enter(participant, engine.snapshot(state, Date.now()));
          if (cloudReady && state.data.knowledge.current === null && !state.completed) resumeExperienceClock();
          if (!cloudReady) { await callbacks.onStudentChange(); return; }
        }
      }
      catch { state.feedback = { tone: 'warn', title: '存档无法使用', text: '当前课程版本与本机存档不匹配。' }; }
    }
    agentUi.menuOpen = false;
    render();
  },
  onExport() {
    const now = Date.now();
    syncPausedClock(now);
    const url = URL.createObjectURL(new Blob([JSON.stringify(engine.snapshot(state, now), null, 2)], { type: 'application/json' }));
    const link = document.createElement('a');
    link.href = url; link.download = `${participant.class_id}-${state.run_id}.json`;
    link.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
    agentUi.menuOpen = false;
    render();
  },
  onMenu() { agentUi.menuOpen = !agentUi.menuOpen; render(); },
  onTour() {
    agentUi.menuOpen = false;
    pauseExperienceClock();
    tour?.open({ welcome: false });
    render();
  },
  onKnowledgeSelect(id) {
    support?.activity({ concept: id });
    if (state.data.knowledge.current === null) return;
    if (!selectKnowledgeConcept(state.data.knowledge, id)) return;
    state.data.revision++;
    persistSession();
    render();
  },
  onKnowledgePair(id) {
    if (!support?.allowSubmission(`pair:${state.data.knowledge.current}:${id}`)) return { ok: false };
    const result = attemptKnowledgePair(state.data.knowledge, id);
    if (!result.ok) return result;
    support?.outcome(result.correct, `${result.conceptId}:${result.explanationId}`, true);
    recordKnowledgeEvents(result.events);
    state.data.revision++;
    persistSession();
    render();
    return result;
  },
  onKnowledgeContinue(reason) {
    const result = dismissKnowledge(state.data.knowledge, reason);
    if (!result.ok) return;
    recordKnowledgeEvents(result.events);
    state.data.revision++;
    resumeExperienceClock();
    if (state.completed) pauseExperienceClock();
    persistSession();
    render();
  },
  onTourFinish() { startGame(); },
  async onEnd() { if (!state.completed) { engine.end(state, Date.now()); state.feedback = { tone: 'info', title: '本局已结束', text: '过程记录已保留，可以重新开始新的观察。' }; } persistSession(); await trialStudy.finish('ended'); render(); },
  onFinish() { agentUi.successDismissed = true; render(); },
  onAgentOpen() {
    if (support?.enabled) { support.manual(); return; }
    agentUi.open = true;
    agentUi.bubble = false;
    if (state.lastRecommendation) state.recommendationViews[state.lastRecommendation.id] = Date.now();
    render();
  },
  onAgentClose() { agentUi.open = false; agentUi.why = false; agentUi.highlightIds = []; render(); },
  onAgentHighlight(rec) {
    agentUi.open = true;
    agentUi.highlightIds = [...(rec?.highlightIds || [])];
    clearTimeout(highlightTimer);
    highlightTimer = setTimeout(() => { agentUi.highlightIds = []; render(); }, 4000);
    render();
  },
  onAgentWhy() { agentUi.why = !agentUi.why; render(); },
  getAgentUi() { return agentUi; }
};

const shell = createVisualGameShell(root, LESSON1_CONFIG, callbacks, {
  selectedCard: () => selectedCard,
  prepareState(current) {
    const elapsedMs = pausedElapsed !== null ? pausedElapsed : started ? elapsed(current, Date.now()) : 0;
    return { ...current, elapsed_ms: elapsedMs, progress: { arrived: current.data.evidence.length } };
  },
  getCardState(card, current) {
    // Every action card stays playable during a challenge. The adapter still
    // validates targets and prerequisites after the student tries an action,
    // so the result teaches through feedback instead of disabling the answer.
    return { unlocked: started && Boolean(participant) && !current.completed && current.ended_at === null, reason: card.rule };
  },
  renderSuccess(layer, current, ui, handlers) {
    layer.hidden = !current.completed || ui.successDismissed || current.data.knowledge.current !== null;
    if (layer.hidden) return;
    layer.innerHTML = '<div class="success-card"><span class="success-stamp">✓ 任务完成</span><h2>你找到了网络创新的三个方向</h2><p>结构要避免单点故障，规则要能够互相理解，连接要有冗余路径。</p><button type="button" class="restart-button">查看成果展板</button></div>';
    layer.querySelector('button').onclick = handlers.onFinish;
  }
});

const scene = createNetworkLessonScene(shell.sceneSlot, LESSON1_CONFIG, { onObject: callbacks.onObject });
const actionSystem = { legalTargets: (current, action) => engine.legalTargets(current, action) };

tour = createLesson1Tour(root, {
  onOpen() { pauseExperienceClock(); },
  onClose() { resumeExperienceClock(); render(); },
  onFinish: callbacks.onTourFinish
});
knowledgeDialog = createKnowledgeDialog(root, {
  onSelect: callbacks.onKnowledgeSelect,
  onPair: callbacks.onKnowledgePair,
  onContinue: callbacks.onKnowledgeContinue,
  onSave: callbacks.onSave
});
studentEntry = createStudentEntry(root, enterAsStudent);
trialStudy = createTrialStudy(root, {
  onPause: pauseExperienceClock,
  onBack: callbacks.onStudentChange,
  async onAssigned(assignment) {
    if (!assignment.experiment) return;
    participant = { ...participant, experiment_version: assignment.experiment.version, experiment_round: assignment.experiment.round, condition: assignment.experiment.condition, scaffold_policy_version: assignment.experiment.policy, data_phase: assignment.experiment.data_phase };
    state.participant = { ...participant };
    record(state, 'experiment_assigned', { ...assignment.experiment });
    await support.bind(assignment);
  },
  onResume() { if (started && !state.completed && state.ended_at === null && state.data.knowledge.current === null && !tour?.isOpen()) resumeExperienceClock(); },
  getSnapshot() { syncPausedClock(); return engine.snapshot(state, Date.now()); }
});
support = createExperimentSupport(root, {
  getState: () => state,
  getAssignment: () => trialStudy.assignment(), renewAssignment: () => trialStudy.renewAssignment(),
  isActive: () => started && state.ended_at === null && (!state.completed || state.data.knowledge.current !== null) && !tour?.isOpen() && !trialStudy?.busy(),
  isSafe: () => !tour?.isOpen() && !trialStudy?.busy() && !studentEntry?.isOpen() && !agentUi.menuOpen,
  emit(type, detail) { syncPausedClock(); record(state, type, detail); persistSession(); },
  save: persistSession
});

function renderStudentIdentity() {
  if (!participant) return;
  const label = `${participant.class_name} · ${participant.student_name}`;
  const kicker = root.querySelector('.mission-kicker');
  kicker.textContent = label;
  kicker.title = label;
  const menu = root.querySelector('.pause-menu');
  const info = document.createElement('p');
  info.className = 'student-menu-identity';
  info.textContent = `当前学生：${label}`;
  menu.prepend(info);
  const change = document.createElement('button');
  change.type = 'button';
  change.dataset.tool = 'student';
  change.textContent = '更换学生';
  change.onclick = callbacks.onStudentChange;
  menu.append(change);
  if (trialStudy.enabled) {
    const upload = document.createElement('button'); upload.type = 'button'; upload.textContent = '上传待传记录';
    upload.onclick = () => { agentUi.menuOpen = false; render(); void trialStudy.uploadPending(participant); };
    menu.append(upload);
  }
}

function render() {
  const now = Date.now();
  if (state.data.knowledge.current !== null || state.completed) pauseExperienceClock();
  if (started && pausedElapsed === null) { engine.tick(state, now); state.elapsed_ms = elapsed(state, now); }
  else if (pausedElapsed !== null) syncPausedClock(now);
  if (state.task_version !== lastProgressVersion) {
    lastProgressVersion = state.task_version;
    lastProgressAt = now;
    state.lastRecommendation = null;
    agentUi.bubble = false;
  }
  if (state.lastRecommendation && state.lastRecommendation.id !== seenRecommendationId) {
    seenRecommendationId = state.lastRecommendation.id;
    agentUi.bubble = true;
  }
  shell.render(state);
  renderStudentIdentity();
  // Keep the experiment just completed behind its review cards, including the
  // final network. The showcase appears only after that checkpoint is closed.
  const reviewIndex = state.data.knowledge.current;
  const sceneState = reviewIndex === null ? state : { ...state, data: { ...state.data, challengeIndex: reviewIndex } };
  scene.render(sceneState, actionSystem, { ...agentUi, selectedCard });
  openKnowledgeIfNeeded();
  if (support?.enabled) { shell.agentSidebar.hidden = true; support.update(); }
}

window.setInterval(() => {
  if (!started || state.completed || state.ended_at !== null || pausedElapsed !== null) return;
  const now = Date.now();
  const proactiveHintsShown = Number(state.data?.proactiveHintsShown || 0);
  const canOfferTutorialHint = state.data?.challengeIndex === 0 && proactiveHintsShown < MAX_PROACTIVE_TUTORIAL_HINTS;
  if (!support?.enabled && canOfferTutorialHint && state.task_version === lastProgressVersion && now - lastProgressAt >= 20000 && !state.lastRecommendation) {
    state.lastRecommendation = recommendLesson1(engine, state, now);
    if (state.lastRecommendation) state.data.proactiveHintsShown = proactiveHintsShown + 1;
    agentUi.bubble = Boolean(state.lastRecommendation);
    render();
    return;
  }
  engine.tick(state, now);
  shell.updateClock(state);
}, 500);

window.addEventListener('keydown', event => {
  if (support?.isOpen() || /^(INPUT|TEXTAREA|SELECT)$/.test(event.target.tagName)) return;
  if (!started || event.repeat || studentEntry?.isOpen() || knowledgeDialog?.isOpen() || tour?.isOpen() || trialStudy?.busy()) return;
  const index = Number(event.key) - 1;
  if (index >= 0 && index < LESSON1_CONFIG.cards.length) callbacks.onSelectCard(LESSON1_CONFIG.cards[index].id);
  if (event.key === 'Escape') { selectedCard = null; render(); }
});

window.addEventListener('pagehide', persistSession);
render();
studentEntry.open();

