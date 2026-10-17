"""Add the lesson 1 trial to the last confirmed FC archive, preserving the old site."""
import hashlib
import json
import pathlib
import zipfile
from datetime import datetime, timezone

ROOT = pathlib.Path(__file__).resolve().parents[2]
BASE = ROOT / 'dist/classroom-experiment-20260921023114.zip'
BASE_SHA = '66aceb6290b15b09c5cf1f28cfcf1f05dc6ffb5d7748f9d108d58edd04605104'
sha = lambda data: hashlib.sha256(data).hexdigest()
assert sha(BASE.read_bytes()) == BASE_SHA, 'Confirmed FC baseline changed'
stamp = datetime.now(timezone.utc).strftime('%Y%m%d%H%M%S')
out = ROOT / 'dist' / ('classroom-lesson1-' + stamp)
out.mkdir()
baseline = {}
with zipfile.ZipFile(BASE) as archive:
    for info in archive.infolist():
        rel = pathlib.PurePosixPath(info.filename)
        assert not rel.is_absolute() and '..' not in rel.parts
        target = out.joinpath(*rel.parts)
        if info.is_dir():
            target.mkdir(parents=True, exist_ok=True)
        else:
            data = archive.read(info)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
            baseline[rel.as_posix()] = sha(data)

backend = ROOT / 'cloud/aliyun-upload-api'
for name in ['src/create-app.js', 'src/lesson1-trial.js', 'src/lesson1-experiment.js', 'src/agent-context.js']:
    target = out / name
    target.write_bytes((backend / name).read_bytes())

lesson = ROOT / 'classroom-web/prototypes/lesson1-card-table'
engine = ROOT / 'classroom-web/prototypes/card-task-engine'
shared = ROOT / 'classroom-web/prototypes/card-game'
lesson4 = ROOT / 'classroom-web/prototypes/lesson4-card-table'
site = out / 'public/classroom/lesson1'
site.mkdir(parents=True)
files = {name: lesson / name for name in ['index.html', 'lesson1-overrides.css', 'student-entry.css', 'trial-study.css',
    'config.mjs', 'agent.mjs', 'app.mjs', 'tour.mjs', 'knowledge-dialog.mjs', 'student-session.mjs', 'student-entry.mjs', 'trial-study.mjs', 'trial-store.mjs',
    'experiment-support.mjs', 'experiment-support.css', 'device-check.html', 'device-check.mjs', 'device-check.css', 'legacy-upload.html', 'legacy-upload.mjs']}
files['experiment-scaffold.mjs'] = ROOT / 'classroom-web/src/experiment-scaffold.js'
files['styles.css'] = lesson4 / 'styles.css'
files['core.mjs'] = engine / 'core.mjs'
for name in ['lesson1.mjs', 'lesson1-knowledge.mjs']:
    files['adapters/' + name] = engine / 'adapters' / name
for name in ['agent-sidebar.mjs', 'card-hand.mjs', 'mission-feedback.mjs', 'mission-header.mjs', 'visual-game-shell.mjs']:
    files[name] = shared / 'ui' / name
files['network-lesson-scene.mjs'] = shared / 'scene/network-lesson-scene.mjs'
for name in ['campus-board-bg-v1.png', 'node-device-v1.png', 'packet-chip-v1.png', 'announcement-screen-v1.png', 'operator-guardian-v1.png']:
    files['assets/' + name] = lesson4 / 'assets' / name
for name in ['lesson1-card-frame-warm-v1.png', 'lesson1-action-icons-warm-v1.png']:
    files['assets/' + name] = lesson / 'assets' / name
files['assets/aliyun-oss-sdk.min.js'] = ROOT / 'classroom-web/assets/aliyun-oss-sdk.min.js'
for name, source in files.items():
    target = site / name
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(source.read_bytes())
index = site / 'index.html'
index.write_text(index.read_text(encoding='utf-8').replace('<script src="trial-config.js"></script>', '<script src="trial-config.js"></script>\n  <script src="assets/aliyun-oss-sdk.min.js"></script>'), encoding='utf-8')
(site / 'trial-config.js').write_text("window.LESSON1_TRIAL_CONFIG = Object.freeze({enabled:true,experimentEnabled:true,version:'lesson1-student-trial-v1'});\n", encoding='utf-8')

