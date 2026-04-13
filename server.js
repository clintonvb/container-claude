const http = require("http");
const { spawn } = require("child_process");

const PORT = process.env.CLAUDE_API_PORT || 3000;
const API_TOKEN = process.env.CLAUDE_API_TOKEN;

if (!API_TOKEN) {
  console.error("CLAUDE_API_TOKEN is not set — refusing to start without auth");
  process.exit(1);
}

function authenticate(req) {
  const header = req.headers.authorization || "";
  return header === `Bearer ${API_TOKEN}`;
}

function runClaude(prompt) {
  return new Promise((resolve, reject) => {
    const args = ["-p", prompt, "--dangerously-skip-permissions"];
    const outputFormat = "--output-format";

    const proc = spawn("claude", [...args, outputFormat, "text"], {
      env: { ...process.env, NO_COLOR: "1" },
    });

    let stdout = "";
    let stderr = "";

    proc.stdout.on("data", (d) => (stdout += d));
    proc.stderr.on("data", (d) => (stderr += d));

    proc.on("close", (code) => {
      if (code !== 0) {
        reject(new Error(stderr || `claude exited with code ${code}`));
      } else {
        resolve(stdout.trim());
      }
    });

    proc.on("error", (err) => reject(err));
  });
}

const server = http.createServer(async (req, res) => {
  if (req.method !== "GET" && !authenticate(req)) {
    res.writeHead(401, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "unauthorized" }));
    return;
  }

  if (req.method === "POST" && req.url === "/ask") {
    let body = "";
    req.on("data", (chunk) => (body += chunk));
    req.on("end", async () => {
      try {
        const payload = JSON.parse(body);
        const { prompt } = payload;
        const async = payload.async === true || payload.async === "true";
        if (!prompt) {
          res.writeHead(400, { "Content-Type": "application/json" });
          res.end(JSON.stringify({ error: "prompt is required" }));
          return;
        }

        console.log(`[ask${async ? " async" : ""}] ${prompt.slice(0, 120)}`);

        if (async) {
          runClaude(prompt).catch((err) =>
            console.error(`[async error] ${err.message}`),
          );
          res.writeHead(202, { "Content-Type": "application/json" });
          res.end(JSON.stringify({ status: "accepted" }));
          return;
        }

        const response = await runClaude(prompt);
        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ response }));
      } catch (err) {
        console.error(`[error] ${err.message}`);
        res.writeHead(500, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ error: err.message }));
      }
    });
  } else if (req.method === "GET" && req.url === "/health") {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ status: "ok" }));
  } else {
    res.writeHead(404, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "not found" }));
  }
});

server.listen(PORT, () => {
  console.log(`Claude API server listening on :${PORT}`);
});
