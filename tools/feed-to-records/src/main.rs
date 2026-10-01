//! Convert one iCalendar feed into the compact records read by berri.
//! Usage: feed-to-records INPUT.ics OUTPUT.json

use std::{
    env, fs, io,
    os::raw::{c_char, c_int, c_long},
    path::Path,
};

#[derive(Clone)]
enum CalendarDate {
    Date(String),
    DateTime {
        value: String,
        zone: Option<String>,
        utc: bool,
    },
}

#[derive(Default)]
struct Record {
    uid: String,
    kind: String,
    is_todo: bool,
    title: String,
    location: String,
    start: Option<CalendarDate>,
    end_value: Option<CalendarDate>,
    color: String,
    own_color: bool,
    repeat: String,
    interval: usize,
    by_day: Vec<usize>,
    until: Option<CalendarDate>,
    count: Option<usize>,
    exdates: Vec<CalendarDate>,
    done_dates: Vec<CalendarDate>,
    alarm_minutes: Option<usize>,
    status: Option<String>,
    override_event: bool,
}

/// One VALARM block while it is read. Only the simple form berri writes is used.
#[derive(Default)]
struct Alarm {
    trigger: Option<(Vec<(String, String)>, String)>,
    action: Option<String>,
    has_other_property: bool,
}

impl Alarm {
    // Same rules as parseAlarm in logic/CalendarFormat.js: a display alarm with one
    // duration trigger before (or at) the start gives minutes. Anything else gives None.
    fn minutes(&self) -> Option<usize> {
        if self.has_other_property || self.action.as_deref() != Some("DISPLAY") {
            return None;
        }
        let (params, value) = self.trigger.as_ref()?;
        let param = |name: &str| params.iter().rev().find(|(key, _)| key == name).map(|(_, v)| v);
        if param("VALUE").is_some_and(|v| !v.eq_ignore_ascii_case("DURATION"))
            || param("RELATED").is_some_and(|v| !v.eq_ignore_ascii_case("START"))
        {
            return None;
        }
        alarm_minutes(value.trim())
    }
}

#[derive(Default)]
struct Feed {
    name: String,
    records: Vec<Record>,
}

#[repr(C)]
#[derive(Default)]
struct Clock {
    second: c_int,
    minute: c_int,
    hour: c_int,
    day: c_int,
    month: c_int,
    year: c_int,
    weekday: c_int,
    yearday: c_int,
    daylight: c_int,
    offset: c_long,
    zone: *const c_char,
}

unsafe extern "C" {
    fn tzset();
    fn mktime(clock: *mut Clock) -> c_long;
    fn localtime_r(seconds: *const c_long, clock: *mut Clock) -> *mut Clock;
}

// Joins physical lines that start with a space or tab.
fn unfold(text: &str) -> Vec<String> {
    let mut lines: Vec<String> = Vec::new();
    for part in text.split(['\r', '\n']) {
        if let Some(rest) = part.strip_prefix([' ', '\t']) {
            if let Some(last) = lines.last_mut() {
                last.push_str(rest);
            }
        } else if !part.is_empty() {
            lines.push(part.to_owned());
        }
    }
    lines
}

// Splits an iCalendar property while quoted parameters can contain punctuation.
fn property(line: &str) -> Option<(String, Vec<(String, String)>, &str)> {
    let mut quote = false;
    let mut colon = None;
    let mut cuts = Vec::new();
    for (index, ch) in line.char_indices() {
        if ch == '"' {
            quote = !quote;
        } else if !quote && ch == ';' {
            cuts.push(index);
        } else if !quote && ch == ':' {
            colon = Some(index);
            break;
        }
    }
    let colon = colon?;
    let mut pieces = Vec::new();
    let mut start = 0;
    for cut in cuts {
        pieces.push(&line[start..cut]);
        start = cut + 1;
    }
    pieces.push(&line[start..colon]);
    let params = pieces[1..]
        .iter()
        .filter_map(|part| part.split_once('='))
        .map(|(key, value)| (key.to_ascii_uppercase(), value.trim_matches('"').to_owned()))
        .collect();
    Some((pieces[0].to_ascii_uppercase(), params, &line[colon + 1..]))
}

