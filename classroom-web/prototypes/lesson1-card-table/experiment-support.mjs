import { ExperimentScaffold } from './experiment-scaffold.mjs';

export async function loadExperimentConfig() {
  if (!window.LESSON1_TRIAL_CONFIG?.experimentEnabled) return;
  const response = await fetch('/api/lesson1/trial/config', { cache: 'no-store', signal: AbortSignal.timeout(12000) });
  if (!response.ok) throw Error('实验配置暂时无法读取，请刷新后重试。');
  const config = await response.json();
  if (!config.experiment_enabled) throw Error('双班实验暂未开放，请联系老师。');
  window.LESSON1_TRIAL_CONFIG = Object.freeze({ ...window.LESSON1_TRIAL_CONFIG, experimentVersion: config.experiment_version, experimentRound: config.experiment_round, classes: config.classes });
}

export function lesson1Scope(state) {
  const k = state.data.knowledge;
  if (k.current !== null) return { id: `knowledge:${k.current}`, kind: 'quiz', eligible: k.checkpoints[k.current].status === 'active', objective: '用刚才的观察检验概念和解释之间的关系' };
  const index = state.data.challengeIndex, c = state.data.challenges[index];
  if (!c || state.completed || state.ended_at !== null) return { id: 'network:mesh:retest', eligible: false, objective: '整理观察结果' };
  const step = index === 0 ? (!c.terminalConnected ? 'connect' : !c.connectionEstablished ? 'link' : !c.testedBeforeFailure ? 'test' : !c.centralFailure ? 'fault' : 'retest')
    : index === 1 ? (!c.networkAConnected ? 'connect' : !c.networkBConnected ? 'connect_b' : !c.connectionEstablished ? 'link' : !c.testedBeforeConfig ? 'test' : !c.protocolConfigured ? 'repair' : 'retest')
      : (!c.mainLineConnected ? 'connect' : !c.mainLineEstablished ? 'link' : !c.testedBeforeFailure ? 'test' : !c.mainLineFailed ? 'fault' : !c.backupAdded ? 'repair' : 'retest');
  return { id: `network:${['early', 'protocol', 'mesh'][index]}:${step}`, kind: 'movement', eligible: true,
    objective: ['比较核心设备正常与停止后的通信现象', '比较不同通信规则与统一规则后的结果', '比较主线路故障前后是否还有替代路径'][index] };
}

