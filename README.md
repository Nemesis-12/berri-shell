# berri-shell
A minimal Quickshell pill bar for Wayland that opens into a full dashboard, with live themes, wallpaper transitions, calendar and notifications

## Setup

Run `git config core.hooksPath .githooks` once after cloning. It runs the tests before every push.

## Calendar feed parser

Build and install the parser in the shell folder:

```sh
cargo build --release --manifest-path tools/feed-to-records/Cargo.toml
cp tools/feed-to-records/target/release/feed-to-records tools/feed-to-records/feed-to-records
```

berri finds the installed binary with `Quickshell.shellPath("tools/feed-to-records/feed-to-records")`. Run `cargo test --manifest-path tools/feed-to-records/Cargo.toml` to test it. The parser reads one `.ics` path and writes one JSON path. Subscriptions use that JSON cache; local editable calendars still use `.ics`. If the program is missing, the Calendar source view shows "Calendar parser is missing. Build tools/feed-to-records". berri makes every subscription's JSON again from its `.ics` file at each start, so a changed system time zone never leaves old clock times. The pre-push hook needs `cargo`.
