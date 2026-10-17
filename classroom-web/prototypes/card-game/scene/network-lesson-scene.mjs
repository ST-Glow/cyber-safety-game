const ASSET_ROOT = 'assets/';

const challengeCopy = [
  ['挑战一 · 早期网络', '中央计算机一停，大家还能通信吗？', '接入终端、建立连接，先测试一次，再模拟中央计算机故障。'],
  ['挑战二 · 协议标准化', '两张网络连上了，为什么消息还过不去？', '观察规则差异，想办法让两张网络互相理解。'],
  ['挑战三 · 网状结构', '一条线路坏了，消息还有别的路吗？', '找出让通信在故障后继续的方法。']
];

const observationCopy = [
  '新手练习：选择一张行动卡，再点击发光的目标。',
  '自己判断：规则不同的网络，怎样才能互相理解？',
  '自己判断：一条线路断开后，怎样让通信继续？'
];

const text = (element, value) => { element.textContent = value; return element; };
const image = (asset, label) => {
  const img = document.createElement('img');
  img.src = ASSET_ROOT + asset;
  img.alt = label;
  img.dataset.asset = asset.replace(/-v1\.png$/, '');
  return img;
};

// Keep the interactive route attached to the two objects it represents. The
// background map has its own decorative dashed paths, so percentage-based
// route positions are too easy to misread and drift at wide viewports.
function alignRoute(stage, routeId, fromId, toId, yOffset = 0) {
  const line = stage.querySelector(`[data-target-id="${routeId}"]`);
  const from = stage.querySelector(`[data-target-id="${fromId}"]`);
  const to = stage.querySelector(`[data-target-id="${toId}"]`);
  if (!line || !from || !to) return;
  const stageRect = stage.getBoundingClientRect();
  const fromRect = from.getBoundingClientRect();
  const toRect = to.getBoundingClientRect();
  const start = {
    x: fromRect.right - stageRect.left,
    y: fromRect.top + fromRect.height / 2 - stageRect.top + yOffset
  };
  const end = {
    x: toRect.left - stageRect.left,
    y: toRect.top + toRect.height / 2 - stageRect.top + yOffset
  };
  const dx = end.x - start.x;
  const dy = end.y - start.y;
  const length = Math.max(24, Math.hypot(dx, dy));
  const angle = Math.atan2(dy, dx) * 180 / Math.PI;
  line.style.left = `${start.x}px`;
  line.style.top = `${start.y}px`;
  line.style.width = `${length}px`;
  line.style.transform = `rotate(${angle}deg)`;
  line.dataset.aligned = 'true';
}

function alignRoutes(stage, challengeIndex) {
  if (challengeIndex === 0) {
    alignRoute(stage, 'early-central-link', 'early-terminal', 'early-central-fault');
  } else if (challengeIndex === 1) {
    alignRoute(stage, 'protocol-bridge', 'protocol-network-a', 'protocol-network-b');
  } else if (challengeIndex === 2) {
    alignRoute(stage, 'mesh-main-line', 'mesh-device', 'mesh-receiver');
    // The backup route intentionally runs below the main route so both paths
    // remain visible while sharing the same two endpoint devices.
    alignRoute(stage, 'mesh-backup-line', 'mesh-device', 'mesh-receiver', 48);
  }
}

function targetButton(id, label, kind, state, targets, onObject, content, status = '') {
  const target = targets.find(item => item.id === id);
  const button = document.createElement('button');
  button.type = 'button';
  button.dataset.targetId = id;
  button.className = `network-target network-${kind}`;
  if (target && !target.disabledReason) button.classList.add('targetable');
  if (target?.disabledReason) button.classList.add('target-disabled');
  if (state.selectedObject === id) button.classList.add('selected');
  button.setAttribute('aria-label', label);
  button.title = target?.disabledReason || label;
  button.append(content);
  const caption = document.createElement('span');
  caption.className = 'network-caption';
  caption.append(text(document.createElement('strong'), label));
  if (status) caption.append(text(document.createElement('small'), status));
  button.append(caption);
  button.addEventListener('click', event => { event.stopPropagation(); onObject(id); });
  return button;
}

