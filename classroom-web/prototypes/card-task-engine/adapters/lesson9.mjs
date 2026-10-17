import { makeTarget } from '../core.mjs';

// 第9课：用同一组行动卡比较可靠传输与实时传输，并观察丢包、延迟和端口区分的后果。
const target = (type, id, label, disabledReason = null) => makeTarget(type, id, label, disabledReason);
const appTarget = (id, label, disabledReason = null) => target('application', id, label, disabledReason);

export const lesson9Adapter = Object.freeze({
  meta: Object.freeze({
    schema_version: 2, course_id: 'g7-internet-application-innovation', curriculum_lesson_id: 'g7-internet-l09',
    task_id: 'transport-choice-card-table', content_version: 'g7-l09-card-table.2.0',
    task_title: '给两种网络应用选择传输方式', evidence_type: 'transport_decision_and_reason', duration_ms: 300000
  }),
  actions: Object.freeze([
    Object.freeze({ id: 'reliable', title: '可靠传输', purpose: '发现缺口并请求重传' }),
    Object.freeze({ id: 'realtime', title: '实时传输', purpose: '优先保持连续和及时' }),
    Object.freeze({ id: 'assign-port', title: '分配端口', purpose: '用不同端口交给正确应用' }),
    Object.freeze({ id: 'simulate-loss', title: '制造网络状况', purpose: '观察丢包或延迟后的真实后果' }),
    Object.freeze({ id: 'submit', title: '提交判断', purpose: '核对协议、端口、后果和理由' })
  ]),
  initialFeedback: Object.freeze({ tone: 'info', title: '两个应用在等你安排', text: '文件传输要完整，直播要及时；先选一张行动卡。' }),

  createInitialState() {
    return {
      applications: {
        file: { id: 'file', title: '科技节海报文件', need: '完整准确', expected: 'reliable', transport: null, port: null, status: 'waiting', recovered: false },
        live: { id: 'live', title: '科技节开幕直播', need: '及时连续', expected: 'realtime', transport: null, port: null, status: 'waiting', delayed: false, dropped_frames: 0 }
      },
      port_cards: [
        { id: 'port-file', number: 443, assignedTo: null },
        { id: 'port-live', number: 8554, assignedTo: null }
      ],
      network: { event: 'idle', loss_detected: false, retransmit_requested: false },
      revision: 0,
      decision: { revision: null, stale: true, protocols: null, ports: null, consequences: null, reason: '' },
      evidence: [], submitted: false
    };
  },

  legalTargets(state, action) {
    const d = state.data;
    if (action === 'reliable') return [
      appTarget('file', '科技节海报文件'),
      appTarget('live', '科技节开幕直播', '直播要优先保持及时连续，请用“实时传输”。')
    ];
    if (action === 'realtime') return [
      appTarget('file', '科技节海报文件', '文件必须完整准确，请用“可靠传输”。'),
      appTarget('live', '科技节开幕直播')
    ];
    if (action === 'assign-port') return d.applications.file.port === null || d.applications.live.port === null
      ? d.port_cards.map(card => target('port', card.id, '端口 ' + card.number, card.assignedTo ? '已分配给' + (d.applications[card.assignedTo]?.title || '另一个应用') + '。' : null))
      : d.port_cards.map(card => target('port', card.id, '端口 ' + card.number, '两个应用都已分配端口。'));
    if (action === 'simulate-loss') return [
      appTarget('file', '科技节海报文件', d.applications.file.transport === 'reliable' ? null : '先为文件选择“可靠传输”，才能观察发现缺口和请求重传。'),
      appTarget('live', '科技节开幕直播', d.applications.live.transport === 'realtime' ? null : '先为直播选择“实时传输”，才能观察及时性和丢帧后果。')
    ];
    if (action === 'submit') return [target('board', 'decision-board', '传输判断板', d.applications.file.recovered && d.applications.live.delayed ? null : '先完成两种协议、端口和网络后果观察，并记录理由。')];
    return [];
  },

  selectableObjects(state, action) {
    if (action === 'assign-port') return ['file', 'live'];
    return this.legalTargets(state, action).filter(item => !item.disabledReason).map(item => item.id);
  },

  actionHint(state, action) {
    if (action === 'reliable') return '文件必须完整；丢包后要能发现缺口并请求重传。';
    if (action === 'realtime') return '直播更看重及时和连续，偶尔丢帧也不能长时间等待。';
    if (action === 'assign-port') return '把不同端口卡分给不同应用，观察接收方如何区分应用。';
    if (action === 'simulate-loss') return '给文件制造丢包，或给直播制造延迟与丢帧，再查看后果。';
    if (action === 'submit') return '提交前检查协议、端口、丢包/延迟后果和你的理由。';
    return '';
  },

  applyAction(state, action, objectId, targetId) {
    const d = state.data;
    if (action === 'submit') {
      const file = d.applications.file; const live = d.applications.live;
      if (targetId !== 'decision-board') return { ok: false, code: 'wrong_target', title: '请选传输判断板', text: '提交判断要作用在中央判断板。' };
      const correct = file.transport === 'reliable' && live.transport === 'realtime' && file.port !== null && live.port !== null && file.port !== live.port && file.recovered && live.delayed;
      if (!correct) return { ok: false, code: 'decision_incomplete', title: '还有传输证据没有完成', text: '文件要可靠并完成恢复，直播要实时且记录延迟/丢帧后果，两个应用还要使用不同端口。' };
      d.submitted = true;
      d.decision = {
        revision: d.revision,
        stale: false,
        protocols: { file: file.transport, live: live.transport },
        ports: { file: file.port, live: live.port },
        consequences: { file: 'loss_detected_and_retransmitted', live: 'delay_and_frame_drop' },
        reason: '文件完整优先，直播及时优先。'
      };
      d.evidence.push({ type: 'decision', protocols: { file: file.transport, live: live.transport }, ports: { file: file.port, live: live.port }, consequences: { file: 'loss_detected_and_retransmitted', live: 'delay_and_frame_drop' }, reason: '文件完整优先，直播及时优先。' });
      return { ok: true, complete: true, phase: 'completed', derived: 'decision', feedback: { tone: 'success', title: '传输方案成立', text: '文件通过发现缺口和重传恢复完整，直播记录了及时性与丢帧的取舍；端口把两个应用分开。' }, detail: { protocols: { file: file.transport, live: live.transport }, reason: '需求决定协议', revision: d.revision } };
    }
    if (action === 'assign-port') {
      const app = d.applications[objectId];
      const card = d.port_cards.find(item => item.id === targetId);
      if (!app || !card) return { ok: false, code: 'wrong_target', title: '端口目标不匹配', text: '请选择一个应用和一张还没有被占用的端口卡。' };
      if (card.assignedTo && card.assignedTo !== objectId) return { ok: false, code: 'port_conflict', title: '端口已经被占用', text: '端口 ' + card.number + ' 已分给' + d.applications[card.assignedTo].title + '，请选择另一张端口卡。' };
      if (app.port !== null && app.port !== card.number) return { ok: false, code: 'port_already_assigned', title: '这个应用已经有端口', text: '先撤销上一张行动卡，再重新安排端口。' };
      app.port = card.number; card.assignedTo = objectId;
      d.revision++;
      d.evidence.push({ type: 'port_assigned', app: objectId, port: card.number, reason: '端口区分应用' });
      return { ok: true, feedback: { tone: 'info', title: '端口已分配', text: app.title + '使用端口 ' + app.port + '，接收方可以把数据交给正确应用。' }, detail: { application: objectId, port: app.port } };
    }
    const app = d.applications[objectId];
    if (!app) return { ok: false, code: 'wrong_object', title: '请选择一个网络应用', text: this.actionHint(state, action) };
    if (action === 'reliable' || action === 'realtime') {
      app.transport = action;
      if (action === 'reliable' && app.status === 'lost') app.status = 'retransmitting';
      d.revision++;
      d.evidence.push({ type: 'transport_selected', app: objectId, value: action, reason: app.expected === action ? '符合应用需求' : '需要比较后修正' });
      const correct = app.expected === action;
      return { ok: true, feedback: { tone: correct ? 'success' : 'warn', title: correct ? '方向正确' : '先观察需求', text: correct ? app.title + '需要' + app.need + '，这张牌符合它的需求。' : app.title + '主要需要' + app.need + '；换一张更合适的牌后再提交。' }, detail: { application: objectId, transport: action, correct } };
    }
    if (action === 'simulate-loss') {
      if (objectId === 'file') {
        if (app.transport !== 'reliable') return { ok: false, code: 'wrong_protocol', title: '文件还不能观察恢复', text: '先用“可靠传输”让文件具备发现缺口和重传的机制。' };
        if (!d.network.loss_detected) {
          d.network.event = 'loss'; d.network.loss_detected = true; app.status = 'lost'; app.recovered = false; d.revision++;
          d.evidence.push({ type: 'loss_detected', app: objectId, reason: '一个数据片段没有到达' });
          return { ok: true, feedback: { tone: 'warn', title: '文件出现缺口', text: '可靠传输发现缺口，但还需要再次使用“可靠传输”请求重传。' }, detail: { application: objectId, consequence: 'loss_detected' } };
        }
        return { ok: false, code: 'recovery_uses_protocol_card', title: '现在应该请求重传', text: '请再次使用“可靠传输”处理文件，完成缺口恢复。' };
      }
      if (objectId === 'live') {
        if (app.transport !== 'realtime') return { ok: false, code: 'wrong_protocol', title: '直播还不能观察及时性', text: '先用“实时传输”让直播优先保持连续和及时。' };
        d.network.event = 'delay'; app.delayed = true; app.dropped_frames = Math.max(1, app.dropped_frames + 2); app.status = 'degraded'; d.revision++;
        d.evidence.push({ type: 'live_consequence', app: objectId, dropped_frames: app.dropped_frames, reason: '实时传输减少等待，允许少量丢帧' });
        return { ok: true, feedback: { tone: 'info', title: '直播保持及时', text: '网络变慢时直播丢了' + app.dropped_frames + '帧，但没有停下来等待整段重传。' }, detail: { application: objectId, consequence: 'delay_and_frame_drop', dropped_frames: app.dropped_frames } };
      }
    }
    return { ok: false, code: 'unhandled_action', title: '行动没有完成', text: '请重新选择行动卡。' };
  },

  invalidateDerived(state, context) {
    const d = state.data;
    if (context.action === 'reliable' && context.objectId === 'file' && d.network.loss_detected && d.applications.file.status === 'retransmitting') {
      d.applications.file.status = 'recovered'; d.applications.file.recovered = true; d.network.retransmit_requested = true; d.network.event = 'recovered';
      d.evidence.push({ type: 'loss_recovered', app: 'file', method: 'retransmit', reason: '可靠传输重新发送缺失片段' });
      state.feedback = { tone: 'success', title: '文件已恢复完整', text: '发现缺口后请求重传，文件现在可以完整使用。' };
    }
    if (context.result?.derived === 'decision') return;
    if (['reliable', 'realtime', 'assign-port', 'simulate-loss'].includes(context.action)) {
      d.submitted = false;
      d.decision.stale = true;
    }
  },

  validateState(state) {
    const d = state.data;
    const file = d?.applications?.file;
    const live = d?.applications?.live;
    const cards = d?.port_cards;
    if (!file || !live || !Array.isArray(cards) || cards.length !== 2 || !d.network || !Number.isInteger(d.revision) || d.revision < 0 || !d.decision || typeof d.decision.stale !== 'boolean' || !Array.isArray(d.evidence) || typeof d.submitted !== 'boolean') return false;
    if (!cards.every(card => card && typeof card.id === 'string' && Number.isInteger(card.number) && card.number > 0 && (card.assignedTo === null || card.assignedTo === 'file' || card.assignedTo === 'live')) || new Set(cards.map(card => card.id)).size !== cards.length) return false;
    if (!['waiting', 'lost', 'retransmitting', 'recovered'].includes(file.status) || !['waiting', 'degraded'].includes(live.status) || typeof file.recovered !== 'boolean' || typeof live.delayed !== 'boolean' || !Number.isInteger(live.dropped_frames) || live.dropped_frames < 0) return false;
    const apps = { file, live };
    for (const app of Object.values(apps)) {
      if (app.port !== null) {
        const card = cards.find(item => item.number === app.port);
        if (!card || card.assignedTo !== app.id) return false;
      }
    }
    const assignedApps = cards.filter(card => card.assignedTo !== null).map(card => card.assignedTo);
    if (new Set(assignedApps).size !== assignedApps.length) return false;
    if (!d.network.event || typeof d.network.loss_detected !== 'boolean' || typeof d.network.retransmit_requested !== 'boolean') return false;
    if (d.decision.revision !== null && (!Number.isInteger(d.decision.revision) || d.decision.revision < 0 || d.decision.revision > d.revision)) return false;
    if (d.submitted && (d.decision.stale || d.decision.revision !== d.revision)) return false;
    return true;
  },

  validateWin(state) {
    const { file, live } = state.data.applications;
    return Boolean(state.data.submitted && !state.data.decision.stale && state.data.decision.revision === state.data.revision && file.transport === 'reliable' && live.transport === 'realtime' && file.recovered && live.delayed && file.port !== null && live.port !== null && file.port !== live.port);
  }
});
