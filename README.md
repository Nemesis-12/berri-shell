# berri-shell

berri is a Quickshell desktop shell for Omarchy and Hyprland. A top pill opens a dashboard with Home, Media, System, Code, Calendar, Weather and Alerts tabs. It also draws wallpapers, a theme and wallpaper picker, a system tray and notification pop-ups. berri is a notification server.

### Screenshots

The maintainer will add these images after checking them for personal data.

![Pill at rest](docs/screenshots/pill.png)
![Dashboard tabs](docs/screenshots/dashboard.png)
![Theme and wallpaper picker](docs/screenshots/picker.png)

## Requirements

- Linux with a Wayland session. Hyprland is the current compositor. The shell uses its Quickshell integration.
- Quickshell 0.3.1 with Qt 6.11. These are the project versions, not tested minimum versions.
- IBM Plex Mono, IBM Plex Sans and IBM Plex Sans Condensed fonts.
- Rust and `cargo` to build the calendar feed parser.

Install the following commands on `PATH`. Some commands apply only to the named function.

| Commands | Use |
| --- | --- |
| `qs` | Run Quickshell, inspect instances and read logs. |
| `sh`, `bash` | Run shell scripts and QML process commands. |
| `curl` | Download calendar feeds and weather data. |
| `python3` | Read code statistics, GitHub statistics, local commits and agent usage. |
| `git`, `gh` | Clone the project and read commit data. GitHub statistics need an authenticated GitHub CLI. |
| `brightnessctl` | Read and set screen brightness. |
| `notify-send` | Send calendar reminders and low-battery alerts. |
| `magick` | Make a display-size copy of a Home sticker. Install ImageMagick for this command. |
| `hyprctl`, `hyprsunset` | Control night light. |
| `nvidia-smi` | Read temperature when an NVIDIA GPU is active. Needed only for that reading. |
| `codex` | Read Codex usage through `codex app-server`. Optional. |
| `basename`, `cat`, `cp`, `df`, `dirname`, `env`, `head`, `ls`, `mkdir`, `mktemp`, `mv`, `rm`, `rmdir`, `sleep`, `test`, `wc` | File operations, script interpreters, display detection and system readings. These are standard core utilities. |
| `find`, `grep`, `sed`, `ps`, `pgrep`, `setsid` | Find calendar files, read processes, control night light and run the restart or toggle scripts. |

For the related controls, provide NetworkManager, BlueZ, PipeWire, UPower and power-profiles-daemon. Quickshell accesses these services directly. Media controls need an MPRIS player. Sensor readings use Linux `/proc` and `/sys`; some readings depend on the hardware.

Development also needs `node` for the JavaScript tests. Python tests use the standard library. The pre-push hook needs `node`, `python3` and `cargo`.

## Install and run

Install the requirements with your distribution's package tools. Then clone the project:

```sh
git clone https://github.com/Nemesis-12/berri-shell.git
cd berri-shell
```

### Calendar feed parser

Build and install the parser from the repository root:

```sh
cargo build --release --manifest-path tools/feed-to-records/Cargo.toml
cp tools/feed-to-records/target/release/feed-to-records tools/feed-to-records/feed-to-records
```

berri finds the binary with `Quickshell.shellPath("tools/feed-to-records/feed-to-records")`. The parser reads one `.ics` path and writes one JSON path. Subscriptions use that JSON cache. Local editable calendars still use `.ics`.

If the binary is missing, the Calendar source view shows "Calendar parser is missing. Build tools/feed-to-records". At each start, berri makes each subscription's JSON again from its `.ics` file. This updates clock times after a system time zone change.

### Start once

First run `qs list --all`. If berri already runs, use that instance. Keep only one berri instance, including across worktrees. Another Quickshell configuration can remain active, such as the Omarchy app menu.

If berri is not running, start it from the repository root:

```sh
qs -p "$PWD"
```

The general command is `qs -p <path>`, where `<path>` is the repository folder. Quickshell reloads changes to existing QML files.

### Daily launch

Add one entry to your Hyprland autostart configuration. Replace the example path with the absolute path of your clone:

```ini
exec-once = qs -n -d -p /absolute/path/to/berri-shell
```

