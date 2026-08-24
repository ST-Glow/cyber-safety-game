# Godot 四关版运行与验收

## 运行模式

- 编辑器/本地非生产构建：主菜单可选四个单关或四关连续流程，F6 可直跑单关。
- 正式 Web 构建：有效 v2 票据 + 成人同意后自动进入四关连续流程，不显示单关菜单。
- `active`：停滞、无进展、重复失败、答题错误、重复策略均可邀请。
- `passive`：仅学生主动打开助手时调用同一个 Bot。

## 自动回归

```powershell
./godot/tests/run_smoke_tests.ps1
```

测试入口固定兼容 Godot 4.7.1，并覆盖主菜单、四关流程、事件、评分、支架
条件与 AI 服务。后端测试从 `cloud/aliyun-upload-api` 运行 `npm test`。

## Web 导出

开发导出：

```powershell
./godot/tools/export_web.ps1 -ApiBaseUrl http://127.0.0.1:8787
```

生产导出：

```powershell
./godot/tools/export_web.ps1 `
  -PrimaryApiBaseUrl https://PRIMARY.cn-hongkong.fcapp.run `
  -FallbackApiBaseUrl https://PROJECT.vercel.app `
  -StudyVersion godot-v1 -BuildVersion RELEASE_ID -ProductionMode
```

脚本会导出 `godot/build/web`，注入主/备 API 与构建版本，并从已锁定的
`ali-oss` npm 依赖复制浏览器 SDK；产物不依赖外部 CDN。请通过 HTTP 服务
打开 WebAssembly，不能双击 `index.html`。

## 数据与上传验收

1. 同意前确认未开始录制、未写事件；拒绝后不进入游戏。
2. 同意后浏览器权限列表中没有麦克风、摄像头或屏幕共享。
3. 刷新页面后确认 IndexedDB 中的待上传包可以续传。
4. 四关完成后仅在服务端确认 `manifest.json` 后显示保存成功。
5. OSS 路径为
   `studies/godot-v1/<class>/<condition>/<student>/<upload_id>/`，包含四个对象。
6. 断开主 FC 或令其返回 5xx，确认 AI 与上传 API 自动切换到 Vercel。

正式验收在最新版桌面 Chrome、Edge 各跑 active/passive 一条。手机和触控
不在本次范围。
