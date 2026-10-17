export const LESSON4_PHASES = Object.freeze({
  INTRO: 'INTRO',
  WHOLE_DATA_BLOCKED: 'WHOLE_DATA_BLOCKED',
  PACKETIZATION: 'PACKETIZATION',
  FORWARDING: 'FORWARDING',
  CONGESTION: 'CONGESTION',
  DELIVERY: 'DELIVERY',
  REASSEMBLY: 'REASSEMBLY',
  SUCCESS: 'SUCCESS',
  TIMEOUT_SOFT: 'TIMEOUT_SOFT',
  ENDED: 'ENDED'
});

export const LESSON4_CONFIG = Object.freeze({
  meta: Object.freeze({
    schema_version: 3,
    course_id: 'g7-internet-application-innovation',
    curriculum_lesson_id: 'g7-internet-l04',
    task_id: 'g7-l04-campus-tabletop',
    content_version: 'g7-l04-campus-tabletop.3.0',
    task_title: '图书馆公告紧急送达',
    duration_ms: 300000,
    evidence_type: 'packet_paths_arrival_order_reassembly'
  }),
  title: '第4课 · 数据分包灵活传',
  missionTitle: '图书馆公告紧急送达',
  objective: '把公告完整送到图书馆。',
  intro: Object.freeze({
    tag: '糖果校园 · 数字任务桌',
    text: '图书馆的新通知还没完整送达。把公告送到公告屏，并恢复正确顺序。',
    firstStep: '试着先把公告送出去。'
  }),
  timeLimitMs: 300000,
  reminderMs: 255000,
  cards: Object.freeze([
    Object.freeze({
      id: 'packetize',
      label: '分包',
      icon: '✂',
      description: '把大数据拆成小包',
      rule: '选择完整公告后拆分',
      canUse: state => state.wholeAnnouncement?.status === 'blocked',
      disabledReason: () => '先让完整公告遇到容量问题。'
    }),
    Object.freeze({
      id: 'forward',
      label: '转发',
      icon: '➜',
      description: '把数据包送到下一站',
      rule: '先选包，再选合法节点',
      canUse: state => ![LESSON4_PHASES.SUCCESS, LESSON4_PHASES.ENDED].includes(state.phase),
      disabledReason: () => '当前阶段暂时不能转发。'
    }),
    Object.freeze({
      id: 'reassemble',
      label: '重组',
      icon: '▦',
      description: '按编号恢复完整数据',
      rule: '4个包到达后排序',
      canUse: state => state.reassembly?.status === 'ready' || state.reassembly?.status === 'sorting',
      disabledReason: () => '先让4个数据包到达公告屏。'
    })
  ]),
  stages: Object.freeze([
    Object.freeze({ id: LESSON4_PHASES.INTRO, label: '事件开始' }),
    Object.freeze({ id: LESSON4_PHASES.WHOLE_DATA_BLOCKED, label: '完整公告太大' }),
    Object.freeze({ id: LESSON4_PHASES.PACKETIZATION, label: '拆成数据包' }),
    Object.freeze({ id: LESSON4_PHASES.FORWARDING, label: '体验存储转发' }),
    Object.freeze({ id: LESSON4_PHASES.CONGESTION, label: '观察拥堵并换路' }),
    Object.freeze({ id: LESSON4_PHASES.DELIVERY, label: '等待所有数据包' }),
    Object.freeze({ id: LESSON4_PHASES.REASSEMBLY, label: '按编号重组' }),
    Object.freeze({ id: LESSON4_PHASES.SUCCESS, label: '公告已恢复' })
  ]),
  sceneObjects: Object.freeze([
    Object.freeze({ id: 'sender', kind: 'source', label: '校园邮局', short: '发送站' }),
    Object.freeze({ id: 'node-a', kind: 'node', label: '节点 A', short: '缓存点' }),
    Object.freeze({ id: 'node-b', kind: 'node', label: '节点 B', short: '备用点' }),
    Object.freeze({ id: 'node-c', kind: 'node', label: '节点 C', short: '备用点' }),
    Object.freeze({ id: 'receiver', kind: 'receiver', label: '图书馆公告屏', short: '目的地' })
  ]),
  routes: Object.freeze([
    Object.freeze({ id: 'sender-node-a', from: 'sender', to: 'node-a' }),
    Object.freeze({ id: 'sender-node-b', from: 'sender', to: 'node-b' }),
    Object.freeze({ id: 'sender-node-c', from: 'sender', to: 'node-c' }),
    Object.freeze({ id: 'node-a-receiver', from: 'node-a', to: 'receiver' }),
    Object.freeze({ id: 'node-b-receiver', from: 'node-b', to: 'receiver' }),
    Object.freeze({ id: 'node-c-receiver', from: 'node-c', to: 'receiver' }),
    Object.freeze({ id: 'node-a-node-b', from: 'node-a', to: 'node-b' }),
    Object.freeze({ id: 'node-a-node-c', from: 'node-a', to: 'node-c' })
  ]),
  packetDefinitions: Object.freeze([
    Object.freeze({ id: '01', text: '图书馆', color: 'cream' }),
    Object.freeze({ id: '02', text: '周五', color: 'orange' }),
    Object.freeze({ id: '03', text: '开放', color: 'blue' }),
    Object.freeze({ id: '04', text: '阅读角', color: 'purple' })
  ]),
  nodeCapacities: Object.freeze({ sender: 4, 'node-a': 2, 'node-b': 2, 'node-c': 2, receiver: 4 })
});

export default LESSON4_CONFIG;
