import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import crypto from 'node:crypto';
import { FrameMetrics, percentile, verdict, formatReport } from '../trial/metrics.js';
import { EncodingLoad, RECORDING_PROFILES } from '../trial/encoder.js';

test('performance reports retain foreground stalls and compute nearest-rank percentiles', () => {
  const metrics = new FrameMetrics();
  for (let i = 0; i < 94; i++) metrics.add(16.67, 2.21, 'course');
  for (let i = 0; i < 5; i++) metrics.add(50.01, 3, 'quiz');
  metrics.add(1500, 4, 'result');
  metrics.add(NaN, 0, 'course'); metrics.add(-1, 0, 'course');
  const exact = metrics.summary(true), live = metrics.summary();
  assert.equal(exact.frames, 100);
  assert.equal(exact.p95_frame_ms, 50.01);
  assert.equal(exact.max_frame_ms, 1500);
  assert.equal(exact.stalls_over_250ms, 1);
  assert.equal(exact.frames_over_50ms, 6);
  assert.equal(exact.measured_seconds, 3.32);
  assert.ok(live.p95_frame_ms >= exact.p95_frame_ms && live.p95_frame_ms - exact.p95_frame_ms <= .1);
  assert.deepEqual(exact.scenes, { course: 94, quiz: 5, result: 1 });
  assert.equal(percentile([], .95), null);
  assert.equal(new FrameMetrics().summary().average_fps, null);
});

test('partial runs and failed encoding cannot be presented as passing a full test', () => {
  const record = { automatic: true, complete: true, metrics: { measured_seconds: 600, average_fps: 60, p95_frame_ms: 16.67, slow_frame_percent: 0 } };
  assert.equal(verdict(record), '流畅');
  assert.equal(verdict({ ...record, complete: false }), '自动测试尚未完成');
  assert.equal(verdict({ ...record, encoder_requested: true, encoder: { status: 'unsupported', bytes: 0 } }), '录像负载未验证');
  assert.equal(verdict({ ...record, encoder_requested: true, encoder: { status: 'stopped', bytes: 500, error: 'stop timed out' } }), '录像负载未验证');
  assert.equal(verdict({ ...record, encoder_requested: true, encoder: { status: 'stopped', bytes: 500 } }), '流畅');
  assert.equal(verdict({ ...record, metrics: { ...record.metrics, measured_seconds: 20 } }), '样本不足，请继续测试');
});

function captureFixture() {
  let stopped = 0, fps = 0;
  const track = { stop: () => stopped++, getSettings: () => ({ frameRate: 30 }) };
  const stream = { getTracks: () => [track], getVideoTracks: () => [track] };
  return { canvas: { captureStream: value => { fps = value; return stream; } }, state: () => ({ stopped, fps }) };
}

test('encoding workload uses codec fallback, 30 fps and classroom bitrate without retaining video', async () => {
  const fixture = captureFixture(), constructors = [];
  class Recorder {
    static isTypeSupported() { return true; }
    constructor(stream, options) {
      constructors.push(options);
      if (options.mimeType === RECORDING_PROFILES[0]) throw Error('unavailable');
      this.mimeType = options.mimeType; this.state = 'inactive';
    }
    start(interval) { assert.equal(interval, 1000); this.state = 'recording'; }
    pause() { this.state = 'paused'; }
    resume() { this.state = 'recording'; }
    stop() { this.state = 'inactive'; this.ondataavailable({ data: { size: 50 } }); queueMicrotask(() => this.onstop()); }
  }
  const load = new EncodingLoad();
  assert.equal(load.start(fixture.canvas, Recorder), true);
  assert.equal(constructors.length, 2);
  assert.equal(constructors[1].videoBitsPerSecond, 1500000);
  assert.equal(fixture.state().fps, 30);
  load.recorder.ondataavailable({ data: { size: 1000 } });
  assert.equal(load.state.bytes, 1000);
  assert.equal(load.state.chunks, 1);
  assert.ok(!Object.values(load).some(Array.isArray));
  load.pause(); assert.equal(load.state.status, 'paused');
  load.resume(); assert.equal(load.state.status, 'recording');
  const [first, second] = await Promise.all([load.stop(), load.stop()]);
  assert.deepEqual(first, second);
  assert.equal(first.status, 'stopped'); assert.equal(first.bytes, 1050);
  assert.equal(fixture.state().stopped, 1);
});

test('unsupported or failed encoders are explicit and release capture tracks', async () => {
  const unsupported = new EncodingLoad();
  assert.equal(unsupported.start({}, null), false);
  assert.equal((await unsupported.stop()).status, 'unsupported');
  const fixture = captureFixture();
  class NoCodec { static isTypeSupported() { return false; } }
  const failed = new EncodingLoad();
  assert.equal(failed.start(fixture.canvas, NoCodec), false);
  assert.equal(failed.state.status, 'error');
  assert.ok(fixture.state().stopped > 0);
});

test('delivery is a self-contained, network-disabled artifact with a valid script hash', () => {
  const report = JSON.parse(fs.readFileSync(new URL('../../tmp/native/trial-build.json', import.meta.url), 'utf8'));
  const html = fs.readFileSync(report.offline, 'utf8');
  const script = html.match(/<script type="module">([\s\S]*?)<\/script>/)[1];
  const hash = crypto.createHash('sha256').update(script).digest('base64');
  assert.ok(html.includes(`script-src 'sha256-${hash}'`));
  assert.ok(html.includes("connect-src 'none'"));
  assert.ok(!/<script[^>]+src=|<link[^>]+href="https?:|<img[^>]+src="https?:/.test(html));
  assert.ok(!/\/api\/classroom|GODOT_EXPERIMENT_CONFIG|UPLOAD_LINK_SECRET/.test(script));
  assert.ok(Buffer.byteLength(html) < 5_000_000);
  assert.equal(report.oldEntriesIncluded, false);
  assert.equal(report.accountCodeIncluded, false);
  assert.equal(report.projectName, 'cyber-safety-performance-trial');
  const entries = fs.readdirSync(report.target);
  assert.ok(!entries.some(name => name.startsWith('.env')));
  assert.ok(report.legacyFilesVerified > 0);
  const baseline = JSON.parse(fs.readFileSync(new URL('../../tmp/native/latest-build.json', import.meta.url), 'utf8'));
  for (const row of baseline.legacyFiles) {
    const bytes = fs.readFileSync(new URL('../../dist/classroom-preview-site/' + row.path, import.meta.url));
    assert.equal(crypto.createHash('sha256').update(bytes).digest('hex'), row.sha256, row.path);
  }
});

test('text report makes test scope and incomplete results visible', () => {
  const text = formatReport({ version: 'test', browser: 'Edge', delivery: '离线', load_ms: 25, exported_at: 'now', runs: [{ automatic: true, complete: false, quality: 'low', metrics: new FrameMetrics().summary(), warmup_seconds: 20, pauses: 0 }] });
  assert.match(text, /未完成整段测试/);
  assert.match(text, /样本不足/);
  assert.match(text, /没有自动上传/);
});
