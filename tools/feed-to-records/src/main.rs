//! Convert one iCalendar feed into the compact records read by berri.
//! Usage: feed-to-records INPUT.ics OUTPUT.json

mod alarm;
mod color;
mod date;
mod json;
mod model;
mod overrides;
mod reader;
mod recurrence;
mod records_json;
mod text;
mod timing;
mod zone;
mod zoned;

use std::{
    env, fs,
    io::{self, Write},
    os::unix::fs::OpenOptionsExt,
    path::Path,
};

use reader::read_feed;
use records_json::feed_json;

// Reads one input file and writes one JSON file.
fn convert(input: &Path, output: &Path) -> io::Result<()> {
    // Bad bytes become U+FFFD and a leading byte-order mark is dropped, so one bad byte does not reject the feed.
    let bytes = fs::read(input)?;
    let decoded = String::from_utf8_lossy(&bytes);
    let text = decoded.strip_prefix('\u{feff}').unwrap_or(&decoded);
    if !text.lines().any(|line| {
        line.trim_end_matches('\r')
            .eq_ignore_ascii_case("BEGIN:VCALENDAR")
    }) {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "not a calendar feed",
        ));
    }
    let feed = read_feed(text);
    let temporary = output.with_extension(format!("json.tmp.{}", std::process::id()));
    // The records file is owner-only, whatever the creation mask is.
    let mut file = fs::OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .mode(0o600)
        .open(&temporary)?;
    file.write_all(feed_json(&feed).as_bytes())?;
    drop(file);
    fs::rename(temporary, output)
}

// Checks arguments and reports a file error to the caller.
fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() != 3 {
        eprintln!("Usage: feed-to-records INPUT.ics OUTPUT.json");
        std::process::exit(2);
    }
    if let Err(error) = convert(Path::new(&args[1]), Path::new(&args[2])) {
        eprintln!("feed-to-records: {error}");
        std::process::exit(1);
    }
}
