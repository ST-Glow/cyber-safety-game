# DigComp AI 学习实验

正式版本是 Godot 4.7.1 Web DigComp 完整版。参与者从 DigComp 大厅依次完成
四大任务：综合闯关、拼图、数据修复匹配和图像风险判断。GitHub Pages 只发布
`godot/build/web`；`web-game/`、`tmp/` 和本地演示服务是历史/开发材料，不参与发布。

## 正式架构

- GitHub Pages：Godot Web 游戏、成人知情同意页和本地 OSS 浏览器 SDK。
- 阿里云香港函数计算：主 API，负责票据校验、扣子代理、STS 和上传确认。
- Vercel：同一后端的自动回退实例。
- 私有阿里云 OSS：按
  `studies/<study_version>/<class>/<condition>/<student>/<upload_id>/` 保存数据。

预览固定使用 `digcomp-v1-preview`，正式固定使用 `digcomp-v1`，两套环境使用
不同的 `UPLOAD_LINK_SECRET`。正式链接使用 v2 签名票据，包含
`study_version` 和 `active|passive` 条件。`active` 可在停滞、无进展、答错和
重复失败/策略时邀请；`passive` 只在学生主动打开助手后调用同一个扣子 Bot。

参与者同意后只录制 Godot Canvas，不请求麦克风、摄像头、桌面或标签页权限。
录像约 1.5 Mbps、30 FPS，分块暂存 IndexedDB；事件逐条保存到 IndexedDB。
四大任务完成后上传 `session.jsonl`、schema v3 的 `summary.json`、录像（或降级
说明）；只有服务端写入 `manifest.json` 后才清理本地数据并显示可以关闭页面。

## 本地验证

```powershell
Set-Location cloud/aliyun-upload-api
npm ci
npm test
Set-Location ../..
./godot/tests/run_smoke_tests.ps1
./godot/tools/export_web.ps1 -ApiBaseUrl http://127.0.0.1:8787
```

隔离预览和正式导出都使用 Godot release 模式，并要求主、备 API 不同：

```powershell
./godot/tools/export_web.ps1 `
  -PrimaryApiBaseUrl https://PREVIEW.cn-hongkong.fcapp.run `
  -FallbackApiBaseUrl https://PREVIEW-API.vercel.app `
  -StudyVersion digcomp-v1-preview -BuildVersion PREVIEW_ID -PreviewMode

./godot/tools/export_web.ps1 `
  -PrimaryApiBaseUrl https://PRIMARY.cn-hongkong.fcapp.run `
  -FallbackApiBaseUrl https://PROJECT.vercel.app `
  -StudyVersion digcomp-v1 -BuildVersion RELEASE_ID `
  -ResearchContact research@example.org -ProductionMode
```

## 运维文档

- [发布准备清单](DEPLOYMENT_READINESS.md)
- [香港函数计算部署](CLOUD_UPLOAD_DEPLOYMENT.md)
- [Vercel 回退端部署](VERCEL_UPLOAD_API_DEPLOYMENT.md)
- [隐私与成人知情同意](PRIVACY_AND_CONSENT.md)
- [Godot 运行与验收](godot/docs/mvp_runbook.md)

正式范围仅支持年满 18 岁的桌面最新版 Chrome 和 Edge 用户，预计完成时间
20–40 分钟，数据保存 12 个月。