// Removes the text escapes defined by iCalendar.
fn text_value(value: &str) -> String {
    let mut output = String::new();
    let mut chars = value.chars();
    while let Some(ch) = chars.next() {
        if ch != '\\' {
            output.push(ch);
            continue;
        }
        match chars.next() {
            Some('n' | 'N') => output.push('\n'),
            Some(next @ ('\\' | ',' | ';')) => output.push(next),
            Some(next) => {
                output.push('\\');
                output.push(next);
            }
            None => output.push('\\'),
        }
    }
    output
}

// Reads a source date and keeps its date or date-time form.
fn calendar_date(value: &str, params: &[(String, String)]) -> Option<CalendarDate> {
    let value = value.trim();
    let bytes = value.as_bytes();
    if bytes.len() == 8 && bytes.iter().all(u8::is_ascii_digit) {
        return Some(CalendarDate::Date(value.to_owned()));
    }
    if (bytes.len() != 15 && bytes.len() != 16)
        || bytes[8] != b'T'
        || !bytes[..8].iter().all(u8::is_ascii_digit)
        || !bytes[9..15].iter().all(u8::is_ascii_digit)
        || (bytes.len() == 16 && bytes[15] != b'Z')
    {
        return None;
    }
    let zone = params
        .iter()
        .find(|(key, _)| key == "TZID")
        .map(|(_, value)| value.clone());
    Some(CalendarDate::DateTime {
        value: value.to_owned(),
        zone,
        utc: bytes.len() == 16,
    })
}

// Reads one repeat rule into the fields that berri uses.
fn repeat_rule(record: &mut Record, value: &str) {
    for part in value.split(';') {
        let Some((key, value)) = part.split_once('=') else {
            continue;
        };
        match key.to_ascii_uppercase().as_str() {
            "FREQ" => {
                record.repeat = match value.to_ascii_uppercase().as_str() {
                    "DAILY" => "daily",
                    "WEEKLY" => "weekly",
                    "MONTHLY" => "monthly",
                    "YEARLY" => "yearly",
                    _ => "none",
                }
                .to_owned()
            }
            "INTERVAL" => record.interval = value.parse::<usize>().unwrap_or(1).max(1),
            "COUNT" => record.count = value.parse::<usize>().ok().filter(|count| *count > 0),
            "UNTIL" => record.until = calendar_date(value, &[]),
            "BYDAY" => {
                let days: Option<Vec<usize>> = value
                    .split(',')
                    .map(|day| match day.to_ascii_uppercase().as_str() {
                        "SU" => Some(0),
                        "MO" => Some(1),
                        "TU" => Some(2),
                        "WE" => Some(3),
                        "TH" => Some(4),
                        "FR" => Some(5),
                        "SA" => Some(6),
                        _ => None,
                    })
                    .collect();
                if let Some(days) = days {
                    record.by_day = days;
                }
            }
            _ => {}
        }
    }
}

// Takes "<digits><unit>" from the front of the text. Leaves the text alone when it does not fit.
fn take_amount(rest: &mut &str, unit: char) -> Option<usize> {
    let digits = rest.bytes().take_while(u8::is_ascii_digit).count();
    if digits == 0 || !rest[digits..].starts_with(unit) {
        return None;
    }
    let amount = rest[..digits].parse().ok()?;
    *rest = &rest[digits + 1..];
    Some(amount)
}

