# 统一卡牌任务底座（实验性）

这个目录把“选行动卡 → 选对象 → 选目标 → 看到后果 → 检查/交付”的交互循环抽成最小底座。第4课原型继续使用自己的 `model.mjs`，作为已验证垂直切片的行为基线；本目录不复制第4课规则。

## 课程适配器

- `lesson4-reference`：只登记第4课已有模型、牌桌区域和学习证据。
- `lesson9`：可靠传输、实时传输、端口和丢包恢复。
- `lesson17`：HTML 元素、预览和真实 HTML 产物。
- `lesson27`：个人信息、受众、元数据、来源不明内容和风险检查。

适配器提供场景对象、行动牌、合法目标、状态变化、错误反馈、完成条件和学习证据。底座只负责生命周期、撤销、保存/恢复、事件记录和通用时间状态。

## 使用方式

```js
import { createCardTaskEngine } from './core.mjs';
import { lesson17Adapter } from './adapters/lesson17.mjs';

const engine = createCardTaskEngine(lesson17Adapter);
const state = engine.createState();
engine.applyAction(state, 'set-heading', 'heading', 'heading');
```

网页和安全课程不是第4课网络图的换皮：它们仍然使用相同的卡牌选择手感，但中央对象、行动结果和交付证据由适配器定义。

## 阶段 B 契约

legalTargets() 返回 { type, id, label, disabledReason? } 描述；引擎会在调用适配器前检查目标，并把禁用原因记录为可理解的反馈。适配器的成功行动可以通过 invalidateDerived() 使旧的预览、风险检查或实验结论失效。

快照包含行动卡 schema、课程版本、累计用时、事件记录、撤销栈和课程数据。恢复会拒绝负时间、伪造完成、无效事件、行动卡版本不一致和不通过适配器校验的课程对象。适配器可通过 artifact(state) 提供学生可以下载或复核的作品证据。

第9课保留文件丢包到发现缺口、请求重传的真实链条，并单独记录直播的延迟与丢帧后果；第17课预览绑定对象 revision，任何对象修改都会让旧预览失效，并提供离线 srcdoc 与 HTML 下载证据；第27课先识别风险，再做受众预览和复核，“暂不分享”会产生安全停止结果而不会伪装成公开发布。
