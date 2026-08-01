# 旋转障碍冲刺（spinner_race）

## 运行方式

- 在 Godot 编辑器中打开 `scenes/levels/spinner_race/spinner_race.tscn`，按 **F6** 运行当前场景。
- 项目的默认主场景仍是 `scenes/main.tscn`。按 **F5** 从第一关开始，完成AI选择题后点击“进入下一关”，会切换到本关卡。
- Web 导出资源清单已包含本关卡及其可复用机关；后续接入关卡选择页时无需移动场景文件。

## 操作与规则

- WASD / 方向键：移动
- Space：跳跃
- Shift：冲刺
- 3 秒倒计时结束后才能移动，限时 90 秒。
- 掉落会在最近检查点重生，计时不会重置。
- 四个检查点都会弹出一道AI三选一题。答题时计时与机关暂停，答对后才会激活并保存检查点；答错会显示解释并允许重选。
- 到达终点或倒计时结束后立即结算；结算显示用时、掉落次数和检查点进度。

## 关卡组成

1. 不同高度的基础跳台
2. 圆形平台与可复用旋转横杆
3. 两个固定周期的可复用移动平台
4. 三个固定周期的可复用左右推板
5. 宽阔安全路线与带高速旋转杆的危险捷径

检查点题目依次覆盖：AI能力边界、有效指令、事实核验和综合应用。

主要场景与脚本：

- `scenes/levels/spinner_race/spinner_race.tscn`
- `scripts/levels/spinner_race/spinner_race.gd`
- `scenes/obstacles/moving_platform.tscn`
- `scenes/obstacles/side_pusher.tscn`
- `scenes/obstacles/rotating_sweeper.tscn`

## 回归测试

```powershell
& "E:\浏览器下载\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe" --headless --path "D:\大学\游戏项目开发\godot" --script "res://tests/spinner_race_smoke_test.gd"
& "E:\浏览器下载\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe" --headless --path "D:\大学\游戏项目开发\godot" --script "res://tests/level_flow_smoke_test.gd"
& "E:\浏览器下载\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe" --headless --path "D:\大学\游戏项目开发\godot" --script "res://tests/mvp_smoke_test.gd"
```
