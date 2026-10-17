export const LESSON1_CONFIG = Object.freeze({
  title: '糖果校园 · 七年级第1课',
  missionTitle: '互联网发展靠创新',
  objective: '观察结构、规则和连接方式怎样让网络从“能用”走向“更可靠”。',
  showTour: true,
  timeLimitMs: 360000,
  progressLabel: '证据',
  progressTotal: null,
  progressSuffix: ' 条',
  cards: Object.freeze([
    Object.freeze({ id: 'connect-device', iconSprite: true, iconIndex: 0, label: '接入设备', description: '把终端或网络接入场景', rule: '点击一个待接入设备或网络' }),
    Object.freeze({ id: 'establish-connection', iconSprite: true, iconIndex: 1, label: '建立连接', description: '连接两个网络节点或线路', rule: '点击一条待连接线路' }),
    Object.freeze({ id: 'configure-protocol', iconSprite: true, iconIndex: 2, label: '配置协议', description: '让通信双方遵守同一套规则', rule: '点击协议配置板' }),
    Object.freeze({ id: 'add-backup-route', iconSprite: true, iconIndex: 3, label: '增设备路', description: '为关键线路增加备用路径', rule: '点击备用线路' }),
    Object.freeze({ id: 'run-test', iconSprite: true, iconIndex: 4, label: '运行测试', description: '观察通信结果并记录证据', rule: '点击测试点或故障模拟器' })
  ]),
  challenges: Object.freeze([
    { id: 'early', title: '早期网络', subtitle: '中央计算机的单点结构' },
    { id: 'protocol', title: '协议标准化', subtitle: '不同规则怎样互相理解' },
    { id: 'mesh', title: '网状结构', subtitle: '备用路径怎样保持通信' }
  ])
});

export default LESSON1_CONFIG;

