# 阿里云香港函数计算主 API 部署

香港 FC 是主 API，Vercel 是自动回退。浏览器直接向私有杭州 OSS 上传，
录像不会经过函数计算请求体。

## 1. 构建与创建函数

```powershell
./tools/build-fc-package.ps1
```

上传 `dist/cyber-safety-upload-api-fc-cn-hongkong.zip`，创建中国香港
`cn-hongkong` Web 函数，Node.js 20，自定义启动命令 `node server.js`，
端口 `9000`，建议 512 MB / 120 秒。HTTP 触发器允许 GET、POST、PUT、
OPTIONS，业务接口仍由签名票据保护。

## 2. 必填环境变量

以下值必须与 Vercel 完全一致；私钥不要写入仓库或聊天：

```text
UPLOAD_LINK_SECRET=<新生成的至少32字符密钥，切换时轮换>
ALLOWED_ORIGINS=https://<你的-pages-origin>

OSS_REGION=oss-cn-hangzhou
OSS_BUCKET=cyber-game
OSS_UPLOAD_ROLE_ARN=<只允许目标对象上传的RAM角色ARN>
OSS_INTERNAL=false
STS_ENDPOINT=https://sts.cn-hongkong.aliyuncs.com

COZE_BOT_ID=<新Bot ID，且Bot已发布到API渠道>
COZE_JWT_OAUTH_CLIENT_ID=<新OAuth Client ID>
COZE_JWT_OAUTH_PUBLIC_KEY_ID=<新Public Key ID>
COZE_JWT_OAUTH_PRIVATE_KEY=<完整PEM私钥>
AI_LEVEL_PROMPTS_JSON=<四关隐藏教学档案JSON>
```

优先给函数绑定最小权限执行角色。若暂时使用专用 RAM AccessKey，还需：

```text
ALIBABA_CLOUD_ACCESS_KEY_ID=<专用RAM用户>
ALIBABA_CLOUD_ACCESS_KEY_SECRET=<专用RAM用户>
```

不要设置 `MOCK_OSS_ROOT` 或 `PUBLIC_BASE_URL`。香港访问杭州 OSS 必须保持
`OSS_INTERNAL=false`。Bucket 必须为私有，并配置 12 个月生命周期删除规则。

## 3. 验证与接入 Pages

访问 `https://<前缀>.cn-hongkong.fcapp.run/api/health`，确认 `ok=true`、
`mode=real`、`coze_configured=true`、`coze_bot_configured=true`。

GitHub Actions Variables 配置：

```text
PRIMARY_API_BASE_URL=https://<前缀>.cn-hongkong.fcapp.run
FALLBACK_API_BASE_URL=https://<项目>.vercel.app
GODOT_STUDY_VERSION=godot-v1
```

随后运行 `Test and deploy Godot study to GitHub Pages`。工作流会运行后端
测试、Godot 回归、Web 导出和静态检查，再发布 `godot/build/web`。

## 4. 生产验收

在最新版桌面 Chrome、Edge 各完成一条 active 和 passive 链接，确认每次
OSS 都有 `session.jsonl`、`summary.json`、录像或缺失说明、`manifest.json`。
确认无真实姓名、无音视频设备权限。临时停用或阻断 FC 后再完成一次，确认
API 自动回退 Vercel。只有页面显示“保存成功，现在可以关闭页面”才算完成。
