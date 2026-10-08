#!/usr/bin/env python3
"""Print token totals per day and per model from local Claude Code and Codex logs.

Reads only numeric usage fields, timestamps and model names from
~/.claude/projects/**/*.jsonl and ~/.codex/sessions/**/*.jsonl. It never reads
message text and never uses the network. Counted tokens: Claude = input +
output + cache writes (cache reads are left out); Codex = total tokens minus
cached input. Cost is an estimate: tokens per model times the list prices in
data/model-prices.json (input, output, cache writes 5m/1h, cache reads).

The result is cached in $XDG_CACHE_HOME/berri-shell/code-stats.json and reused
for 10 minutes (pass --force to skip the cache).

Output shape:
    {"generatedAt": iso8601,
     "days": [{"date": "YYYY-MM-DD", "claude": int, "codex": int}, ... 7 items, oldest first],
     "models": {"claude": [{"name": str, "tokens": int}, ...],
                "codex":  [...]},       # this week (Monday to now), largest first
     "usage": {"claude": {"today"|"week"|"month": {"tokens": int, "cost": usd}}, "codex": {...}},
     "unpricedModels": {"claude": [model id], "codex": [...]}}  # tokens counted, no cost
"""
import datetime as dt
import json
import re
import sys
import time
from collections.abc import Iterable
from pathlib import Path

from recent_answers import answer_path, read_recent_answer, save_answer

CACHE_PATH = answer_path("code-stats.json")
CACHE_FRESH_S = 10 * 60
DAY_COUNT = 7
PRICES_PATH = Path(__file__).resolve().parent.parent / "data" / "model-prices.json"


def pretty_model(raw: str) -> str:
    """"claude-opus-4-1-20250805" -> "Opus 4.1", "gpt-6-sol" -> "GPT-6-Sol"."""
    if raw.startswith("claude-"):
        parts = [p for p in raw[7:].split("-") if not re.fullmatch(r"\d{8}", p)]
        words = [p for p in parts if not p.isdigit()]
        nums = [p for p in parts if p.isdigit()]
        return " ".join([" ".join(w.capitalize() for w in words), ".".join(nums)]).strip()
    return "-".join("GPT" if p == "gpt" else p.capitalize() if p.isalpha() else p for p in raw.split("-"))


def local_day(ts: str) -> dt.date | None:
    try:
        return dt.datetime.fromisoformat(ts.replace("Z", "+00:00")).astimezone().date()
    except Exception:
        return None


KINDS = ("input", "output", "cache_write_5m", "cache_write_1h", "cache_read")


def counted(k: dict) -> int:
    """Tokens shown in the tab: everything except cache reads."""
    return k["input"] + k["output"] + k["cache_write_5m"] + k["cache_write_1h"]


def load_prices() -> tuple[dict, dict]:
    """Load prices and aliases from model-prices.json. Returns (models, aliases)."""
    try:
        data = json.loads(PRICES_PATH.read_text(encoding="utf-8"))
        return data.get("models", {}), data.get("aliases", {})
    except (OSError, ValueError, KeyError):
        return {}, {}


def price_for(prices: dict, aliases: dict, model: str) -> dict | None:
    """Price entry: check exact alias match first, then longest prefix."""
    resolved = aliases.get(model, model)
    keys = [k for k in prices if resolved.startswith(k)]
    return prices[max(keys, key=len)] if keys else None


def cost_of(k: dict, price: dict) -> float:
    return sum(k[n] * price[n] for n in KINDS) / 1e6


def claude_events(paths: Iterable[Path], first_day: dt.date):
    """Count each response once across streamed lines and copied session logs."""
    latest = {}
    for path in paths:
        try:
            with path.open(encoding="utf-8", errors="replace") as f:
                for line_number, line in enumerate(f):
                    if '"usage"' not in line:
                        continue
                    try:
                        o = json.loads(line)
                        m = o["message"]
                        u = m["usage"]
                        day = local_day(o["timestamp"])
                        model = m.get("model") or ""
                        if o.get("type") != "assistant" or day is None or day < first_day or model.startswith("<"):
                            continue
                        write = int(u.get("cache_creation_input_tokens") or 0)
                        split = u.get("cache_creation") or {}
                        w1 = int(split.get("ephemeral_1h_input_tokens") or 0)
                        w5 = int(split.get("ephemeral_5m_input_tokens") or 0) if split else write
                        kinds = {
                            "input": int(u.get("input_tokens") or 0),
                            "output": int(u.get("output_tokens") or 0),
                            "cache_write_5m": w5,
                            "cache_write_1h": w1,
                            "cache_read": int(u.get("cache_read_input_tokens") or 0),
                        }
                        message_id = m.get("id") or o.get("uuid") or (path, line_number)
                        previous = latest.get(message_id)
                        # A copied partial response must not replace its final usage.
                        if previous is None or kinds["output"] >= previous[2]["output"]:
                            latest[message_id] = (day, model, kinds)
                    except Exception:
                        continue
        except OSError:
            continue
    yield from latest.values()


