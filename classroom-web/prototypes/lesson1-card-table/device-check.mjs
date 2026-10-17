import { createCardTaskEngine } from './core.mjs';
import { lesson1Adapter } from './adapters/lesson1.mjs';
import { createVisualGameShell } from './visual-game-shell.mjs';
import { createNetworkLessonScene } from './network-lesson-scene.mjs';
import { createTrialStudy } from './trial-study.mjs';
import LESSON from './config.mjs';

const root = document.querySelector('#app'), entry = document.querySelector('#check-entry'), result = document.querySelector('#check-result');
const engine = createCardTaskEngine(lesson1Adapter), state = engine.createState(Date.now(), `lesson1-${crypto.randomUUID()}`);
state.device_check = { version: 'device-check-30s-v2', activity_type: 'device_check_30s', duration_ms: 30000, invalid_reasons: [], stages: {} };
const CHECK_CLASSES = { 'g7-01': '初一1班', 'g7-06': '初一6班', 'g7-other': '其他班级' };
let selected = null, running = false, start = 0, frames = [], frameStart = null, longTasks = [], clicks = [], phase = -1, tick = null, uploaded = false;
const config = { ...LESSON, missionTitle: '30秒 · 互动试玩', objective: '点击卡牌和场景，保持当前标签页，完成这段小游玩。', timeLimitMs: 30000, progressLabel: '点击', progressSuffix: ' 次' };
const log = (type, detail = {}) => { state.events.push({ seq: state.next_event++, at: Date.now(), type, detail, elapsed_ms: running ? performance.now() - start : state.device_check.elapsed_ms || 0 }); };
function render() { shell.render({ ...state, elapsed_ms: running ? performance.now() - start : state.device_check.elapsed_ms || 0, progress: { arrived: clicks.length } }); scene.render(state, { legalTargets: () => [] }, { selectedCard: selected });
  const heading = scene.root.querySelector('.lesson1-scene-title'); heading.querySelector('span').textContent = `30秒试玩 · 场景 ${Math.min(3, state.data.challengeIndex + 1)}/3`;
  heading.querySelector('strong').textContent = '试着点击不同卡牌和场景对象'; heading.querySelector('small').textContent = '场景会自动轮换；请保持此游玩标签页在前台。';
  for (let i = 0; i < 3; i++) { const packet = document.createElement('img'); packet.src = 'assets/packet-chip-v1.png'; packet.alt = ''; packet.className = 'check-packet'; packet.style.animationDelay = `${-i * 1.3}s`; scene.root.querySelector('.map-stage').append(packet); }
}
const shell = createVisualGameShell(root, config, {
  onSelectCard(id) { if (!running) return; const at = performance.now(); selected = id; clicked('card', id, at); render(); },
  getAgentUi: () => ({})
}, { selectedCard: () => selected, getCardState: () => ({ unlocked: running }) });
const scene = createNetworkLessonScene(shell.sceneSlot, config, { onObject(id) { if (!running) return; const at = performance.now(); clicked('object', id, at); state.feedback = { tone: 'success', title: '点击已收到', text: '继续试试其他卡牌或对象，试玩结束后会保存记录。' }; render(); } });
const live = document.createElement('div'); live.className = 'check-live'; live.textContent = '准备开始'; root.append(live);
function clicked(kind, id, at) { requestAnimationFrame(() => { const reaction = performance.now() - at; clicks.push(reaction); log('device_click', { kind, id, next_frame_ms: reaction }); }); }
function snapshot() { return { schema_version: 1, state: structuredClone(state) }; }
function metrics() {
  const sorted = [...frames].sort((a, b) => a - b), total = frames.reduce((a, b) => a + b, 0);
  return { samples: frames.length, average_fps: total ? Math.round(frames.length * 10000 / total) / 10 : null,
    p95_frame_ms: sorted.length ? Math.round(sorted[Math.floor((sorted.length - 1) * .95)] * 10) / 10 : null,
    frames_over_50ms: frames.filter(ms => ms > 50).length, long_task_count: longTasks.length,
    clicks: clicks.length, click_p95_ms: clicks.length ? [...clicks].sort((a, b) => a - b)[Math.floor((clicks.length - 1) * .95)] : null,
    viewport: { width: innerWidth, height: innerHeight, pixel_ratio: devicePixelRatio }, browser: /Edg\//.test(navigator.userAgent) ? 'Edge' : /Chrome\//.test(navigator.userAgent) ? 'Chrome' : 'other' };
}
function showResult() {
  const data = state.device_check, measured = data.metrics || metrics(), invalid = data.invalid_reasons.length || measured.samples < 30 || data.elapsed_ms < 29000;
  document.querySelector('#result-title').textContent = invalid ? '本次试玩未完成' : uploaded ? '试玩完成，记录已保存' : '30秒完成，正在保存记录';
  document.querySelector('#result-copy').textContent = invalid ? '试玩期间离开页面、提前停止录制或画面样本不足，请保持游玩标签页在前台再玩一次。' : `${state.participant.class_name} · ${state.participant.student_name}：这段游玩${measured.average_fps >= 45 ? '运行很流畅' : measured.average_fps >= 25 ? '有一些卡顿，可以再玩一遍' : '运行较慢，可以换一台电脑试试'}。${measured.clicks ? '' : '本次还没有点击记录，可以再玩一遍。'}`;
  const grid = document.querySelector('#check-metrics'); grid.replaceChildren();
  for (const [name, value] of [['平均画面帧率', measured.average_fps === null ? '无样本' : measured.average_fps + ' FPS'], ['95%帧间隔', (measured.p95_frame_ms ?? '—') + ' ms'], ['慢帧（超过50ms）', measured.frames_over_50ms], ['点击次数', measured.clicks]]) { const cell = document.createElement('div'), label = document.createElement('dt'), number = document.createElement('dd'); label.textContent = name; number.textContent = value; cell.append(label, number); grid.append(cell); }
  const stages = document.querySelector('#check-stages'); stages.replaceChildren();
  for (const [key, name] of [['playable', '录像可播放'], ['events', '互动记录上传'], ['summary', '游玩结果上传'], ['recording', '录像上传'], ['verified', '记录已保存']]) { const item = document.createElement('li'); item.textContent = `${data.stages[key] ? '✓' : '…'} ${name}${data.stages[key] ? '：完成' : '：等待或待重试'}`; stages.append(item); }
  document.querySelector('#retry-upload').hidden = uploaded;
  if (!result.open) result.showModal();
}
const study = createTrialStudy(root, { activityType: 'device_check_30s', autoUpload: true, getSnapshot: snapshot,
  onPause() {}, onResume() {}, onBack() { if (!entry.open) entry.showModal(); },
  onProgress(stage) { state.device_check.stages[stage] = true; },
  onUploaded(confirmation) { uploaded = true; state.device_check.confirmation = confirmation; showResult(); },
  onInterrupted() { if (running) { state.device_check.invalid_reasons.push('sharing_stopped'); seal(); showResult(); } }
});
function seal() { running = false; clearInterval(tick); state.device_check.elapsed_ms = performance.now() - start; state.device_check.metrics = metrics(); state.ended_at = Date.now(); log('device_check_finished', state.device_check.metrics); live.textContent = '30秒试玩已结束'; }
async function finish() { if (!running) return; seal(); await study.finish('device_check_completed'); showResult(); }
function frame(now) { if (!running) return; if (!document.hidden && frameStart !== null) frames.push(now - frameStart); frameStart = now; requestAnimationFrame(frame); }
try { new PerformanceObserver(list => { if (running) longTasks.push(...list.getEntries().map(item => item.duration)); }).observe({ type: 'longtask', buffered: false }); } catch { /* Frame intervals remain available. */ }
document.addEventListener('visibilitychange', () => { if (running && document.hidden) { state.device_check.invalid_reasons.push('tab_hidden'); log('device_tab_hidden'); } frameStart = null; });
const assets = ['campus-board-bg-v1.png', 'node-device-v1.png', 'packet-chip-v1.png', 'announcement-screen-v1.png', 'lesson1-card-frame-warm-v1.png', 'lesson1-action-icons-warm-v1.png'];
const ready = Promise.all(assets.map(name => new Promise((resolve, reject) => { const image = new Image(); image.onload = resolve; image.onerror = reject; image.src = 'assets/' + name; }))).catch(() => false);
entry.querySelector('form').onsubmit = async event => {
  event.preventDefault(); const form = event.currentTarget, error = form.querySelector('.check-error'); error.textContent = '';
  const name = form.elements.student_name.value.normalize('NFC').trim().replace(/\s+/gu, ' '), classId = form.elements.class_id.value;
  if (!Object.hasOwn(CHECK_CLASSES, classId) || !name || name.length > 32 || !/\p{L}/u.test(name) || /[<>\p{Cc}\p{Cf}]/u.test(name)) { error.textContent = '请选择班级，并填写1—32字的姓名，请勿只填空格或数字。'; return; }
  if (await ready === false) { error.textContent = '校园素材未能加载，请恢复网络并刷新后重试。'; return; }
  state.participant = { class_id: classId, class_name: CHECK_CLASSES[classId], student_name: name, identity_source: 'device_check', study_version: 'lesson1-student-trial-v1' };
  entry.close();
  if (!await study.enter(state.participant, snapshot())) { entry.showModal(); return; }
  start = performance.now(); running = true; frameStart = null; log('device_check_started'); requestAnimationFrame(frame);
  tick = setInterval(() => {
    const elapsed = performance.now() - start; live.textContent = `● 试玩进行中 · 还剩 ${Math.max(0, Math.ceil((30000 - elapsed) / 1000))} 秒`;
    if (elapsed >= 30000) { void finish(); return; }
    const next = Math.min(2, Math.floor(elapsed / 10000));
    if (next !== phase) { phase = next; state.data.challengeIndex = phase; const c = state.data.challenges[phase]; Object.assign(c, { terminalConnected: true, connectionEstablished: true, testedBeforeFailure: true, networkAConnected: true, networkBConnected: true, protocolConfigured: true, testedAfterConfig: true, mainLineConnected: true, mainLineEstablished: true, backupAdded: true, testedAfterBackup: true }); render(); log('device_scene', { phase }); }
    shell.updateClock({ ...state, elapsed_ms: elapsed, progress: { arrived: clicks.length } });
    study.observe(snapshot());
  }, 200);
};
document.querySelector('#retry-upload').onclick = async () => { result.close(); await study.uploadPending(state.participant); showResult(); };
document.querySelector('#download-report').onclick = () => { const url = URL.createObjectURL(new Blob([JSON.stringify(snapshot(), null, 2)], { type: 'application/json' })); const link = document.createElement('a'); link.href = url; link.download = `device-check-${state.run_id}.json`; link.click(); setTimeout(() => URL.revokeObjectURL(url), 1000); };
document.querySelector('#repeat-check').onclick = () => location.reload();
entry.addEventListener('cancel', event => event.preventDefault()); result.addEventListener('cancel', event => event.preventDefault());
render(); entry.showModal();
