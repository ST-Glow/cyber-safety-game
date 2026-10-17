const currentTarget = (engine, state, action) => engine.legalTargets(state, action).find(item => !item.disabledReason) || null;

export function recommendLesson1(engine, state, now = Date.now()) {
  const d = state.data;
  // Proactive help teaches the interaction during the first challenge. Once
  // the player reaches the protocol and mesh challenges, the scene gives a
  // question and the player must discover the route independently. The
  // assistant remains available when the student opens it manually.
  if (d.challengeIndex !== 0) return null;
  if (d.challengeIndex === 0) {
    if (!d.challenges[0].terminalConnected) return recommendation(state, now, '先让网络有一个入口', '看看早期网络里哪个设备还没有接入。', '把观察到的设备和行动卡对应起来。', 'connect-device', ['connect-device', 'early-terminal']);
    if (!d.challenges[0].connectionEstablished) return recommendation(state, now, '连接还没有建立', '终端已经在场景里了，哪条线路能把它接到中央计算机？', '先观察线路，再让通信测试有机会发生。', 'establish-connection', ['establish-connection', 'early-central-link']);
    return recommendation(state, now, '观察中央计算机的影响', '先比较一次正常测试，再看看故障发生后通信是否还在。', '把测试前后的结果放在一起，能看见单点结构的局限。', 'run-test', ['run-test', 'early-communication-test', 'early-central-fault']);
  }
  if (d.challengeIndex === 1) {
    const c = d.challenges[1];
    if (!c.networkAConnected || !c.networkBConnected) return recommendation(state, now, '先把两张网络放到一起', '场景里有两个规则不同的网络，先检查哪一个还没有接入。', '协议差异要在两张网络连接后才会显现。', 'connect-device', ['connect-device', c.networkAConnected ? 'protocol-network-b' : 'protocol-network-a']);
    if (!c.connectionEstablished) return recommendation(state, now, '准备一条跨网络线路', '两张网络都在场景中，接下来可以连接中间的待连接线路。', '把网络连接起来，才能观察规则是否相容。', 'establish-connection', ['establish-connection', 'protocol-bridge']);
    if (!c.testedBeforeConfig) return recommendation(state, now, '先测试，再下结论', '通信失败时，看看两边使用的规则名称是否相同。', '先收集证据，再选择配置协议这张牌。', 'run-test', ['run-test', 'protocol-bridge']);
    if (!c.protocolConfigured) return recommendation(state, now, '寻找共同的规则', '两张网络已经连上，但规则 A 和规则 B 对不上。', '配置成同一套协议后，再测试一次。', 'configure-protocol', ['configure-protocol', 'protocol-bridge']);
    return recommendation(state, now, '检查协议统一后的结果', '协议已经相同了，重新运行通信测试，比较前后变化。', '同一套规则让不同网络能够互相理解。', 'run-test', ['run-test', 'protocol-bridge']);
  }
  if (d.challengeIndex === 2) {
    const c = d.challenges[2];
    if (!c.mainLineConnected) return recommendation(state, now, '先接入网状节点', '网状结构的节点还没有加入场景，先找出它。', '没有节点就没有可以增加的路径。', 'connect-device', ['connect-device', 'mesh-node']);
    if (!c.mainLineEstablished) return recommendation(state, now, '先建立主线路', '节点已经接入，看看它和接收端之间的主线路。', '先让原来的连接工作，再观察故障影响。', 'establish-connection', ['establish-connection', 'mesh-main-line']);
    if (!c.testedBeforeFailure) return recommendation(state, now, '记录主线路的正常状态', '运行一次主线路测试，记下通信是否成功。', '有了故障前的结果，才能比较备用路径的作用。', 'run-test', ['run-test', 'mesh-main-line']);
    if (!c.mainLineFailed) return recommendation(state, now, '观察单条线路的局限', '主线路现在可以模拟故障，看看消息有没有第二条路。', '先观察失败，再决定要不要增加路径。', 'run-test', ['run-test', 'mesh-fault-switch']);
    if (!c.backupAdded) return recommendation(state, now, '给网络多一条路', '主线路已经断开，场景中的备用线路正等着接入。', '冗余连接可以在一条线路出问题时继续传递消息。', 'add-backup-route', ['add-backup-route', 'mesh-backup-line']);
    return recommendation(state, now, '检查备用路径是否接管', '备用线路已经接好，重新运行测试观察通信是否恢复。', '比较主线路故障前后的测试结果。', 'run-test', ['run-test', 'mesh-backup-line']);
  }
  return null;
}

function recommendation(state, now, title, message, rationale, card, highlightIds) {
  return {
    id: `lesson1-recommendation-${state.run_id}-${state.next_event}`,
    lessonId: state.meta.curriculum_lesson_id,
    type: 'metacognitive_prompt', level: 1, triggerReason: 'adaptive_triggered', difficultyType: 'stalled_progress',
    title, message, rationale, suggestedCardId: card, suggestedPacketIds: [], suggestedTargetIds: [], highlightIds,
    stateVersion: state.task_version, createdAt: now
  };
}

