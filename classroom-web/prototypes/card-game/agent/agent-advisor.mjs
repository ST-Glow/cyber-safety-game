import { createRecommendation } from './recommendation.mjs';

// Pure advisor: receives a detached snapshot, never the mutable lesson model.
export function advise(snapshot, unused = null, now = Date.now()) {
  const level = snapshot.difficultyState?.adviceLevel || 1;
  const difficultyType = snapshot.difficultyState?.type || 'stalled_progress';
  const sorting = ['ready', 'sorting'].includes(snapshot.reassemblyState?.status);
  const whole = !snapshot.wholeAnnouncementState?.packetized;
  const packet = snapshot.packets.find(p => !p.delivered && p.movableTargets.length);
  const node = packet?.movableTargets[0];
  const congested = Object.values(snapshot.routes || {}).some(r => r.status === 'congested');
  let card = sorting ? 'reassemble' : whole && snapshot.availableCards.includes('packetize') ? 'packetize' : 'forward';
  let message, title, rationale, type = 'metacognitive_prompt';
  if (sorting) {
    title = '观察编号与顺序';
    message = level === 1 ? '这些包上有没有能帮你判断顺序的信息？' : level === 2 ? '比较编号和当前排列，看看哪里需要调整。' : '可以先把01放在最前面，再检查后面的包。';
    rationale = '到达顺序可能不同，编号保留了原公告的先后关系。';
  } else if (whole) {
    title = '看看公告和节点';
    message = level === 1 ? '公告留在原地了，节点为什么装不下它？' : level === 2 ? '看看「分包」能不能让公告变小。' : card === 'packetize' ? '可以试试「分包」，再点这张完整公告。' : '先选「转发」，点完整公告，再选一个节点。';
    rationale = '节点容量有限，小包可以分别缓存和传输。';
  } else if (difficultyType === 'operation_confusion') {
    type = 'operation_help'; title = '先看手牌';
    message = '先选一张行动牌，再点数据包和一个高亮目标。';
    rationale = '一张牌表示一个动作，目标决定动作作用在哪里。';
  } else {
    title = congested ? '还有哪些路线能走？' : '找一个能推进的包';
    message = level === 1 ? (congested ? 'A现在是什么状态？旁边还有没有空的位置？' : '先看看哪个包还没送达，它现在能去哪？') :
      level === 2 ? '可以继续用「转发」，观察还有空位的下一站。' :
      packet ? '可以试试把' + packet.id + '号包转发到' + (node === 'receiver' ? '公告屏' : node.replace('node-', '').toUpperCase() + '站') + '。' : '先检查还有哪个数据包没有到达。';
    rationale = '节点先缓存数据，再转发到下一站；拥堵时可以观察其他路径。';
    if (level > 1) type = 'task_feedback';
  }
  const highlighted = sorting ? ['receiver', 'reassemble'] : whole ? [card, 'whole-announcement'] :
    [card, ...(packet ? ['packet-' + packet.id, ...(node ? [node, packet.currentNode + '-' + node] : [])] : [])];
  const context = {run_id:snapshot.runId, next_event:snapshot.nextEvent, meta:{curriculum_lesson_id:snapshot.lessonId},
    task_version:snapshot.taskVersion, difficultyState:snapshot.difficultyState};
  return createRecommendation({state:context, type, level, triggerReason:'adaptive_triggered', difficultyType,
    title, message, rationale, suggestedCardId:card,
    suggestedPacketIds: packet && !sorting && !whole ? [packet.id] : [],
    suggestedTargetIds: node && !sorting && !whole ? [node] : [], highlightIds:highlighted, now});
}