`-d` detaches the process. `-n` prevents a duplicate for the same configuration path. Use only one autostart entry and one clone for daily use. Do not stop the Omarchy app menu. If another notification server runs, remove its notification-server launch before using berri for notifications.

For an optional manual toggle, run `./toggle.sh` from this clone. It stops this configuration if it runs, or starts it with `-d`. It sets `MALLOC_CONF=background_thread:true,dirty_decay_ms:100,muzzy_decay_ms:100` on start.

Read logs with `qs log -i <instance-id>`. Find the ID with `qs list --all`.

### Use

Click the top pill to open the dashboard. Select a tab on its side. Click outside the dashboard to close it.

Click the bottom-center notch to open the theme and wallpaper picker. Select a theme, or add a wallpaper and assign it to a monitor or all monitors. Press Escape or click outside to close the picker. In fullscreen, move the pointer to the top or bottom edge to reveal the controls.

The Code tab reads GitHub data through `gh`. Authenticate with `gh auth login` for that data. Local commit discovery uses `~/Programming` by default. Set `BERRI_PROGRAMMING_ROOT` in the shell's launch environment to use another folder.

## Data folders

Back up these folders before changing or removing saved data.

| Folder | Contents |
| --- | --- |
| `~/.local/state/berri-shell/` | Theme choice, wallpaper assignments, calendar settings, reminders, notification history and saved control settings. |
| `~/.local/share/berri-shell/` | Wallpaper library in `wallpapers/`. Editable `.ics` calendars in `calendar/`. Feed `.ics` files and JSON records in `calendar/subscriptions/`. |
| `~/.config/berri-shell/` | Home sticker source and `sticker-display.png`. |
| `~/.cache/berri-shell/` | Code statistics, GitHub data, local commits and agent usage caches. These scripts use `$XDG_CACHE_HOME/berri-shell/` if `XDG_CACHE_HOME` is set. |

The QML state, share and config paths use `HOME` directly. They do not use the corresponding XDG overrides. The Home profile image uses `~/.face`. Weather can read Omarchy's location setting at `~/.local/state/omarchy/settings/weather.json`. Built-in theme data is in the repository's `data/` folder.

## Development

From the repository root, enable the hook once per clone:

```sh
git config core.hooksPath .githooks
```

### Folder layout

| Path | Purpose |
| --- | --- |
| `shell.qml` | Entry point and per-monitor windows. |
| `pill/`, `dashboard/` | Pill, tray, dashboard frame and tab selection. |
| `tabs/` | Home, Media, System, Code, Calendar, Weather and Alerts views. |
| `picker/` | Theme picker, wallpaper picker and wallpaper layer. |
| `notifications/` | Notification server, history, pop-ups and reminders. |
| `services/` | Shared data and system controls. |
| `common/` | Shared QML components and generated icons. |
| `logic/` | Pure JavaScript logic with `.pragma library`. |
| `scripts/` | Data collection, feed downloads, sticker conversion and Python tests. |
| `tools/` | Rust feed parser, icon generator and restart script. |
| `assets/`, `data/`, `shaders/` | Icons, theme data and rendering shaders. |
| `tests/` | Node tests and fixtures. |
| `.githooks/` | Pre-push test hook. |
| `scratchpad/` | Git-ignored temporary work. |

### Tests

Run all three test groups from the repository root:

```sh
node --test tests/
(cd scripts && python3 -m unittest test-*.py)
cargo test --manifest-path tools/feed-to-records/Cargo.toml --offline
```

You can also test the parser with `cargo test --manifest-path tools/feed-to-records/Cargo.toml`. The pre-push hook runs all three groups and stops a push if any group fails.

Existing QML files reload when their content changes. After adding or moving QML files, the maintainer must run `tools/restart-berri.sh` from the daily clone. Worktree agents must not run it or start another instance. Keep temporary files in `scratchpad/`.

## License and credits

berri-shell uses the [MIT license](LICENSE).

Icons come from [Lucide](https://lucide.dev/) under the ISC license. The bundled [icon license](assets/icons/lucide/LICENSE) also includes the MIT notice for icons derived from Feather.
