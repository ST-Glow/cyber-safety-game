# 隐私核心护送行动

这是面向教师现场演示的 3–5 分钟单关 Web 游戏。玩家护送隐私核心穿过网络安全训练基地，收集三枚隐私密钥、避开巡逻机器人，并在安全终端完成一次综合判断。

## 启动

在 `web-game` 目录运行：

```powershell
python -m http.server 4173 --bind 127.0.0.1
```

然后打开 `http://127.0.0.1:4173/`。

## 操作

- `WASD` 或方向键：移动并护送隐私核心。
- `Space`：开启 2.5 秒隐私护盾，冷却 6 秒。
- 依次收集三枚隐私密钥，到达安全终端后完成最终决策。
- 未开盾接触巡逻机器人会扣 10 分并回到最近检查点，不会死亡。

## 演示流程

- 点击开始后自动生成 `DEMO-XXXX` 匿名编号，不显示前测或后测。
- 浏览器会请求共享当前游戏标签页，用于录制 HUD、地图、终端和智能体抽屉；拒绝后自动退回 Canvas 录像。
- 12 秒无有效操作，或连续两次风险接触，会弹出强制选择抽屉。
- 选择“我需要提示”后接入 Coze；不记录 token 和聊天内容。
- 正式学生链接会携带教师预分配的匿名编号和签名票据。
- 通关后自动上传 `session.jsonl`、`summary.json` 和录像；三份文件经服务端确认后才提示可以关闭页面。
- 网络失败时任务保存在 IndexedDB，并自动重试或在下次打开同一链接时继续上传。

## 采集事件

- 基础流程：`session_started`、`level_started`、`session_completed`
- 行为轨迹：`player_move_sample`、`click`、`activity`
- 玩法事件：`clue_collected`、`checkpoint_reached`、`patrol_detected`、`risk_contacted`
- 护盾事件：`shield_activated`、`shield_blocked`
- 决策事件：`terminal_locked`、`terminal_opened`、`terminal_answer`、`wrong_attempt`
- 完成评价：`level_completed`、`mission_completed`、`demo_score`
- 智能体介入：`idle_or_stuck_episode`、`agent_overlay_opened`、`agent_choice`、`agent_overlay_closed`、`intervention_recovered`

`summary.json` 保留兼容字段 `pretest_score: null`、`posttest_score: null`，并明确标注 `pretest_removed` 和 `posttest_removed`。

## 录像格式

录像优先使用 MP4/H.264；浏览器不支持时自动使用 WebM/VP8。浏览器必须按真实编码扩展名下载，不能只修改文件后缀。

调试视觉效果时可以打开 `http://127.0.0.1:4173/?recording=off`，跳过标签页共享提示；正式演示不要使用该参数。

仅调试玩法且不连接上传服务时，可以增加 `upload=off`。无备案的正式部署步骤见根目录 `VERCEL_UPLOAD_API_DEPLOYMENT.md`。
