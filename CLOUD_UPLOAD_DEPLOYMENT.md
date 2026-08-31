# 阿里云香港函数计算主 API 部署

香港 FC 是主 API，Vercel 是自动回退。浏览器直接向私有杭州 OSS 上传，录像
不会经过函数计算请求体。先建立隔离预览函数
`cyber-safety-upload-api-digcomp-preview`，验收通过后再更新正式函数。

## 1. 构建与创建函数

```powershell
./tools/build-fc-package.ps1
```

上传 `dist/cyber-safety-upload-api-fc-cn-hongkong.zip`，创建中国香港
`cn-hongkong` Web 函数，使用 Node.js 20 或更高版本，启动命令 `node server.js`，
端口 `9000`，建议至少 512 MB / 120 秒。HTTP 触发器允许 GET、POST、PUT、
OPTIONS，业务接口仍由签名票据保护。录像允许值为 1 GiB，但由浏览器直传 OSS。

## 2. 环境变量

同一环境的 FC 与 Vercel 必须完全一致；预览和正式的
`UPLOAD_LINK_SECRET` 必须不同。私钥不要写入仓库、日志或聊天：

```text
UPLOAD_LINK_SECRET=<至少32字符；预览与正式分别生成>
ALLOWED_ORIGINS=https://<该环境唯一前端Origin>

OSS_REGION=oss-cn-hangzhou
OSS_BUCKET=cyber-game
OSS_UPLOAD_ROLE_ARN=<只允许目标对象上传的RAM角色ARN>
OSS_INTERNAL=false
STS_ENDPOINT=https://sts.cn-hongkong.aliyuncs.com

COZE_BOT_ID=<已发布到API渠道的Bot ID>
COZE_JWT_OAUTH_CLIENT_ID=<OAuth Client ID>
COZE_JWT_OAUTH_PUBLIC_KEY_ID=<Public Key ID>
COZE_JWT_OAUTH_PRIVATE_KEY=<完整PEM私钥>
AI_LEVEL_PROMPTS_JSON=<8个服务端隐藏教学档案JSON>
```

8 个档案 ID 必须为 `level_1`、`level_2`、`level_3`、`level_4`、
`digcomp_hub`、`level_2_puzzle`、`level_3_matching`、
`level_4_image_judgment`。可从本地生成的
`generated/digcomp-v1-ai-level-prompts.json` 复制值到控制台；该文件被 Git
忽略，不作为云端密钥来源。后端只接受白名单数值状态，不接受客户端
`instruction`，也不向模型传递正确答案、拼图位置或匹配结果。

优先给函数绑定最小权限执行角色。若暂时使用专用 RAM AccessKey，还需：

```text
ALIBABA_CLOUD_ACCESS_KEY_ID=<专用RAM用户>
ALIBABA_CLOUD_ACCESS_KEY_SECRET=<专用RAM用户>
```

不要设置 `MOCK_OSS_ROOT` 或 `PUBLIC_BASE_URL`。香港访问杭州 OSS 保持
`OSS_INTERNAL=false`。Bucket 必须为私有，并配置 12 个月生命周期删除规则。

## 3. 预览与正式顺序

1. 预览函数只允许 `https://<preview-project>` 的精确 Origin，使用预览密钥。
2. 健康接口必须返回 `ok=true`、`mode=real`、`coze_configured=true`、
   `coze_bot_configured=true`、`ai_profile_count=8`。
3. 预览完成 Chrome/Edge、active/passive、主 API/回退和约 40 分钟断点续传验收。
4. 先发布兼容旧前端的正式 FC/Vercel 后端，再轮换正式密钥，最后发布 Pages。

GitHub Actions Variables：

```text
PRIMARY_API_BASE_URL=https://<正式前缀>.cn-hongkong.fcapp.run
FALLBACK_API_BASE_URL=https://<正式项目>.vercel.app
GODOT_STUDY_VERSION=digcomp-v1
RESEARCH_CONTACT=<公开的研究及删除请求邮箱>
```

工作流会运行后端测试、Godot 回归、release Web 导出与静态检查。正式产物必须
显示 `deploymentStage=production`，且页面不存在 `(DEBUG)`。

## 4. OSS 验收

每条链接对应路径：
`studies/<study_version>/<class>/<condition>/<student>/<upload_id>/`。确认存在：

- `session.jsonl`
- `summary.json`（schema v3）
- `recording.webm`/`recording.mp4` 或 `recording-status.json`
- 服务端生成的 `manifest.json`

在阿里云控制台实际确认 Bucket 私有、RAM 最小权限、12 个月生命周期规则生效。
切换失败时回滚到前一个 Pages 提交；新版后端是旧接口超集，可暂时保留。
