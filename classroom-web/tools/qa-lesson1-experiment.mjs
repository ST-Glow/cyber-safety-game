import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
process.env.LESSON1_EXPERIMENT_ENABLED = 'true'; process.env.LESSON1_EXPERIMENT_ROUND_ID = 'qa-two-class';
const build = JSON.parse(await fs.readFile(path.join(root, 'tmp/lesson1-cloud/build.json'), 'utf8'));
const require = createRequire(path.join(build.directory, 'package.json'));
const { createApp } = require('./src/create-app'), { createSqliteStore } = require('./src/classroom/store');
const { Lesson1TrialService } = require('./src/lesson1-trial'), { createCloudAdapter } = require('./src/cloud');
const { chromium } = require('C:/Users/Lenovo/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const browserName = process.argv[2] || 'chrome', out = path.join(root, 'tmp/lesson1-experiment', browserName + '-' + Date.now());
await fs.mkdir(out, { recursive: true });
const store = await createSqliteStore(':memory:'), secret = 'qa-two-class-secret-at-least-32-characters', calls = [], errors = [];
const service = new Lesson1TrialService(store, secret);
const config = { linkSecret: secret, allowedOrigins: [], aiPromptsConfigured: false };
const app = createApp({ config, cloud: createCloudAdapter({ mockRoot: path.join(out, 'objects') }), lesson1TrialService: service,
  classroomService: { async me() { throw Object.assign(Error('login_required'), { status: 401, code: 'login_required' }); } },
  coze: { configured: true, async startChat(input) { calls.push(input); return { conversationId: 'qa-conversation', chatId: 'qa-chat' }; }, async getChatResult() { return { status: 'completed', conversationId: 'qa-conversation', reply: '先明确你想验证的现象，再比较两次观察记录。你准备怎样检查自己的想法？' }; } } });
const server = app.listen(0, '127.0.0.1'); await new Promise(resolve => server.once('listening', resolve));
const base = `http://127.0.0.1:${server.address().port}`; config.allowedOrigins.push(base);
const browser = await chromium.launch({ headless: true, executablePath: browserName === 'edge' ? 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe' : 'C:/Program Files/Google/Chrome/Application/chrome.exe' });
let checks = 0;
async function context(viewport = { width: 1366, height: 768 }) {
  const ctx = await browser.newContext({ viewport });
  await ctx.addInitScript(() => {
    let handle;
    navigator.mediaDevices.setCaptureHandleConfig = value => { handle = value.handle; };
    navigator.mediaDevices.getDisplayMedia = async () => {
      const canvas = document.createElement('canvas'); canvas.width = 640; canvas.height = 360; document.body.append(canvas); canvas.style.display = 'none';
      const draw = canvas.getContext('2d'); let count = 0;
      const paint = () => { draw.fillStyle = count++ % 2 ? '#416c61' : '#f0cf88'; draw.fillRect(0, 0, 640, 360); draw.fillStyle = '#fff'; draw.font = '24px sans-serif'; draw.fillText('Synthetic QA ' + count, 30, 60); };
      paint(); const stream = canvas.captureStream(15), track = stream.getVideoTracks()[0], timer = setInterval(paint, 70), settings = track.getSettings.bind(track);
      track.getSettings = () => ({ ...settings(), displaySurface: 'browser' }); track.getCaptureHandle = () => ({ handle }); track.addEventListener('ended', () => clearInterval(timer));
      return stream;
    };
  });
  return ctx;
}
async function enter(ctx, classroom, name) {
  const page = await ctx.newPage(); page.on('pageerror', error => errors.push(error.message));
  await page.goto(base + '/classroom/lesson1/');
  assert.equal(await page.locator('#student-class option').count(), 3); checks++;
  await page.getByLabel('你在哪个班级？').selectOption(classroom); await page.getByLabel('你的姓名', { exact: true }).fill(name);
  await page.getByRole('button', { name: '进入实验台' }).click(); await page.getByRole('button', { name: '同意并选择游戏标签页' }).click();
  await page.getByRole('button', { name: '直接开始' }).click(); return page;
}
async function aiReply(page) { await page.locator('.lesson1-ai-reply').filter({ hasText: '先明确' }).waitFor({ timeout: 20000 }); checks++; }
async function closeAi(page) { await page.getByRole('button', { name: '收起学习支持' }).click(); }
try {
  const a = await context(), pageA = await enter(a, 'g7-01', '主动技术验收生');
  await pageA.locator('.lesson1-ai-invite:not([hidden])').waitFor({ timeout: 23000 }); checks++;
  await pageA.screenshot({ path: path.join(out, 'proactive-invitation.png') });
  await pageA.getByRole('button', { name: '看看思路', exact: true }).click(); await aiReply(pageA); await closeAi(pageA);
  await a.route('**/api/coze/chat', route => route.fulfill({ status: 503, contentType: 'application/json', body: '{"code":"qa_ai_unavailable"}' }));
  await pageA.getByRole('button', { name: '小糖 · 想一想', exact: true }).click();
  await pageA.locator('.lesson1-ai-status').filter({ hasText: '本次未收到' }).waitFor();
  assert.equal(await pageA.locator('.lesson1-ai-reply').innerText(), ''); checks++;
  await a.unroute('**/api/coze/chat'); await pageA.getByRole('button', { name: '询问小糖', exact: true }).click(); await aiReply(pageA); await closeAi(pageA);
  const act = async (card, target) => { await pageA.locator(`[data-card-id="${card}"]`).click(); await pageA.locator(`[data-target-id="${target}"]`).click(); };
  const createdChat = pageA.waitForResponse(response => response.url().endsWith('/api/coze/chat'));
  await pageA.getByRole('button', { name: '小糖 · 想一想', exact: true }).click(); await createdChat;
  await act('connect-device', 'early-terminal'); await pageA.waitForTimeout(1100);
  assert.equal(await pageA.locator('.lesson1-ai-panel:not([hidden])').count(), 0, 'scope change closes pending help'); checks++;
  await act('establish-connection', 'early-central-link');
  await act('run-test', 'early-communication-test'); await act('run-test', 'early-central-fault'); await act('run-test', 'early-communication-test');
  await pageA.locator('.knowledge-dialog[open]').waitFor();
  await pageA.getByRole('button', { name: '小糖 · 想一想', exact: true }).click(); await aiReply(pageA);
  assert.equal(await pageA.locator('.knowledge-dialog .lesson1-ai-panel:not([hidden])').count(), 1); checks++;
  await pageA.screenshot({ path: path.join(out, 'matching-ai.png') }); await closeAi(pageA);
  assert.ok(calls.every(call => !call.message.includes('主动技术验收生') && !call.message.includes('proactive') && !call.message.includes('reactive'))); checks++;
  const match = async ids => {
    for (const id of ids) { await pageA.locator(`[data-knowledge-card="concept:${id}"]`).click(); await pageA.locator(`[data-knowledge-card="explanation:${id}"]`).click(); }
    await pageA.locator('.knowledge-dialog').waitFor({ state: 'hidden', timeout: 6000 });
  };
  await match(['single-point', 'central-structure']);
  await act('connect-device', 'protocol-network-a'); await act('connect-device', 'protocol-network-b');
  await act('establish-connection', 'protocol-bridge'); await act('run-test', 'protocol-bridge'); await act('configure-protocol', 'protocol-bridge'); await act('run-test', 'protocol-bridge');
  await match(['communication-protocol', 'standardization']);
  await act('connect-device', 'mesh-node'); await act('establish-connection', 'mesh-main-line'); await act('run-test', 'mesh-main-line');
  await act('run-test', 'mesh-fault-switch'); await act('add-backup-route', 'mesh-backup-line'); await act('run-test', 'mesh-backup-line');
  await pageA.locator('.knowledge-dialog[open]').waitFor();
  await pageA.getByRole('button', { name: '小糖 · 想一想', exact: true }).click(); await aiReply(pageA); await closeAi(pageA);
  await match(['backup-path', 'redundancy']);
  await pageA.getByRole('button', { name: '上传记录与录像', exact: true }).click();
  await pageA.getByText('上传完成，云端已核验记录和录像。', { exact: true }).waitFor(); checks++;
  await pageA.getByRole('button', { name: '继续', exact: true }).click();
  assert.ok(await pageA.locator('.success-layer').isVisible()); checks++;
  await pageA.screenshot({ path: path.join(out, 'full-lesson-complete.png') });
  await a.close();
  const b = await context({ width: 1024, height: 768 }), pageB = await enter(b, 'g7-06', '反应技术验收生');
  assert.equal(await pageB.locator('.lesson1-ai-invite:not([hidden])').count(), 0); checks++;
  await pageB.locator('[data-card-id="configure-protocol"]').click(); await pageB.locator('[data-target-id="early-terminal"]').click();
  await pageB.waitForTimeout(800);
  assert.equal(await pageB.locator('.lesson1-ai-invite:not([hidden])').count(), 0); checks++;
  await pageB.locator('[data-target-id="early-terminal"]').click();
  await pageB.locator('.lesson1-ai-invite:not([hidden])').waitFor({ timeout: 6000 }); checks++;
  await pageB.getByRole('button', { name: '看看思路', exact: true }).click(); await aiReply(pageB);
  await pageB.screenshot({ path: path.join(out, 'reactive-ai-1024.png') }); await closeAi(pageB);
  await b.close();
  const c = await context({ width: 1024, height: 768 }), probe = await c.newPage(); probe.on('pageerror', error => errors.push(error.message));
  let failedVideo = false;
  await c.route(/\/api\/mock-upload\/[^/]+\/recording\.(mp4|webm)$/, route => { if (!failedVideo) { failedVideo = true; return route.abort(); } return route.continue(); });
  await probe.goto(base + '/classroom/lesson1-check/');
  assert.equal(await probe.locator('[name="class_id"] option').count(), 4);
  assert.equal(await probe.locator('[name="station"]').count(), 0); checks++;
  await probe.locator('[name="class_id"]').selectOption('g7-other'); await probe.getByLabel('姓名', { exact: true }).fill('设备技术验收生');
  await probe.screenshot({ path: path.join(out, 'device-entry-1024.png') });
  await probe.getByRole('button', { name: '开始互动试玩' }).click(); await probe.getByRole('button', { name: '同意并选择游戏标签页' }).click();
  await probe.waitForTimeout(1200); await probe.locator('[data-card-id="run-test"]').click(); await probe.locator('[data-target-id="early-terminal"]').click();
  await probe.screenshot({ path: path.join(out, 'device-running.png') });
  await probe.locator('.trial-message').filter({ hasText: /网络暂时不可用|本次操作未完成/ }).waitFor({ timeout: 50000 });
  assert.equal(await probe.getByRole('heading', { name: '试玩完成，记录已保存', exact: true }).count(), 0); checks++;
  await probe.getByRole('button', { name: '上传记录与录像', exact: true }).click();
  await probe.getByRole('heading', { name: '试玩完成，记录已保存', exact: true }).waitFor({ timeout: 25000 }); checks++;
  assert.equal(await probe.locator('#check-stages li').filter({ hasText: '：完成' }).count(), 5); checks++;
  await probe.screenshot({ path: path.join(out, 'device-confirmed.png') });
  for (const size of [{ width: 1366, height: 768 }, { width: 1024, height: 768 }]) {
    await probe.setViewportSize(size);
    assert.ok(await probe.evaluate(() => document.documentElement.scrollWidth <= innerWidth && document.documentElement.scrollHeight <= innerHeight)); checks++;
  }
  const files = [];
  async function walk(dir) { for (const entry of await fs.readdir(dir, { withFileTypes: true })) { const file = path.join(dir, entry.name); if (entry.isDirectory()) await walk(file); else files.push(file); } }
  await walk(path.join(out, 'objects'));
  const manifests = await Promise.all(files.filter(file => file.endsWith('manifest.json')).map(async file => ({ file, value: JSON.parse(await fs.readFile(file, 'utf8')) })));
  const check = manifests.find(item => item.value.trial?.activity_type === 'device_check_30s');
  assert.ok(check); assert.equal(check.value.condition, 'passive'); assert.equal(check.value.class_id, 'g7-other'); assert.equal(check.value.trial.student_name, '设备技术验收生'); assert.ok(check.value.files.recording.bytes > 1000); checks++;
  const summary = JSON.parse(await fs.readFile(path.join(path.dirname(check.file), 'summary.json'), 'utf8'));
  assert.ok(summary.snapshot.state.device_check.elapsed_ms >= 29000); assert.ok(summary.snapshot.state.device_check.metrics.samples > 30); checks++;
  const lesson = manifests.find(item => item.value.trial?.experiment_version === 'lesson1-two-class-v1');
  assert.equal(lesson.value.condition, 'proactive');
  const lessonSummary = JSON.parse(await fs.readFile(path.join(path.dirname(lesson.file), 'summary.json'), 'utf8'));
  assert.equal(lessonSummary.snapshot.state.completed, true); assert.equal(lessonSummary.snapshot.state.data.knowledge.current, null); checks++;
  const legacy = await c.newPage(); await legacy.goto(base + '/classroom/lesson1/legacy-upload.html');
  assert.equal(await legacy.locator('#student-class option').count(), 17); checks++;
  assert.deepEqual(errors, []);
  await c.close();
  await fs.writeFile(path.join(out, 'report.json'), JSON.stringify({ passed: true, checks, browser: browserName, calls: calls.length, errors, archiveSha256: build.archiveSha256, scope: 'Isolated mock OSS/AI; real synthetic MediaRecorder video, real 30-second timer; no desktop capture.' }, null, 2));
  console.log(JSON.stringify({ passed: true, checks, out }));
} catch (error) { await fs.writeFile(path.join(out, 'failure.json'), JSON.stringify({ error: error.message, stack: error.stack, errors }, null, 2)); console.error(error); process.exitCode = 1; }
finally { await browser.close(); await new Promise(resolve => server.close(resolve)); store.close(); }
