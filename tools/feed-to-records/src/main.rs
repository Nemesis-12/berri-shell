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
    // Week number (1 to 5, or -1 for the last) and weekday (0 = Sunday) of a monthly rule such as BYDAY=2TU.
    month_weekday: Option<(i32, usize)>,
    until: Option<CalendarDate>,
    count: Option<usize>,
    exdates: Vec<CalendarDate>,
    done_dates: Vec<CalendarDate>,
    alarm_minutes: Option<usize>,
    status: Option<String>,
    // Set on a RECURRENCE-ID component: the start of the occurrence it replaces.
    recurrence_id: Option<CalendarDate>,
    override_event: bool,
    changed: Vec<ChangedOccurrence>,
}

/// What a feed changed in one occurrence of a repeating event. Date and clock fields are None for a cancelled occurrence.
struct ChangedOccurrence {
    from: String,
    cancelled: bool,
    title: Option<String>,
    timing: Timing,
}

/// The shown date and clock of a record: start day and time, end time, and last day of a longer event.
#[derive(Default)]
struct Timing {
    date: Option<String>,
    time: Option<String>,
    end: Option<String>,
    end_date: Option<String>,
}

/// How a repeating event in a named zone moves through the daylight-saving changes of that zone.
struct ZonedSeries {
    date: String,
    time: String,
    length: Option<i64>,
    // Offset from UTC in seconds from each source day on: (first day, offset).
    offsets: Vec<(String, i64)>,
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
    // RECURRENCE-ID components, until they are attached to their repeating event.
    overrides: Vec<Record>,
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
    // The seconds are optional, as in the JavaScript reader. A missing seconds part is read as 00.
    let (clock, utc) = match value.strip_suffix('Z') {
        Some(clock) => (clock, true),
        None => (value, false),
    };
    let bytes = clock.as_bytes();
    if (bytes.len() != 13 && bytes.len() != 15)
        || bytes[8] != b'T'
        || !bytes[..8].iter().all(u8::is_ascii_digit)
        || !bytes[9..].iter().all(u8::is_ascii_digit)
    {
        return None;
    }
    let value = if bytes.len() == 13 {
        format!("{clock}00{}", if utc { "Z" } else { "" })
    } else {
        value.to_owned()
    };
    let zone = params
        .iter()
        .find(|(key, _)| key == "TZID")
        .map(|(_, value)| value.clone());
    Some(CalendarDate::DateTime { value, zone, utc })
}

// Reads one repeat rule into the fields that berri uses.
fn repeat_rule(record: &mut Record, value: &str) {
    let mut ordinal_day = None;
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
                } else {
                    ordinal_day = ordinal_weekday(value);
                }
            }
            _ => {}
        }
    }
    // A week number counts only in a monthly rule, and FREQ can come after BYDAY.
    if record.repeat == "monthly" {
        record.month_weekday = ordinal_day;
    }
}

