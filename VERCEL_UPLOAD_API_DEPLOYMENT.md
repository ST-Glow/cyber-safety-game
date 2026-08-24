# Vercel 回退 API 部署

Vercel 部署与香港 FC 相同的 Express 后端，仅在主 API 网络失败或返回 5xx
时由 Godot Web 自动调用。录像和日志仍由浏览器直传私有 OSS。

## 项目设置

从 GitHub 导入仓库，Root Directory 设为 `cloud/aliyun-upload-api`，Node.js
设为 20。Production 环境必须配置：

```text
UPLOAD_LINK_SECRET=<与香港FC相同的新密钥>
ALLOWED_ORIGINS=https://<你的-pages-origin>

OSS_REGION=oss-cn-hangzhou
OSS_BUCKET=cyber-game
OSS_UPLOAD_ROLE_ARN=<浏览器上传角色ARN>
OSS_INTERNAL=false
STS_ENDPOINT=https://sts.cn-hangzhou.aliyuncs.com
ALIBABA_CLOUD_ACCESS_KEY_ID=<最小权限RAM用户>
ALIBABA_CLOUD_ACCESS_KEY_SECRET=<最小权限RAM用户>

COZE_BOT_ID=<新Bot ID>
COZE_JWT_OAUTH_CLIENT_ID=<新OAuth Client ID>
COZE_JWT_OAUTH_PUBLIC_KEY_ID=<新Public Key ID>
COZE_JWT_OAUTH_PRIVATE_KEY=<完整PEM私钥>
AI_LEVEL_PROMPTS_JSON=<与香港FC完全相同的四关JSON>
```

敏感变量只填入 Vercel 控制台，不要写入 GitHub Variables。不要配置
`MOCK_OSS_ROOT`、`PUBLIC_BASE_URL` 或 `PORT`。新 Bot 必须先发布到扣子 API
渠道。

部署后访问 `https://<项目>.vercel.app/api/health`，确认 `ok=true`、
`mode=real`、`coze_configured=true`、`coze_bot_configured=true`。健康接口不
返回 Bot ID。

## 生成 active / passive 链接

教师端使用同一份新 `UPLOAD_LINK_SECRET`：

```powershell
$env:UPLOAD_LINK_SECRET = "与两个后端相同的新密钥"
node tools/generate-student-links.cjs `
  --base-url https://<你的-pages地址>/ `
  --class PILOT-A --count 30 --prefix P --hours 24 `
  --study-version godot-v1 --seed PILOT-A-2026 `
  --output generated/PILOT-A-links.csv
```

CSV 包含 `condition`，按固定种子近似 1:1 分配。条件在 v2 票据内签名，不能
由查询参数篡改。只向每位参与者发送其自己的 `game_url`。

切换正式版本时必须轮换 `UPLOAD_LINK_SECRET`，先同步更新 Vercel 和香港
FC，再生成新链接；旧链接会立即失效。
