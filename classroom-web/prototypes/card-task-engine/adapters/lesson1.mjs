import { makeTarget } from '../core.mjs';
import { createKnowledgeState, validateKnowledgeState } from './lesson1-knowledge.mjs';

const target = (type, id, label, disabledReason = null, meta = undefined) => makeTarget(type, id, label, disabledReason, meta);
const reason = (text) => text;

const CHALLENGE_LABELS = Object.freeze(['早期网络', '协议标准化', '网状结构']);
const SHOWCASE = Object.freeze([
  { year: '1987', title: '第一封电子邮件', text: '中国发出第一封电子邮件，互联网应用从探索走向连接世界。' },
  { year: '1994', title: '全功能接入互联网', text: '中国正式接入国际互联网，更多学校、机构和家庭开始使用网络。' },
  { year: '今天', title: '5G 与北斗', text: '5G 提供更快更稳的连接，北斗导航服务千行百业，创新让网络更可靠、更普惠。' }
]);

const pushEvidence = (state, item) => state.data.evidence.push({ ...item, challenge: state.data.challengeIndex });
const challenge = state => state.data.challenges[state.data.challengeIndex];

export const lesson1Adapter = Object.freeze({
  meta: Object.freeze({
    schema_version: 1,
    course_id: 'g7-internet-application-innovation',
    curriculum_lesson_id: 'g7-internet-l01',
    task_id: 'innovation-network-card-table',
    content_version: 'g7-l01-card-table.1.1',
    task_title: '互联网发展靠创新',
    duration_ms: 360000,
    evidence_type: 'network_innovation_observation'
  }),
  actions: Object.freeze([
    Object.freeze({ id: 'connect-device', title: '接入设备', purpose: '把终端或网络接入场景' }),
    Object.freeze({ id: 'establish-connection', title: '建立连接', purpose: '连接两个网络节点或线路' }),
    Object.freeze({ id: 'configure-protocol', title: '配置协议', purpose: '让通信双方遵守同一套规则' }),
    Object.freeze({ id: 'add-backup-route', title: '增设备路', purpose: '为关键线路增加备用路径' }),
    Object.freeze({ id: 'run-test', title: '运行测试', purpose: '观察通信是否成功并记录证据' })
  ]),
  initialFeedback: Object.freeze({ tone: 'info', title: '先观察网络结构', text: '选择底部行动卡，再点击场景里被高亮的对象。先从“接入设备”开始。' }),

  createInitialState() {
    return {
      challengeIndex: 0,
      proactiveHintsShown: 0,
      challengeLabels: [...CHALLENGE_LABELS],
      challenges: [
        {
          id: 'early', terminalConnected: false, connectionEstablished: false,
          testedBeforeFailure: false, centralFailure: false, testedAfterFailure: false,
          communication: 'not_tested'
        },
        {
          id: 'protocol', networkAConnected: false, networkBConnected: false,
          connectionEstablished: false, testedBeforeConfig: false, protocolConfigured: false,
          testedAfterConfig: false, communication: 'not_tested', protocolA: '规则 A', protocolB: '规则 B'
        },
        {
          id: 'mesh', mainLineConnected: false, mainLineEstablished: false, testedBeforeFailure: false,
          mainLineFailed: false, backupAdded: false, testedAfterBackup: false,
          communication: 'not_tested', routes: { main: 'online', backup: 'absent' }
        }
      ],
      evidence: [],
      knowledge: createKnowledgeState(),
      showcase: { visible: false, items: clone(SHOWCASE), completed: false },
      revision: 0,
      lastAction: null
    };
  },

  legalTargets(state, action) {
    const d = state.data;
    const c = challenge(state);
    if (d.challengeIndex === 0) {
      if (action === 'connect-device') return [target('device', 'early-terminal', '早期终端', c.terminalConnected ? reason('终端已经接入。') : null)];
      if (action === 'establish-connection') return [target('line', 'early-central-link', '终端—中央计算机线路', !c.terminalConnected ? '先接入早期终端，再建立连接。' : c.connectionEstablished ? '这条线路已经建立。' : null)];
      if (action === 'run-test') return [
        target('test', 'early-communication-test', '通信测试台', !c.connectionEstablished ? '先建立终端与中央计算机的连接。' : c.testedBeforeFailure && !c.centralFailure ? '先模拟中央计算机故障，再重新测试。' : c.testedAfterFailure ? '故障后的测试已经完成。' : null),
        target('fault', 'early-central-fault', '模拟中央计算机故障', !c.testedBeforeFailure ? '先运行一次正常通信测试，记录早期结构的初始状态。' : c.centralFailure ? '中央计算机故障已经模拟。' : null)
      ];
      return [target('object', action, '当前早期网络对象', '这一关先观察中央计算机的单点结构。')];
    }
    if (d.challengeIndex === 1) {
      if (action === 'connect-device') return [
        target('network', 'protocol-network-a', '网络 A（规则 A）', c.networkAConnected ? '网络 A 已接入。' : null),
        target('network', 'protocol-network-b', '网络 B（规则 B）', c.networkBConnected ? '网络 B 已接入。' : null)
      ];
      if (action === 'establish-connection') return [target('line', 'protocol-bridge', 'A—B 待连接线路', !(c.networkAConnected && c.networkBConnected) ? '先把网络 A 和网络 B 都接入场景。' : c.connectionEstablished ? '两张网络已经连接。' : null)];
      if (action === 'configure-protocol') return [target('protocol', 'protocol-bridge', '协议配置板（统一为 TCP/IP）', !c.connectionEstablished ? '先连接两个网络，再配置它们共同遵守的协议。' : c.protocolConfigured ? '两个网络已经使用相同协议。' : null)];
      if (action === 'run-test') return [target('test', 'protocol-bridge', 'A—B 通信测试线', !c.connectionEstablished ? '先建立 A—B 连接。' : c.testedBeforeConfig && !c.protocolConfigured ? '先配置相同协议，再重新测试。' : c.testedAfterConfig ? '配置协议后的测试已经完成。' : null)];
      return [target('object', action, '协议标准化对象', '这张牌要等通信测试发现规则差异后再使用。')];
    }
    if (d.challengeIndex === 2) {
      if (action === 'connect-device') return [target('device', 'mesh-node', '网状结构节点', c.mainLineConnected ? '节点已经接入。' : null)];
      if (action === 'establish-connection') return [target('line', 'mesh-main-line', '主线路（节点—接收端）', !c.mainLineConnected ? '先接入网状结构节点。' : c.mainLineEstablished ? '主线路已经建立。' : null)];
      if (action === 'add-backup-route') return [target('line', 'mesh-backup-line', '备用线路（节点—接收端）', !c.mainLineFailed ? '先运行测试并模拟主线路故障，再增加备用路径。' : c.backupAdded ? '备用线路已经接入。' : null)];
      if (action === 'run-test') return [
        target('test', 'mesh-main-line', '主线路测试点', !c.mainLineEstablished ? '先接入节点并建立主线路。' : c.testedBeforeFailure ? '先模拟主线路故障，再测试备用路径。' : null),
        target('fault', 'mesh-fault-switch', '模拟主线路故障', !c.testedBeforeFailure ? '先运行一次主线路测试，确认原来的连接可用。' : c.mainLineFailed ? '主线路故障已经模拟。' : null),
        target('test', 'mesh-backup-line', '备用线路测试点', !c.backupAdded ? '先增加备用线路。' : c.testedAfterBackup ? '备用线路测试已经完成。' : null)
      ];
      return [target('object', action, '网状结构对象', '观察线路状态后再选择这张牌。')];
    }
    return [];
  },

  selectableObjects(state, action) {
    return this.legalTargets(state, action).filter(item => !item.disabledReason).map(item => item.id);
  },

  actionHint(state, action) {
    const index = state.data.challengeIndex;
    if (index === 0) {
      if (action === 'connect-device') return '先把终端接入中央计算机旁边的早期网络。';
      if (action === 'establish-connection') return '终端接入后，点击终端—中央计算机线路。';
      if (action === 'run-test') return '先测一次正常通信，再模拟中央计算机故障，最后重新测试。';
    }
    if (index === 1) {
      if (action === 'connect-device') return '把规则不同的网络 A、网络 B 都接入。';
      if (action === 'establish-connection') return '点击 A—B 待连接线路，把两张网络连起来。';
      if (action === 'run-test') return '先测试通信，观察规则不同会导致失败。';
      if (action === 'configure-protocol') return '在协议配置板上让两边使用同一套 TCP/IP 规则。';
    }
    if (index === 2) {
      if (action === 'connect-device') return '先接入网状结构节点。';
      if (action === 'establish-connection') return '先建立主线路，再运行测试。';
      if (action === 'run-test') return '先测主线路，再模拟故障，增加备用线路后重新测试。';
      if (action === 'add-backup-route') return '主线路故障后，给节点增加一条备用路径。';
    }
    return '';
  },

  applyAction(state, action, objectId, targetId) {
    const d = state.data;
    const c = challenge(state);
    if (objectId !== null && objectId !== targetId) return { ok: false, code: 'single_object_required', title: '请点击场景中的明确对象', text: '这张牌一次作用于一个设备、线路或测试点。' };
    d.lastAction = { action, targetId };
    if (d.challengeIndex === 0) {
      if (action === 'connect-device' && targetId === 'early-terminal' && !c.terminalConnected) {
        c.terminalConnected = true; d.revision++; pushEvidence(state, { type: 'device_connected', object: targetId });
        return { ok: true, phase: 'challenge_early', feedback: { tone: 'success', title: '终端已接入', text: '早期终端接入中央计算机网络。下一步可以建立连接。' }, detail: { object: targetId } };
      }
      if (action === 'establish-connection' && targetId === 'early-central-link' && c.terminalConnected && !c.connectionEstablished) {
        c.connectionEstablished = true; d.revision++; pushEvidence(state, { type: 'connection_established', object: targetId });
        return { ok: true, phase: 'challenge_early', feedback: { tone: 'success', title: '连接已经建立', text: '终端现在能和中央计算机通信。先运行一次正常测试。' }, detail: { object: targetId } };
      }
      if (action === 'run-test' && targetId === 'early-communication-test' && c.connectionEstablished && !c.testedBeforeFailure) {
        c.testedBeforeFailure = true; c.communication = 'success'; d.revision++; pushEvidence(state, { type: 'communication_test', result: 'success', object: targetId });
        return { ok: true, phase: 'challenge_early', feedback: { tone: 'success', title: '第一次通信成功', text: '终端能收到中央计算机的回复。现在模拟一次中央计算机故障。' }, detail: { result: 'success' } };
      }
      if (action === 'run-test' && targetId === 'early-central-fault' && c.testedBeforeFailure && !c.centralFailure) {
        c.centralFailure = true; c.communication = 'failed_central_single_point'; d.revision++; pushEvidence(state, { type: 'central_failure', result: 'whole_network_stopped', object: targetId });
        return { ok: true, phase: 'challenge_early', feedback: { tone: 'warn', title: '中央计算机故障，通信中断', text: '所有终端都依赖同一台中央计算机；它一停，整段网络都停了。请重新运行测试确认。' }, detail: { result: 'central_failure' } };
      }
      if (action === 'run-test' && targetId === 'early-communication-test' && c.centralFailure && !c.testedAfterFailure) {
        c.testedAfterFailure = true; c.communication = 'failed_central_single_point'; d.revision++; pushEvidence(state, { type: 'communication_test_after_failure', result: 'failed', object: targetId });
        d.challengeIndex = 1; d.revision++;
        return { ok: true, phase: 'challenge_protocol', feedback: { tone: 'success', title: '早期网络的局限找到了', text: '中央计算机是单点故障。接下来观察不同网络为什么需要共同的通信规则。' }, detail: { challenge_complete: 'early', next: 'protocol' } };
      }
    }
    if (d.challengeIndex === 1) {
      if (action === 'connect-device' && targetId === 'protocol-network-a' && !c.networkAConnected) { c.networkAConnected = true; d.revision++; pushEvidence(state, { type: 'network_connected', network: 'A' }); return { ok: true, phase: 'challenge_protocol', feedback: { tone: 'success', title: '网络 A 已接入', text: '规则 A 的网络进入场景。看看另一边的规则有什么不同。' } }; }
      if (action === 'connect-device' && targetId === 'protocol-network-b' && !c.networkBConnected) { c.networkBConnected = true; d.revision++; pushEvidence(state, { type: 'network_connected', network: 'B' }); return { ok: true, phase: 'challenge_protocol', feedback: { tone: 'success', title: '网络 B 已接入', text: '两张网络都在场景中。先观察它们各自遵守的规则。' } }; }
      if (action === 'establish-connection' && targetId === 'protocol-bridge' && c.networkAConnected && c.networkBConnected && !c.connectionEstablished) { c.connectionEstablished = true; d.revision++; pushEvidence(state, { type: 'connection_established', object: targetId, protocols: [c.protocolA, c.protocolB] }); return { ok: true, phase: 'challenge_protocol', feedback: { tone: 'info', title: '两张网络连上了', text: '线路已经接通，但规则 A 和规则 B 仍然不同。试试看消息能否通过。' } }; }
      if (action === 'run-test' && targetId === 'protocol-bridge' && c.connectionEstablished && !c.testedBeforeConfig) { c.testedBeforeConfig = true; c.communication = 'failed_protocol_mismatch'; d.revision++; pushEvidence(state, { type: 'communication_test', result: 'failed_protocol_mismatch', protocols: [c.protocolA, c.protocolB] }); return { ok: true, phase: 'challenge_protocol', feedback: { tone: 'warn', title: '通信失败：规则对不上', text: '连接存在，消息却无法互相理解。看看哪种创新能解决规则差异。' } }; }
      if (action === 'configure-protocol' && targetId === 'protocol-bridge' && c.testedBeforeConfig && !c.protocolConfigured) { c.protocolConfigured = true; c.protocolA = 'TCP/IP'; c.protocolB = 'TCP/IP'; d.revision++; pushEvidence(state, { type: 'protocol_standardized', protocol: 'TCP/IP' }); return { ok: true, phase: 'challenge_protocol', feedback: { tone: 'success', title: '协议已统一', text: '两张网络现在遵守同一套规则。再验证一次前后的变化。' } }; }
      if (action === 'run-test' && targetId === 'protocol-bridge' && c.protocolConfigured && !c.testedAfterConfig) { c.testedAfterConfig = true; c.communication = 'success'; d.revision++; pushEvidence(state, { type: 'communication_test_after_protocol', result: 'success', protocol: 'TCP/IP' }); d.challengeIndex = 2; d.revision++; return { ok: true, phase: 'challenge_mesh', feedback: { tone: 'success', title: '协议标准化让网络互通', text: '共同规则让不同网络能够互相理解。下一关思考：一条线路断了，网络还能怎样保持通信？', detail: { challenge_complete: 'protocol', next: 'mesh' } } }; }
    }
    if (d.challengeIndex === 2) {
      if (action === 'connect-device' && targetId === 'mesh-node' && !c.mainLineConnected) { c.mainLineConnected = true; d.revision++; pushEvidence(state, { type: 'device_connected', object: targetId }); return { ok: true, phase: 'challenge_mesh', feedback: { tone: 'success', title: '网状节点已接入', text: '观察节点、主线路和接收端之间的关系。' } }; }
      if (action === 'establish-connection' && targetId === 'mesh-main-line' && c.mainLineConnected && !c.mainLineEstablished && !c.mainLineFailed) { c.mainLineEstablished = true; d.revision++; pushEvidence(state, { type: 'connection_established', object: targetId, route: 'main' }); return { ok: true, phase: 'challenge_mesh', feedback: { tone: 'success', title: '主线路已建立', text: '主线路现在可以传递消息。验证一下它的状态。' } }; }
      if (action === 'run-test' && targetId === 'mesh-main-line' && c.mainLineEstablished && !c.testedBeforeFailure) { c.testedBeforeFailure = true; c.communication = 'success'; d.revision++; pushEvidence(state, { type: 'communication_test', result: 'success', route: 'main' }); return { ok: true, phase: 'challenge_mesh', feedback: { tone: 'success', title: '主线路通信成功', text: '如果这条路断开，网络还剩下什么选择？' } }; }
      if (action === 'run-test' && targetId === 'mesh-fault-switch' && c.testedBeforeFailure && !c.mainLineFailed) { c.mainLineFailed = true; c.communication = 'failed_single_route'; c.routes.main = 'failed'; d.revision++; pushEvidence(state, { type: 'line_failure', route: 'main', result: 'communication_interrupted' }); return { ok: true, phase: 'challenge_mesh', feedback: { tone: 'warn', title: '主线路断开，通信中断', text: '单一路径无法应对故障。找一条能继续传递消息的路径。' } }; }
      if (action === 'add-backup-route' && targetId === 'mesh-backup-line' && c.mainLineFailed && !c.backupAdded) { c.backupAdded = true; c.routes.backup = 'online'; d.revision++; pushEvidence(state, { type: 'backup_route_added', route: 'backup' }); return { ok: true, phase: 'challenge_mesh', feedback: { tone: 'success', title: '备用路径已增加', text: '现在有两条路径了。验证哪一条能够接管通信。' } }; }
      if (action === 'run-test' && targetId === 'mesh-backup-line' && c.backupAdded && !c.testedAfterBackup) { c.testedAfterBackup = true; c.communication = 'success_via_backup'; d.revision++; pushEvidence(state, { type: 'communication_test_after_backup', result: 'success', route: 'backup' }); d.challengeIndex = 3; d.showcase.visible = true; d.showcase.completed = true; d.revision++; return { ok: true, complete: true, phase: 'completed', feedback: { tone: 'success', title: '三种创新思路都验证了', text: '中央计算机、统一协议、备用路径分别说明了结构、规则和冗余连接的重要性。现在看看中国互联网发展的几个节点。' }, detail: { challenge_complete: 'mesh', showcase: SHOWCASE.map(item => item.year) } }; }
    }
    return { ok: false, code: 'not_ready', title: '这一步还没有前置条件', text: this.actionHint(state, action) || '先观察场景中高亮的对象。' };
  },

  validateState(state) {
    const d = state.data;
    if (!d || !Number.isInteger(d.challengeIndex) || d.challengeIndex < 0 || d.challengeIndex > 3 || !Array.isArray(d.challenges) || d.challenges.length !== 3 || !Array.isArray(d.evidence) || !Number.isInteger(d.revision) || d.revision < 0 || !d.showcase || !Array.isArray(d.showcase.items)) return false;
    const [early, protocol, mesh] = d.challenges;
    if (!validateKnowledgeState(d.knowledge, d.challengeIndex)) return false;
    return Boolean(early && protocol && mesh && typeof early.terminalConnected === 'boolean' && typeof protocol.protocolConfigured === 'boolean' && typeof mesh.mainLineEstablished === 'boolean' && typeof mesh.backupAdded === 'boolean' && d.showcase.items.length === SHOWCASE.length && d.showcase.items.every(item => item.year && item.title && item.text));
  },

  validateWin(state) {
    const [early, protocol, mesh] = state.data.challenges;
    return Boolean(state.data.challengeIndex === 3 && early.testedAfterFailure && protocol.testedAfterConfig && mesh.testedAfterBackup && state.data.showcase.visible && state.data.showcase.completed);
  },

  artifact(state) {
    if (!this.validateWin(state)) return null;
    return { mime: 'application/json;charset=utf-8', name: 'lesson1-innovation-evidence.json', text: JSON.stringify({ task: this.meta.task_id, showcase: state.data.showcase.items, evidence: state.data.evidence, knowledge: state.data.knowledge }, null, 2) };
  }
});

function clone(value) { return JSON.parse(JSON.stringify(value)); }

