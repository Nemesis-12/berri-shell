//! Daylight-saving data of a repeating event in a named zone.

use crate::date::{civil_from_days, day_key, days_from_civil, CalendarDate};
use crate::model::Record;
use crate::zone::{instant_of, mktime, source_zone, zone_known, Clock, ZoneGuard};

/// How a repeating event in a named zone moves through the daylight-saving changes of that zone.
pub struct ZonedSeries {
    pub date: String,
    pub time: String,
    pub length: Option<i64>,
    // Offset from UTC in seconds from each source day on: (first day, offset).
    pub offsets: Vec<(String, i64)>,
}

// A zoned series is followed for ten years, in steps of this many days (same values as CalendarFormat.js).
const ZONE_SCAN_DAYS: i64 = 3660;
const ZONE_SCAN_STEP: i64 = 21;

// Offset of the current zone at a clock time (seconds in the day) on one source day.
fn offset_on(day: i64, clock_seconds: i64) -> Option<i64> {
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
}

// The first day after `low`, up to `high`, with an offset other than `offset`.
fn change_day(mut low: i64, mut high: i64, offset: i64, clock_seconds: i64) -> Option<i64> {
    while high - low > 1 {
        let middle = (low + high) / 2;
        if offset_on(middle, clock_seconds)? == offset {
            low = middle;
        } else {
            high = middle;
        }
    }
    Some(high)
}

// Every offset change of the current zone in the scanned years, from the first day on.
fn zone_offsets(first: i64, clock_seconds: i64) -> Option<Vec<(String, i64)>> {
    let mut offset = offset_on(first, clock_seconds)?;
    let mut offsets = vec![(day_key(first), offset)];
    let mut before = first;
    let mut day = first + ZONE_SCAN_STEP;
    while day <= first + ZONE_SCAN_DAYS {
        let now = offset_on(day, clock_seconds)?;
        if now != offset {
            offsets.push((day_key(change_day(before, day, offset, clock_seconds)?), now));
            offset = now;
        }
        before = day;
        day += ZONE_SCAN_STEP;
    }
    Some(offsets)
}

// The length in minutes of an event that starts at `start`. None when the end is unknown or before the start.
fn series_length(record: &Record, start: i64) -> Option<i64> {
    match &record.end_value {
        Some(CalendarDate::DateTime { value, zone, utc })
            if *utc || zone.as_deref().is_none_or(zone_known) =>
        {
            instant_of(value, source_zone(zone.as_deref(), *utc))
                .map(|end| (end - start + 30).div_euclid(60))
                .filter(|length| *length >= 0)
        }
        _ => None,
    }
}

// The source-zone data of a repeating event with a named zone (see zonedSeries in CalendarFormat.js).
// Returns None for other events and for an unknown zone.
pub fn zoned_series(record: &Record) -> Option<ZonedSeries> {
    let Some(CalendarDate::DateTime {
        value,
        zone: Some(zone),
        utc: false,
    }) = &record.start
    else {
        return None;
    };
    if !record.repeats() || !zone_known(zone) {
        return None;
    }
    let first = days_from_civil(
        value[..4].parse().ok()?,
        value[4..6].parse().ok()?,
        value[6..8].parse().ok()?,
    );
    let clock_seconds =
        value[9..11].parse::<i64>().ok()? * 3600 + value[11..13].parse::<i64>().ok()? * 60;
    let offsets = {
        let _restore = ZoneGuard::set(zone);
        zone_offsets(first, clock_seconds)?
    };
    let start = instant_of(value, Some(zone))?;
    Some(ZonedSeries {
        date: day_key(first),
        time: format!("{}:{}", &value[9..11], &value[11..13]),
        length: series_length(record, start),
        offsets,
    })
}
