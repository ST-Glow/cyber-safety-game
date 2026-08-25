"use strict";

const fs = require("node:fs/promises");
const path = require("node:path");

function objectPrefix(claims) {
  return `studies/${claims.study_version}/${claims.class_id}/${claims.condition}/${claims.student_code}/${claims.upload_id}`;
}

function objectNames(claims, recordingExtension, recordingAvailable) {
  const prefix = objectPrefix(claims);
  const extension = String(recordingExtension || "").toLowerCase();
  if (recordingAvailable && !["mp4", "webm"].includes(extension)) {
    throw new Error("recording_extension_invalid");
  }
  return {
    events: `${prefix}/session.jsonl`,
    summary: `${prefix}/summary.json`,
    recording: recordingAvailable ? `${prefix}/recording.${extension}` : `${prefix}/recording-status.json`,
    manifest: `${prefix}/manifest.json`,
  };
}

function rolePolicy(bucket, objects) {
  const resources = [objects.events, objects.summary, objects.recording].map(
    (key) => `acs:oss:*:*:${bucket}/${key}`
  );
  return JSON.stringify({
    Version: "1",
    Statement: [
      {
        Effect: "Allow",
        Action: [
          "oss:PutObject",
          "oss:InitiateMultipartUpload",
          "oss:UploadPart",
          "oss:CompleteMultipartUpload",
          "oss:AbortMultipartUpload",
          "oss:ListParts",
        ],
        Resource: resources,
      },
    ],
  });
}

function requestHeader(request, name) {
  if (!request) return "";
  if (typeof request.get === "function") return request.get(name) || "";
  const headers = request.headers || {};
  return headers[name] || headers[name.toLowerCase()] || "";
}

function cloudCredentials(request) {
  const requestCredentials = {
    accessKeyId: requestHeader(request, "x-fc-access-key-id"),
    accessKeySecret: requestHeader(request, "x-fc-access-key-secret"),
    stsToken: requestHeader(request, "x-fc-security-token"),
  };
  if (requestCredentials.accessKeyId && requestCredentials.accessKeySecret && requestCredentials.stsToken) {
    return requestCredentials;
  }
  return {
    accessKeyId: process.env.ALIBABA_CLOUD_ACCESS_KEY_ID || process.env.ACCESS_KEY_ID,
    accessKeySecret: process.env.ALIBABA_CLOUD_ACCESS_KEY_SECRET || process.env.ACCESS_KEY_SECRET,
    stsToken: process.env.ALIBABA_CLOUD_SECURITY_TOKEN || process.env.SECURITY_TOKEN,
  };
}

function createRealAdapter(config) {
  function client(request) {
    const OSS = require("ali-oss");
    const credentials = cloudCredentials(request);
    if (!credentials.accessKeyId || !credentials.accessKeySecret) throw new Error("function_role_credentials_missing");
    return new OSS({
      region: config.ossRegion,
      bucket: config.ossBucket,
      internal: config.ossInternal,
      authorizationV4: true,
      ...credentials,
    });
  }

  async function head(name, request) {
    try {
      const result = await client(request).head(name);
      const headers = result.res?.headers || {};
      return {
        exists: true,
        bytes: Number(headers["content-length"] || 0),
        contentType: headers["content-type"] || "",
        etag: headers.etag || "",
      };
    } catch (error) {
      if (error.status === 404 || error.code === "NoSuchKey") return { exists: false };
      throw error;
    }
  }

  return {
    mode: "real",
    async assumeRole(claims, objects, request) {
      const Core = require("@alicloud/pop-core");
      const credentials = cloudCredentials(request);
      if (!config.ossRoleArn) throw new Error("oss_upload_role_arn_missing");
      const sts = new Core({
        accessKeyId: credentials.accessKeyId,
        accessKeySecret: credentials.accessKeySecret,
        securityToken: credentials.stsToken,
        endpoint: config.stsEndpoint || "https://sts.cn-hangzhou.aliyuncs.com",
        apiVersion: "2015-04-01",
      });
      const response = await sts.request("AssumeRole", {
        RoleArn: config.ossRoleArn,
        RoleSessionName: `cyber-${claims.upload_id.slice(0, 24)}`,
        DurationSeconds: 900,
        Policy: rolePolicy(config.ossBucket, objects),
      }, { method: "POST" });
      return response.Credentials;
    },
    head,
    async writeManifest(name, manifest, request) {
      await client(request).put(name, Buffer.from(JSON.stringify(manifest, null, 2), "utf8"), {
        headers: { "Content-Type": "application/json" },
      });
    },
  };
}

function safeMockPath(root, objectName) {
  const normalizedRoot = path.resolve(root);
  const resolved = path.resolve(root, ...objectName.split("/"));
  if (!resolved.startsWith(`${normalizedRoot}${path.sep}`)) throw new Error("mock_path_invalid");
  return resolved;
}

function createMockAdapter(config) {
  return {
    mode: "mock",
    async head(name) {
      const filePath = safeMockPath(config.mockRoot, name);
      try {
        const stat = await fs.stat(filePath);
        let contentType = "application/octet-stream";
        try {
          const meta = JSON.parse(await fs.readFile(`${filePath}.meta.json`, "utf8"));
          contentType = meta.contentType || contentType;
        } catch {
          // Metadata is optional in local tests.
        }
        return { exists: true, bytes: stat.size, contentType, etag: `mock-${stat.size}` };
      } catch (error) {
        if (error.code === "ENOENT") return { exists: false };
        throw error;
      }
    },
    async writeObject(name, bytes, contentType) {
      const filePath = safeMockPath(config.mockRoot, name);
      await fs.mkdir(path.dirname(filePath), { recursive: true });
      await fs.writeFile(filePath, bytes);
      await fs.writeFile(`${filePath}.meta.json`, JSON.stringify({ contentType }, null, 2));
    },
    async writeManifest(name, manifest) {
      await this.writeObject(name, Buffer.from(JSON.stringify(manifest, null, 2)), "application/json");
    },
  };
}

function createCloudAdapter(config) {
  return config.mockRoot ? createMockAdapter(config) : createRealAdapter(config);
}

module.exports = { cloudCredentials, createCloudAdapter, objectNames, objectPrefix, rolePolicy };
