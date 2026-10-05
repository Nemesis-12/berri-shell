# berri-shell

berri is a Quickshell desktop shell for Omarchy and Hyprland. A top pill opens a dashboard with Home, Media, System, Code, Calendar, Weather and Alerts tabs. It also draws wallpapers, a theme and wallpaper picker, a system tray and notification pop-ups. berri is a notification server.

## Requirements

You need:

- Linux with Wayland. Hyprland is the current compositor.
- Quickshell 0.3.1 with Qt 6.11.
- These fonts: IBM Plex Mono, IBM Plex Sans, IBM Plex Sans Condensed.
- Rust and `cargo` to build the calendar parser.
- These programs: `qs`, `curl`, `python3`, `git`, `gh`, `brightnessctl`, `notify-send`, `magick` (ImageMagick), `hyprctl`, `hyprsunset`.
- Optional: `nvidia-smi` for NVIDIA temperature, `codex` for Codex usage.
- These services for the related controls: NetworkManager, BlueZ, PipeWire, UPower, power-profiles-daemon. Media controls need an MPRIS player.

Authenticate `gh` with `gh auth login` to use the Code tab.

## Install

Install the requirements with your distribution tools. Then clone the project:

```sh
git clone https://github.com/Nemesis-12/berri-shell.git
cd berri-shell
```

Build the calendar parser from the repository root:

```sh
cargo build --release --manifest-path tools/feed-to-records/Cargo.toml
cp tools/feed-to-records/target/release/feed-to-records tools/feed-to-records/feed-to-records
```

If the binary is missing, the Calendar source view shows a warning. Rebuild it with the same commands.

## Run

First check for a running instance:

```sh
qs list --all
```

Keep only one berri instance. Another Quickshell configuration can stay active, such as the Omarchy app menu.

If berri is not running, start it from the repository root:

```sh
qs -p "$PWD"
```

For daily use, add one autostart entry to Hyprland. Replace the path with your clone path:

```ini
exec-once = qs -n -d -p /absolute/path/to/berri-shell
```

Use only one autostart entry and one clone for daily use. Keep the Omarchy app menu running. berri is the sole notification server. See "Notification ownership".

For a manual toggle, run `./toggle.sh` from this clone. It stops this configuration if it runs, or starts it again.

Read logs with `qs log -i <instance-id>`. Find the ID with `qs list --all`.

## Notification ownership

berri starts its notification server by default. There is no setting to turn it off. berri must be the sole owner of `org.freedesktop.Notifications` on the session D-Bus. Other notification daemons must not run. This includes `mako`, which Omarchy ships. Before you start berri, remove other notification-daemon launches from your autostart configuration or user services. Keep the Omarchy app menu running.

If another daemon already owns the name, berri leaves it running. Quickshell writes a warning to the berri log and retries when that daemon releases the name. Until then, the other daemon receives notifications; berri receives none. Use `qs log -i <instance-id>` to check for the warning. berri does not stop or disable other daemons.

Reminders and the low-battery alert follow the same rule. Both call `notify-send`, so the owner of `org.freedesktop.Notifications` receives them. With berri as sole owner, they show in Alerts and as pop-ups. A reminder pop-up has two actions: +15m and Done. If a reminder cannot be sent, berri tries again every 30 seconds.

The old `serverEnabled` key in saved notification state is ignored. Saved history and do not disturb state still load. No saved-data reset is needed.

## Use

Click the top pill to open the dashboard. Select a tab on its side. Click outside the dashboard to close it.

Click the bottom-center notch to open the theme and wallpaper picker. Select a theme, or add a wallpaper and assign it to a monitor or to all monitors. Press Escape or click outside to close the picker. In fullscreen, move the pointer to the top or bottom edge to reveal the controls.

Local commit discovery uses `~/Programming` by default. Set `BERRI_PROGRAMMING_ROOT` in the shell launch environment to use another folder.

## Saved data

Back up these folders before you change or remove saved data:

| Folder | Contents |
| --- | --- |
| `~/.local/state/berri-shell/` | Theme choice, wallpaper assignments, calendar settings, reminders, notification history, saved control settings. |
| `~/.local/share/berri-shell/` | Wallpaper library, editable calendars, feed files and JSON records. |
| `~/.config/berri-shell/` | Home sticker source and display copy. |
| `~/.cache/berri-shell/` | Code statistics, GitHub data, local commit and agent usage caches. |

The Home profile image uses `~/.face`. Weather can read the Omarchy location at `~/.local/state/omarchy/settings/weather.json`.

### Weather location

Weather lookup is automatic. There is no off switch. berri reads the Omarchy location first. If that file is missing or invalid, it uses an IP-based lookup. It sends latitude and longitude to `api.open-meteo.com` for the forecast, and to `wttr.in` for the place name when needed.

## License and credits

berri-shell uses the [MIT license](LICENSE).

Icons come from [Lucide](https://lucide.dev/) under the ISC license. The bundled [icon license](assets/icons/lucide/LICENSE) also includes the MIT notice for icons derived from Feather.

## Development

Development also needs `node` for the JavaScript tests and Qt's `qmltestrunner` with QtTest for offscreen QML tests. Set `QMLTESTRUNNER` if it is not at `/usr/lib/qt6/bin/qmltestrunner`. It also needs `qml6` for isolated weather service tests. These tests use Qt's offscreen platform, fake services or synthetic data. They do not start a shell instance or make network requests. Python tests use the standard library. The pre-push hook needs `node`, `qmltestrunner`, `qml6`, `python3` and `cargo`.
