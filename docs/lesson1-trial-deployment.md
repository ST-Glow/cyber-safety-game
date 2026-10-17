# 第1课试玩云端发布

> 2026-10-17 更新：双班智能体和30秒设备检测已上线，最终发布包真实OSS和Coze验收通过。当前配置、入口与回退点见 [双班部署说明](lesson1-two-class-deployment.md)。下方保留此前普通试玩部署准备记录。

## 发布目标

- 域名：`https://tangguoketang.cn`，首页转到 `/classroom/lesson1/`。
- 函数：中国香港 `cyber-safety-upload-api-digcomp-preview/LATEST`。
- 旧糖果乐园保留 `/classroom/native/`，原 A/B 入口和老师页保留原地址。
- 复用私有 OSS `cyber-game`（杭州）、现有上传角色和课堂数据库；没有数据库结构迁移。

## 实验流程

学生选择七年级1—16班并填写姓名，确认录制后，在 Chrome/Edge 的共享窗口选择**当前游戏标签页**。不申请摄像头、麦克风或整个屏幕。录制包含界面、导览、配对和反馈；主线倒计时仍在导览和配对期间暂停。

每次录制分配独立片段编号；刷新后旧片段可上传，新录制重新授权。相同一局的片段通过 `run_id` 关联，避免将不同录制文件直接拼接为损坏视频。录像分块保存在专用 IndexedDB 中；本机可播放检查通过后才上传。通关、结束、重开和换学生时封装片段并显示上传页，可选择稍后上传和下载本机备份。只有服务器核验视频、操作记录、结果并写入清单后才显示“上传完成”；确认成功后释放本机视频块。跨电脑自动续玩和姓名身份验证不属于本版能力。

## API 与归档

- `POST /api/lesson1/trial/sessions`：班级、姓名、`run_id`、`segment_id`、本机随机 `client_key` 和录制告知版本，领取15分钟上传票据。重复提交返回同一个片段；相同姓名不合并不同录制会话。班级仅允许1—16班；录制告知版本固定 `lesson1-tab-recording-v1`。
- `POST /api/lesson1/trial/renew`：凭原片段编号和本机随机密钥续签，只允许原上传身份，最长恢复窗口30天。本机密钥不放入 URL、结果导出或日志。
- 复用 `/api/upload/credentials` 和 `/api/upload/complete`；第1课票据只用于上传，不能调用原 Coze 接口。开始接口按来源 IP 的不可逆摘要在数据库中进行跨实例限流，学校共用出口支持每10分钟240段开始。
- OSS 路径：`studies/lesson1-student-trial-v1/<g7-01到g7-16>/passive/<匿名学生编号>/<上传编号>/`。`passive` 仅为兼容现有票据的技术目录字段，不代表本次试验进行了实验分组。身份标注为 `self_reported_trial`。
- 文件：`session.jsonl`、`summary.json`、`recording.mp4`或`recording.webm`、`manifest.json`。清单包含服务器保存的班级姓名和片段/运行编号。录像上限256 MiB。本版从 OSS 控制台按研究目录下载；未新增教师端录像管理界面。

## 配置与权限

构建命令：`python classroom-web/tools/build-lesson1-fc.py`。构建报告位于 `tmp/lesson1-cloud/build.json`，包含 ZIP 路径、SHA256 和文件清单。基线为已在线导出并核对相同 SHA256 的 `classroom-experiment-20260921023114.zip`；2882个旧文件保持原哈希，仅修改两个已有文件并增加第1课文件。包不携带账号表、数据库或环境密钥。

保留 FC 原环境变量，仅新增 `LESSON1_TRIAL_ENABLED=true`。保留域名解析和 HTTPS 证书。

需要给现有 API 用户 `cyber-safety-upload-api` 和现有浏览器上传角色分别增加新研究目录权限，使用独立附加策略，不替换旧策略：

- `cloud/aliyun-upload-api/deployment/lesson1-trial-api-policy.json`：读取/核验新研究目录对象，仅向 `manifest.json` 写入。
- `cloud/aliyun-upload-api/deployment/lesson1-trial-browser-policy.json`：仅允许写入新研究目录的事件、结果和视频文件，并允许管理这些对象的分片；实际 STS 再限制到当前片段的三个对象。

2026-10-15 实际 GET 检查域名旧首页和健康接口均200，OSS PUT/POST预检均200，允许精确来源 `https://tangguoketang.cn`，并暴露 ETag、请求编号；已有跨域规则无需扩大来源。

## 验收与回退

- 前端111项、后端77项自动测试通过；Chrome/Edge普通游戏全流程通过。
- `node classroom-web/tools/qa-lesson1-cloud.mjs chrome`（或 `edge`）运行隔离环境：使用真实 MediaRecorder 编码合成画面，模拟 OSS，检查断网、刷新、身份隔离、三关完成、自动封装和上传确认。它不代表真实云端或真实标签页录制已验收。
- 发布后必须实际核验：新首页及旧入口、班级登记、当前标签页共享、真实 OSS 上传及清单、同名跨班隔离、刷新续传。使用技术测试姓名，不占用原实验学生账号。
- 上传前保存当前函数版本；出现旧站回归或上传问题时恢复旧 ZIP/版本，并关闭第1课开关。新研究目录数据和原有账号、课堂数据不因回退而删除。

## 2026-10-15 控制台进度

- `CandyLesson1TrialApiPolicy` 已创建并成功绑定 API 用户 `cyber-safety-upload-api`，控制台显示1项绑定成功、0项失败。
- `CandyLesson1TrialBrowserPolicy` 已在账号持有人完成安全验证后创建，并成功绑定现有角色 `cyber-safety-browser-upload`。控制台明确显示1项绑定成功、0项失败；原有策略保留。
- 已验收部署包：`dist/classroom-lesson1-20261015081959.zip`，19,273,507字节；SHA256 `17a5e782fc393727c3688f2c688e3446079e7d2bc4135d926cf527e0e1fb2269`。
- 尚未修改函数环境开关或上传本版代码，域名仍为原版本。2026-10-16 用户改为亲自操作控制台；接下来保存函数回退版本、新增开关、上传部署并验证真实 OSS。权限配置已经完成，无需再次创建或绑定。

历史状态已由本文开头的2026-10-16发布记录取代。
