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
                "weekly": {...} | null, "fetchedAt": iso8601 | ""},
     "codex":  {"session": {...} | null, "weekly": {...} | null, "fetchedAt": iso8601 | ""},
     "cacheSeconds": time in seconds that a reading is reused before a new request}
"""
import contextlib
import datetime as dt
import json
import math
import os
import select
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

from child_cleanup import stop_children_with_script
from recent_answers import answer_path, read_recent_answer, save_answer

USAGE_ENDPOINT = "https://api.anthropic.com/api/oauth/usage"
REQUEST_TIMEOUT_S = 10

CACHE_PATH = answer_path("agent-usage.json")
# Reported as `cacheSeconds` in the output, so AgentUsage.qml derives its freshness limit from it.
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
    """A cached bucket is worth showing while its percent is a real number and its reset time is still ahead of us."""
    if not isinstance(bucket, dict):
        return False
    percent = bucket.get("percent")
    if isinstance(percent, bool) or not isinstance(percent, (int, float)) or not math.isfinite(percent):
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


class UsageRedirectHandler(urllib.request.HTTPRedirectHandler):
    """Keep the bearer on the configured usage endpoint by refusing redirects."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def read_claude_token() -> str | None:
    """The OAuth access token, or None when it is missing, expired or unreadable."""
    try:
        creds_path = claude_config_dir() / ".credentials.json"
        data = json.loads(creds_path.read_text(encoding="utf-8"))
        login = data.get("claudeAiOauth") or {}
        token = str(login.get("accessToken") or "")
        expires_at = float(login.get("expiresAt") or 0)
        if not token or (expires_at and expires_at < time.time() * 1000):
            return None
        return token
    except Exception:
        return None


def note_rate_limit(entry: dict, err: urllib.error.HTTPError, now: dt.datetime) -> None:
    """After a 429, remember when to ask again: the Retry-After header, else the default backoff."""
    try:
        retry_seconds = float(err.headers.get("Retry-After"))
    except Exception:
        retry_seconds = None
    backoff = retry_seconds if retry_seconds and retry_seconds > 0 else RATE_LIMIT_BACKOFF_S
    entry["retryAfter"] = (now + dt.timedelta(seconds=backoff)).isoformat()


def request_claude_usage(token: str, cache: dict, entry: dict, now: dt.datetime) -> dict | None:
    """The usage payload, or None when the request fails. A 429 sets the retry time in the cache."""
    request = urllib.request.Request(
        USAGE_ENDPOINT,
        headers={
            "Authorization": "Bearer " + token,
            "anthropic-beta": "oauth-2025-04-20",
            "Accept": "application/json",
        },
    )
    try:
        opener = urllib.request.build_opener(UsageRedirectHandler())
        with opener.open(request, timeout=REQUEST_TIMEOUT_S) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as err:
        if err.code == 429:
            note_rate_limit(entry, err, now)
            cache["claude"] = entry
        err.close()
        return None
    except Exception:
        return None


def cache_is_fresh(entry: dict, now: dt.datetime) -> bool:
    fetched_at = parse_iso(entry.get("fetchedAt"))
    return bool(fetched_at and now - fetched_at < dt.timedelta(seconds=CACHE_FRESH_S))


def cache_entry(cache: dict, key: str) -> dict:
    """The cached entry of one provider; anything that is not an object counts as no entry."""
    entry = cache.get(key)
    return entry if isinstance(entry, dict) else {}


def claude_usage(cache: dict) -> dict:
    """Session (5-hour) and weekly (7-day) usage, falling back to cache on any failure."""
    entry = cache_entry(cache, "claude")
    now = now_utc()
    if cache_is_fresh(entry, now):
        return cached_buckets(entry)
    retry_after = parse_iso(entry.get("retryAfter"))
    if retry_after and now < retry_after:
        return cached_buckets(entry)
    token = read_claude_token()
    if token is None:
        return cached_buckets(entry)
    payload = request_claude_usage(token, cache, entry, now)
    if not isinstance(payload, dict):
        return cached_buckets(entry)
    buckets = {
        "session": claude_bucket(payload.get("five_hour")),
        "weekly": claude_bucket(payload.get("seven_day_oauth_apps") or payload.get("seven_day")),
    }
    cache["claude"] = {**buckets, "fetchedAt": now.isoformat()}
    return buckets


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
    # OAuth usage reports percentages, including values below 1 percent.
    return {"percent": max(0.0, min(100.0, percent)), "resetsAt": str(resets_at)}


