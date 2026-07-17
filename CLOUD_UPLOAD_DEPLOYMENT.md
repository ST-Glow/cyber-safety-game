# 网页游戏自动上传部署指南

本项目采用“GitHub Pages 静态网页 + 阿里云函数计算 + 私有 OSS”的结构。学生浏览器只获得短期、单次实验、三个固定对象的写入权限，网页代码中不保存永久 AccessKey。

## 1. 本地完整模拟

在第一个 PowerShell 窗口运行上传 API：

```powershell
Set-Location cloud/aliyun-upload-api
npm.cmd install
$env:PORT = "8787"
$env:UPLOAD_LINK_SECRET = "local-development-secret-change-me"
$env:ALLOWED_ORIGINS = "http://127.0.0.1:4173,http://localhost:4173"
$env:MOCK_OSS_ROOT = "../../mock-oss"
$env:PUBLIC_BASE_URL = "http://127.0.0.1:8787"
npm.cmd start
```

在第二个窗口生成学生链接并启动网页：

```powershell
$env:UPLOAD_LINK_SECRET = "local-development-secret-change-me"
node tools/generate-student-links.cjs --base-url http://127.0.0.1:4173/ --class CLASS-5A --students S001 --output generated/student-links.csv
Set-Location web-game
python -m http.server 4173 --bind 127.0.0.1
```

打开 CSV 中的链接。通关后，`mock-oss/sessions/CLASS-5A/S001/<upload_id>/` 应出现三份学生文件和 `manifest.json`。

## 2. 创建私有 OSS Bucket

1. 在免费试用支持的中国内地地域创建“标准存储、同城冗余”Bucket；函数计算选择同一地域。
2. 保持“阻止公共访问”开启，Bucket ACL 保持“私有”。不要把网站文件放入这个数据 Bucket。
3. 开启默认服务端加密（SSE-OSS/AES256）。
4. 设置生命周期：`sessions/` 下对象 365 天后删除；未完成的分片上传 3 天后中止。
5. 设置 CORS：
   - 来源：`http://127.0.0.1:4173`、`http://localhost:4173`、最终 GitHub Pages Origin，例如 `https://YOUR-USER.github.io`。
   - Methods：`GET`、`POST`、`PUT`、`DELETE`、`HEAD`。
   - Allowed Headers：`*`。
   - Expose Headers：`ETag`、`x-oss-request-id`。
   - 不要在正式配置中使用来源 `*`。

## 3. RAM 最小权限

创建角色 `cyber-safety-browser-upload`，允许函数计算执行角色扮演。该角色自身只授予以下基础权限，API 还会在每次 AssumeRole 时把资源缩小到单个学生的三个固定对象：

```json
{
  "Version": "1",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["oss:PutObject", "oss:AbortMultipartUpload", "oss:ListParts"],
    "Resource": ["acs:oss:*:*:YOUR_PRIVATE_BUCKET/sessions/*"]
  }]
}
```

函数计算执行角色需要：

- 对上述上传角色的 `sts:AssumeRole`。
- 对 `acs:oss:*:*:YOUR_PRIVATE_BUCKET/sessions/*` 的 `oss:GetObject` 和 `oss:PutObject`，用于检查文件元数据并写入 `manifest.json`。

不要给浏览器上传角色附加 `AliyunOSSFullAccess`。

## 4. 部署函数计算

1. 创建 Node.js 20 Web 函数，选择与 OSS 相同地域，启动命令为 `npm start`，监听端口 `9000`。
2. 在 `cloud/aliyun-upload-api` 执行 `npm.cmd install --omit=dev`，将该目录连同 `node_modules` 打包上传。
3. 为函数绑定上一步的执行角色，并设置环境变量：
   - `UPLOAD_LINK_SECRET`：至少 32 位随机字符串，教师链接生成器使用同一值。
   - `ALLOWED_ORIGINS`：本地来源和 GitHub Pages Origin，以逗号分隔。
   - `OSS_REGION`：例如 `oss-cn-hangzhou`。
   - `OSS_BUCKET`：私有数据 Bucket 名。
   - `OSS_UPLOAD_ROLE_ARN`：浏览器上传角色 ARN。
   - `OSS_INTERNAL=true`：函数与 OSS 同地域时使用内网。
4. HTTP 触发器允许匿名调用；业务接口仍要求不可伪造且会过期的学生票据。先访问 `/api/health` 检查状态。
5. 当前无备案域名时，函数默认公网地址只作为实验阶段 API 使用，不作为学生直接浏览的网页地址。

## 5. 发布 GitHub Pages

1. 将代码推送至 GitHub 仓库，并在仓库 Settings > Pages 中选择 GitHub Actions。
2. 在 Settings > Secrets and variables > Actions > Variables 创建 `UPLOAD_API_BASE_URL`，值为函数计算 HTTPS 地址，不带末尾 `/`。
3. 运行 `Deploy web game to GitHub Pages` 工作流。
4. 复制 Pages 地址，并把它加入 OSS CORS 与函数的 `ALLOWED_ORIGINS`。
5. 使用相同的 `UPLOAD_LINK_SECRET` 生成正式学生链接：

```powershell
$env:UPLOAD_LINK_SECRET = "与函数相同的签名密钥"
node tools/generate-student-links.cjs --base-url https://YOUR-USER.github.io/YOUR-REPO/ --class CLASS-5A --students S001,S002,S003 --hours 12 --output generated/student-links.csv
```

## 6. 上线检查

- 用学校实际网络至少测试两台电脑同时通关。
- OSS 中每名学生应有 `session.jsonl`、`summary.json`、录像和 `manifest.json`。
- 匿名窗口直接访问任意 OSS 文件 URL 必须返回无权限。
- 上传期间断网并恢复，确认页面能继续上传；刷新后确认 IndexedDB 能恢复待上传任务。
- 学生只在看到“保存成功，可以关闭页面”后离开。

## 安全提醒

项目原来包含直接写在网页中的 Coze 长期令牌，现已从公开网页移除。旧令牌已经出现在本地源码中，应立即在 Coze 控制台吊销并重新签发。正式恢复智能体时，应配置服务端短期令牌接口，不要把新长期令牌写回 HTML 或 JavaScript。
