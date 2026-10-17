// Explicit live deployment check. Uses synthetic QA video and no real student data.
// node --use-env-proxy classroom-web/tools/qa-lesson1-live-cloud.mjs --upload
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const require = createRequire(path.join(root, 'cloud/aliyun-upload-api/package.json'));
const OSS = require('ali-oss');
const origin = 'https://tangguoketang.cn';
const report = { startedAt: new Date().toISOString(), origin, passed: false, checks: [],
  scope: 'Live HTTPS/OSS check using synthetic QA video; does not verify the browser screen-sharing picker.' };
let phase = 'static';
const check = (condition, name) => { assert.ok(condition, name); report.checks.push(name); };
const sha = data => crypto.createHash('sha256').update(data).digest('hex');
async function read(url, options = {}) {
  const attempts = !options.method || ['GET', 'HEAD'].includes(options.method) ? 3 : 1;
  for (let attempt = 0; attempt < attempts; attempt++) {
    try { return await fetch(url, { ...options, signal: AbortSignal.timeout(60000) }); }
    catch (error) { if (attempt + 1 === attempts) throw error; }
  }
}

async function post(endpoint, body, expected = 200) {
  const response = await read(origin + endpoint, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
  const value = await response.json();
  if (response.status !== expected) {
    const code = /^[\w.-]{1,96}$/.test(value.code || '') ? value.code : 'unexpected_response';
    throw Object.assign(Error(code), { safeCode: code, httpStatus: response.status, diagnosticId: value.diagnostic_id });
  }
  return value;
}

try {
  const build = JSON.parse(await fs.readFile(path.join(root, 'tmp/lesson1-cloud/build.json'), 'utf8'));
  report.archiveSha256 = build.archiveSha256;
  const entry = await read(origin + '/', { redirect: 'manual' });
  check(entry.status === 302 && entry.headers.get('location') === '/classroom/lesson1/', 'root routes to lesson 1');
  for (const url of ['/api/health', '/classroom/native/', '/classroom/a/', '/classroom/b/', '/classroom/teacher.html', '/classroom/lesson1-check/']) {
    const response = await read(origin + url);
    check(response.status === 200, `existing endpoint ${url} remains available`);
    await response.arrayBuffer(); // Release the connection before the next check.
  }
  const configuration = await (await read(origin + '/api/lesson1/trial/config')).json();
  check(configuration.experiment_enabled && configuration.classes.map(item => item.class_id).join(',') === 'g7-01,g7-06', 'server exposes exactly the two experimental classes');
  for (const name of ['index.html', 'app.mjs', 'trial-config.js', 'trial-study.mjs', 'device-check.html', 'device-check.mjs', 'assets/aliyun-oss-sdk.min.js', 'assets/lesson1-card-frame-warm-v1.png']) {
    const expected = build.lesson1Files.find(item => item.path === name);
    const response = await read(origin + '/classroom/lesson1/' + name);
    check(response.ok && sha(Buffer.from(await response.arrayBuffer())) === expected.sha256, `published asset matches tested bundle: ${name}`);
    if (name === 'index.html') {
      check(response.headers.get('permissions-policy')?.includes('display-capture=(self)'), 'current-tab capture policy present');
      check(response.headers.get('content-security-policy')?.includes('https://cyber-game.oss-cn-hangzhou.aliyuncs.com'), 'CSP permits only the expected OSS destination');
    }
  }
  if (process.argv.includes('--upload')) {
    phase = 'start_trial';
    const localQa = JSON.parse(await fs.readFile(path.join(root, 'tmp/lesson1-cloud/qa-1792056750279/report.json'), 'utf8'));
    check(localQa.passed && localQa.scope.includes('synthetic'), 'source video is explicitly synthetic QA media');
    const video = await fs.readFile(localQa.video);
    check(video.length === localQa.videoBytes, 'source video matches the locally playable QA artifact');
    const participant = { class_id: 'g7-other', student_name: '部署设备验收（非学生）' };
    const session = { ...participant, run_id: `lesson1-${crypto.randomUUID()}`, segment_id: crypto.randomUUID(),
      client_key: crypto.randomBytes(32).toString('hex'), consent_version: 'lesson1-tab-recording-v1', activity_type: 'device_check_30s' };
    const assignment = await post('/api/lesson1/trial/sessions', session);
    report.uploadId = assignment.claims.upload_id;
    report.segmentId = session.segment_id;
    const again = await post('/api/lesson1/trial/sessions', session);
    check(again.claims.upload_id === report.uploadId, 'session retry keeps the same upload identity');
    await post('/api/lesson1/trial/renew', { ...session, client_key: crypto.randomBytes(32).toString('hex') }, 403);
    report.checks.push('different client key cannot renew this session');
    const body = { ticket: assignment.ticket, recording_extension: 'mp4', recording_available: true };
    await post('/api/upload/credentials', { ...body, recording_available: false }, 400);
    report.checks.push('metadata-only submission is rejected');
    const auth = await post('/api/upload/credentials', body);
    check(auth.mode === 'oss' && auth.bucket === 'cyber-game' && auth.region === 'oss-cn-hangzhou', 'credentials target the existing private OSS bucket');
    const prefix = `studies/lesson1-student-trial-v1/g7-other/passive/${assignment.claims.student_code}/${report.uploadId}/`;
    check(Object.values(auth.objects).every(key => key.startsWith(prefix)), 'all returned objects stay within the lesson 1 session directory');
    report.prefix = prefix;
    const client = new OSS({ bucket: auth.bucket, region: auth.region, accessKeyId: auth.credentials.AccessKeyId,
      accessKeySecret: auth.credentials.AccessKeySecret, stsToken: auth.credentials.SecurityToken, secure: true, authorizationV4: true });
    async function requestObject(method, object, queries = {}, bytes, type) {
      const headers = type ? { 'Content-Type': type } : {};
      const signed = await client.signatureUrlV4(method, 300, { headers, queries }, object);
      const response = await read(signed, { method, headers, ...(bytes ? { body: bytes } : {}) });
      if (!response.ok) {
        const xml = await response.text(), code = xml.match(/<Code>([A-Za-z0-9_.-]+)<\/Code>/)?.[1] || 'oss_request_failed';
        throw Object.assign(Error(code), { safeCode: code, httpStatus: response.status, diagnosticId: xml.match(/<RequestId>([A-Za-z0-9-]+)<\/RequestId>/)?.[1] });
      }
      return response;
    }
    phase = 'upload_records';
    const event = { type: 'deployment_technical_check', synthetic: true, time: new Date().toISOString() };
    const events = Buffer.from(JSON.stringify(event) + '\n');
    const summary = Buffer.from(JSON.stringify({ schema_version: 1, study_version: 'lesson1-student-trial-v1',
      participant, run_id: session.run_id, segment_id: session.segment_id, reason: 'deployment_technical_check',
      synthetic: true, recording: { source: 'synthetic_qa_canvas', mime: 'video/mp4', bytes: video.length } }));
    await requestObject('PUT', auth.objects.events, {}, events, 'application/x-ndjson');
    await requestObject('PUT', auth.objects.summary, {}, summary, 'application/json');
    phase = 'multipart_video';
    const started = await requestObject('POST', auth.objects.recording, { uploads: null }, undefined, 'video/mp4');
    const xml = await started.text();
    const uploadId = xml.match(/<UploadId>([^<]+)<\/UploadId>/)?.[1];
    check(Boolean(uploadId), 'OSS accepts multipart video initialization');
    const parts = [];
    for (let offset = 0; offset < video.length; offset += 1024 * 1024) {
      const number = parts.length + 1;
      const response = await requestObject('PUT', auth.objects.recording, { uploadId, partNumber: number }, video.subarray(offset, offset + 1024 * 1024));
      const etag = response.headers.get('etag')?.replaceAll('"', '');
      assert.match(etag || '', /^[a-f0-9]+$/i);
      parts.push({ number, etag });
    }
    await (await requestObject('GET', auth.objects.recording, { uploadId })).arrayBuffer();
    report.checks.push('OSS accepts listing this video’s parts');
    const completedXml = '<CompleteMultipartUpload>' + parts.map(part => `<Part><PartNumber>${part.number}</PartNumber><ETag>"${part.etag}"</ETag></Part>`).join('') + '</CompleteMultipartUpload>';
    await requestObject('POST', auth.objects.recording, { uploadId }, Buffer.from(completedXml), 'application/xml');
    report.checks.push('OSS accepts all video parts and multipart completion');
    phase = 'server_verification';
    body.ticket = (await post('/api/lesson1/trial/renew', session)).ticket;
    const result = await post('/api/upload/complete', body);
    check(result.status === 'complete' && result.files.recording.bytes === video.length && result.files.events.bytes === events.length && result.files.summary.bytes === summary.length,
      'server verifies exact uploaded video/record/summary sizes and writes the completion manifest');
    const confirmed = await post('/api/upload/credentials', body);
    check(confirmed.status === 'already_completed', 'server finds the written manifest on retry');
    const privateUrl = await client.signatureUrlV4('GET', 300, {}, auth.objects.recording);
    const blocked = await read(privateUrl);
    check(blocked.status === 403, 'browser upload role cannot read the private video');
    const anonymous = await read(`https://cyber-game.oss-cn-hangzhou.aliyuncs.com/${auth.objects.manifest}`);
    check(anonymous.status === 403, 'completion manifest remains inaccessible without authorization');
    report.files = result.files;
  }
  if (process.argv.includes('--ai')) {
    report.ai = [];
    for (const [class_id, condition] of [['g7-01', 'proactive'], ['g7-06', 'reactive']]) {
      phase = 'live_ai_' + condition;
      const assignment = await post('/api/lesson1/trial/sessions', { class_id, student_name: '智能体技术验收（非学生）', run_id: `lesson1-${crypto.randomUUID()}`, segment_id: crypto.randomUUID(), client_key: crypto.randomBytes(32).toString('hex'), consent_version: 'lesson1-tab-recording-v1', experiment_version: 'lesson1-two-class-v1' });
      check(assignment.claims.condition === condition, 'server assigns ' + condition + ' to ' + class_id);
      const client_id = crypto.randomUUID(), scaffold_id = crypto.randomUUID(), scope_id = 'network:early:connect';
      await post('/api/lesson1/trial/scaffold', { ticket: assignment.ticket, client_id, events: [{ seq: 1, type: 'scope', scope_id }, { seq: 2, type: 'request', scope_id, scaffold_id, trigger_reason: 'manual' }] });
      let answer = await post('/api/coze/chat', { ticket: assignment.ticket, level_id: 'g7_internet_l01', trigger: 'manual', scaffold_id, state: { scope_id, challenge_index: 0, current_objective: '比较操作前后的网络现象' }, message: '我想检查自己的观察是否有依据，可以怎样思考？' });
      const started = Date.now();
      while (answer.status === 'pending') {
        assert.ok(Date.now() - started < 70000, 'AI completed within the supported wait budget');
        await new Promise(resolve => setTimeout(resolve, 1000));
        answer = await post('/api/coze/chat/status', { ticket: assignment.ticket, level_id: 'g7_internet_l01', poll: answer.poll });
      }
      check(answer.status === 'completed' && typeof answer.reply === 'string' && answer.reply.length > 0, 'live Coze response completed for ' + condition);
      report.ai.push({ class_id, condition, reply: answer.reply, diagnosticId: answer.diagnostic_id });
    }
  }
  report.passed = true;
} catch (error) {
  // Never print request objects, temporary credentials, client keys or signed URLs.
  const transport = String(error.cause?.code || error.name || '');
  report.failure = { phase, code: error.safeCode || (error.code === 'ERR_ASSERTION' ? 'assertion_failed' : /^[A-Za-z0-9_-]{1,80}$/.test(transport) ? transport : 'check_failed'),
    httpStatus: error.httpStatus || null, diagnosticId: error.diagnosticId || null };
  process.exitCode = 1;
}
const output = path.join(root, 'tmp/lesson1-cloud/live-report.json');
await fs.writeFile(output, JSON.stringify(report, null, 2));
console.log(JSON.stringify(report, null, 2));
