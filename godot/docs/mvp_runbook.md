# Godot DigComp 完整版运行与验收

## 运行模式

- 编辑器/本地开发构建：主菜单可进入单项、DigComp 大厅或完整流程；使用 debug 导出。
- 隔离预览：release 导出，仅供项目组内部技术测试；有效预览票据直接进入完整
  流程，不显示参与者知情同意页，研究版本 `digcomp-v1-preview`。不得向真实参与者发放。
- 正式 Web：release 导出，有效正式票据与成人同意后自动进入 DigComp 大厅，
  不显示 `(DEBUG)`，研究版本 `digcomp-v1`。
- `active`：停滞、无进展、重复失败、答题错误、重复策略均可邀请。
- `passive`：仅参与者主动打开助手时调用同一个 Bot。

四大任务为综合闯关、拼图、数据修复匹配、图像风险判断；综合闯关内部保留原
四关流程。AI 请求只上传每项的白名单数值进度，不上传正确答案、位置或客户端
指令文本。

## 自动回归

```powershell
./godot/tests/run_smoke_tests.ps1
Set-Location cloud/aliyun-upload-api
npm test
```

测试覆盖大厅、四大任务、原四关、事件、评分、支架条件、AI 服务、8 档案过滤、
录屏分块契约和 1 GiB 上限。

## Web 导出

开发 debug 导出：

```powershell
./godot/tools/export_web.ps1 -ApiBaseUrl http://127.0.0.1:8787
```

隔离预览 release 导出：

```powershell
./godot/tools/export_web.ps1 `
  -PrimaryApiBaseUrl https://PREVIEW.cn-hongkong.fcapp.run `
  -FallbackApiBaseUrl https://PREVIEW-API.vercel.app `
  -StudyVersion digcomp-v1-preview -BuildVersion PREVIEW_ID -PreviewMode
```

生产 release 导出：

```powershell
./godot/tools/export_web.ps1 `
  -PrimaryApiBaseUrl https://PRIMARY.cn-hongkong.fcapp.run `
  -FallbackApiBaseUrl https://PROJECT.vercel.app `
  -StudyVersion digcomp-v1 -BuildVersion RELEASE_ID `
  -ResearchContact research@example.org -ProductionMode
```

脚本输出到 `godot/build/web`，注入部署阶段、主/备 API、构建版本、研究邮箱、
12 个月保存期和 45 分钟设计容量，并从锁定的 `ali-oss` 依赖复制浏览器 SDK。
通过 HTTP 服务打开 WebAssembly，不能双击 `index.html`。

## 数据与上传验收

1. 同意前确认未开始录制、未写事件；拒绝后不进入游戏。
2. 同意后浏览器权限列表中没有麦克风、摄像头或屏幕共享。
3. 录像约 1.5 Mbps、30 FPS，分块写入 IndexedDB；刷新后可继续上传。
4. 四大任务完成后仅在服务端确认 `manifest.json` 后显示保存成功并清理本地块。
5. OSS 路径为
   `studies/digcomp-v1[-preview]/<class>/<condition>/<student>/<upload_id>/`。
6. 对象包含 `session.jsonl`、schema v3 `summary.json`、录像或降级说明和
   `manifest.json`。
7. 断开主 FC 或令其返回 5xx，确认 AI 与上传 API 自动切换到 Vercel。
8. 完成接近 40 分钟测试，确认录像低于 1 GiB，刷新后不会提前显示保存成功。

正式验收在最新版桌面 Chrome、Edge 各跑 active/passive 一条。手机和触控不在
本次范围。
