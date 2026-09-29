// Minimal static server for the admin dashboard (server/public) so we can
// smoke-test the front against the deployed Neon gateway from the browser.
// The gateway sends access-control-allow-origin: * (CORS_ALLOWED_ORIGIN=*),
// so a localhost origin can call it directly — no same-origin hosting needed.
// Usage:  node tool/local_serve_dashboard.cjs [port]
const http = require("http");
const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "..", "server", "public");
const PORT = parseInt(process.argv[2] || "8787", 10);
const TYPES = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".svg": "image/svg+xml",
  ".ico": "image/x-icon",
};

http.createServer((req, res) => {
  let urlPath = decodeURIComponent((req.url || "/").split("?")[0]);
  if (urlPath === "/" || urlPath === "") urlPath = "/index.html";
  const file = path.normalize(path.join(ROOT, urlPath));
  if (!file.startsWith(ROOT)) { res.writeHead(403); res.end("forbidden"); return; }
  fs.readFile(file, (err, buf) => {
    if (err) { res.writeHead(404, { "Content-Type": "text/plain" }); res.end("not found"); return; }
    res.writeHead(200, { "Content-Type": TYPES[path.extname(file).toLowerCase()] || "application/octet-stream" });
    res.end(buf);
  });
}).listen(PORT, () => console.log("serving " + ROOT + " -> http://localhost:" + PORT));
