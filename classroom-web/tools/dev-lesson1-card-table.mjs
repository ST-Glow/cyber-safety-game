import http from 'node:http';
import fs from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

const prefix = '/prototype/g7-l01-card-table/';
const port = Number(process.argv[2] || 8797);
const base = new URL('../prototypes/lesson1-card-table/', import.meta.url);
const engineBase = new URL('../prototypes/card-task-engine/', import.meta.url);
const cardGameBase = new URL('../prototypes/card-game/', import.meta.url);
const lesson4Base = new URL('../prototypes/lesson4-card-table/', import.meta.url);
const files = new Map([
  [prefix + 'index.html', new URL('index.html', base)],
  [prefix + 'styles.css', new URL('styles.css', lesson4Base)],
  [prefix + 'lesson1-overrides.css', new URL('lesson1-overrides.css', base)],
  [prefix + 'student-entry.css', new URL('student-entry.css', base)],
  [prefix + 'trial-study.css', new URL('trial-study.css', base)],
  [prefix + 'trial-config.js', new URL('trial-config.js', base)],
  ...['experiment-support.mjs', 'experiment-support.css', 'device-check.html', 'device-check.mjs', 'device-check.css', 'legacy-upload.html', 'legacy-upload.mjs'].map(name => [prefix + name, new URL(name, base)]),
  [prefix + 'experiment-scaffold.mjs', new URL('../src/experiment-scaffold.js', import.meta.url)],
  ...['config.mjs', 'agent.mjs', 'app.mjs', 'tour.mjs', 'knowledge-dialog.mjs', 'student-session.mjs', 'student-entry.mjs', 'trial-study.mjs', 'trial-store.mjs'].map(name => [prefix + name, new URL(name, base)]),
  [prefix + 'core.mjs', new URL('core.mjs', engineBase)],
  [prefix + 'adapters/lesson1.mjs', new URL('adapters/lesson1.mjs', engineBase)],
  [prefix + 'adapters/lesson1-knowledge.mjs', new URL('adapters/lesson1-knowledge.mjs', engineBase)],
  [prefix + 'agent-sidebar.mjs', new URL('ui/agent-sidebar.mjs', cardGameBase)],
  [prefix + 'card-hand.mjs', new URL('ui/card-hand.mjs', cardGameBase)],
  [prefix + 'mission-feedback.mjs', new URL('ui/mission-feedback.mjs', cardGameBase)],
  [prefix + 'mission-header.mjs', new URL('ui/mission-header.mjs', cardGameBase)],
  [prefix + 'visual-game-shell.mjs', new URL('ui/visual-game-shell.mjs', cardGameBase)],
  [prefix + 'network-lesson-scene.mjs', new URL('scene/network-lesson-scene.mjs', cardGameBase)]
]);
for (const name of ['campus-board-bg-v1.png', 'action-card-frame-landscape-v1.png', 'action-icons-v1.png', 'node-device-v1.png', 'packet-chip-v1.png', 'announcement-screen-v1.png', 'operator-guardian-v1.png']) {
  files.set(prefix + 'assets/' + name, new URL('assets/' + name, lesson4Base));
}
for (const name of ['lesson1-card-frame-warm-v1.png', 'lesson1-action-icons-warm-v1.png']) {
  files.set(prefix + 'assets/' + name, new URL('assets/' + name, base));
}
const mime = { html: 'text/html; charset=utf-8', css: 'text/css; charset=utf-8', mjs: 'text/javascript; charset=utf-8', js: 'text/javascript; charset=utf-8', png: 'image/png', jpg: 'image/jpeg', jpeg: 'image/jpeg' };
const headers = { 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer', 'Content-Security-Policy': "default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'none'; img-src 'self'; object-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'" };
const server = http.createServer(async (req, res) => {
  if (!['127.0.0.1:' + port, 'localhost:' + port].includes(req.headers.host)) { res.writeHead(403, headers); res.end(); return; }
  if (!['GET', 'HEAD'].includes(req.method)) { res.writeHead(405, { ...headers, Allow: 'GET, HEAD' }); res.end(); return; }
  const path = req.url.split('?')[0];
  if (path === '/' || path === prefix.slice(0, -1)) { res.writeHead(302, { ...headers, Location: prefix }); res.end(); return; }
  const file = files.get(path === prefix ? prefix + 'index.html' : path);
  if (!file) { res.writeHead(404, headers); res.end('Not found'); return; }
  try { const data = await fs.readFile(fileURLToPath(file)); res.writeHead(200, { ...headers, 'Content-Type': mime[file.pathname.split('.').at(-1)] || 'application/octet-stream', 'Content-Length': data.length }); res.end(req.method === 'HEAD' ? undefined : data); }
  catch { res.writeHead(500, headers); res.end('Local preview unavailable'); }
});
server.listen(port, '127.0.0.1', () => console.log(`Lesson 1 card table: http://127.0.0.1:${port}${prefix}`));

