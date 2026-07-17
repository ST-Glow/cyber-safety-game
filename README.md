# 小学生网络安全保护游戏

这是一个 Unity Windows 桌面端课堂实验原型，面向小学 5-6 年级，主题为“个人信息保护”。当前实现重点是研究闭环：匿名进入、前测、游戏任务、后测、行为日志、游戏画面录制、Coze 介入适配、离线缓存与自动上传。

## 打开方式

1. 使用 Unity 6 或 Unity 2022 LTS 以上版本打开本目录。
2. 等待 Unity 安装 `Input System` 和 `uGUI` 包。
3. 在 Unity 菜单中执行 `Cyber Safety/Create Prototype Scene`。
4. 打开生成的 `Assets/Scenes/Main.unity`，点击 Play。

## 当前功能

- 匿名学生编号进入，不采集姓名、手机号、头像等真实身份。
- 前测 - 游戏任务 - 后测流程。
- 中间任务段是 2D 俯视闯关：使用 WASD 或方向键移动角色，收集黄色安全线索，避开红色风险点，到蓝色终端完成判断。
- 当前美术使用 `Assets/StreamingAssets/art/` 中的儿童向临时素材：玩家角色、机器人助手、线索、风险、终端等。后续可以替换为正式商用资产包。
- 行为事件写入 JSONL：点击、移动、题目选择、错误尝试、停滞、介入、完成等。
- 30 秒无有效操作触发 `idle_or_stuck_episode`。
- 默认 30 秒停滞时会自动打开 `Assets/StreamingAssets/coze-agent/agent.html` 中的 Coze 智能体页面；学生恢复操作后，下次再次停滞可再次触发。
- Coze 介入通过 `InterventionAgentClient` 抽象，默认用 mock，正式环境建议由自有后端转发到 Coze。
- 录屏只录 Unity 游戏画面，不录桌面、麦克风或摄像头。
- 数据先写入本地，再按配置上传服务器。

## 本地数据

运行数据默认保存在：

`Application.persistentDataPath/CyberSafetyResearch/sessions/<session_id>/`

每个 session 包含：

- `session.jsonl`：事件流。
- `summary.json`：会话摘要。
- `recording.mp4`：如果找到 FFmpeg，会生成 MP4。
- `frames/`：如果 FFmpeg 不可用，会退化为 PNG 帧序列。

## 录屏依赖

发布版 MP4 录制需要 FFmpeg。将 `ffmpeg.exe` 放到：

`Assets/StreamingAssets/ffmpeg/bin/ffmpeg.exe`

如果没有 FFmpeg，游戏仍会运行，并自动保存低帧率 PNG 帧序列，方便测试数据链路。

## 重要隐私约束

本项目默认只采集研究所需的最少数据。课堂实验前应准备学校/监护人知情同意材料，说明采集目的、范围、保存期限和删除方式。详见 `PRIVACY_AND_CONSENT.md`。