export function createExperimentSupport(root, { getState, getAssignment, renewAssignment, isActive, isSafe, emit, save } = {}) {
  const enabled = window.LESSON1_TRIAL_CONFIG?.experimentEnabled === true;
  const box = document.createElement('section'); box.className = 'lesson1-ai'; box.setAttribute('aria-label', '小糖学习支持'); box.hidden = true; root.append(box);
  let model = null, identity = null, clientId = null, sequence = 0, queue = [], syncing = null, connected = false;
  let opened = false, invitation = null, reply = '', status = '', question = '', busy = false, controller = null, conversation = null, lastContext = null;
  let renderKey = '', lastTick = performance.now(), unsafeUntil = 0, dragging = false, lastSubmission = null, epoch = 0, confirming = false;
  function log(type, detail = {}) { if (identity) emit(type === 'scaffold_invitation_shown' ? 'scaffold_invitation_reserved' : type, { ...detail, condition: identity.condition, experiment_version: identity.version, experiment_round: identity.round, scaffold_policy_version: 'timing-v2' }); }
  function snapshot() { return { client_id: clientId, next_seq: sequence, queue: structuredClone(queue), round: identity?.round }; }
  function persist(event) {
    if (event.scope_id === 'start') return;
    queue.push({ ...event, ...(event.type === 'decision' ? { scaffold_id: lastContext?.scaffold_id || '' } : {}), seq: ++sequence });
    save();
  }
  async function post(path, body = {}, signal) {
    let assignment = getAssignment();
    if (!assignment || assignment.claims.exp * 1000 < Date.now() + 15000) assignment = await renewAssignment();
    const response = await fetch(path, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ ...body, ticket: assignment.ticket }), signal: signal || AbortSignal.timeout(15000) });
    const result = await response.json();
    if (!response.ok) throw Object.assign(Error('学习支持暂时无法连接，请重试；你也可以继续探索。'), { code: result.code, status: response.status });
    return result;
  }
  async function sync() {
    if (syncing) { await syncing; if (queue.length) return sync(); return; }
    syncing = (async () => {
      while (queue.length) {
        const events = queue.slice(0, 50);
        const result = await post('/api/lesson1/trial/scaffold', { client_id: clientId, events });
        queue = queue.filter(event => event.seq > result.acknowledged);
        if (model) { model.count = Math.max(model.count, result.state.shown); model.cooldown = Math.max(model.cooldown, result.state.cooldown); }
      }
      connected = true; save();
    })().catch(error => { connected = false; throw error; }).finally(() => { syncing = null; });
    return syncing;
  }
  async function bind(assignment) {
    if (!enabled || !assignment.experiment) return;
    reset(); identity = assignment.experiment;
    const pending = getState().experiment_support;
    clientId = pending?.round === identity.round && pending.client_id ? pending.client_id : crypto.randomUUID();
    sequence = pending?.client_id === clientId ? pending.next_seq : 0;
    queue = pending?.client_id === clientId ? pending.queue || [] : [];
    try {
      if (queue.length) await sync();
      const result = await post('/api/lesson1/trial/scaffold', { client_id: clientId });
      sequence = Math.max(sequence, result.acknowledged);
      model = new ExperimentScaffold({ condition: identity.condition, lessonId: identity.round, levelId: 'g7_internet_l01', saved: result.state,
        emit: log, persist, state: () => aiState() });
      connected = true; update();
    } catch { status = '学习支持暂时无法连接，请稍后重新登记或联系老师；游戏可以继续。'; }
    render();
  }
  function reset() {
    epoch++; controller?.abort(); controller = null;
    model = null; identity = null; opened = false; invitation = null; conversation = null; reply = ''; status = ''; busy = false; connected = false; renderKey = ''; box.hidden = true;
    lastTick = performance.now();
  }
  function aiState() {
    const state = getState(), scope = lesson1Scope(state), checkpoint = state.data.knowledge.current;
    return { scope_id: scope.id, current_objective: scope.objective, current_checkpoint: checkpoint === null ? 'network_observation' : 'knowledge_review',
      challenge_index: Math.min(2, state.data.challengeIndex), errors: state.error_count,
      matched_pairs: checkpoint === null ? 0 : state.data.knowledge.checkpoints[checkpoint].matched.length,
      elapsed: state.elapsed_ms / 1000, scaffold_policy_version: 'timing-v2',
      recent_failures: model?.failures.slice(-5) || [], previous_hints: reply ? [reply] : [] };
  }
  function update() {
    if (!model) return;
    const scope = lesson1Scope(getState());
    if (model.scope.id !== scope.id || !scope.eligible) {
      controller?.abort(); epoch++; if (model.support) { model.close(); opened = false; }
      invitation = null; busy = false; reply = ''; status = ''; question = '';
    }
    model.objective = scope.objective; model.setScope(scope);
    if (!model.pending) invitation = null;
    render();
  }
  function render() {
    if (!identity) { box.hidden = true; return; }
    const dialog = root.querySelector('.knowledge-dialog[open]');
    const parent = dialog || root;
    if (box.parentElement !== parent) parent.append(box);
    box.hidden = false;
    const key = JSON.stringify([opened, invitation?.scaffold_id, reply, status, busy, model?.scope.id]);
    if (renderKey === key) return;
    renderKey = key;
    box.innerHTML = '<button class="lesson1-ai-tab" type="button">小糖 · 想一想</button><div class="lesson1-ai-invite" hidden><strong>要一起整理一下思路吗？</strong><p>我可以陪你计划、检查或调整下一步。</p><div><button data-choice="accepted">看看思路</button><button data-choice="rejected">自己尝试</button><button data-choice="dismissed">稍后</button></div></div><section class="lesson1-ai-panel" hidden><div class="lesson1-ai-head"><strong>小糖 · 学习搭子</strong><button data-close aria-label="收起学习支持">×</button></div><p class="lesson1-ai-source">真实 AI · 帮你思考与验证</p><p class="lesson1-ai-status" role="status"></p><p class="lesson1-ai-reply"></p><form><label>你想一起想一想什么？<input maxlength="300" placeholder="例如：怎样检查我的想法？"></label><button type="submit">询问小糖</button></form></section>';
    box.querySelector('.lesson1-ai-tab').onclick = manual;
    box.querySelector('.lesson1-ai-invite').hidden = !invitation || opened;
    box.querySelector('.lesson1-ai-panel').hidden = !opened;
    box.querySelector('.lesson1-ai-status').textContent = status;
    box.querySelector('.lesson1-ai-reply').textContent = reply;
    box.querySelector('input').value = question;
    box.querySelector('input').oninput = event => { question = event.target.value; };
    box.querySelector('form button').disabled = busy;
    box.querySelector('form').onsubmit = event => { event.preventDefault(); if (!model) manual(); else void ask(question || '请陪我检查当前的想法，不要告诉我答案。'); };
    box.querySelector('[data-close]').onclick = close;
    for (const button of box.querySelectorAll('[data-choice]')) button.onclick = () => {
      lastContext = { ...model.pending }; const choice = button.dataset.choice;
      model.decide(choice); invitation = null;
      if (choice === 'accepted') { opened = true; void ask('请帮我整理当前的观察和下一步验证思路，不要直接告诉我解法。'); }
      else { void sync().catch(() => {}); render(); }
    };
  }
  function close() {
    controller?.abort(); epoch++; busy = false; opened = false;
    if (model?.support) model.close();
    void sync().catch(() => {}); render();
  }
  function manual() {
    if (!model) { opened = true; render(); const assignment = getAssignment(); if (assignment && !busy) { busy = true; void bind(assignment).then(() => { busy = false; if (model) manual(); else { opened = true; render(); } }); } return; }
    if (opened) return;
    invitation = null; opened = true; lastContext = model.open();
    void ask('我想先想清楚当前目标，并检查我的想法，请给一个观察问题。');
  }
  async function ask(message) {
    if (busy || !model?.support) return;
    controller?.abort(); controller = new AbortController();
    const localEpoch = ++epoch, scopeId = model.scope.id;
    busy = true; reply = ''; status = '小糖正在思考…'; render();
    const deadline = setTimeout(() => controller?.abort(), 65000);
    try {
      const context = model.support;
      persist({ type: 'request', scope_id: scopeId, scaffold_id: context.scaffold_id, trigger_reason: context.trigger_reason });
      await sync();
      log('ai_request_started', { scope_id: scopeId, scaffold_id: context.scaffold_id, trigger: context.trigger_reason });
      const body = { level_id: 'g7_internet_l01', trigger: context.trigger_reason, scaffold_id: context.scaffold_id, state: aiState(), message, session: conversation };
      let result = await post('/api/coze/chat', body, controller.signal);
      while (result.status === 'pending') {
        await new Promise(resolve => setTimeout(resolve, 800));
        result = await post('/api/coze/chat/status', { level_id: body.level_id, poll: result.poll }, controller.signal);
      }
      if (epoch !== localEpoch || model.scope.id !== scopeId || !opened || !isActive()) { log('ai_reply_discarded', { scope_id: scopeId }); return; }
      conversation = result.session; reply = result.reply; status = '可以先观察，再用自己的操作验证。';
      model.hintShown(); log('ai_reply_shown', { scope_id: scopeId, scaffold_id: context.scaffold_id, reply });
      await sync();
    } catch (error) {
      log('ai_request_failed', { scope_id: scopeId, code: error.code || error.name || 'request_failed' });
      if (epoch === localEpoch) status = '本次未收到 AI 回复。可以重试，也可以继续探索。';
    } finally { clearTimeout(deadline); if (epoch === localEpoch) { busy = false; render(); } save(); }
  }
  function activity(detail = {}) { model?.activity(detail); }
  function allowSubmission(key) {
    if (!model) return true;
    const now = performance.now();
    if (lastSubmission?.key === key && now - lastSubmission.at < 650) return false;
    lastSubmission = { key, at: now }; return true;
  }
  function outcome(correct, strategy, quiz = false) {
    if (!model) return;
    model.activity({ strategy });
    if (quiz) model.quizResult(correct, { strategy });
    else if (correct) model.success({ strategy });
    else model.failure('invalid_action', { strategy });
    if (!correct) unsafeUntil = performance.now() + 1200;
    invitation = null; void sync().catch(() => {});
  }
  root.addEventListener('pointerdown', () => { dragging = true; activity(); });
  window.addEventListener('pointerup', () => { dragging = false; });
  window.addEventListener('pointercancel', () => { dragging = false; });
  root.addEventListener('keydown', () => activity());
  box.addEventListener('keydown', event => { if (opened && event.key === 'Escape') { event.preventDefault(); event.stopPropagation(); close(); } });
  document.addEventListener('visibilitychange', () => { lastTick = performance.now(); dragging = false; });
  setInterval(async () => {
    const now = performance.now(), dt = Math.min(1, (now - lastTick) / 1000); lastTick = now;
    if (!model || !isActive() || document.hidden) return;
    update();
    const canShow = connected && !dragging && now >= unsafeUntil && isSafe() && model.scope.eligible;
    const ready = model.tick(dt, canShow, true);
    if (ready && !invitation && !opened && !confirming) {
      confirming = true;
      const reserved = { ...model.pending }, boundModel = model;
      let displayed = false;
      try {
        await sync();
        if (model === boundModel && model.pending?.scaffold_id === reserved.scaffold_id && isSafe() && !document.hidden) {
          invitation = reserved; lastContext = invitation; render();
          await new Promise(resolve => requestAnimationFrame(resolve));
          displayed = !document.hidden && (invitation?.scaffold_id === reserved.scaffold_id || model.support?.scaffold_id === reserved.scaffold_id);
          if (displayed) {
            persist({ type: 'displayed', scope_id: reserved.scope_id, scaffold_id: reserved.scaffold_id });
            emit('scaffold_invitation_shown', { ...reserved, condition: identity.condition, experiment_version: identity.version, experiment_round: identity.round, scaffold_policy_version: 'timing-v2' });
          }
        }
      } catch { status = '学习支持暂时无法连接'; }
      finally {
        if (!displayed && model === boundModel) {
          persist({ type: 'unshown', scope_id: reserved.scope_id, scaffold_id: reserved.scaffold_id });
          model.count = Math.max(0, model.count - 1); model.cancel('display_window_changed'); invitation = null; render();
        }
        confirming = false;
      }
    }
    if (queue.length && !syncing) void sync().catch(() => {});
  }, 500);
  return { enabled, bind, reset, update, activity, allowSubmission, outcome, snapshot, manual, close, flush: sync, isOpen: () => opened };
}
