function packetChip(packet, selectedObject, targetIds, onObject) {
  const button = document.createElement('button');
  button.type = 'button';
  button.className = 'packet-chip packet-' + packet.color + (selectedObject === 'packet-' + packet.id ? ' selected' : '') + (targetIds.has('packet-' + packet.id) ? ' targetable' : '');
  button.dataset.targetId = 'packet-' + packet.id;
  button.innerHTML = '<span class="packet-number">' + packet.id + '</span><span class="packet-text"></span><small></small>';
  button.querySelector('.packet-text').textContent = packet.text;
  button.querySelector('small').textContent = packet.status === 'arrived' ? '已到达' : packet.status === 'blocked' ? '拥堵' : packet.area === 'sender' ? '待出发' : '缓存';
  button.addEventListener('click', event => {
    event.stopPropagation();
    onObject('packet-' + packet.id);
  });
  return button;
}

export function renderSceneObject(object, state, targetIds, selectedObject, onObject) {
  const node = document.createElement('article');
  node.className = 'scene-object object-' + object.kind + (targetIds.has(object.id) ? ' targetable' : '') + (state.selectedObject === object.id ? ' selected' : '');
  node.dataset.targetId = object.id;
  const title = document.createElement('div');
  title.className = 'object-heading';
  title.innerHTML = '<span class="object-pin"></span><strong></strong><small></small>';
  title.querySelector('strong').textContent = object.label;
  title.querySelector('small').textContent = object.short;
  node.append(title);
  if (object.kind === 'receiver') {
    const received = state.arrivalOrder.length;
    const screen = document.createElement('div');
    screen.className = 'notice-board';
    screen.innerHTML = '<span class="notice-label">图书馆公告</span><strong>' + (state.missionStatus === 'success' ? '图书馆周五开放阅读角' : '图书馆 ' + '□ '.repeat(4 - Math.min(received, 4))) + '</strong><small>' + (received ? received + '/4 已到达' : '等待数据包') + '</small>';
    node.append(screen);
  }
  const stack = document.createElement('div');
  stack.className = 'packet-stack';
  if (object.kind === 'source' && state.wholeAnnouncement?.status !== 'packetized') {
    const announcement = document.createElement('button');
    announcement.type = 'button';
    announcement.className = 'announcement-token' + (targetIds.has('whole-announcement') ? ' targetable' : '') + (selectedObject === 'whole-announcement' ? ' selected' : '');
    announcement.dataset.targetId = 'whole-announcement';
    announcement.innerHTML = '<strong></strong><small>完整公告 · 体积太大</small>';
    announcement.querySelector('strong').textContent = state.wholeAnnouncement?.text || '图书馆公告';
    announcement.addEventListener('click', event => { event.stopPropagation(); onObject('whole-announcement'); });
    stack.append(announcement);
  }
  Object.values(state.packets)
    .filter(packet => packet.area === object.id)
    .filter(packet => state.tutorialStage !== 0 || packet.id === '01')
    .forEach(packet => stack.append(packetChip(packet, selectedObject, targetIds, onObject)));
  node.append(stack);
  if (object.kind === 'node') {
    const capacity = state.nodes[object.id]?.capacity || 0;
    const count = Object.values(state.packets).filter(packet => packet.area === object.id).length;
    const stateLabel = state.nodes[object.id]?.status === 'congested' ? '出口拥堵' : count ? '缓存中' : '空闲';
    const meta = document.createElement('div');
    meta.className = 'node-meta';
    meta.innerHTML = '<span>' + stateLabel + '</span><b>' + count + '/' + capacity + '</b>';
    node.append(meta);
  }
  node.addEventListener('click', () => onObject(object.id));
  return node;
}