def rpc_request(proc, request_id, method, params=None, timeout=8):
    """Read one response without letting a partial line extend the deadline."""
    deadline = time.monotonic() + timeout
    proc.stdin.write(json.dumps({"id": request_id, "method": method, "params": params or {}}) + "\n")
    proc.stdin.flush()
    pending = b""
    while (remaining := deadline - time.monotonic()) > 0:
        ready, _, _ = select.select([proc.stdout], [], [], remaining)
        if not ready:
            continue
        chunk = os.read(proc.stdout.fileno(), 65536)
        if not chunk:
            break
        pending += chunk
        while b"\n" in pending:
            line, pending = pending.split(b"\n", 1)
            try:
                message = json.loads(line)
            except (ValueError, UnicodeDecodeError):
                continue
            if isinstance(message, dict) and message.get("id") == request_id:
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
        percent = float(used)
        resets_at = dt.datetime.fromtimestamp(float(resets_in), dt.timezone.utc).isoformat()
    except (TypeError, ValueError, OverflowError, OSError):
        return None
    return {"percent": max(0.0, min(100.0, percent)), "resetsAt": resets_at}


def stop_codex(proc) -> None:
    """Ends the app-server child and closes its pipes."""
    try:
        proc.terminate()
        proc.wait(timeout=0.2)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()
    finally:
        with contextlib.suppress(BrokenPipeError):
            proc.stdin.close()
        proc.stdout.close()


def read_codex_limits(codex: str) -> dict:
    """Asks `codex app-server` for the rate limits. Raises on any failure; the child always stops."""
    env = os.environ.copy()
    codex_home = os.environ.get("CODEX_HOME")
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
        return (limits_msg.get("result") or {}).get("rateLimits") or {}
    finally:
        if proc is not None:
            stop_codex(proc)


def codex_usage(cache: dict) -> dict:
    """Primary (5-hour) and secondary (weekly) usage from `codex app-server`, falling back to cache on any failure."""
    entry = cache_entry(cache, "codex")
    now = now_utc()
    if cache_is_fresh(entry, now):
        return cached_buckets(entry)
    codex = shutil.which("codex")
    if not codex:
        return cached_buckets(entry)
    try:
        limits = read_codex_limits(codex)
        primary, secondary = limits.get("primary"), limits.get("secondary")
    except Exception:
        return cached_buckets(entry)
    buckets = {"session": codex_window(primary), "weekly": codex_window(secondary)}
    cache["codex"] = {**buckets, "fetchedAt": now.isoformat()}
    return buckets


def provider_usage(read_usage, cache: dict) -> dict:
    """One provider's usage; a failure in it must not stop the other provider's output."""
    try:
        return read_usage(cache)
    except Exception:
        return {"session": None, "weekly": None}


def source_result(cache: dict, name: str, buckets: dict) -> dict:
    """Attach the last successful fetch time so the view can mark stale data unknown."""
    entry = cache.get(name)
    fetched_at = entry.get("fetchedAt", "") if isinstance(entry, dict) else ""
    return {**buckets, "fetchedAt": str(fetched_at or "")}


def main() -> None:
    try:
        cache = json.loads(read_recent_answer(CACHE_PATH) or "{}")
    except ValueError:
        cache = {}
    if not isinstance(cache, dict):
        cache = {}
    result = {
        "claude": source_result(cache, "claude", provider_usage(claude_usage, cache)),
        "codex": source_result(cache, "codex", provider_usage(codex_usage, cache)),
        "cacheSeconds": CACHE_FRESH_S,
    }
    save_answer(CACHE_PATH, json.dumps(cache))
    print(json.dumps(result))


if __name__ == "__main__":
    stop_children_with_script()
    main()
