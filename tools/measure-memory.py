#!/usr/bin/env python3
"""Warm every berri view and report process memory in MiB."""
import argparse
import json
import re
import subprocess
import sys
import time
from pathlib import Path


# Read the kernel's CPU memory totals without including similarly named fields.
def parse_smaps(text):
    fields = dict(re.findall(r"^(Rss|Pss|Pss_Anon):\s+(\d+) kB$", text, re.MULTILINE))
    return {name: int(fields[key]) for name, key in
            (("RSS", "Rss"), ("PSS", "Pss"), ("anon", "Pss_Anon"))}


# Sum distinct DRM clients; duplicate file descriptors share the same allocation.
# DRM counters without a unit are bytes, per the kernel's drm-usage-stats docs.
def parse_gpu(texts):
    clients = {}
    units = {"B": 1 / 1024, "kB": 1, "KiB": 1, "MiB": 1024}
    for text in texts:
        fields = dict(line.split(":", 1) for line in text.splitlines() if ":" in line)
        if "drm-client-id" not in fields:
            continue
        key = (fields.get("drm-pdev", "").strip(), fields["drm-client-id"].strip())
        if key in clients:
            continue
        totals = {}
        for name in ("VRAM", "GTT"):
            value, *unit = fields[f"drm-memory-{name.lower()}"].split()
            totals[name] = int(value) * units[unit[0] if unit else "B"]
        clients[key] = totals
    if not clients:
        raise ValueError("no DRM memory counters; GPU memory is unavailable")
    return {name: sum(client[name] for client in clients.values()) for name in ("VRAM", "GTT")}


# Select exactly this checkout, never another shell or an ambiguous instance.
def parse_instance(text, repo):
    matches = []
    config = (repo / "shell.qml").resolve()
    for instance, body in re.findall(r"^Instance ([^:\n]+):\n(.*?)(?=^Instance |\Z)",
                                     text, re.MULTILINE | re.DOTALL):
        fields = dict(line.strip().split(":", 1) for line in body.splitlines() if ":" in line)
        if Path(fields.get("Config path", "").strip()).resolve() == config:
            matches.append((instance, int(fields["Process ID"].strip())))
    if len(matches) != 1:
        raise ValueError(f"expected one running berri for {repo}, found {len(matches)}")
    return matches[0]


# Run shell commands with errors visible and a finite wait.
def run(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True, timeout=15).stdout


# Use Quickshell's instance metadata rather than a partial process-name match.
def find_instance(repo):
    return parse_instance(run("qs", "list", "--all", "--no-color"), repo)


# Reject stale PIDs or a process replacement during the warm-up.
def process_start(pid):
    process = Path("/proc") / str(pid)
    if (process / "exe").resolve().name not in ("qs", "quickshell"):
        raise ValueError(f"PID {pid} is not Quickshell")
    return (process / "stat").read_text().rsplit(")", 1)[1].split()[19]


# Open each body for real, close the views, and let background work settle.
def warm_views(instance):
    for tab in ("home", "media", "system", "code", "calendar", "weather", "alerts"):
        run("qs", "ipc", "-i", instance, "call", "pickertest", "dash", tab)
        time.sleep(2)
    run("qs", "ipc", "-i", instance, "call", "pickertest", "dashClose")
    time.sleep(1)
    for tab in ("themes", "walls"):
        run("qs", "ipc", "-i", instance, "call", "pickertest", "open", tab)
        time.sleep(3)
        run("qs", "ipc", "-i", instance, "call", "pickertest", "close")
        time.sleep(1)
    time.sleep(20)


# Read CPU and GPU accounting from the same warmed process.
def read_memory(pid):
    process = Path("/proc") / str(pid)
    cpu = parse_smaps((process / "smaps_rollup").read_text())
    texts = []
    for fd in (process / "fdinfo").iterdir():
        try:
            texts.append(fd.read_text())
        except FileNotFoundError:
            continue  # A descriptor can close between listing and reading it.
    totals = cpu | parse_gpu(texts)
    totals["PSS+GPU"] = totals["PSS"] + totals["VRAM"] + totals["GTT"]
    return totals


# Stop before measuring: pickertest silently opens nothing without the laptop display.
def require_laptop_display(monitors_json):
    names = {monitor["name"] for monitor in json.loads(monitors_json)}
    if "eDP-2" not in names:
        raise ValueError("laptop display eDP-2 is missing; pickertest would open nothing")


# Print full precision only after summing or averaging KiB values.
def report(label, totals):
    print(f"{label}: " + " | ".join(f"{name} {value / 1024:.2f} MiB"
                                     for name, value in totals.items()), flush=True)


# Each restarted run has the same startup, warm-up, and idle wait.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("label", nargs="?", default="memory")
    parser.add_argument("--no-restart", action="store_true",
                        help="warm the current process; repeated samples share its history")
    parser.add_argument("--runs", type=int, default=1, help="print each run and their average")
    args = parser.parse_args()
    if args.runs < 1:
        parser.error("--runs must be at least 1")
    repo = Path(__file__).resolve().parent.parent
    # Require an existing instance before restarting. A worktree cannot start a second shell.
    find_instance(repo)
    require_laptop_display(run("hyprctl", "monitors", "-j"))
    samples = []
    for number in range(1, args.runs + 1):
        if not args.no_restart:
            run(str(repo / "tools/restart-berri.sh"))
            time.sleep(6)
        instance, pid = find_instance(repo)
        started = process_start(pid)
        print(f"{args.label} run {number}/{args.runs}: PID {pid}, warming views", flush=True)
        warm_views(instance)
        if find_instance(repo) != (instance, pid) or process_start(pid) != started:
            raise ValueError("berri changed during the warm-up; discard this run")
        totals = read_memory(pid)
        report(f"{args.label} run {number}", totals)
        samples.append(totals)
    report(f"{args.label} average of {args.runs}",
           {name: sum(sample[name] for sample in samples) / args.runs for name in samples[0]})


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        print(f"measure-memory: {error}", file=sys.stderr)
        sys.exit(1)
