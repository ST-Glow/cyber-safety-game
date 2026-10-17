import { trialStore, ownerKey } from './trial-store.mjs';

const CONSENT = 'lesson1-tab-recording-v1';
const safeError = error => {
  if (error?.name === 'NotAllowedError') return '没有开启录制。请点击按钮，选择当前游戏标签页并允许共享。';
  if (error?.name === 'QuotaExceededError') return '这台电脑的浏览器空间不足。请先下载并上传已有记录，或联系老师。';
  if (error?.code === 'trial_rate_limited') return '本次开始人数较多，请稍候重试。';
  if (/Failed to fetch|NetworkError|fetch failed|timeout/i.test(error?.message || '') || error?.name === 'TimeoutError') return '网络暂时不可用，记录仍保存在当前浏览器，请恢复网络后重试。';
  return error?.displayMessage || '本次操作未完成，记录仍保留在这台电脑。请重试或联系老师。';
};
const problem = displayMessage => Object.assign(Error(displayMessage), { displayMessage });

async function post(path, body) {
  const response = await fetch(path, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body), signal: AbortSignal.timeout(30000), credentials: 'omit' });
  const data = await response.json();
  if (!response.ok) throw Object.assign(Error(data.code || 'request_failed'), { code: data.code, status: response.status });
  return data;
}
function sessionBody(record) {
  return { segment_id: record.segment_id, run_id: record.run_id, client_key: record.client_key,
    class_id: record.participant.class_id, student_name: record.participant.student_name, consent_version: CONSENT,
    activity_type: record.activity_type || 'lesson1_game', ...(record.participant.experiment_version ? { experiment_version: record.participant.experiment_version } : {}) };
}
function download(blob, name) {
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a'); link.href = url; link.download = name; link.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
async function checkVideo(blob) {
  const video = document.createElement('video'); video.muted = true; video.preload = 'auto';
  const url = URL.createObjectURL(blob);
  try {
    await new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(problem('本段录像暂时无法播放，请下载本机备份交给老师核对。')), 12000);
      video.onloadeddata = () => { clearTimeout(timer); video.videoWidth > 0 && video.videoHeight > 0 ? resolve() : reject(problem('本段录像没有有效画面，请联系老师。')); };
      video.onerror = () => { clearTimeout(timer); reject(problem('本段录像不完整，请保留本机备份并联系老师。')); };
      video.src = url;
    });
  } finally { video.removeAttribute('src'); video.load(); URL.revokeObjectURL(url); }
}

