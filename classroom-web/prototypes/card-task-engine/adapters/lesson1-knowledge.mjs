// Lesson 1 only: two concepts and two explanations per checkpoint. The other
// explanation is the distractor; no extra cards or position-based answer cues.
export const KNOWLEDGE_CHECKPOINTS = Object.freeze([
  {
    id: 'early', title: '刚才的中断说明了什么？',
    pairs: [
      { id: 'single-point', concept: '单点故障', explanation: '核心设备停止后，依赖它的网络可能一起中断' },
      { id: 'central-structure', concept: '中央计算机结构', explanation: '多个终端依赖同一个核心设备' }
    ],
    mismatch: {
      'single-point': '这张解释描述的是设备之间的依赖关系。再想想：“故障”强调的是核心停止后造成的影响。',
      'central-structure': '这张解释描述的是故障后果。“结构”强调的是终端平时怎样连接和依赖核心。'
    }
  },
  {
    id: 'protocol', title: '连得上，为什么还需要共同规则？',
    pairs: [
      { id: 'communication-protocol', concept: '通信协议', explanation: '通信双方共同遵守的规则' },
      { id: 'standardization', concept: '协议标准化', explanation: '让规则不同的网络能够互相理解' }
    ],
    mismatch: {
      'communication-protocol': '这张解释强调统一规则带来的效果。“协议”本身指的是双方遵守的规则。',
      'standardization': '这张解释说明什么是协议。再回想：统一两边的规则之后，通信结果发生了什么变化？'
    }
  },
  {
    id: 'mesh', title: '多一条路，为什么更可靠？',
    pairs: [
      { id: 'backup-path', concept: '备用路径', explanation: '主线路断开后仍有另一条线路可以传递消息' },
      { id: 'redundancy', concept: '冗余连接', explanation: '增加替代路径，提高网络可靠性' }
    ],
    mismatch: {
      'backup-path': '这张解释讲的是整体设计的作用。“备用路径”强调故障后由哪条路接替传递消息。',
      'redundancy': '这张解释讲的是备用线路怎样接替工作。“冗余连接”强调用替代路径提高整体可靠性。'
    }
  }
]);

export function createKnowledgeState() {
  return {
    current: null,
    evidence: [],
    checkpoints: KNOWLEDGE_CHECKPOINTS.map(({ id }) => ({
      id, status: 'pending', order: [], matched: [], attempts: [], selected: null
    }))
  };
}

const cardIds = index => KNOWLEDGE_CHECKPOINTS[index].pairs.flatMap(pair => [`concept:${pair.id}`, `explanation:${pair.id}`]);
const isIndex = index => Number.isInteger(index) && index >= 0 && index < KNOWLEDGE_CHECKPOINTS.length;

export function activateKnowledge(knowledge, index, random = Math.random) {
  if (!isIndex(index) || knowledge.current !== null || knowledge.checkpoints[index].status !== 'pending') return false;
  const checkpoint = knowledge.checkpoints[index];
  const order = cardIds(index);
  for (let i = order.length - 1; i > 0; i--) {
    const j = Math.floor(random() * (i + 1));
    [order[i], order[j]] = [order[j], order[i]];
  }
  checkpoint.order = order;
  checkpoint.status = 'active';
  knowledge.current = index;
  return true;
}

export function selectKnowledgeConcept(knowledge, id) {
  if (knowledge.current === null) return false;
  const checkpoint = knowledge.checkpoints[knowledge.current];
  if (checkpoint.status !== 'active' || checkpoint.matched.includes(id)
    || !KNOWLEDGE_CHECKPOINTS[knowledge.current].pairs.some(pair => pair.id === id)) return false;
  checkpoint.selected = checkpoint.selected === id ? null : id;
  return true;
}

