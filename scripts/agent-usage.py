#!/usr/bin/env python3
"""Print one JSON record with Claude and Codex rate-limit usage.

Reads Claude's OAuth token straight from ~/.claude/.credentials.json (or
CLAUDE_CONFIG_DIR) and calls Anthropic's usage endpoint directly. Talks to
Codex through its own `codex app-server` JSON-RPC process. Neither token nor
any other secret is ever printed or cached; on failure we fall back to the
last good reading on disk, so the caller (AgentUsage.qml) keeps showing real
numbers instead of an empty ring during a rate limit or a transient error.

Cache file: $XDG_CACHE_HOME/berri-shell/agent-usage.json (default
~/.cache/berri-shell/). Holds only percents, reset times, and fetch/backoff
timestamps for each agent — never a token.

Output shape:
    {"claude": {"session": {"percent": 0-100, "resetsAt": iso8601} | null,
                "weekly": {...} | null},
     "codex":  {"session": {...} | null, "weekly": {...} | null}}
"""
import datetime as dt
import json
import os
import select
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

from recent_answers import answer_path, read_recent_answer, save_answer

USAGE_ENDPOINT = "https://api.anthropic.com/api/oauth/usage"
REQUEST_TIMEOUT_S = 10

CACHE_PATH = answer_path("agent-usage.json")
CACHE_FRESH_S = 5 * 60
RATE_LIMIT_BACKOFF_S = 10 * 60


def claude_config_dir() -> Path:
    return Path(os.path.expandvars(os.path.expanduser(
        os.environ.get("CLAUDE_CONFIG_DIR") or "~/.claude"
    )))


def now_utc() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


def parse_iso(value) -> dt.datetime | None:
    if not value:
        return None
    try:
        parsed = dt.datetime.fromisoformat(str(value))
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=dt.timezone.utc)
        return parsed
    except Exception:
        return None


def bucket_still_fresh(bucket) -> bool:
    """A cached bucket is worth showing while its reset time is still ahead of us."""
    if not isinstance(bucket, dict):
        return False
    reset = parse_iso(bucket.get("resetsAt"))
    return reset is not None and reset > now_utc()


def cached_buckets(entry: dict) -> dict:
    """The last good session/weekly reading, dropped once its reset has passed."""
    session = entry.get("session")
    weekly = entry.get("weekly")
    return {
        "session": session if bucket_still_fresh(session) else None,
        "weekly": weekly if bucket_still_fresh(weekly) else None,
    }


