# Godot 四关 AI 学习实验

正式版本是 Godot 4.7.1 Web 四关连续流程。GitHub Pages 只发布
`godot/build/web`；`web-game/` 是历史实现，不再参与构建或课堂运行。

## 正式架构

- GitHub Pages：Godot Web 游戏、成人知情同意页、本地 OSS 浏览器 SDK。
- 阿里云香港函数计算：主 API，负责票据校验、扣子代理、STS 和上传确认。
- Vercel：同一后端的自动回退实例。
- 私有阿里云 OSS：按
  `studies/godot-v1/<class>/<condition>/<student>/<upload_id>/` 保存数据。

正式链接使用 v2 签名票据，包含 `study_version` 和 `active|passive`
条件。`active` 可在停滞、无进展、答错和重复失败/策略时邀请；`passive`
只在学生主动打开助手后调用同一个扣子 Bot。

参与者同意后只录制 Godot Canvas，不请求麦克风、摄像头、桌面或标签页
权限。事件逐条保存到 IndexedDB，四关完成后上传 `session.jsonl`、
`summary.json`、录像（或缺失说明）；只有服务端写入 `manifest.json` 后才
显示可以关闭页面。

## 本地验证

```powershell
Set-Location cloud/aliyun-upload-api
npm ci
npm test
Set-Location ../..
./godot/tests/run_smoke_tests.ps1
./godot/tools/export_web.ps1 -ApiBaseUrl http://127.0.0.1:8787
```

正式导出必须提供两个不同的 HTTPS API：

```powershell
./godot/tools/export_web.ps1 `
  -PrimaryApiBaseUrl https://PRIMARY.cn-hongkong.fcapp.run `
  -FallbackApiBaseUrl https://PROJECT.vercel.app `
  -StudyVersion godot-v1 -BuildVersion RELEASE_ID -ProductionMode
```

## 运维文档

- [香港函数计算部署](CLOUD_UPLOAD_DEPLOYMENT.md)
- [Vercel 回退端部署](VERCEL_UPLOAD_API_DEPLOYMENT.md)
- [隐私与成人知情同意](PRIVACY_AND_CONSENT.md)
- [Godot 运行与验收](godot/docs/mvp_runbook.md)

正式范围仅支持电脑最新版 Chrome 和 Edge，不提供手机触控适配。
