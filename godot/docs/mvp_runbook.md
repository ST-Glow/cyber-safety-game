# AI训练场大挑战：运行与验收手册

## 当前入口与运行模式

- F5 运行 `res://scenes/main_menu.tscn`，可选择四个单关或“派对流程”。
- 单关模式结算后返回主菜单；派对流程从第一关开始，依次串联四关并在最终关展示汇总。
- F6 仍可直接运行当前关卡场景，默认按单关模式处理。
- 所有关卡结果统一使用 0–100 分、`score_schema_version = 2`；运行 HUD 显示“过程表现 /40”，结算显示“综合评分 /100”。

完整自动回归从项目根目录运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\godot\tests\run_smoke_tests.ps1
```

测试入口支持 `-GodotExe <path>`、`GODOT4_BIN`，最后回退到文档化的 Godot 4.7.1 路径。当前套件包含 9 项冒烟测试。

## 当前范围

这个版本实现一个约 1–2 分钟的第三人称 3D 赛段：Ranger 角色移动、跳跃、冲刺、旋转扫杆、三道升降门、倾斜软桥、碰撞或跌落复位、一道生成式 AI 单选题和结算。

暂未加入录像、上传、学生编号、IndexedDB、智能体网络调用和正式三赛段内容。右下角的 AI 助手仅用于验证暂停交互。

## 运行与操作

在 Godot 4.7.1 中打开 `project.godot` 并运行主场景。

- `WASD` 或方向键：相对摄像机移动
- `Space`：跳跃
- `Shift`：冲刺 220 ms，2.5 倍速度，冷却 2.5 秒
- 鼠标或数字键 `1`、`2`、`3`：选择答案

## 自动化检查

```powershell
& 'E:\浏览器下载\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe' --headless --path 'D:\大学\游戏项目开发\godot' --script 'res://tests/mvp_smoke_test.gd'
```

成功标志为 `MVP_SMOKE_TEST_OK`。测试覆盖 34 个断言，包括方向、跳跃高度、冲刺、暂停、机关相位、跌落、复位、答题、评分和结算字段。

## Web 导出

项目使用 Compatibility 渲染器和无多线程 Web 模板。导出命令：

```powershell
& 'E:\浏览器下载\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe' --headless --path 'D:\大学\游戏项目开发\godot' --export-debug 'Web' 'D:\大学\游戏项目开发\godot\build\web\index.html'
```

不要直接双击 `index.html` 验证 WebAssembly；请在 `build/web` 上启动本地 HTTP 服务后访问。当前导出已经在 1280×720、1366×768 和 1920×1080 视口验证，Canvas 覆盖完整视口，中文字体离线可用，浏览器控制台无警告或错误。

## 后续数据接口

`GameManager` 已提供以下信号：

- `run_started`
- `jump_used`
- `dash_used`
- `obstacle_hit`
- `player_respawned`
- `quiz_answered`
- `run_completed(result)`

`run_completed` 的结果包含 `elapsed_seconds`、`obstacle_hits`、`falls`、`quiz_attempts`、`score` 和 `stars`，后续录像与实验数据模块可以只监听这些接口，不需要修改关卡玩法。

## 测试环境说明

项目关闭了 Godot 的文件日志输出，避免受限环境无法写入 `AppData` 时触发日志轮转错误；控制台输出和自动化测试结果不受影响。需要恢复本地日志时，应先确认 `user://logs` 可写，再重新启用 `debug/file_logging/enable_file_logging.pc`。
