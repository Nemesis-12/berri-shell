import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import http from "node:http";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawn } from "node:child_process";

const repo = fileURLToPath(new URL("../", import.meta.url));

/** Every Text item in the shell must name its format; the default would read tags in outside text. */
test("every Text item is plain text", () => {
  const bad = [];
  const walk = (dir) => {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        if (!["tests", "scratchpad", ".git", "node_modules"].includes(entry.name)) walk(full);
      } else if (entry.name.endsWith(".qml")) {
        const lines = fs.readFileSync(full, "utf8").split("\n");
        lines.forEach((line, i) => {
          if (!/^\s*(component \w+: )?Text \{$/.test(line)) return;
          let depth = 0;
          for (let j = i; j < lines.length; j++) {
            depth += (lines[j].match(/\{/g) || []).length - (lines[j].match(/\}/g) || []).length;
            if (/textFormat:\s*Text\.PlainText/.test(lines[j])) return;
            if (depth <= 0) break;
          }
          bad.push(`${path.relative(repo, full)}:${i + 1}`);
        });
      }
    }
  };
  walk(repo);
  assert.deepEqual(bad, []);
});

/** Real shared text and art parts load markup and an HTTP art link; the server must see nothing. */
test("outside text and HTTP artwork cause no request", async (t) => {
  const runner = process.env.QMLTESTRUNNER || "/usr/lib/qt6/bin/qmltestrunner";
  if (!fs.existsSync(runner)) return t.skip("qmltestrunner is not installed");
  const hits = [];
  const server = http.createServer((req, res) => { hits.push(req.url); res.statusCode = 404; res.end(); });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const base = `http://127.0.0.1:${server.address().port}`;
  fs.mkdirSync(path.join(repo, "scratchpad"), { recursive: true });
  const dir = fs.mkdtempSync(path.join(repo, "scratchpad", "plain-text-"));
  try {
    const fixture = path.join(repo, "tests/fixtures/plain-text-qml/tst_plain_text.qml");
    fs.writeFileSync(path.join(dir, "tst_plain_text.qml"), fs.readFileSync(fixture, "utf8").replaceAll("BASE", base));
    const fake = path.join(repo, "tests/fixtures/notification-qml");
    fs.cpSync(path.join(fake, "Quickshell"), path.join(dir, "Quickshell"), { recursive: true });
    fs.cpSync(path.join(fake, "qs/services"), path.join(dir, "qs/services"), { recursive: true });
    fs.mkdirSync(path.join(dir, "qs/common"), { recursive: true });
    fs.mkdirSync(path.join(dir, "qs/logic"), { recursive: true });
    fs.copyFileSync(path.join(repo, "logic/ArtUrl.js"), path.join(dir, "qs/logic/ArtUrl.js"));
    const common = ["MonoText", "CondensedText", "AlbumArt", "Fade"];
    for (const name of common) fs.copyFileSync(path.join(repo, "common", `${name}.qml`), path.join(dir, "qs/common", `${name}.qml`));
    fs.writeFileSync(path.join(dir, "qs/common/qmldir"), "module qs.common\n" + common.map((n) => `${n} 1.0 ${n}.qml`).join("\n"));
    const env = { ...process.env, QT_QPA_PLATFORM: "offscreen", QSG_RHI_BACKEND: "software", XDG_CACHE_HOME: path.join(dir, "cache") };
    delete env.LD_LIBRARY_PATH;
    const output = await new Promise((resolve) => {
      const child = spawn(runner, ["-input", dir, "-import", dir], { env });
      let text = "";
      child.stdout.on("data", (d) => (text += d));
      child.stderr.on("data", (d) => (text += d));
      child.on("close", (code) => resolve({ code, text }));
    });
    t.diagnostic(output.text.trim());
    assert.equal(output.code, 0, output.text);
    assert.deepEqual(hits.filter((url) => !url.includes("control-rich")), []);
    assert.ok(hits.some((url) => url.includes("control-rich")), "control: rich text must reach the server");
  } finally {
    server.close();
    fs.rmSync(dir, { recursive: true, force: true });
  }
});
