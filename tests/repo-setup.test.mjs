// Repository setup: temporary root images stay ignored, and the setup scripts work in a fresh clone.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";

const repo = new URL("../", import.meta.url).pathname;

// Remove GIT_* environment variables to prevent inherited Git state from affecting spawned commands.
const cleanEnv = () => {
  const env = { ...process.env };
  for (const key of Object.keys(env)) {
    if (key.startsWith("GIT_")) {
      delete env[key];
    }
  }
  return env;
};

const git = (cwd, ...args) => spawnSync("git", args, { cwd, encoding: "utf8", env: cleanEnv() });

test("a synthetic root screenshot is ignored and nested images are not", () => {
  const ignored = (file) => git(repo, "check-ignore", "-q", file).status === 0;
  for (const name of ["shot.png", "Screenshot 1.png", "a.jpg", "a.jpeg", "a.webp"]) assert.ok(ignored(name), name);
  assert.ok(!ignored("assets/brands/claude.png"));
});

test("AGENTS.md stays ignored", () => {
  assert.equal(git(repo, "check-ignore", "-q", "AGENTS.md").status, 0);
  assert.equal(git(repo, "ls-files", "AGENTS.md").stdout, "");
});

test("new-worktree.sh copies AGENTS.md into a new worktree", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "berri-wt-"));
  const main = path.join(dir, "main");
  fs.mkdirSync(path.join(main, "tools"), { recursive: true });
  fs.copyFileSync(path.join(repo, "tools/new-worktree.sh"), path.join(main, "tools/new-worktree.sh"));
  fs.writeFileSync(path.join(main, ".gitignore"), "AGENTS.md\n");
  fs.writeFileSync(path.join(main, "AGENTS.md"), "rules\n");
  const env = cleanEnv();
  git(main, "init", "-q", "-b", "main");
  git(main, "add", ".");
  git(main, "-c", "user.name=t", "-c", "user.email=t@example.test", "commit", "-q", "-m", "init");
  const target = path.join(dir, "wt");
  const result = spawnSync("sh", ["tools/new-worktree.sh", "topic", target], { cwd: main, encoding: "utf8", env });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(fs.readFileSync(path.join(target, "AGENTS.md"), "utf8"), "rules\n");
  assert.equal(git(target, "ls-files", "AGENTS.md").stdout, "");
});

test("new-worktree.sh stops with a message when AGENTS.md is missing", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "berri-wt-"));
  fs.mkdirSync(path.join(dir, "tools"));
  fs.copyFileSync(path.join(repo, "tools/new-worktree.sh"), path.join(dir, "tools/new-worktree.sh"));
  const env = cleanEnv();
  git(dir, "init", "-q", "-b", "main");
  git(dir, "-c", "user.name=t", "-c", "user.email=t@example.test", "commit", "-q", "--allow-empty", "-m", "init");
  const result = spawnSync("sh", ["tools/new-worktree.sh", "topic", path.join(dir, "wt")], { cwd: dir, encoding: "utf8", env });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /AGENTS\.md/);
});

test("setup.sh builds the feed reader where the shell looks for it", () => {
  const text = fs.readFileSync(path.join(repo, "tools/setup.sh"), "utf8");
  assert.match(text, /cargo build --release --manifest-path tools\/feed-to-records\/Cargo\.toml/);
  assert.match(text, /tools\/feed-to-records\/feed-to-records/);
  assert.match(text, /core\.hooksPath \.githooks/);
});

test("start-berri.sh sets the allocator and runs qs for the repo with the extra flags", () => {
  const bin = fs.mkdtempSync(path.join(os.tmpdir(), "berri-qs-"));
  fs.writeFileSync(path.join(bin, "qs"), '#!/bin/sh\necho "$MALLOC_CONF|$*"\n', { mode: 0o755 });
  const result = spawnSync(path.join(repo, "tools/start-berri.sh"), ["-n", "-d"], {
    encoding: "utf8",
    env: { ...cleanEnv(), PATH: `${bin}:${process.env.PATH}`, MALLOC_CONF: "" },
  });
  assert.equal(result.status, 0, result.stderr);
  const root = path.resolve(repo);
  assert.equal(result.stdout.trim(), `background_thread:true,dirty_decay_ms:100,muzzy_decay_ms:100|-p ${root} -n -d`);
});

// A hook runs git with GIT_DIR set. The temp-repo steps must ignore it and leave the decoy repo alone.
test("temp-repo steps ignore an inherited GIT_DIR", () => {
  const decoyDir = fs.mkdtempSync(path.join(os.tmpdir(), "berri-decoy-"));
  git(decoyDir, "init", "-q", "-b", "main");
  git(decoyDir, "-c", "user.name=t", "-c", "user.email=t@example.test", "commit", "-q", "--allow-empty", "-m", "decoy");
  const snapshot = () => [
    git(decoyDir, "rev-parse", "HEAD").stdout,
    git(decoyDir, "config", "core.bare").stdout,
    git(decoyDir, "worktree", "list").stdout,
    git(decoyDir, "branch", "--list").stdout,
    git(decoyDir, "status", "--porcelain").stdout,
  ];
  const before = snapshot();

  const savedGitDir = process.env.GIT_DIR;
  try {
    process.env.GIT_DIR = path.join(decoyDir, ".git");

    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "berri-wt-"));
    const main = path.join(dir, "main");
    fs.mkdirSync(path.join(main, "tools"), { recursive: true });
    fs.copyFileSync(path.join(repo, "tools/new-worktree.sh"), path.join(main, "tools/new-worktree.sh"));
    fs.writeFileSync(path.join(main, ".gitignore"), "AGENTS.md\n");
    fs.writeFileSync(path.join(main, "AGENTS.md"), "rules\n");
    git(main, "init", "-q", "-b", "main");
    git(main, "add", ".");
    git(main, "-c", "user.name=t", "-c", "user.email=t@example.test", "commit", "-q", "-m", "init");
    spawnSync("sh", ["tools/new-worktree.sh", "topic", path.join(dir, "wt")], { cwd: main, encoding: "utf8", env: cleanEnv() });
  } finally {
    if (savedGitDir === undefined) delete process.env.GIT_DIR;
    else process.env.GIT_DIR = savedGitDir;
  }

  assert.deepEqual(snapshot(), before);
});

test("every start method uses the launcher and only the launcher sets the allocator", () => {
  const read = (file) => fs.readFileSync(path.join(repo, file), "utf8");
  assert.match(read("toggle.sh"), /tools\/start-berri\.sh/);
  assert.match(read("tools/restart-berri.sh"), /start-berri\.sh/);
  assert.match(read("README.md"), /^exec-once = .*\/tools\/start-berri\.sh -n -d$/m);
  for (const file of ["toggle.sh", "tools/restart-berri.sh", "README.md"]) assert.doesNotMatch(read(file), /MALLOC_CONF/, file);
});
