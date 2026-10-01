#!/usr/bin/env python3
"""Print the GitHub contribution calendars (last 12 months and every year) and the last 20 public commits.

local-commits.py merges these commits with the ones from local git folders.

Uses the logged-in GitHub CLI (`gh api`); no token is read or stored here.
The result is cached in $XDG_CACHE_HOME/berri-shell/github.json and reused for
30 minutes. Finished years never change, so they stay in the cache for good; only
the current year is fetched again. If `gh` fails (offline), the old cache is printed instead.

Output shape:
    {"fetchedAt": iso8601, "total": int,
     "days": [[YYYY-MM-DD, count], ...]   # oldest first, whole weeks starting Sunday
     "years": [{"year": int, "total": int, "days": [...]}, ...]   # newest first; days like above,
                                          # count -1 marks a padding day outside the year
     "commits": [{"sha": 7 chars, "message": str, "repo": str, "date": iso8601}, ...]}   # up to 20
"""
import datetime as dt
import json
import subprocess
import sys

from recent_answers import answer_path, read_recent_answer, save_answer

CACHE_PATH = answer_path("github.json")
CACHE_FRESH_S = 30 * 60
CALENDAR = "contributionCalendar{totalContributions weeks{contributionDays{date contributionCount}}}"
QUERY = "{viewer{login contributionsCollection{contributionYears " + CALENDAR + "}}}"


def gh(*args: str) -> dict:
    out = subprocess.run(["gh", "api", *args], capture_output=True, text=True, timeout=30, check=True)
    return json.loads(out.stdout)


def year_days(calendar: dict, year: int) -> list:
    """Days of one year, padded at the start with count -1 so the first column begins on Sunday."""
    days = [[d["date"], d["contributionCount"]] for w in calendar["weeks"] for d in w["contributionDays"]]
    first = dt.date(year, 1, 1)
    pad = (first.weekday() + 1) % 7  # Monday is 0 in Python; the week starts on Sunday
    return [[(first - dt.timedelta(days=pad - i)).isoformat(), -1] for i in range(pad)] + days


def fetch_years(years: list, cached: dict) -> list:
    """One entry per year, newest first. Finished years come from `cached` when it has them."""
    this_year = dt.date.today().year
    missing = [y for y in years if not (y in cached and cached[y].get("final"))]
    fresh = {}
    if missing:
        parts = " ".join(
            f"y{y}:contributionsCollection(from:\"{y}-01-01T00:00:00Z\",to:\"{y}-12-31T23:59:59Z\"){{{CALENDAR}}}"
            for y in missing)
        viewer = gh("graphql", "-f", f"query={{viewer{{{parts}}}}}")["data"]["viewer"]
        for y in missing:
            calendar = viewer[f"y{y}"]["contributionCalendar"]
            fresh[y] = {"year": y, "total": calendar["totalContributions"],
                        "days": year_days(calendar, y), "final": y < this_year}
    return [fresh.get(y) or cached[y] for y in sorted(years, reverse=True)]


def fetch(cached_years: dict) -> dict:
    viewer = gh("graphql", "-f", f"query={QUERY}")["data"]["viewer"]
    collection = viewer["contributionsCollection"]
    calendar = collection["contributionCalendar"]
    days = [[d["date"], d["contributionCount"]] for w in calendar["weeks"] for d in w["contributionDays"]]
    found = gh(f"/search/commits?q=author:{viewer['login']}&sort=author-date&order=desc&per_page=20")
    commits = [{
        "sha": c["sha"][:7],
        "message": c["commit"]["message"].splitlines()[0],
        "repo": c["repository"]["name"],
        "date": c["commit"]["author"]["date"],
    } for c in found["items"][:20]]
    return {"fetchedAt": dt.datetime.now(dt.timezone.utc).isoformat(),
            "total": calendar["totalContributions"], "days": days,
            "years": fetch_years(collection["contributionYears"], cached_years), "commits": commits}


def main() -> None:
    cached = None
    cached_years: dict = {}
    try:
        cached = read_recent_answer(CACHE_PATH)
        if cached is None:
            raise ValueError("No cache")
        parsed = json.loads(cached)
        cached_years = {y["year"]: y for y in parsed.get("years", [])}
        if ("--force" not in sys.argv and "years" in parsed
                and read_recent_answer(CACHE_PATH, CACHE_FRESH_S) is not None):
            print(cached)
            return
    except (OSError, ValueError):
        pass
    try:
        text = json.dumps(fetch(cached_years))
    except Exception:
        # Offline or logged out: show the last good data, and wait one interval before retrying.
        if cached:
            try:
                CACHE_PATH.touch()
            except OSError:
                pass
            print(cached)
        return
    save_answer(CACHE_PATH, text)
    print(text)


if __name__ == "__main__":
    main()
