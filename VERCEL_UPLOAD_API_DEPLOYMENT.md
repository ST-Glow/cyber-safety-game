# Vercel 回退 API 部署

Vercel 部署与香港 FC 相同的 Express 后端，仅在主 API 网络失败或返回 5xx 时
由 Godot Web 自动调用。录像和日志仍由浏览器直传私有 OSS。

## 项目与环境

现有后端项目 Root Directory 为 `cloud/aliyun-upload-api`，Node.js 使用 20 或
更高版本。先创建 Preview 部署；Preview 与 Production 各自配置变量，且使用
不同的 `UPLOAD_LINK_SECRET`：

```text
UPLOAD_LINK_SECRET=<与同环境香港FC一致；预览和正式不同>
ALLOWED_ORIGINS=https://<该环境唯一前端Origin>

OSS_REGION=oss-cn-hangzhou
OSS_BUCKET=cyber-game
OSS_UPLOAD_ROLE_ARN=<浏览器上传角色ARN>
OSS_INTERNAL=false
STS_ENDPOINT=https://sts.cn-hangzhou.aliyuncs.com
ALIBABA_CLOUD_ACCESS_KEY_ID=<最小权限RAM用户>
ALIBABA_CLOUD_ACCESS_KEY_SECRET=<最小权限RAM用户>

COZE_BOT_ID=<已发布到API渠道的Bot ID>
COZE_JWT_OAUTH_CLIENT_ID=<OAuth Client ID>
COZE_JWT_OAUTH_PUBLIC_KEY_ID=<Public Key ID>
COZE_JWT_OAUTH_PRIVATE_KEY=<完整PEM私钥>
AI_LEVEL_PROMPTS_JSON=<与同环境香港FC相同的8档案JSON>
```

敏感变量只填入 Vercel 控制台。不要配置 `MOCK_OSS_ROOT`、`PUBLIC_BASE_URL`
或 `PORT`。健康接口必须返回 `ok=true`、`mode=real`、
`coze_configured=true`、`coze_bot_configured=true`、`ai_profile_count=8`。

预览静态前端使用独立项目 `cyber-safety-game-preview`，研究版本固定为
`digcomp-v1-preview`。Vercel Preview API 与预览 FC 都只允许该前端精确
Origin；不得把 GitHub Pages 正式 Origin 加入预览白名单。

## 生成链接

教师端只在本机临时设置同环境密钥，不写入文件：

```powershell
$env:UPLOAD_LINK_SECRET = "与两个预览后端相同的预览密钥"
node tools/generate-student-links.cjs `
  --base-url https://<preview-project>/ `
  --class PREVIEW-20260831 --count 4 --prefix T --hours 48 `
  --study-version digcomp-v1-preview --seed PREVIEW-20260831 `
  --output generated/PREVIEW-20260831-links.csv
```

验收 CSV 应包含 `T001`–`T004`，active/passive 各两条。正式切换时使用新的正式
密钥、正式班级参数和 `digcomp-v1` 重新生成，绝不复用预览链接。

## 切换顺序

1. Preview 部署与预览 FC 配置一致并通过健康检查。
2. 完成四条端到端和长录像/断点续传验收。
3. 先部署兼容旧前端的正式 FC 和 Vercel 后端。
4. 同步轮换两个正式后端的密钥并做健康检查。
5. 合并 `main`，由 GitHub Actions 发布正式 Pages。

旧正式链接在密钥轮换后立即失效。前后端失败时不要显示保存成功；只有服务端
`manifest.json` 已完成才允许清理 IndexedDB 并提示关闭页面。
