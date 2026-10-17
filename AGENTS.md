# DeepSeek Harness 工作区说明

## 当前任务范围

本分支用于审查和修改七年级第 1 课双班试玩：

- `classroom-web/prototypes/lesson1-card-table/`：学生端、导览、匹配、30 秒互动试玩。
- `classroom-web/prototypes/card-game/`、`classroom-web/prototypes/card-task-engine/`：第 1 课依赖的共享界面和逻辑。
- `cloud/aliyun-upload-api/src/lesson1-experiment.js`、`src/lesson1-trial.js`、`src/create-app.js`：双班分组、AI 支持和上传票据。
- `docs/lesson1-two-class-deployment.md`：已发布行为和验收范围。

服务器固定规则：初一 1 班 `g7-01` 为 `proactive`，初一 6 班 `g7-06` 为 `reactive`；30 秒入口的 `g7-other` 只能进入互动试玩，不能调用 AI 或进入正式实验。

## 修改边界

- 默认只修改第 1 课和相关测试。不要为了修第 1 课改动 Godot 主游戏、旧 `/classroom/native/`、第 4 课牌桌或生产路由。
- 不读取、复制或输出 `.env*`、OSS/Coze/RAM 凭据、账号表、`tmp/`、`dist/`、`mock-oss/`、本地录像和浏览器技术账号文件。
- 不调用真实学生数据，不访问生产数据库，不修改 OSS、RAM、FC 环境变量、域名、CORS 或部署版本。
- 不执行 `git push`、发布、购买、权限变更或删除操作；这些动作需要用户明确确认。
- 不把生成包、截图、录像、临时 JSON 或账号文件加入提交。

## 本地验证

在改动后运行：

```powershell
npm test --prefix classroom-web
npm test --prefix cloud/aliyun-upload-api
```

需要浏览器回归时使用隔离本地服务：

```powershell
node classroom-web/tools/qa-lesson1-experiment.mjs chrome
node classroom-web/tools/qa-lesson1-experiment.mjs edge
```

不要运行带有真实 OSS、Coze 或技术账号的云端脚本，除非用户在当前任务中明确要求并确认目标环境。

## 交付要求

- 先说明计划和会修改的文件，再编辑。
- 保持五张主线行动卡都可尝试；错误操作只反馈，不锁死卡牌。
- AI 回复不能泄露正确卡牌、场景目标、匹配答案、班级条件或学生姓名。
- 修改后报告测试结果、未覆盖的真实环境风险和准确的文件路径。
- 提交前运行 `git diff --check`，确认没有凭据、临时文件或生成产物。
