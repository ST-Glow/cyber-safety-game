"use strict";

// Vercel's Express detector requires the recognized entrypoint itself to
// import Express, even though app construction lives in a separate module.
require("express");
const { createApp } = require("./src/create-app");

const port = Number(process.env.PORT || 9000);
const app = createApp();

if (require.main === module) {
  if (process.env.CLASSROOM_SETUP_MODE === "true") {
    require("./tools/classroom-cloud-setup").startSetupServer();
  } else {
    app.listen(port, "0.0.0.0", () => {
      console.log(`Cyber Safety upload API listening on ${port}`);
    });
  }
}

// Vercel imports the Express application as a single serverless function.
module.exports = app;
