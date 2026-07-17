"use strict";

const { createApp } = require("./src/app");

const port = Number(process.env.PORT || 9000);
const app = createApp();

app.listen(port, "0.0.0.0", () => {
  console.log(`Cyber Safety upload API listening on ${port}`);
});
