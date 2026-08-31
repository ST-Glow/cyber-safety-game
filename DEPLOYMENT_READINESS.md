# DigComp v1 发布准备清单

## 已在代码中完成

- 8 个服务端 AI 档案与新任务数值状态白名单；客户端指令和答案信息被丢弃。
- `digcomp-v1-preview` / `digcomp-v1` 数据前缀隔离和不同密钥的部署约束。
- schema v2 事件兼容、schema v3 DigComp 总结、录像元数据。
- Canvas-only 录屏，约 1.5 Mbps / 30 FPS / 1 GiB，IndexedDB 分块与
  `manifest.json` 后清理。
- 预览/正式 release 导出，开发 debug 导出；正式产物禁止 `(DEBUG)`。
- 成人 18+、20–40 分钟、12 个月保存期、匿名编号删除和无单独伦理编号说明。
- 内部预览按项目负责人要求暂不显示知情同意页；该绕过仅限
  `deploymentStage=preview`，正式 `digcomp-v1` 仍强制成人知情同意。

## 预览发布顺序

1. 本机完成 GitHub、Vercel、阿里云交互登录，不把密钥粘贴到仓库或聊天。
2. 创建香港测试函数 `cyber-safety-upload-api-digcomp-preview`。
3. 创建现有 Vercel 后端的 Preview 部署和静态项目
   `cyber-safety-game-preview`。
4. 两个预览后端填同一套 OSS/扣子/8 档案，使用预览专属密钥，只允许预览
   前端的精确 Origin。
5. 生成 `PREVIEW-20260831` 的 `T001`–`T004` 四条 48 小时链接，
   active/passive 各两条。
6. 完成四条端到端测试和接近 40 分钟的录像/刷新续传测试。

## 正式发布顺序

1. 先部署兼容旧页面的正式 FC 与 Vercel 后端，并确认健康接口档案数为 8。
2. 同步轮换两个正式后端的 `UPLOAD_LINK_SECRET`。
3. 确认研究邮箱和正式班级/编号/有效期，生成新的 `digcomp-v1` 链接。
4. 合并到 `main`，由 GitHub Actions release 导出并发布 Pages。
5. Chrome/Edge 各覆盖 active/passive 与 FC/Vercel 回退，检查四个 OSS 对象。

## 仍需由项目负责人提供或在控制台确认

- 公开的研究联系及匿名编号删除请求专用邮箱。
- GitHub、Vercel、阿里云三个平台的本机交互登录。
- 正式班级代码、参与者数量、匿名编号前缀和链接有效期。
- 阿里云控制台权限，用于创建预览函数并核验 Bucket 私有、RAM 最小权限、
  12 个月生命周期规则。

在以上信息和权限补齐前，只发布隔离预览，不向真实参与者发放正式链接。
