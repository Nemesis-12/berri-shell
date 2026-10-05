// Real curl against local test servers (127.0.0.1) with a self-signed cert made in a temp folder.
// The links are synthetic. No outside host is contacted.
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import http from "node:http";
import https from "node:https";
import os from "node:os";
import path from "node:path";
import { spawn, spawnSync } from "node:child_process";

const script = new URL("../scripts/feed-download.sh", import.meta.url).pathname;
const tools = ["curl", "openssl"].every((tool) => spawnSync(tool, ["--version"]).status === 0);
const hasProc = fs.existsSync("/proc/self/cmdline");
const marker = "synthetic-feed-marker-7f3a";
const feed = "BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n";

let root, certFile, keyFile;
const servers = [];

before(() => {
  if (!tools) return;
  root = fs.mkdtempSync(path.join(os.tmpdir(), "berri-link-"));
  certFile = path.join(root, "cert.pem");
  keyFile = path.join(root, "key.pem");
  const made = spawnSync("openssl", ["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1", "-subj", "/CN=127.0.0.1",
    "-addext", "subjectAltName=IP:127.0.0.1", "-keyout", keyFile, "-out", certFile], { encoding: "utf8" });
  assert.equal(made.status, 0, made.stderr);
  fs.mkdirSync(path.join(root, "bin"));
  fs.writeFileSync(path.join(root, "bin", "parser"), `#!/bin/sh\nprintf '{"name":"","records":[]}' > "$2"\n`, { mode: 0o755 });
});

after(() => {
  for (const server of servers) { server.closeAllConnections?.(); server.close(); }
  if (root) fs.rmSync(root, { recursive: true, force: true });
});

function listen(server) {
  servers.push(server);
  return new Promise((resolve) => server.listen(0, "127.0.0.1", () => resolve(server.address().port)));
}

const tlsOptions = () => ({ key: fs.readFileSync(keyFile), cert: fs.readFileSync(certFile) });

// Starts the download script like the shell does: the link is in the environment, never in the arguments.
function startDownload(link) {
  const sub = path.join(root, "sub-" + Math.random().toString(36).slice(2));
  const child = spawn("sh", [script, path.join(root, "bin", "parser"), "", sub, "127", "70", "71"], {
    env: { ...process.env, BERRI_FEED_URL: link, CURL_CA_BUNDLE: certFile }, stdio: ["ignore", "pipe", "pipe"] });
  const done = new Promise((resolve) => child.on("close", (code) => resolve(code)));
  return { child, done };
}

// Process ids below `pid`, found through /proc.
function descendants(pid) {
  const found = [];
  const parents = new Map();
  for (const name of fs.readdirSync("/proc").filter((n) => /^\d+$/.test(n))) {
    try {
      const stat = fs.readFileSync(`/proc/${name}/stat`, "utf8");
      parents.set(+name, +stat.slice(stat.lastIndexOf(")") + 2).split(" ")[1]);
    } catch { /* The process ended. */ }
  }
  const queue = [pid];
  while (queue.length) {
    const next = queue.pop();
    for (const [child, parent] of parents) if (parent === next) { found.push(child); queue.push(child); }
  }
  return found;
}

test("an HTTPS link that redirects to HTTP fails and the HTTP target gets no request", { skip: !tools && "needs curl and openssl" }, async () => {
  let plainRequests = 0;
  const plain = http.createServer((req, res) => { plainRequests++; res.end(feed); });
  const plainPort = await listen(plain);
  const secure = https.createServer(tlsOptions(), (req, res) => {
    res.writeHead(302, { Location: `http://127.0.0.1:${plainPort}/feed.ics` });
    res.end();
  });
  const securePort = await listen(secure);
  const { child, done } = startDownload(`https://127.0.0.1:${securePort}/${marker}.ics`);
  const code = await done;
  assert.equal(code, 1, "curl exit 1 means the protocol is not allowed");
  assert.equal(plainRequests, 0);
  // A control: the same server with an HTTPS target works, so the failure above is the protocol rule.
  const target = https.createServer(tlsOptions(), (req, res) => res.end(feed));
  const targetPort = await listen(target);
  const redirectSecure = https.createServer(tlsOptions(), (req, res) => {
    res.writeHead(302, { Location: `https://127.0.0.1:${targetPort}/feed.ics` });
    res.end();
  });
  const redirectPort = await listen(redirectSecure);
  const ok = startDownload(`https://127.0.0.1:${redirectPort}/${marker}.ics`);
  assert.equal(await ok.done, 0);
  child.kill();
});

test("a redirect loop stops after a few redirects", { skip: !tools && "needs curl and openssl" }, async () => {
  let requests = 0;
  const loop = https.createServer(tlsOptions(), (req, res) => {
    requests++;
    res.writeHead(302, { Location: `/${requests}.ics` });
    res.end();
  });
  const port = await listen(loop);
  const code = await startDownload(`https://127.0.0.1:${port}/${marker}.ics`).done;
  assert.equal(code, 47, "curl exit 47 means too many redirects");
  assert.ok(requests >= 2 && requests <= 10, `requests: ${requests}`);
});

test("during a held download neither the script nor curl has the link in its arguments", { skip: (!tools && "needs curl and openssl") || (!hasProc && "needs /proc") }, async () => {
  let seenPath = null;
  let arrived;
  const hasArrived = new Promise((resolve) => { arrived = resolve; });
  const held = https.createServer(tlsOptions(), (req) => { seenPath = req.url; arrived(); });
  const port = await listen(held);
  const { child, done } = startDownload(`https://127.0.0.1:${port}/${marker}.ics`);
  let timer;
  await Promise.race([hasArrived, new Promise((_, reject) => { timer = setTimeout(() => reject(new Error("The request did not arrive")), 10000); })]);
  clearTimeout(timer);
  const pids = [child.pid, ...descendants(child.pid)];
  const lines = pids.map((pid) => fs.readFileSync(`/proc/${pid}/cmdline`, "utf8").replaceAll("\0", " "));
  assert.ok(lines.some((line) => line.includes("curl")), "curl runs while the download is held");
  assert.ok(seenPath.includes(marker), "curl got the link");
  for (const line of lines) assert.ok(!line.includes(marker) && !line.includes("127.0.0.1:" + port), "an argument list holds the link");
  for (const pid of pids.slice().reverse()) { try { process.kill(pid, "SIGKILL"); } catch { /* Already gone. */ } }
  await done;
});
