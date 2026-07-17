"use strict";

const fs = require("node:fs");
const path = require("node:path");

const projectRoot = path.resolve(__dirname, "..");
const source = path.join(projectRoot, "web-game");
const destination = path.join(projectRoot, "_site");
const apiBaseUrl = String(process.env.UPLOAD_API_BASE_URL || "").trim().replace(/\/$/, "");

if (!/^https:\/\//i.test(apiBaseUrl)) {
  throw new Error("Repository variable UPLOAD_API_BASE_URL must be a valid HTTPS URL");
}

fs.rmSync(destination, { recursive: true, force: true });
fs.cpSync(source, destination, {
  recursive: true,
  filter: (entry) => !entry.endsWith(".log") && !entry.endsWith("upload-test.html"),
});

const configPath = path.join(destination, "upload-config.js");
const configSource = fs.readFileSync(configPath, "utf8");
if (!configSource.includes("__UPLOAD_API_BASE_URL__")) {
  throw new Error("Upload API placeholder was not found");
}
fs.writeFileSync(configPath, configSource.replace("__UPLOAD_API_BASE_URL__", apiBaseUrl), "utf8");
console.log(`GitHub Pages artifact created at ${destination}`);