// Reads a trigger duration such as -PT15M. Returns None for a trigger after the start.
fn alarm_minutes(value: &str) -> Option<usize> {
    let (before_start, mut rest) = match value.strip_prefix('-') {
        Some(rest) => (true, rest),
        None => (false, value),
    };
    rest = rest.strip_prefix('P')?;
    let weeks = take_amount(&mut rest, 'W').unwrap_or(0);
    let days = take_amount(&mut rest, 'D').unwrap_or(0);
    let (mut hours, mut minutes) = (0, 0);
    if let Some(time) = rest.strip_prefix('T') {
        rest = time;
        hours = take_amount(&mut rest, 'H').unwrap_or(0);
        minutes = take_amount(&mut rest, 'M').unwrap_or(0);
        take_amount(&mut rest, 'S');
    }
    if !rest.is_empty() {
        return None;
    }
    let total = weeks * 10080 + days * 1440 + hours * 60 + minutes;
    (before_start || total == 0).then_some(total)
}

// Reads events and tasks from one calendar feed.
fn read_feed(text: &str) -> Feed {
    let mut feed = Feed::default();
    let mut stack: Vec<String> = Vec::new();
    let mut event: Option<Record> = None;
    let mut alarm = Alarm::default();
    for line in unfold(text) {
        let Some((name, params, value)) = property(&line) else {
            if stack.len() == 3 && stack[2] == "VALARM" {
                alarm.has_other_property = true;
            }
            continue;
        };
        if name == "BEGIN" {
            stack.push(value.to_ascii_uppercase());
            if stack.len() == 2
                && stack[0] == "VCALENDAR"
                && (value.eq_ignore_ascii_case("VEVENT") || value.eq_ignore_ascii_case("VTODO"))
            {
                event = Some(Record {
                    kind: if value.eq_ignore_ascii_case("VTODO") {
                        "task"
                    } else {
                        "event"
                    }
                    .to_owned(),
                    is_todo: value.eq_ignore_ascii_case("VTODO"),
                    color: "accent".to_owned(),
                    repeat: "none".to_owned(),
                    interval: 1,
                    ..Record::default()
                });
            }
            if stack.len() == 3 && stack[2] == "VALARM" {
                alarm = Alarm::default();
            }
            continue;
        }
        if name == "END" {
            if stack.len() == 3 && stack[2] == "VALARM" {
                if let Some(record) = event.as_mut().filter(|r| r.alarm_minutes.is_none()) {
                    record.alarm_minutes = alarm.minutes();
                }
            } else if stack.len() == 2 {
                if let Some(mut record) = event.take() {
                    if record.uid.is_empty() {
                        record.uid = format!("missing-{}", feed.records.len());
                    }
                    if record.repeat == "none" {
                        record.interval = 1;
                        record.by_day.clear();
                        record.until = None;
                        record.count = None;
                    }
                    if !record.override_event {
                        feed.records.push(record);
                    }
                }
            }
            stack.pop();
            continue;
        }
        if stack.len() == 1
            && stack[0] == "VCALENDAR"
            && name == "X-WR-CALNAME"
            && feed.name.is_empty()
        {
            feed.name = text_value(value).trim().to_owned();
        }
        if stack.len() == 3 && stack[2] == "VALARM" {
            match name.as_str() {
                "TRIGGER" => alarm.trigger = Some((params.clone(), value.to_owned())),
                "ACTION" => alarm.action = Some(value.to_ascii_uppercase()),
                "DESCRIPTION" => {}
                _ => alarm.has_other_property = true,
            }
        }
        if stack.len() != 2 {
            continue;
        }
        let Some(record) = event.as_mut() else {
            continue;
        };
        match name.as_str() {
            "UID" => record.uid = value.to_owned(),
            "RECURRENCE-ID" => record.override_event = true,
            "SUMMARY" => record.title = text_value(value),
            "LOCATION" => record.location = text_value(value),
            "DTSTART" => record.start = calendar_date(value, &params),
            "DTEND" if !record.is_todo => record.end_value = calendar_date(value, &params),
            "DUE" if record.is_todo => record.end_value = calendar_date(value, &params),
            "RRULE" => repeat_rule(record, value),
            "EXDATE" => record.exdates.extend(
                value
                    .split(',')
                    .filter_map(|date| calendar_date(date, &params)),
            ),
            "X-BERRI-DONE" => record
                .done_dates
                .extend(value.split(',').filter_map(|date| calendar_date(date, &[]))),
            "X-BERRI-KIND" if value.eq_ignore_ascii_case("reminder") => {
                record.kind = "reminder".to_owned()
            }
            "X-BERRI-COLOR" => {
                if let Some(color) = clean_color(value) {
                    record.color = color;
                    record.own_color = true;
                }
            }
            "CATEGORIES" if !record.own_color => {
                let old = match value.trim().to_ascii_lowercase().as_str() {
                    "personal" => Some("accent"),
                    "work" => Some("blue"),
                    "health" => Some("green"),
                    "home" => Some("yellow"),
                    _ => None,
                };
                if let Some(color) = old {
                    record.color = color.to_owned();
                }
            }
            "STATUS" => record.status = Some(value.to_ascii_uppercase()),
            _ => {}
        }
    }
    feed.records.sort_by_cached_key(source_sort_key);
    feed
}