# Insert before the old root handler; /classroom/native/ and A/B entries stay intact.
mount = out / 'src/classroom/native-site.js'
code = mount.read_text(encoding='utf-8')
needle = 'function mountNativeSite(app) {'
assert code.count(needle) == 1
code = code.replace(needle, needle + '\n  require("./lesson1-site").mountLesson1Site(app);')
mount.write_text(code, encoding='utf-8', newline='\n')
(out / 'src/classroom/lesson1-site.js').write_text('''"use strict";
const express = require("express");
const path = require("node:path");
function mountLesson1Site(app) {
  app.get("/", (_req, res) => { res.setHeader("Cache-Control", "no-store"); res.redirect(302, "/classroom/lesson1/"); });
  app.get("/prototype/g7-l01-card-table/", (_req, res) => res.redirect(302, "/classroom/lesson1/"));
  const checkSite = express.static(path.join(__dirname, "../../public/classroom/lesson1"), { index: 'device-check.html', dotfiles: 'deny', setHeaders(res) {
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('Permissions-Policy', 'camera=(), microphone=(), display-capture=(self)');
    res.setHeader('Content-Security-Policy', "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; media-src 'self' blob:; connect-src 'self' https://cyber-game.oss-cn-hangzhou.aliyuncs.com; object-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'");
  }});
  app.use('/classroom/lesson1-check', checkSite);
  app.use("/classroom/lesson1", express.static(path.join(__dirname, "../../public/classroom/lesson1"), {
    dotfiles: "deny", setHeaders(res) {
      res.setHeader("Cache-Control", "no-store");
      res.setHeader("X-Content-Type-Options", "nosniff");
      res.setHeader("Referrer-Policy", "no-referrer");
      res.setHeader("Permissions-Policy", "camera=(), microphone=(), display-capture=(self)");
      res.setHeader("Content-Security-Policy", "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; media-src 'self' blob:; connect-src 'self' https://cyber-game.oss-cn-hangzhou.aliyuncs.com; object-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'");
    }
  }));
}
module.exports = { mountLesson1Site };
''', encoding='utf-8')
allowed = {'src/create-app.js', 'src/classroom/native-site.js', 'src/agent-context.js'}
changed = []
for name, digest in baseline.items():
    assert (out / name).is_file(), 'Baseline file removed: ' + name
    if sha((out / name).read_bytes()) != digest:
        assert name in allowed, 'Unexpected baseline change: ' + name
        changed.append(name)
paths = sorted(p for p in out.rglob('*') if p.is_file())
for p in paths:
    assert not any(part.startswith('.env') for part in p.relative_to(out).parts)
    assert p.suffix.lower() not in {'.db', '.sqlite', '.csv', '.xlsx'}
archive = out.with_suffix('.zip')
with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as bundle:
    for p in paths:
        bundle.write(p, p.relative_to(out).as_posix())
report = dict(createdAt=datetime.now(timezone.utc).isoformat(), directory=str(out), archive=str(archive), archiveSha256=sha(archive.read_bytes()),
    baselineArchiveSha256=BASE_SHA, changedBaselineFiles=changed, preservedBaselineFiles=len(baseline)-len(changed),
    lesson1Files=[dict(path=p.relative_to(site).as_posix(), bytes=p.stat().st_size, sha256=sha(p.read_bytes())) for p in site.rglob('*') if p.is_file()],
    databaseMigrationRequired=False, requiredEnvironment={'LESSON1_TRIAL_ENABLED': 'true', 'LESSON1_EXPERIMENT_ENABLED': 'true', 'LESSON1_EXPERIMENT_ROUND_ID': 'lesson1-pilot-20261016'}, deployed=False)
report_file = ROOT / 'tmp/lesson1-cloud/build.json'
report_file.parent.mkdir(parents=True, exist_ok=True)
report_file.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps({k:v for k,v in report.items() if k != 'lesson1Files'}, ensure_ascii=False))