def codex_session_events(path: Path, first_day: dt.date):
    """Yields (day, model, kinds) per growth of the running session totals."""
    model = ""
    prev = {"input": 0, "output": 0, "cache_read": 0}
    with path.open(encoding="utf-8", errors="replace") as f:
        for line in f:
            is_turn = '"turn_context"' in line
            if not is_turn and '"token_count"' not in line:
                continue
            try:
                o = json.loads(line)
                p = o["payload"]
                if is_turn:
                    model = p.get("model") or model
                    continue
                if p.get("type") != "token_count" or not p.get("info"):
                    continue
                t = p["info"]["total_token_usage"]
                cached = int(t.get("cached_input_tokens") or 0)
                cur = {
                    "input": int(t.get("input_tokens") or 0) - cached,  # input_tokens includes cached ones
                    "output": int(t.get("output_tokens") or 0),
                    "cache_read": cached,
                }
                day = local_day(o["timestamp"])
                delta = {n: max(0, cur[n] - prev[n]) for n in prev}
                prev = {n: max(prev[n], cur[n]) for n in prev}
                if day is not None and day >= first_day and any(delta.values()):
                    yield day, model, {**delta, "cache_write_5m": 0, "cache_write_1h": 0}
            except Exception:
                continue


def codex_events(paths: Iterable[Path], first_day: dt.date):
    """Read each session independently and skip logs that cannot be opened."""
    for path in paths:
        try:
            yield from codex_session_events(path, first_day)
        except OSError:
            continue


def recent_logs(root: Path, cutoff: float):
    """Find logs changed since the earliest day included in the totals."""
    for path in root.rglob("*.jsonl"):
        try:
            if path.stat().st_mtime >= cutoff:
                yield path
        except OSError:
            continue


def empty_kinds() -> dict:
    return {n: 0 for n in KINDS}


def add_event(totals: dict, agent: str, day: dt.date, model: str, kinds: dict, periods: dict) -> None:
    """Adds one usage event to the per-day, per-model and per-period totals."""
    tokens = counted(kinds)
    if day >= periods["first_day"]:
        totals["per_day"][day.isoformat()][agent] += tokens
    if day >= periods["week"] and model:
        name = pretty_model(model)
        by_name = totals["per_model"][agent]
        by_name[name] = by_name.get(name, 0) + tokens
    for bucket in ("today", "week", "month"):
        if day >= periods[bucket]:
            acc = totals["buckets"][agent][bucket].setdefault(model or "unknown", empty_kinds())
            for n in KINDS:
                acc[n] += kinds[n]


def priced_usage(by_model: dict, prices, aliases, unknown: set) -> dict:
    """Token and cost totals for one bucket. Models without a price go into `unknown`."""
    total_tokens, total_cost = 0, 0.0
    for model, kinds in by_model.items():
        total_tokens += counted(kinds)
        price = price_for(prices, aliases, model)
        if price is not None:
            total_cost += cost_of(kinds, price)
        elif counted(kinds) or kinds["cache_read"]:
            unknown.add(model)
    return {"tokens": total_tokens, "cost": round(total_cost, 4)}


def collect() -> dict:
    today = dt.date.today()
    first_day = today - dt.timedelta(days=DAY_COUNT - 1)
    periods = {"first_day": first_day, "today": today,
               "week": today - dt.timedelta(days=today.weekday()), "month": today.replace(day=1)}
    oldest = min(first_day, periods["month"])
    cutoff = time.mktime(oldest.timetuple())
    home = Path.home()
    prices, aliases = load_prices()
    sources = {
        "claude": (home / ".claude" / "projects", claude_events),
        "codex": (home / ".codex" / "sessions", codex_events),
    }
    totals = {
        "per_day": {(first_day + dt.timedelta(days=i)).isoformat(): {"claude": 0, "codex": 0} for i in range(DAY_COUNT)},
        "per_model": {"claude": {}, "codex": {}},
        # buckets[agent][bucket][raw model] = kinds
        "buckets": {a: {"today": {}, "week": {}, "month": {}} for a in sources},
    }
    for agent, (root, events) in sources.items():
        if not root.is_dir():
            continue
        for day, model, kinds in events(recent_logs(root, cutoff), oldest):
            if day > today:  # A wrong clock or copied log can hold a future date.
                continue
            add_event(totals, agent, day, model, kinds, periods)
    usage = {a: {} for a in sources}
    unknown = {a: set() for a in sources}
    for agent, by_bucket in totals["buckets"].items():
        for bucket, by_model in by_bucket.items():
            usage[agent][bucket] = priced_usage(by_model, prices, aliases, unknown[agent])
    return {
        "generatedAt": dt.datetime.now(dt.timezone.utc).isoformat(),
        "days": [{"date": d, **v} for d, v in totals["per_day"].items()],
        "models": {a: [{"name": n, "tokens": t} for n, t in sorted(m.items(), key=lambda kv: -kv[1])]
                   for a, m in totals["per_model"].items()},
        "usage": usage,
        "unpricedModels": {a: sorted(u) for a, u in unknown.items()},
    }


def main() -> None:
    cached = read_recent_answer(CACHE_PATH, CACHE_FRESH_S) if "--force" not in sys.argv else None
    if cached is not None:
        print(cached)
        return
    text = json.dumps(collect())
    save_answer(CACHE_PATH, text)
    print(text)


if __name__ == "__main__":
    main()