// Orders records by the local day and clock shown by berri.
fn source_sort_key(record: &Record) -> String {
    let local = record
        .start
        .as_ref()
        .or(record.end_value.as_ref())
        .and_then(local_clock);
    local
        .map(|(date, time)| format!("{}{}", date, time.unwrap_or_default()))
        .unwrap_or_default()
}

// Accepts the color keys and hex colors that berri can show.
fn clean_color(value: &str) -> Option<String> {
    let color = value.trim().to_ascii_lowercase();
    if [
        "accent", "blue", "green", "yellow", "red", "cyan", "magenta", "orange",
    ]
    .contains(&color.as_str())
    {
        return Some(color);
    }
    let hex = color.strip_prefix('#')?;
    if ![3, 6].contains(&hex.len()) || !hex.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        return None;
    }
    if hex.len() == 6 {
        return Some(color);
    }
    let mut full = String::from("#");
    for ch in hex.chars() {
        full.push(ch);
        full.push(ch);
    }
    Some(full)
}

// Sets TZ for the life of the guard and puts the old value back when it drops,
// on every return path.
struct ZoneGuard(Option<std::ffi::OsString>);

impl ZoneGuard {
    fn set(zone: &str) -> Self {
        let guard = ZoneGuard(env::var_os("TZ"));
        env::set_var("TZ", zone);
        unsafe { tzset() };
        guard
    }
}

impl Drop for ZoneGuard {
    fn drop(&mut self) {
        match self.0.take() {
            Some(zone) => env::set_var("TZ", zone),
            None => env::remove_var("TZ"),
        }
        unsafe { tzset() };
    }
}

// True when the zone name is a file in the time-zone database. Other names
// (for example "Eastern Standard Time") are unknown, as they are for the old
// JavaScript reader, and must not reach TZ, where mktime would treat them as UTC.
fn zone_known(name: &str) -> bool {
    if name.is_empty() || name.starts_with('/') || name.split('/').any(|part| part == "..") {
        return false;
    }
    let root = env::var_os("TZDIR")
        .filter(|dir| !dir.is_empty())
        .unwrap_or_else(|| "/usr/share/zoneinfo".into());
    Path::new(&root).join(name).is_file()
}

