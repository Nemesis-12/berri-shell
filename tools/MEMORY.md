# Memory baseline

Run from the main checkout with its one berri instance already running. The tool
matches the exact config path in `qs list --all`, requires one matching instance,
and checks that the process did not change during warm-up. It refuses to start a
shell from an inactive worktree. Do not run two copies of this tool at once.

For an independent baseline, install the measurement tool before the start-path
change, then run:

```sh
tools/measure-memory.sh --runs 2 before-thp
```

After installing the start-path change, run the same sequence:

```sh
tools/measure-memory.sh --runs 2 after-thp
```

Each run restarts only this checkout through `tools/restart-berri.sh`, waits six
seconds, opens home, media, system, code, calendar, weather, and alerts for two
seconds each, closes the dashboard, then opens `themes` and `walls` for three
seconds each. It closes each picker body and waits one second before continuing.
It waits another 20 seconds after closing the last body before reading memory.
The TEMP `pickertest` IPC handler in `shell.qml` and the laptop display `eDP-2`
are required. No theme or wallpaper is selected. Do not interact with the shell
during a run. Keep monitors, applications, and other conditions the same.

To measure the existing process without restarting:

```sh
tools/measure-memory.sh --no-restart current
```

`--no-restart --runs 2` gives two samples from the same process history. Use the
default restart mode for independent before and after comparisons. The label is
optional. The tool prints every run and the arithmetic average, in MiB, without
rounding inputs. RSS, PSS, and anon come from `smaps_rollup`; VRAM and GTT come
from `fdinfo`. GPU totals count each device/client pair once, even if it has
multiple file descriptors. Missing counters fail the measurement instead of
reporting zero. These are the main shell process counters, not a sum of child
processes or all GPU users.

To confirm the process setting, use the PID printed by the tool:

```sh
grep '^THP_enabled:' /proc/<pid>/status
```

It must print `THP_enabled: 0` after the start-path change. The helper sets
`PR_SET_THP_DISABLE` only for the process it replaces and its children. It never
writes the system THP setting. If Python or the kernel call is unavailable,
startup continues with a warning.

The maintainer's 2026-10-08 prototype measured PSS from 326 to about 240 MiB,
with no GPU change. jemalloc `thp:never` did not help. These are prior results,
not measurements from this tool. Record the new two-run averages, variation,
and feature/motion checks in the PR before claiming the new baseline.

Kernel references: [process THP controls](https://docs.kernel.org/admin-guide/mm/transhuge.html#process-thp-controls)
and [DRM client accounting](https://docs.kernel.org/gpu/drm-usage-stats.html).