def claude_usage(cache: dict) -> dict:
    """Session (5-hour) and weekly (7-day) usage, falling back to cache on any failure."""
    entry = cache.get("claude") or {}
    now = now_utc()

    fetched_at = parse_iso(entry.get("fetchedAt"))
    if fetched_at and now - fetched_at < dt.timedelta(seconds=CACHE_FRESH_S):
        return cached_buckets(entry)

    retry_after = parse_iso(entry.get("retryAfter"))
    if retry_after and now < retry_after:
        return cached_buckets(entry)

    try:
        creds_path = claude_config_dir() / ".credentials.json"
        data = json.loads(creds_path.read_text(encoding="utf-8"))
        login = data.get("claudeAiOauth") or {}
        token = str(login.get("accessToken") or "")
        expires_at = float(login.get("expiresAt") or 0)
        if not token or (expires_at and expires_at < time.time() * 1000):
            return cached_buckets(entry)
    except Exception:
        return cached_buckets(entry)

    request = urllib.request.Request(
        USAGE_ENDPOINT,
        headers={
            "Authorization": "Bearer " + token,
            "anthropic-beta": "oauth-2025-04-20",
            "Accept": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT_S) as resp:
            payload = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as err:
        if err.code == 429:
            retry_seconds = None
            try:
                retry_seconds = float(err.headers.get("Retry-After"))
            except Exception:
                retry_seconds = None
            backoff = retry_seconds if retry_seconds and retry_seconds > 0 else RATE_LIMIT_BACKOFF_S
            entry["retryAfter"] = (now + dt.timedelta(seconds=backoff)).isoformat()
            cache["claude"] = entry
        return cached_buckets(entry)
    except Exception:
        return cached_buckets(entry)

    new_session = claude_bucket(payload.get("five_hour"))
    new_weekly = claude_bucket(payload.get("seven_day_oauth_apps") or payload.get("seven_day"))
    session = new_session or (entry.get("session") if bucket_still_fresh(entry.get("session")) else None)
    weekly = new_weekly or (entry.get("weekly") if bucket_still_fresh(entry.get("weekly")) else None)
    cache["claude"] = {"session": session, "weekly": weekly, "fetchedAt": now.isoformat()}
    return {"session": session, "weekly": weekly}


def claude_bucket(bucket) -> dict | None:
    if not isinstance(bucket, dict):
        return None
    utilization = bucket.get("utilization")
    resets_at = bucket.get("resets_at")
    if utilization is None or not resets_at:
        return None
    try:
        percent = float(utilization)
    except Exception:
        return None
    # The endpoint reports a 0-100 percentage; guard against a stray 0-1 fraction.
    if percent <= 1:
        percent *= 100
    return {"percent": max(0.0, min(100.0, percent)), "resetsAt": str(resets_at)}


def rpc_request(proc, request_id, method, params=None, timeout=8):
    proc.stdin.write(json.dumps({"id": request_id, "method": method, "params": params or {}}) + "\n")
    proc.stdin.flush()
    deadline = time.time() + timeout
    while time.time() < deadline:
        ready, _, _ = select.select([proc.stdout], [], [], 0.25)
        if not ready:
            continue
        line = proc.stdout.readline()
        if not line:
            break
        try:
            message = json.loads(line)
        except Exception:
            continue
        if message.get("id") == request_id:
            return message
    raise TimeoutError(method)


def codex_window(window) -> dict | None:
    if not isinstance(window, dict):
        return None
    used = window.get("usedPercent")
    resets_in = window.get("resetsAt")
    if used is None or resets_in is None:
        return None
    try:
        reset_epoch = float(resets_in)
    except Exception:
        return None
    resets_at = dt.datetime.fromtimestamp(reset_epoch, dt.timezone.utc).isoformat()
    return {"percent": max(0.0, min(100.0, float(used))), "resetsAt": resets_at}


def codex_usage(cache: dict) -> dict:
    """Primary (5-hour) and secondary (weekly) usage from `codex app-server`, falling back to cache on any failure."""
    entry = cache.get("codex") or {}
    now = now_utc()

    fetched_at = parse_iso(entry.get("fetchedAt"))
    if fetched_at and now - fetched_at < dt.timedelta(seconds=CACHE_FRESH_S):
        return cached_buckets(entry)

    codex = shutil.which("codex")
    if not codex:
        return cached_buckets(entry)

    codex_home = os.environ.get("CODEX_HOME")
    env = os.environ.copy()
    if codex_home:
        env["CODEX_HOME"] = codex_home

    proc = None
    try:
        proc = subprocess.Popen(
            [codex, "-s", "read-only", "-a", "on-request", "app-server"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            env=env,
        )
        rpc_request(proc, 1, "initialize", {"clientInfo": {"name": "berri-shell", "version": "1"}}, timeout=8)
        proc.stdin.write(json.dumps({"method": "initialized", "params": {}}) + "\n")
        proc.stdin.flush()
        limits_msg = rpc_request(proc, 2, "account/rateLimits/read", timeout=4)
        limits = (limits_msg.get("result") or {}).get("rateLimits") or {}
    except Exception:
        return cached_buckets(entry)
    finally:
        if proc is not None:
            try:
                proc.terminate()
                proc.wait(timeout=2)
            except Exception:
                try:
                    proc.kill()
                except Exception:
                    pass

    new_session = codex_window(limits.get("primary"))
    new_weekly = codex_window(limits.get("secondary"))
    session = new_session or (entry.get("session") if bucket_still_fresh(entry.get("session")) else None)
    weekly = new_weekly or (entry.get("weekly") if bucket_still_fresh(entry.get("weekly")) else None)
    cache["codex"] = {"session": session, "weekly": weekly, "fetchedAt": now.isoformat()}
    return {"session": session, "weekly": weekly}


def main() -> None:
    try:
        cache = json.loads(read_recent_answer(CACHE_PATH) or "{}")
    except ValueError:
        cache = {}
    result = {"claude": claude_usage(cache), "codex": codex_usage(cache)}
    save_answer(CACHE_PATH, json.dumps(cache))
    print(json.dumps(result))


if __name__ == "__main__":
    main()
