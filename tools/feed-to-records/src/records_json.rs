//! The compact JSON of a feed, with the field names used by CalendarFormat.js.

use crate::date::CalendarDate;
use crate::json::{field, json_string, list, number, number_list, string_list};
use crate::model::{Feed, Record, Status};
use crate::overrides::ChangedOccurrence;
use crate::timing::{timing, Timing};
use crate::zone::{instant_of, local_day, source_zone, zone_known};
use crate::zoned::{zoned_series, ZonedSeries};

// The local days of a list of source dates.
fn local_days(dates: &[crate::date::CalendarDate]) -> Vec<String> {
    dates.iter().filter_map(local_day).collect()
}

// The days on which a record is done. A completed single record is done on its day.
fn done_days(record: &Record, date: Option<&str>) -> Vec<String> {
    let mut done_dates = local_days(&record.done_dates);
    if record.status == Some(Status::Completed) && !record.repeats() {
        if let Some(date) = date {
            if !done_dates.iter().any(|done| done == date) {
                done_dates.push(date.to_owned());
            }
        }
    }
    done_dates
}

// Appends the monthWeekday field: the week number and weekday of a monthly rule, or null.
fn month_weekday_json(output: &mut String, month_weekday: Option<(i32, usize)>) {
    json_string(output, "monthWeekday");
    match month_weekday {
        Some((nth, day)) => output.push_str(&format!(":{{\"nth\":{nth},\"day\":{day}}},")),
        None => output.push_str(":null,"),
    }
}

// Names of unknown source zones, used by the same calendar source note as editable files.
fn unknown_zones(record: &Record) -> Vec<String> {
    let mut zones = Vec::new();
    for date in record.start.iter().chain(record.end_value.iter()).chain(record.until.iter()).chain(record.exdates.iter()) {
        if let CalendarDate::DateTime { zone: Some(zone), utc: false, .. } = date {
            if !zone_known(zone) && !zones.contains(zone) {
                zones.push(zone.clone());
            }
        }
    }
    zones
}

// Writes one record with the field names used by CalendarFormat.js.
fn record_json(output: &mut String, record: &Record) {
    let Timing {
        date,
        time,
        end: end_time,
        end_date,
    } = timing(record);
    let until = record.until.as_ref().and_then(local_day);
    let done_dates = done_days(record, date.as_deref());
    output.push('{');
    field(output, "uid", Some(&record.uid));
    field(output, "kind", Some(record.kind.name()));
    field(output, "title", Some(&record.title));
    field(output, "location", Some(&record.location));
    field(output, "date", date.as_deref());
    field(output, "time", time.as_deref());
    field(output, "end", end_time.as_deref());
    field(output, "endDate", end_date.as_deref());
    field(output, "color", Some(&record.color));
    field(output, "repeat", Some(record.repeat.name()));
    number(output, "interval", Some(record.interval));
    number_list(output, "byDay", &record.by_day);
    field(output, "until", until.as_deref());
    number(output, "count", record.count);
    string_list(output, "exdates", &local_days(&record.exdates));
    string_list(output, "doneDates", &done_dates);
    output.push_str("\"alarmMinutes\":");
    output.push_str(&record.alarm_minutes.map_or_else(|| "null".to_owned(), |minutes| minutes.to_string()));
    output.push(',');
    field(output, "status", record.status.as_ref().and_then(Status::shown));
    field(output, "ruleRest", record.rule_rest.as_deref());
    month_weekday_json(output, record.month_weekday);
    zoned_json(output, zoned_series(record).as_ref());
    changed_json(output, &record.changed);
    let until_ms = match &record.until {
        Some(CalendarDate::DateTime { value, zone, utc }) => {
            instant_of(value, source_zone(zone.as_deref(), *utc)).map(|seconds| seconds * 1000)
        }
        _ => None,
    };
    output.push_str("\"untilMs\":");
    output.push_str(&until_ms.map_or_else(|| "null".to_owned(), |ms| ms.to_string()));
    output.push(',');
    let start_second = match record.start.as_ref().or(record.end_value.as_ref()) {
        Some(CalendarDate::DateTime { value, .. }) => value[13..15].parse().ok(),
        _ => Some(0),
    };
    number(output, "startSecond", start_second);
    string_list(output, "unknownZones", &unknown_zones(record));
    string_list(output, "raw", &record.raw);
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
pub fn feed_json(feed: &Feed) -> String {
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