// Reads one BYDAY value with a week number, such as 2TU or -1FR.
fn ordinal_weekday(value: &str) -> Option<(i32, usize)> {
    let (week, day) = value.split_at(value.len().checked_sub(2)?);
    let nth: i32 = week.parse().ok()?;
    let digits = week.trim_start_matches(['+', '-']);
    if digits.len() != 1 || !(1..=5).contains(&nth.abs()) {
        return None;
    }
    let day = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"]
        .iter()
        .position(|name| name.eq_ignore_ascii_case(day))?;
    Some((nth, day))
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

const MAX_EXACT_MINUTES: usize = (1 << 53) - 1;

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
    // A total above 2^53 - 1 cannot be counted exactly by the JavaScript reader, so it is not an alarm.
    let total = weeks
        .checked_mul(10080)?
        .checked_add(days.checked_mul(1440)?)?
        .checked_add(hours.checked_mul(60)?)?
        .checked_add(minutes)?;
    (total <= MAX_EXACT_MINUTES && (before_start || total == 0)).then_some(total)
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
                    if record.override_event {
                        feed.overrides.push(record);
                    } else {
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
            "RECURRENCE-ID" => {
                record.override_event = true;
                record.recurrence_id = calendar_date(value, &params);
            }
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
    attach_overrides(&mut feed);
    feed.records.sort_by_cached_key(source_sort_key);
    feed
}

// Gives each repeating event the changes that RECURRENCE-ID components make to its occurrences.
fn attach_overrides(feed: &mut Feed) {
    for over in std::mem::take(&mut feed.overrides) {
        let Some(from) = over
            .recurrence_id
            .as_ref()
            .and_then(local_clock)
            .map(|(date, _)| date)
        else {
            continue;
        };
        let cancelled = over.status.as_deref() == Some("CANCELLED");
        let timing = if cancelled {
            Timing::default()
        } else {
            timing(&over)
        };
        let title = (!cancelled && !over.title.is_empty()).then(|| over.title.clone());
        let series = feed
            .records
            .iter_mut()
            .find(|record| record.uid == over.uid && record.repeat != "none");
        if let Some(series) = series.filter(|_| !over.uid.is_empty()) {
            series.changed.push(ChangedOccurrence {
                from,
                cancelled,
                title,
                timing,
            });
        }
    }
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

// The instant of a source clock "YYYYMMDDTHHMMSS" in `zone`, or in the system zone for None.
fn instant_of(value: &str, zone: Option<&str>) -> Option<c_long> {
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
        let _restore = zone.map(ZoneGuard::set);
        unsafe { mktime(&mut clock) }
    };
    (instant != -1).then_some(instant)
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
    let instant = {
        let source_zone = if *utc { Some("UTC") } else { zone.as_deref() };
        instant_of(value, source_zone)?
    };
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

// Days since 1970-01-01 of a calendar day (Howard Hinnant's civil-days algorithm).
fn days_from_civil(year: i64, month: i64, day: i64) -> i64 {
    let year = if month <= 2 { year - 1 } else { year };
    let era = year.div_euclid(400);
    let year_of_era = year - era * 400;
    let day_of_year = (153 * (month + if month > 2 { -3 } else { 9 }) + 2) / 5 + day - 1;
    let day_of_era = year_of_era * 365 + year_of_era / 4 - year_of_era / 100 + day_of_year;
    era * 146097 + day_of_era - 719468
}

// The calendar day (year, month, day) of a day count from days_from_civil.
fn civil_from_days(days: i64) -> (i64, i64, i64) {
    let days = days + 719468;
    let era = days.div_euclid(146097);
    let day_of_era = days - era * 146097;
    let year_of_era =
        (day_of_era - day_of_era / 1460 + day_of_era / 36524 - day_of_era / 146096) / 365;
    let day_of_year = day_of_era - (365 * year_of_era + year_of_era / 4 - year_of_era / 100);
    let month_index = (5 * day_of_year + 2) / 153;
    let day = day_of_year - (153 * month_index + 2) / 5 + 1;
    let month = if month_index < 10 { month_index + 3 } else { month_index - 9 };
    let year = year_of_era + era * 400 + i64::from(month <= 2);
    (year, month, day)
}

fn day_key(days: i64) -> String {
    let (year, month, day) = civil_from_days(days);
    format!("{year:04}-{month:02}-{day:02}")
}

// A zoned series is followed for ten years, in steps of this many days (same values as CalendarFormat.js).
const ZONE_SCAN_DAYS: i64 = 3660;
const ZONE_SCAN_STEP: i64 = 21;

// The source-zone data of a repeating event with a named zone (see zonedSeries in CalendarFormat.js).
// Returns None for other events and for an unknown zone.
fn zoned_series(record: &Record) -> Option<ZonedSeries> {
    let Some(CalendarDate::DateTime {
        value,
        zone: Some(zone),
        utc: false,
    }) = &record.start
    else {
        return None;
    };
    if record.repeat == "none" || !zone_known(zone) {
        return None;
    }
    let first = days_from_civil(
        value[..4].parse().ok()?,
        value[4..6].parse().ok()?,
        value[6..8].parse().ok()?,
    );
    let clock_seconds = value[9..11].parse::<i64>().ok()? * 3600 + value[11..13].parse::<i64>().ok()? * 60;
    // Offset of the source zone at the event's clock on one source day.
    let offset_on = |day: i64| -> Option<i64> {
        let (year, month, date) = civil_from_days(day);
        let mut clock = Clock {
            year: i32::try_from(year - 1900).ok()?,
            month: i32::try_from(month - 1).ok()?,
            day: i32::try_from(date).ok()?,
            hour: i32::try_from(clock_seconds / 3600).ok()?,
            minute: i32::try_from(clock_seconds % 3600 / 60).ok()?,
            daylight: -1,
            ..Clock::default()
        };
        let instant = unsafe { mktime(&mut clock) };
        (instant != -1).then(|| day * 86400 + clock_seconds - instant)
    };
    let mut offsets;
    {
        let _restore = ZoneGuard::set(zone);
        let mut offset = offset_on(first)?;
        offsets = vec![(day_key(first), offset)];
        let mut before = first;
        let mut day = first + ZONE_SCAN_STEP;
        while day <= first + ZONE_SCAN_DAYS {
            let now = offset_on(day)?;
            if now != offset {
                // The offset changes on a day after `low`, up to `high`.
                let (mut low, mut high) = (before, day);
                while high - low > 1 {
                    let middle = (low + high) / 2;
                    if offset_on(middle)? == offset {
                        low = middle;
                    } else {
                        high = middle;
                    }
                }
                offsets.push((day_key(high), now));
                offset = now;
            }
            before = day;
            day += ZONE_SCAN_STEP;
        }
    }
    let start = instant_of(value, Some(zone))?;
    let length = match &record.end_value {
        Some(CalendarDate::DateTime { value, zone, utc }) if *utc || zone.as_deref().is_none_or(zone_known) => {
            let source_zone = if *utc { Some("UTC") } else { zone.as_deref() };
            instant_of(value, source_zone)
                .map(|end| (end - start + 30).div_euclid(60))
                .filter(|length| *length >= 0)
        }
        _ => None,
    };
    Some(ZonedSeries {
        date: day_key(first),
        time: format!("{}:{}", &value[9..11], &value[11..13]),
        length,
        offsets,
    })
}

// The shown start, end and last day of a record, as the JavaScript reader gives them.
fn timing(record: &Record) -> Timing {
    let start = record
        .start
        .as_ref()
        .or(record.end_value.as_ref())
        .and_then(local_clock);
    let end = record.end_value.as_ref().and_then(local_clock);
    let all_day = matches!(record.start, Some(CalendarDate::Date(_)));
    let mut timing = Timing {
        date: start.as_ref().map(|(date, _)| date.clone()),
        time: start.as_ref().and_then(|(_, time)| time.clone()),
        ..Timing::default()
    };
    if let (Some((start_date, start_time)), Some((last_date, last_time))) = (&start, &end) {
        if all_day {
            let last = if record.is_todo {
                last_date.clone()
            } else {
                previous_day(last_date)
            };
            if last > *start_date {
                timing.end_date = Some(last);
            }
        } else if last_time.is_some() {
            if last_time != start_time || last_date != start_date {
                timing.end = last_time.clone();
            }
            if last_date != start_date {
                timing.end_date = Some(last_date.clone());
            }
        }
    }
    timing
}

// Writes one record with the field names used by CalendarFormat.js.
fn record_json(output: &mut String, record: &Record) {
    let Timing {
        date,
        time,
        end: end_time,
        end_date,
    } = timing(record);
    let date = date.as_deref();
    let time = time.as_deref();
    let end_time = end_time.as_deref();
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
    json_string(output, "monthWeekday");
    match record.month_weekday {
        Some((nth, day)) => output.push_str(&format!(":{{\"nth\":{nth},\"day\":{day}}},")),
        None => output.push_str(":null,"),
    }
    zoned_json(output, zoned_series(record).as_ref());
    changed_json(output, &record.changed);
    output.pop();
    output.push('}');
}

// Appends the zoned field: the source-zone data of a repeating event, or null.
fn zoned_json(output: &mut String, zoned: Option<&ZonedSeries>) {
    json_string(output, "zoned");
    output.push(':');
    let Some(zoned) = zoned else {
        output.push_str("null,");
        return;
    };
    output.push('{');
    field(output, "date", Some(&zoned.date));
    field(output, "time", Some(&zoned.time));
    number(output, "length", zoned.length.map(|length| length as usize));
    let offsets: Vec<String> = zoned
        .offsets
        .iter()
        .map(|(day, offset)| format!("[\"{day}\",{offset}]"))
        .collect();
    list(output, "offsets", &offsets);
    output.pop();
    output.push_str("},");
}

// Appends the changedOccurrences field: the changes a feed made to single occurrences.
fn changed_json(output: &mut String, changed: &[ChangedOccurrence]) {
    let entries: Vec<String> = changed
        .iter()
        .map(|change| {
            let mut entry = String::from("{");
            field(&mut entry, "from", Some(&change.from));
            entry.push_str(&format!("\"cancelled\":{},", change.cancelled));
            field(&mut entry, "title", change.title.as_deref());
            field(&mut entry, "date", change.timing.date.as_deref());
            field(&mut entry, "time", change.timing.time.as_deref());
            field(&mut entry, "end", change.timing.end.as_deref());
            field(&mut entry, "endDate", change.timing.end_date.as_deref());
            entry.pop();
            entry.push('}');
            entry
        })
        .collect();
    json_string(output, "changedOccurrences");
    output.push(':');
    output.push_str(&format!("[{}],", entries.join(",")));
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
