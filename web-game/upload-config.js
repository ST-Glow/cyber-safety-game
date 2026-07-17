(() => {
  "use strict";

  const localHostnames = new Set(["127.0.0.1", "localhost"]);
  const localApi = "http://127.0.0.1:8787";
  const deployedApi = "__UPLOAD_API_BASE_URL__";
  const apiBaseUrl = localHostnames.has(window.location.hostname) ? localApi : deployedApi;

  window.CYBER_UPLOAD_CONFIG = Object.freeze({
    enabled: new URLSearchParams(window.location.search).get("upload") !== "off",
    apiBaseUrl,
    requireSignedTicket: true,
    retryDelaysMs: [0, 2000, 5000, 15000, 30000],
    backgroundRetryMs: 60000,
    multipartThresholdBytes: 20 * 1024 * 1024,
    multipartPartSizeBytes: 5 * 1024 * 1024,
    multipartParallel: 3,
  });
})();