function route(id, status, label, state, targets, onObject) {
  const target = targets.find(item => item.id === id);
  const line = document.createElement('button');
  line.type = 'button';
  line.dataset.targetId = id;
  line.className = `network-route route-${id} route-${status || 'idle'}`;
  if (target && !target.disabledReason) line.classList.add('targetable');
  if (target?.disabledReason) line.classList.add('target-disabled');
  line.setAttribute('aria-label', label);
  line.title = target?.disabledReason || label;
  line.append(text(document.createElement('span'), label));
  line.addEventListener('click', event => { event.stopPropagation(); onObject(id); });
  return line;
}

function packet(status = 'ready') {
  const wrap = document.createElement('div');
  wrap.className = `lesson1-packet packet-${status}`;
  wrap.append(image('packet-chip-v1.png', '数据包')); 
  wrap.append(text(document.createElement('span'), status === 'failed' ? '通信中断' : status === 'active' ? '传输中' : '等待测试'));
  return wrap;
}

function earlyScene(stage, state, targets, onObject) {
  const c = state.data.challenges[0];
  const group = document.createElement('div');
  group.className = 'network-layout early-layout';
  group.append(targetButton('early-terminal', '早期终端', 'device terminal-device', state, targets, onObject, image('node-device-v1.png', '早期终端'), c.terminalConnected ? '已接入' : '待接入'));
  const central = targetButton('early-central-fault', '中央计算机', 'device central-device', state, targets, onObject, image('node-device-v1.png', '中央计算机'), c.centralFailure ? '故障' : '单点核心');
  central.classList.toggle('failed', c.centralFailure);
  group.append(central);
  group.append(route('early-central-link', c.centralFailure ? 'failed' : c.connectionEstablished ? 'online' : 'idle', '终端—中央计算机', state, targets, onObject));
  const test = targetButton('early-communication-test', '通信测试台', 'test-device', state, targets, onObject, image('announcement-screen-v1.png', '通信测试台'), c.testedAfterFailure ? '故障后仍失联' : c.testedBeforeFailure ? '正常通信成功' : '等待测试');
  test.classList.toggle('failed', c.centralFailure);
  group.append(test);
  group.append(packet(c.centralFailure ? 'failed' : c.testedBeforeFailure ? 'active' : 'ready'));
  return group;
}

function protocolScene(state, targets, onObject) {
  const c = state.data.challenges[1];
  const group = document.createElement('div');
  group.className = 'network-layout protocol-layout';
  group.append(targetButton('protocol-network-a', '网络 A', 'device network-a', state, targets, onObject, image('node-device-v1.png', '网络 A'), c.protocolA));
  group.append(route('protocol-bridge', c.testedBeforeConfig && !c.protocolConfigured ? 'failed' : c.protocolConfigured && c.testedAfterConfig ? 'online' : c.protocolConfigured ? 'recovering' : c.connectionEstablished ? 'connected' : 'idle', 'A—B 协议线路', state, targets, onObject));
  group.append(targetButton('protocol-network-b', '网络 B', 'device network-b', state, targets, onObject, image('node-device-v1.png', '网络 B'), c.protocolB));
  const screen = document.createElement('div');
  screen.className = `protocol-screen ${c.protocolConfigured ? 'standardized' : ''}`;
  screen.append(image('announcement-screen-v1.png', '协议配置屏'));
  screen.append(text(document.createElement('strong'), c.protocolConfigured ? 'TCP/IP 已统一' : `${c.protocolA} ≠ ${c.protocolB}`));
  screen.append(text(document.createElement('small'), c.testedBeforeConfig ? (c.protocolConfigured ? '重新测试：可互通' : '测试失败：规则不一致') : '先运行测试观察差异'));
  group.append(screen);
  group.append(packet(c.testedAfterConfig ? 'active' : c.testedBeforeConfig ? 'failed' : 'ready'));
  return group;
}

