"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const { cloudCredentials } = require("../src/cloud");

function fakeRequest(headers) {
  const normalized = Object.fromEntries(
    Object.entries(headers).map(([key, value]) => [key.toLowerCase(), value])
  );
  return { get: (name) => normalized[name.toLowerCase()] };
}

test("FC request credentials take precedence over environment credentials", () => {
  const previous = {
    id: process.env.ALIBABA_CLOUD_ACCESS_KEY_ID,
    secret: process.env.ALIBABA_CLOUD_ACCESS_KEY_SECRET,
    token: process.env.ALIBABA_CLOUD_SECURITY_TOKEN,
  };
  process.env.ALIBABA_CLOUD_ACCESS_KEY_ID = "env-id";
  process.env.ALIBABA_CLOUD_ACCESS_KEY_SECRET = "env-secret";
  process.env.ALIBABA_CLOUD_SECURITY_TOKEN = "env-token";
  try {
    assert.deepEqual(cloudCredentials(fakeRequest({
      "x-fc-access-key-id": "request-id",
      "x-fc-access-key-secret": "request-secret",
      "x-fc-security-token": "request-token",
    })), {
      accessKeyId: "request-id",
      accessKeySecret: "request-secret",
      stsToken: "request-token",
    });
  } finally {
    for (const [key, value] of Object.entries({
      ALIBABA_CLOUD_ACCESS_KEY_ID: previous.id,
      ALIBABA_CLOUD_ACCESS_KEY_SECRET: previous.secret,
      ALIBABA_CLOUD_SECURITY_TOKEN: previous.token,
    })) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  }
});

test("incomplete FC headers fall back to one complete environment credential set", () => {
  const previous = {
    id: process.env.ALIBABA_CLOUD_ACCESS_KEY_ID,
    secret: process.env.ALIBABA_CLOUD_ACCESS_KEY_SECRET,
    token: process.env.ALIBABA_CLOUD_SECURITY_TOKEN,
  };
  process.env.ALIBABA_CLOUD_ACCESS_KEY_ID = "env-id";
  process.env.ALIBABA_CLOUD_ACCESS_KEY_SECRET = "env-secret";
  process.env.ALIBABA_CLOUD_SECURITY_TOKEN = "env-token";
  try {
    assert.deepEqual(cloudCredentials(fakeRequest({
      "x-fc-access-key-id": "request-id",
      "x-fc-access-key-secret": "request-secret",
    })), {
      accessKeyId: "env-id",
      accessKeySecret: "env-secret",
      stsToken: "env-token",
    });
  } finally {
    for (const [key, value] of Object.entries({
      ALIBABA_CLOUD_ACCESS_KEY_ID: previous.id,
      ALIBABA_CLOUD_ACCESS_KEY_SECRET: previous.secret,
      ALIBABA_CLOUD_SECURITY_TOKEN: previous.token,
    })) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  }
});
