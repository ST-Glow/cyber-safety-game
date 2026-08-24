"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const bridgePath = path.resolve(__dirname, "../../../godot/web/experiment-bridge.js");
const bridge = fs.readFileSync(bridgePath, "utf8");

test("web bridge records only the Godot canvas and has an explicit degradation file", () => {
  assert.match(bridge, /canvas\.captureStream/);
  assert.match(bridge, /MediaRecorder/);
  assert.match(bridge, /recordingStatusBlob/);
  assert.doesNotMatch(bridge, /getUserMedia\s*\(/);
  assert.doesNotMatch(bridge, /getDisplayMedia\s*\(/);
});

test("web bridge persists finalized blobs and multipart checkpoints in IndexedDB", () => {
  assert.match(bridge, /indexedDB\.open/);
  assert.match(bridge, /eventsBlob/);
  assert.match(bridge, /summaryBlob/);
  assert.match(bridge, /record\.checkpoints\[key\]/);
  assert.match(bridge, /resumePending/);
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