export function attemptKnowledgePair(knowledge, explanationId) {
  if (knowledge.current === null) return { ok: false, events: [] };
  const index = knowledge.current;
  const checkpoint = knowledge.checkpoints[index];
  const definition = KNOWLEDGE_CHECKPOINTS[index];
  const conceptId = checkpoint.selected;
  if (checkpoint.status !== 'active' || !conceptId || checkpoint.matched.includes(explanationId)
    || !definition.pairs.some(pair => pair.id === explanationId)) return { ok: false, events: [] };
  const correct = conceptId === explanationId;
  const attempt = { conceptId, explanationId, correct };
  checkpoint.attempts.push(attempt);
  knowledge.evidence.push({ type: 'knowledge_pair_attempted', checkpoint: definition.id, challenge: index, ...attempt, attempt: checkpoint.attempts.length });
  if (correct) {
    checkpoint.matched.push(conceptId);
    checkpoint.selected = null;
  }
  const detail = { checkpoint: definition.id, challenge: index, ...attempt, attempt: checkpoint.attempts.length };
  const events = [{ type: 'knowledge_pair_attempted', detail }];
  if (checkpoint.matched.length === definition.pairs.length) {
    checkpoint.status = 'completed';
    knowledge.evidence.push({ type: 'knowledge_match_completed', checkpoint: definition.id, challenge: index, attempts: checkpoint.attempts.length, matched: [...checkpoint.matched] });
    events.push({ type: 'knowledge_match_completed', detail: { checkpoint: definition.id, challenge: index, attempts: checkpoint.attempts.length, matched: [...checkpoint.matched] } });
  }
  return {
    ok: true, correct, conceptId, explanationId, events,
    text: correct
      ? checkpoint.status === 'completed' ? '两组知识已经整理好。带着这些发现，继续探索吧！' : '配对正确！再找出另一组对应关系。'
      : definition.mismatch[conceptId]
  };
}

export function dismissKnowledge(knowledge, reason = 'continue') {
  if (knowledge.current === null) return { ok: false, events: [] };
  const index = knowledge.current;
  const checkpoint = knowledge.checkpoints[index];
  const events = [];
  if (checkpoint.status !== 'completed') {
    checkpoint.status = 'skipped';
    events.push({ type: 'knowledge_match_skipped', detail: {
      checkpoint: checkpoint.id, challenge: index, reason,
      attempts: checkpoint.attempts.length, matched: [...checkpoint.matched]
    } });
    knowledge.evidence.push({ type: 'knowledge_match_skipped', checkpoint: checkpoint.id, challenge: index, attempts: checkpoint.attempts.length, matched: [...checkpoint.matched], reason });
  }
  checkpoint.selected = null;
  knowledge.current = null;
  return { ok: true, events };
}

// Replay attempts when validating a backup: completion must follow actual
// correct pairs, not an untrusted "completed" flag or a count in the UI.
export function validateKnowledgeState(knowledge, challengeIndex) {
  if (!knowledge || (knowledge.current !== null && !isIndex(knowledge.current))
    || !Array.isArray(knowledge.evidence) || !Array.isArray(knowledge.checkpoints) || knowledge.checkpoints.length !== 3) return false;
  return knowledge.checkpoints.every((checkpoint, index) => {
    const definition = KNOWLEDGE_CHECKPOINTS[index];
    const ids = definition.pairs.map(pair => pair.id);
    if (!checkpoint || checkpoint.id !== definition.id || !['pending', 'active', 'completed', 'skipped'].includes(checkpoint.status)
      || !Array.isArray(checkpoint.order) || !Array.isArray(checkpoint.matched) || !Array.isArray(checkpoint.attempts)
      || (checkpoint.selected !== null && !ids.includes(checkpoint.selected))) return false;
    const matched = [];
    for (const attempt of checkpoint.attempts) {
      if (!attempt || !ids.includes(attempt.conceptId) || !ids.includes(attempt.explanationId)
        || matched.includes(attempt.conceptId) || matched.includes(attempt.explanationId)
        || attempt.correct !== (attempt.conceptId === attempt.explanationId)) return false;
      if (attempt.correct) matched.push(attempt.conceptId);
    }
    if (JSON.stringify(matched) !== JSON.stringify(checkpoint.matched)) return false;
    if (checkpoint.status === 'pending') return checkpoint.order.length === 0 && matched.length === 0
      && checkpoint.attempts.length === 0 && checkpoint.selected === null && knowledge.current !== index;
    if (index >= challengeIndex || checkpoint.order.length !== 4 || new Set(checkpoint.order).size !== 4
      || !checkpoint.order.every(id => cardIds(index).includes(id))) return false;
    if (checkpoint.status === 'active' && (knowledge.current !== index || matched.length === 2)) return false;
    if (knowledge.current === index && (index !== challengeIndex - 1 || !['active', 'completed'].includes(checkpoint.status))) return false;
    if ((checkpoint.status === 'completed') !== (matched.length === 2)) return false;
    return checkpoint.selected === null || (checkpoint.status === 'active' && !matched.includes(checkpoint.selected));
  });
}
