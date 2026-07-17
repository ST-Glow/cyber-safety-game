# 上传接口约定

Unity 客户端默认支持离线缓存。服务器不可用时，数据保留在本地，下一次启动后继续尝试上传。

## 配置

在 Unity Inspector 的 `UploadManager` 中设置：

- `Upload Enabled`: 是否启用上传。
- `Base Url`: 后端根地址，例如 `https://example.edu/api/research`.
- `Api Key`: 可选课堂实验密钥，不应使用长期管理员密钥。

## 文件上传

`POST /sessions/{sessionId}/files/{fileName}`

Headers:

- `Content-Type: application/octet-stream`
- `X-Research-Api-Key: <apiKey>`，如果配置了密钥。

Body:

- 原始文件内容。

建议服务器按 `sessionId` 和 `fileName` 保存文件，并拒绝路径穿越字符。

## 会话完成

`POST /sessions/{sessionId}/complete`

Headers:

- `Content-Type: application/json`
- `X-Research-Api-Key: <apiKey>`，如果配置了密钥。

Body:

```json
{
  "session_id": "20260707_120000_abcd",
  "client_time_utc": "2026-07-07T04:00:00Z"
}
```

服务器成功接收全部必要文件后返回 2xx。客户端会写入 `uploaded.ok`。

