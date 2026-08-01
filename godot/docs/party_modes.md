# 多玩法派对关卡

当前流程为：基础训练关 → 旋转障碍冲刺 → AI芯片收集赛 → 信号炸弹生存赛 → 综合结算。

## AI芯片收集赛

- 场景：`res://scenes/levels/data_chip_hunt/data_chip_hunt.tscn`
- 3秒倒计时，75秒内收集12枚芯片。
- 三条路线分别使用坡道、弹簧圆环和移动平台。
- 第6枚与第12枚芯片触发三选一题；答题时计时与机关暂停。
- 掉落回到中央检查点，已收集芯片不会恢复。

## 信号炸弹生存赛

- 场景：`res://scenes/levels/signal_bomb_survival/signal_bomb_survival.tscn`
- 3秒倒计时，完成固定60秒生存即成功，不设置淘汰。
- 0–20秒为定轨彩球，20–40秒加入扫杆与推板，40–60秒加入定时炸弹。
- 第20秒与第40秒触发三选一题；答题时波次相位完全停止。
- 受击推力和连续受击均有上限，掉落后在竞技场中心重生且计时继续。

## 回归命令

```powershell
& "E:\浏览器下载\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe" --headless --path "D:\大学\游戏项目开发\godot" --script "res://tests/data_chip_hunt_smoke_test.gd"
& "E:\浏览器下载\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe" --headless --path "D:\大学\游戏项目开发\godot" --script "res://tests/signal_bomb_survival_smoke_test.gd"
& "E:\浏览器下载\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe" --headless --path "D:\大学\游戏项目开发\godot" --script "res://tests/level_flow_smoke_test.gd"
```