export function createTrialStudy(root, { onPause, onResume, onBack, onAssigned, getSnapshot, activityType = 'lesson1_game', autoUpload = false, onProgress, onUploaded, onInterrupted } = {}) {
  const enabled = window.LESSON1_TRIAL_CONFIG?.enabled === true;
  if (!enabled) return { enabled: false, busy: () => false, enter: async () => true, observe() {}, finish: async () => {}, uploadPending: async () => {} };
  let active = null, recorder = null, stream = null, chain = Promise.resolve(), stopPromise = null;
  let participant = null, sequence = 0, bytes = 0, lastEvent = -1, writeError = null, finishing = null;
  let currentAssignment = null;
  const handle = `lesson1-${crypto.randomUUID()}`;
  navigator.mediaDevices?.setCaptureHandleConfig?.({ handle, exposeOrigin: true, permittedOrigins: [location.origin] });
  const dialog = document.createElement('dialog'); dialog.className = 'trial-dialog';
  dialog.setAttribute('aria-labelledby', 'trial-dialog-title');
  root.append(dialog);
  let closeResolve = null;
  function open(title, text) {
    onPause?.();
    dialog.innerHTML = '<section class="trial-paper"><span class="trial-eyebrow">糖果课堂 · 试玩记录</span><h2 id="trial-dialog-title"></h2><p class="trial-copy"></p><div class="trial-detail"></div><p class="trial-message" role="status"></p><div class="trial-actions"></div></section>';
    dialog.querySelector('h2').textContent = title;
    dialog.querySelector('.trial-copy').textContent = text;
    if (!dialog.open) dialog.showModal();
  }
  function close(value = true) { dialog.close(); closeResolve?.(value); closeResolve = null; onResume?.(); }
  function message(text) { dialog.querySelector('.trial-message').textContent = text; }
  function button(label, handler, secondary = false) {
    const node = document.createElement('button'); node.type = 'button'; node.textContent = label;
    if (secondary) node.className = 'secondary';
    node.onclick = handler; dialog.querySelector('.trial-actions').append(node); return node;
  }
  dialog.addEventListener('cancel', event => event.preventDefault());
  function badge(text, tone = '') {
    let node = root.querySelector('.trial-recording-badge');
    if (!node) { node = document.createElement('div'); node.className = 'trial-recording-badge'; node.setAttribute('role', 'status'); root.append(node); }
    node.textContent = text; node.dataset.tone = tone;
  }
  async function recover(student) {
    const records = (await trialStore.all()).filter(row => row.owner === ownerKey(student) && !['complete', 'cancelled'].includes(row.status) && row.segment_id !== active?.segment_id);
    for (const record of records) {
      if (record.status === 'collecting' || record.status === 'uploading') {
        record.status = 'pending'; record.reason ||= 'page_interrupted'; record.interrupted = true;
        await trialStore.save(record);
      }
    }
    return records;
  }
  async function uploadRecord(record, progress) {
    const video = await trialStore.recording(record);
    if (!video.size) throw problem('这段录像没有可上传的画面，请下载过程记录交给老师。');
    progress('正在检查本机录像…');
    await checkVideo(video);
    onProgress?.('playable', true);
    const assignment = await post('/api/lesson1/trial/sessions', sessionBody(record));
    const body = { ticket: assignment.ticket, recording_extension: record.extension, recording_available: true };
    const credentials = await post('/api/upload/credentials', body);
    const summary = { schema_version: 1, study_version: window.LESSON1_TRIAL_CONFIG.version, activity_type: record.activity_type || 'lesson1_game',
      participant: record.participant, run_id: record.run_id, segment_id: record.segment_id, reason: record.reason,
      started_at: record.created_at, stopped_at: record.stopped_at, interrupted: Boolean(record.interrupted),
      recording: { source: 'current_game_tab', mime: record.mime, bytes: video.size, consent_version: CONSENT }, snapshot: record.snapshot };
    const events = [...(record.snapshot?.state?.events || []), ...(record.lifecycle || [])];
    const blobs = { events: new Blob([events.map(event => JSON.stringify(event)).join('\n') + '\n'], { type: 'application/x-ndjson' }),
      summary: new Blob([JSON.stringify(summary)], { type: 'application/json' }), recording: video };
    if (credentials.status !== 'already_completed') {
      if (credentials.mode === 'mock') {
        for (const [name, blob] of Object.entries(blobs)) {
          progress(`正在上传${name === 'recording' ? '录像' : '过程记录'}…`);
          const response = await fetch(credentials.upload_urls[name], { method: 'PUT', headers: { Authorization: `Bearer ${assignment.ticket}`, 'Content-Type': blob.type }, body: blob, signal: AbortSignal.timeout(180000) });
          if (!response.ok) throw Error('upload_failed');
          onProgress?.(name, true);
        }
      } else {
        if (!window.OSS) throw problem('上传组件未能加载，请刷新页面后重试。');
        const token = credentials.credentials;
        const client = new window.OSS({ region: credentials.region, bucket: credentials.bucket,
          accessKeyId: token.AccessKeyId, accessKeySecret: token.AccessKeySecret, stsToken: token.SecurityToken,
          secure: true, authorizationV4: true,
          refreshSTSToken: async () => {
            const renewal = await post('/api/lesson1/trial/renew', sessionBody(record));
            body.ticket = renewal.ticket;
            const renewed = await post('/api/upload/credentials', body);
            return { accessKeyId: renewed.credentials.AccessKeyId, accessKeySecret: renewed.credentials.AccessKeySecret, stsToken: renewed.credentials.SecurityToken };
          }, refreshSTSTokenInterval: 240000 });
        for (const [name, blob] of Object.entries(blobs)) {
          progress(`正在上传${name === 'recording' ? '录像' : '过程记录'}…`);
          if (name === 'recording') await client.multipartUpload(credentials.objects[name], blob, { mime: blob.type, parallel: 2, partSize: 1024 * 1024, timeout: 180000,
            progress: percentage => { progress(`正在上传录像 ${Math.floor(percentage * 100)}%`); } });
          else await client.put(credentials.objects[name], blob, { headers: { 'Content-Type': blob.type } });
          onProgress?.(name, true);
        }
      }
    }
    // An expired ticket is renewed before final verification, including long uploads.
    body.ticket = (await post('/api/lesson1/trial/renew', sessionBody(record))).ticket;
    progress('正在核验云端文件…');
    const confirmation = await post('/api/upload/complete', body);
    if (confirmation.status !== 'complete' || confirmation.files?.recording?.bytes !== video.size) throw problem('云端尚未确认完整录像，请重试。');
    record.status = 'complete'; record.confirmed_at = Date.now(); record.confirmation = confirmation;
    await trialStore.save(record);
    await trialStore.clearChunks(record.segment_id);
    onProgress?.('verified', true); onUploaded?.(confirmation, record);
  }
  async function pendingDialog(student) {
    const records = await recover(student);
    if (!records.length) return;
    open('保存这次探索', '录像和操作记录已暂存在当前浏览器。上传成功后会显示云端确认；请在离开电脑前完成上传。');
    const detail = dialog.querySelector('.trial-detail');
    detail.textContent = `待上传 ${records.length} 段 · ${student.class_name} · ${student.student_name}`;
    const closed = new Promise(resolve => { closeResolve = resolve; });
    let uploading = false;
    const upload = button('上传记录与录像', async () => {
      if (uploading) return;
      uploading = true; upload.disabled = later.disabled = backup.disabled = true;
      try {
        for (const record of records) if (record.status !== 'complete') await uploadRecord(record, message);
        message('上传完成，云端已核验记录和录像。'); badge('记录与录像已上传', 'success');
        if (autoUpload) { close(); return; }
        upload.textContent = '继续'; upload.disabled = false; upload.onclick = () => close();
        later.hidden = backup.hidden = true;
      } catch (error) {
        message(safeError(error)); uploading = false; upload.disabled = later.disabled = backup.disabled = false;
      }
    });
    const backup = button('下载本机备份', async () => {
      try {
        const record = records.find(item => item.status !== 'complete') || records[0];
        download(new Blob([JSON.stringify({ ...record.snapshot, trial: { segment_id: record.segment_id, reason: record.reason } }, null, 2)], { type: 'application/json' }), `${record.participant.class_id}-${record.segment_id}.json`);
        const video = await trialStore.recording(record);
        if (video.size) download(video, `${record.participant.class_id}-${record.segment_id}.${record.extension}`);
        message('已请求下载过程记录和录像；请核对浏览器下载列表。');
      } catch (error) { message(safeError(error)); }
    }, true);
    const later = button('稍后上传', () => { badge('有待上传的试玩记录', 'warning'); close(); }, true);
    if (autoUpload) upload.click();
    return closed;
  }
  function queueSave(snapshot) {
    if (!active) return;
    active.snapshot = snapshot;
    if (lastEvent === snapshot.state.next_event) return;
    lastEvent = snapshot.state.next_event;
    const copy = structuredClone(active);
    chain = chain.then(() => trialStore.save(copy)).catch(error => { writeError = error; badge('本机暂存失败，请结束并保存记录', 'warning'); });
  }
  async function finish(reason = 'completed', show = true) {
    if (finishing) return finishing;
    finishing = (async () => {
      if (active) {
        queueSave(getSnapshot());
        if (recorder && recorder.state !== 'inactive') recorder.stop();
        await stopPromise;
        stream?.getTracks().forEach(track => track.stop());
        await chain;
        active.status = 'pending'; active.reason = reason; active.stopped_at = Date.now();
        active.snapshot = getSnapshot();
        active.lifecycle.push({ type: 'trial_recording_stopped', at: active.stopped_at, detail: { reason, segment_id: active.segment_id } });
        await trialStore.save(active);
        active = null; recorder = null; stream = null; stopPromise = null;
        badge(writeError ? '本机暂存发生错误，请联系老师' : '记录待上传', 'warning');
      }
      if (show && participant) await pendingDialog(participant);
    })().finally(() => { finishing = null; });
    return finishing;
  }
  async function enter(student, snapshot) {
    participant = student;
    try { await pendingDialog(student); }
    catch (error) { open('本机暂存不可用', '本次试玩需要保存录像。请确认浏览器允许保存站点数据，或联系老师。'); message(safeError(error)); return new Promise(resolve => { button('返回登记', () => { close(false); resolve(false); }); }); }
    if (snapshot.state.completed || snapshot.state.ended_at !== null) return true;
    open('开始前，确认录制', '本次试玩将记录游戏标签页画面、行动卡操作、匹配尝试和结果，并上传至老师的阿里云存储，用于课堂试玩分析。不会申请摄像头或麦克风。');
    dialog.querySelector('.trial-detail').textContent = '请在浏览器窗口中选择“此标签页 / 糖果课堂”，不要选择整个屏幕或其他窗口。刷新页面后需要重新选择录制。';
    return new Promise(resolve => {
      let loading = false;
      const begin = button('同意并选择游戏标签页', async () => {
        if (loading) return;
        loading = true; begin.disabled = back.disabled = true;
        try {
          if (!navigator.mediaDevices?.getDisplayMedia || !navigator.mediaDevices.setCaptureHandleConfig || !window.MediaRecorder) throw problem('请使用桌面版 Chrome 或 Edge 打开本游戏并录制。');
          // Call directly from this click, before any asynchronous storage/network work.
          stream = await navigator.mediaDevices.getDisplayMedia({ video: { displaySurface: 'browser', frameRate: { ideal: 15, max: 20 }, width: { max: 1280 }, height: { max: 720 } }, audio: false,
            preferCurrentTab: true, selfBrowserSurface: 'include', monitorTypeSurfaces: 'exclude', surfaceSwitching: 'exclude', systemAudio: 'exclude' });
          const track = stream.getVideoTracks()[0];
          if (track.getSettings().displaySurface !== 'browser' || track.getCaptureHandle?.()?.handle !== handle) throw problem('请选择当前糖果课堂游戏标签页；已停止录制所选的其他画面。');
          const mime = ['video/mp4;codecs=avc1.42E01E', 'video/mp4', 'video/webm;codecs=vp8', 'video/webm'].find(type => MediaRecorder.isTypeSupported(type));
          if (!mime) throw problem('当前浏览器没有可用的视频编码器，请使用 Chrome 或 Edge。');
          const key = [...crypto.getRandomValues(new Uint8Array(32))].map(value => value.toString(16).padStart(2, '0')).join('');
          active = { segment_id: crypto.randomUUID(), run_id: snapshot.state.run_id, owner: ownerKey(student), participant: { ...student }, client_key: key, activity_type: activityType,
            created_at: Date.now(), status: 'collecting', mime, extension: mime.startsWith('video/mp4') ? 'mp4' : 'webm', snapshot,
            lifecycle: [{ type: 'trial_recording_started', at: Date.now(), detail: { consent_version: CONSENT, source: 'current_game_tab' } }] };
          await trialStore.save(active);
          currentAssignment = await post('/api/lesson1/trial/sessions', sessionBody(active));
          if (currentAssignment.experiment) {
            active.experiment = currentAssignment.experiment;
            active.participant = { ...active.participant, experiment_version: currentAssignment.experiment.version, experiment_round: currentAssignment.experiment.round, condition: currentAssignment.experiment.condition, scaffold_policy_version: currentAssignment.experiment.policy, data_phase: currentAssignment.experiment.data_phase };
          }
          await onAssigned?.(currentAssignment);
          recorder = new MediaRecorder(stream, { mimeType: mime, videoBitsPerSecond: 1500000 });
          sequence = 0; bytes = 0; writeError = null; lastEvent = -1; chain = Promise.resolve();
          recorder.ondataavailable = event => {
            if (!event.data.size || !active) return;
            const segment = active.segment_id, index = sequence++;
            bytes += event.data.size;
            chain = chain.then(() => trialStore.chunk(segment, index, event.data)).catch(error => { writeError = error; });
            if (bytes > 240 * 1024 * 1024) void finish('size_limit');
          };
          stopPromise = new Promise(resolveStop => { recorder.onstop = resolveStop; });
          recorder.onerror = () => { badge('录像发生中断，请保存后继续', 'warning'); void finish('recorder_error'); };
          recorder.start(1000);
          track.onended = () => { if (active && !finishing) { onPause?.(); if (activityType === 'device_check_30s') { onInterrupted?.(); void finish('sharing_stopped'); return; } void finish('sharing_stopped').then(() => { open('录制已停止', '本段记录已保留。请重新选择当前游戏标签页后继续探索。'); button('继续并重新选择', async () => { close(); if (!await enter(student, getSnapshot())) onBack?.(); }); }); } };
          badge('● 正在录制游戏标签页'); close(); resolve(true);
        } catch (error) {
          stream?.getTracks().forEach(track => track.stop()); stream = null;
          if (active && !recorder) { active.status = 'cancelled'; active.reason = 'start_failed'; await trialStore.save(active).catch(() => {}); active = null; }
          message(safeError(error)); loading = false; begin.disabled = back.disabled = false;
        }
      });
      const back = button('返回登记', () => { close(false); resolve(false); }, true);
    });
  }
  window.addEventListener('pagehide', () => { if (active) { active.snapshot = getSnapshot(); void trialStore.save(active); if (recorder?.state === 'recording') recorder.requestData(); } });
  return { enabled, busy: () => dialog.open || Boolean(finishing), enter, finish,
    assignment: () => currentAssignment,
    async renewAssignment() { if (!active) throw Error('recording_session_required'); currentAssignment = await post('/api/lesson1/trial/renew', sessionBody(active)); return currentAssignment; },
    observe(snapshot) { queueSave(snapshot); if (active && snapshot.state.completed && snapshot.state.data.knowledge.current === null) void finish('completed'); },
    async uploadPending(student) { await pendingDialog(student); } };
}