// Converts a source clock through the Linux time-zone database to local time.
// A clock in an unknown zone stays as written, like the old JavaScript reader.
fn local_clock(date: &CalendarDate) -> Option<(String, Option<String>)> {
    let (value, zone, utc) = match date {
        CalendarDate::Date(value) => {
            return Some((
                format!("{}-{}-{}", &value[..4], &value[4..6], &value[6..8]),
                None,
            ))
        }
        CalendarDate::DateTime { value, zone, utc } => (value, zone, utc),
    };
    if zone.as_deref().is_some_and(|name| !zone_known(name)) {
        return Some((
            format!("{}-{}-{}", &value[..4], &value[4..6], &value[6..8]),
            Some(format!("{}:{}", &value[9..11], &value[11..13])),
        ));
    }
    let mut clock = Clock {
        year: value[..4].parse::<i32>().ok()? - 1900,
        month: value[4..6].parse::<i32>().ok()? - 1,
        day: value[6..8].parse().ok()?,
        hour: value[9..11].parse().ok()?,
        minute: value[11..13].parse().ok()?,
        second: value[13..15].parse().ok()?,
        daylight: -1,
        ..Clock::default()
    };
    let instant = {
        let source_zone = if *utc { Some("UTC") } else { zone.as_deref() };
        let _restore = source_zone.map(ZoneGuard::set);
        unsafe { mktime(&mut clock) }
    };
    if instant == -1 {
        return None;
    }
    let mut local = Clock::default();
    if unsafe { localtime_r(&instant, &mut local) }.is_null() {
        return None;
    }
    Some((
        format!(
            "{:04}-{:02}-{:02}",
            local.year + 1900,
            local.month + 1,
            local.day
        ),
        Some(format!("{:02}:{:02}", local.hour, local.minute)),
    ))
}

// Moves an ISO date one day backward for exclusive all-day event ends.
fn previous_day(date: &str) -> String {
    let year = date[..4].parse::<i32>().unwrap_or(1970);
    let month = date[5..7].parse::<u32>().unwrap_or(1);
    let day = date[8..10].parse::<u32>().unwrap_or(1);
    let days = if day > 1 {
        (year, month, day - 1)
    } else if month > 1 {
        let prior = month - 1;
        (year, prior, days_in_month(year, prior))
    } else {
        (year - 1, 12, 31)
    };
    format!("{:04}-{:02}-{:02}", days.0, days.1, days.2)
}

// Returns the number of days in a month, including leap years.
fn days_in_month(year: i32, month: u32) -> u32 {
    match month {
        4 | 6 | 9 | 11 => 30,
        2 if year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) => 29,
        2 => 28,
        _ => 31,
    }
}

// Appends one escaped JSON string without an external crate.
fn json_string(output: &mut String, value: &str) {
    output.push('"');
    for ch in value.chars() {
        match ch {
            '"' => output.push_str("\\\""),
            '\\' => output.push_str("\\\\"),
            '\n' => output.push_str("\\n"),
            '\r' => output.push_str("\\r"),
            '\t' => output.push_str("\\t"),
            ch if ch <= '\u{001f}' => output.push_str(&format!("\\u{:04x}", ch as u32)),
            _ => output.push(ch),
        }
    }
    output.push('"');
}

// Appends a named string value or null.
fn field(output: &mut String, name: &str, value: Option<&str>) {
    json_string(output, name);
    output.push(':');
    if let Some(value) = value {
        json_string(output, value);
    } else {
        output.push_str("null");
    }
    output.push(',');
}

// Appends a named number value or null.
fn number(output: &mut String, name: &str, value: Option<usize>) {
    json_string(output, name);
    output.push(':');
    if let Some(value) = value {
        output.push_str(&value.to_string());
    } else {
        output.push_str("null");
    }
    output.push(',');
}

// Appends a named list of already-written JSON values, or null when the list is empty.
fn list(output: &mut String, name: &str, values: &[String]) {
    json_string(output, name);
    output.push(':');
    if values.is_empty() {
        output.push_str("null,");
        return;
    }
    output.push('[');
    output.push_str(&values.join(","));
    output.push_str("],");
}

// Appends a named list of strings, or null when the list is empty.
fn string_list(output: &mut String, name: &str, values: &[String]) {
    let quoted: Vec<String> = values
        .iter()
        .map(|value| {
            let mut text = String::new();
            json_string(&mut text, value);
            text
        })
        .collect();
    list(output, name, &quoted);
}

