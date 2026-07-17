# Vercel 上传 API 部署指南（无备案域名方案）

本方案使用 GitHub Pages 托管游戏网页、Vercel 托管短期授权 API、阿里云私有 OSS 保存实验文件。录像、行为序列和总结由学生浏览器直接上传到 OSS，不经过 Vercel 文件请求体。

## 1. 创建专用 RAM 用户

在阿里云 RAM 中创建用户 `cyber-safety-upload-api`，只启用 OpenAPI/AccessKey 访问，不启用控制台登录。为它创建并附加自定义策略 `CyberSafetyUploadApiPolicy`：

```json
{
  "Version": "1",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Resource": "acs:ram::1906810925835797:role/cyber-safety-browser-upload"
    },
    {
      "Effect": "Allow",
      "Action": [
        "oss:GetObject",
        "oss:PutObject"
      ],
      "Resource": "acs:oss:*:*:cyber-game/sessions/*"
    }
  ]
}
```

为该 RAM 用户创建一组 AccessKey。Secret 只显示一次，不要发送到聊天、写入源码或提交 GitHub。

## 2. 从 GitHub 导入 Vercel

1. 登录 Vercel，选择 **Add New > Project**。
2. 导入 `ST-Glow/cyber-safety-game`。
3. Root Directory 选择 `cloud/aliyun-upload-api`。
4. Framework Preset 保持 Vercel 自动识别的 Express；不要设置静态输出目录。
5. Node.js 版本选择 20 或更高版本。

## 3. 配置 Vercel 环境变量

在 Production、Preview 中配置：

```text
UPLOAD_LINK_SECRET=<至少32位随机字符串>
ALLOWED_ORIGINS=https://st-glow.github.io
OSS_REGION=oss-cn-hangzhou
OSS_BUCKET=cyber-game
OSS_UPLOAD_ROLE_ARN=acs:ram::1906810925835797:role/cyber-safety-browser-upload
OSS_INTERNAL=false
ALIBABA_CLOUD_ACCESS_KEY_ID=<专用RAM用户AccessKey ID>
ALIBABA_CLOUD_ACCESS_KEY_SECRET=<专用RAM用户AccessKey Secret>
COZE_API_TOKEN=<扣子个人访问令牌PAT>
COZE_BOT_ID=<已经发布到API渠道的扣子智能体ID>
```

将 `UPLOAD_LINK_SECRET`、`ALIBABA_CLOUD_ACCESS_KEY_ID`、`ALIBABA_CLOUD_ACCESS_KEY_SECRET` 和 `COZE_API_TOKEN` 标记为 Sensitive。不要设置 `MOCK_OSS_ROOT`、`PUBLIC_BASE_URL` 或 `PORT`。

`COZE_API_TOKEN` 只添加到 Vercel，不能写入 GitHub、GitHub Actions Variables 或任何网页文件。扣子智能体需要先发布到 API 渠道；如果曾把旧 Token 放进公开代码，应先在扣子后台撤销旧 Token，再创建新的 PAT。

## 4. 验证并连接 GitHub Pages

部署成功后访问：

```text
https://<vercel-project>.vercel.app/api/health
```

应返回包含 `"ok":true`、`"mode":"real"` 和 `"coze_configured":true` 的 JSON。若 `coze_configured` 为 `false`，说明 Vercel 中的两个 Coze 环境变量尚未同时配置。然后在 GitHub 仓库的 **Settings > Secrets and variables > Actions > Variables** 新增：

```text
UPLOAD_API_BASE_URL=https://<vercel-project>.vercel.app
```

重新运行 `Deploy web game to GitHub Pages` 工作流。

## 5. 生成学生链接

教师电脑使用与 Vercel 完全相同的 `UPLOAD_LINK_SECRET`：

```powershell
$env:UPLOAD_LINK_SECRET = "与Vercel相同的密钥"
node tools/generate-student-links.cjs --base-url https://st-glow.github.io/cyber-safety-game/ --class CLASS-5A --students S001,S002,S003 --hours 12 --output generated/student-links.csv
```

只把 CSV 中生成的专属链接发给学生，不直接发送无票据的 Pages 首页地址。
