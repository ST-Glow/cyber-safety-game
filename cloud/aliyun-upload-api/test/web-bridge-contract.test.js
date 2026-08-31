"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const bridgePath = path.resolve(__dirname, "../../../godot/web/experiment-bridge.js");
const bridge = fs.readFileSync(bridgePath, "utf8");
const exportScript = fs.readFileSync(path.resolve(__dirname, "../../../godot/tools/export_web.ps1"), "utf8");
const apiSource = fs.readFileSync(path.resolve(__dirname, "../src/create-app.js"), "utf8");

test("web bridge records only the Godot canvas and has an explicit degradation file", () => {
  assert.match(bridge, /canvas\.captureStream/);
  assert.match(bridge, /MediaRecorder/);
  assert.match(bridge, /recordingStatusBlob/);
  assert.doesNotMatch(bridge, /getUserMedia\s*\(/);
  assert.doesNotMatch(bridge, /getDisplayMedia\s*\(/);
});

test("web bridge prefers MP4 recording and keeps WebM as a compatibility fallback", () => {
  const mp4Index = bridge.indexOf('video/mp4;codecs=avc1.42E01E');
  const webmIndex = bridge.indexOf('video/webm;codecs=vp9');
  assert.ok(mp4Index >= 0);
  assert.ok(webmIndex > mp4Index);
  assert.match(bridge, /state\.recordingExtension = selected\.profile\.extension/);
  assert.match(bridge, /recordingExtension: state\.recordingBlob \? state\.recordingExtension : "json"/);
});

test("web bridge persists finalized blobs and multipart checkpoints in IndexedDB", () => {
  assert.match(bridge, /indexedDB\.open/);
  assert.match(bridge, /CHUNK_STORE_NAME = "recording_chunks"/);
  assert.match(bridge, /saveRecordingChunk/);
  assert.match(bridge, /loadRecordingChunks/);
  assert.match(bridge, /deleteRecordingChunks/);
  assert.match(bridge, /eventsBlob/);
  assert.match(bridge, /summaryBlob/);
  assert.match(bridge, /record\.checkpoints\[key\]/);
  assert.match(bridge, /resumePending/);
});

test("web bridge uses the DigComp v1 long-session recording budget", () => {
  assert.match(bridge, /recordingBitsPerSecond \|\| 1500000/);
  assert.match(bridge, /maxRecordingBytes \|\| 1024 \* 1024 \* 1024/);
  assert.match(bridge, /schema_version: 3/);
  assert.match(bridge, /event_schema_version: 2/);
  assert.match(bridge, /level_4_image_judgment/);
});

test("production adult consent remains while internal preview bypass is explicit", () => {
  assert.match(bridge, /年满 18 岁/);
  assert.match(bridge, /20–40 分钟/);
  assert.match(bridge, /data-field="research-contact"/);
  assert.match(bridge, /config\.researchContact/);
  assert.match(bridge, /internalPreview/);
  assert.match(exportScript, /consentMode = if \(\$ProductionMode\) \{ "adult" \} elseif \(\$PreviewMode\) \{ "internal_preview" \}/);
});

test("web bridge tries primary then fallback only for network or server failures", () => {
  assert.match(bridge, /primaryApiBaseUrl/);
  assert.match(bridge, /fallbackApiBaseUrl/);
  assert.match(bridge, /response\.status < 500/);
  assert.match(bridge, /for \(const base of apiBases\(\)\)/);
});

test("success is gated by the server completion endpoint that writes manifest", () => {
  assert.match(bridge, /api\/upload\/complete/);
  assert.match(bridge, /showUploadSuccess\(result\.status\)/);
  assert.ok(bridge.indexOf("completeUpload(record)") < bridge.indexOf("showUploadSuccess(result.status)"));
});

test("production export is a release build and requires a research contact", () => {
  assert.match(exportScript, /--export-release/);
  assert.match(exportScript, /Production export requires ResearchContact/);
  assert.match(exportScript, /recordingBitsPerSecond = 1500000/);
  assert.match(exportScript, /maxRecordingBytes = 1073741824/);
});

test("server validates recordings up to one GiB", () => {
  assert.match(apiSource, /recording: \{ max: 1024 \* 1024 \* 1024/);
  assert.match(apiSource, /limit: "1gb"/);
});