// Appends a named list of numbers, or null when the list is empty.
fn number_list(output: &mut String, name: &str, values: &[usize]) {
    let numbers: Vec<String> = values.iter().map(usize::to_string).collect();
    list(output, name, &numbers);
}

// Writes one record with the field names used by CalendarFormat.js.
fn record_json(output: &mut String, record: &Record) {
    let start = record
        .start
        .as_ref()
        .or(record.end_value.as_ref())
        .and_then(local_clock);
    let end = record.end_value.as_ref().and_then(local_clock);
    let all_day = matches!(record.start, Some(CalendarDate::Date(_)));
    let date = start.as_ref().map(|(date, _)| date.as_str());
    let time = start.as_ref().and_then(|(_, time)| time.as_deref());
    let mut end_time = None;
    let mut end_date = None;
    if let (Some((start_date, start_time)), Some((last_date, last_time))) = (&start, &end) {
        if all_day {
            let last = if record.is_todo {
                last_date.clone()
            } else {
                previous_day(last_date)
            };
            if last > *start_date {
                end_date = Some(last);
            }
        } else if last_time.is_some() {
            if last_time != start_time || last_date != start_date {
                end_time = last_time.as_deref();
            }
            if last_date != start_date {
                end_date = Some(last_date.clone());
            }
        }
    }
    let until = record
        .until
        .as_ref()
        .and_then(local_clock)
        .map(|(date, _)| date);
    let exdates: Vec<String> = record
        .exdates
        .iter()
        .filter_map(local_clock)
        .map(|(date, _)| date)
        .collect();
    let mut done_dates: Vec<String> = record
        .done_dates
        .iter()
        .filter_map(local_clock)
        .map(|(date, _)| date)
        .collect();
    if record.status.as_deref() == Some("COMPLETED") && record.repeat == "none" {
        if let Some(date) = date {
            if !done_dates.iter().any(|done| done == date) {
                done_dates.push(date.to_owned());
            }
        }
    }
    output.push('{');
    field(output, "uid", Some(&record.uid));
    field(output, "kind", Some(&record.kind));
    field(output, "title", Some(&record.title));
    field(output, "location", Some(&record.location));
    field(output, "date", date);
    field(output, "time", time);
    field(output, "end", end_time);
    field(output, "endDate", end_date.as_deref());
    field(output, "color", Some(&record.color));
    field(output, "repeat", Some(&record.repeat));
    number(output, "interval", Some(record.interval));
    number_list(output, "byDay", &record.by_day);
    field(output, "until", until.as_deref());
    number(output, "count", record.count);
    string_list(output, "exdates", &exdates);
    string_list(output, "doneDates", &done_dates);
    number(output, "alarmMinutes", record.alarm_minutes);
    let status = record
        .status
        .as_deref()
        .filter(|value| *value != "COMPLETED" && *value != "NEEDS-ACTION");
    field(output, "status", status);
    output.pop();
    output.push('}');
}

// Converts the complete feed into one compact JSON object.
fn feed_json(feed: &Feed) -> String {
    let mut output = String::new();
    output.push_str("{\"name\":");
    json_string(&mut output, &feed.name);
    output.push_str(",\"records\":[");
    for (index, record) in feed.records.iter().enumerate() {
        if index > 0 {
            output.push(',');
        }
        record_json(&mut output, record);
    }
    output.push_str("]}");
    output
}

// Reads one input file and writes one JSON file.
fn convert(input: &Path, output: &Path) -> io::Result<()> {
    let text = fs::read_to_string(input)?;
    if !text.lines().any(|line| {
        line.trim_end_matches('\r')
            .eq_ignore_ascii_case("BEGIN:VCALENDAR")
    }) {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "not a calendar feed",
        ));
    }
    let feed = read_feed(&text);
    let temporary = output.with_extension(format!("json.tmp.{}", std::process::id()));
    fs::write(&temporary, feed_json(&feed))?;
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