function meshScene(state, targets, onObject) {
  const c = state.data.challenges[2];
  const group = document.createElement('div');
  group.className = 'network-layout mesh-layout';
  group.append(targetButton('mesh-node', '网状节点', 'device mesh-device', state, targets, onObject, image('node-device-v1.png', '网状节点'), c.mainLineConnected ? '已接入' : '待接入'));
  group.append(targetButton('mesh-fault-switch', '主线路故障', 'fault-device', state, targets, onObject, image('announcement-screen-v1.png', '线路故障开关'), c.mainLineFailed ? '线路已断开' : '模拟故障'));
  group.append(route('mesh-main-line', c.mainLineFailed ? 'failed' : c.mainLineEstablished ? 'online' : 'idle', '主线路', state, targets, onObject));
  group.append(route('mesh-backup-line', c.backupAdded ? 'online' : 'backup', '备用线路', state, targets, onObject));
  group.append(targetButton('mesh-receiver', '接收端', 'device mesh-receiver', state, targets, onObject, image('announcement-screen-v1.png', '接收端'), c.testedAfterBackup ? '通信恢复' : c.mainLineFailed ? '等待备用路径' : '等待通信'));
  group.append(packet(c.testedAfterBackup ? 'active' : c.mainLineFailed && !c.backupAdded ? 'failed' : 'ready'));
  return group;
}

export function createNetworkLessonScene(root, config, callbacks) {
  root.innerHTML = '<div class="mission-map lesson1-scene"><div class="lesson1-scene-title"><span></span><strong></strong><small></small></div><div class="map-stage"></div></div>';
  const map = root.querySelector('.mission-map');
  const title = root.querySelector('.lesson1-scene-title');
  const stage = root.querySelector('.map-stage');
  function render(state, actionSystem, ui = {}) {
    const index = state.data.challengeIndex;
    if (index >= challengeCopy.length) {
      stage.innerHTML = '<div class="lesson1-showcase"><img data-asset="announcement-screen" src="assets/announcement-screen-v1.png" alt="中国互联网创新成果展示"><strong>三种结构创新都被你验证了</strong><p>1987 · 1994 · 5G · 北斗</p></div>';
      return;
    }
    const [eyebrow, heading, note] = challengeCopy[index];
    title.querySelector('span').textContent = eyebrow;
    title.querySelector('strong').textContent = heading;
    title.querySelector('small').textContent = note;
    const selected = ui.selectedCard || null;
    const targets = selected ? actionSystem.legalTargets(state, selected) : [];
    const linkEndpointIds = selected === 'establish-connection'
      ? (index === 0 ? ['early-terminal', 'early-central-fault'] : index === 1 ? ['protocol-network-a', 'protocol-network-b'] : ['mesh-node', 'mesh-receiver'])
      : [];
    const selectedTargets = new Set((ui.highlightIds || []));
    const allTargets = [...targets, ...linkEndpointIds.map(id => ({ id, linkEndpoint: true })), ...[...selectedTargets].map(id => ({ id }))];
    stage.innerHTML = '';
    const scene = index === 0 ? earlyScene(stage, state, allTargets, callbacks.onObject) : index === 1 ? protocolScene(state, allTargets, callbacks.onObject) : meshScene(state, allTargets, callbacks.onObject);
    stage.append(scene);
    alignRoutes(stage, index);
    const observation = document.createElement('div');
    observation.className = 'scene-observation';
    observation.dataset.guidance = index === 0 ? 'tutorial' : 'challenge';
    observation.textContent = state.feedback?.text || observationCopy[index];
    stage.append(observation);
    map.dataset.stage = String(index);
  }
  return { root, map, render };
}
