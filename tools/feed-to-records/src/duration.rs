//! Nominal days and exact seconds in iCalendar durations.

use crate::date::{calendar_date, day_key, days_from_civil, CalendarDate};
use crate::zone::{instant_of, source_clock, source_zone, zone_known};

pub struct Duration {
    pub days: u64,
    pub seconds: u64,
    pub negative: bool,
}

// Takes one numeric unit without slicing through a UTF-8 character.
fn amount(rest: &mut &str, unit: char) -> Option<u64> {
    let digits = rest.bytes().take_while(u8::is_ascii_digit).count();
    if digits == 0 || !rest[digits..].starts_with(unit) {
        return Some(0);
    }
    let value = rest[..digits].parse().ok()?;
    *rest = &rest[digits + 1..];
    Some(value)
}

// Reads the RFC duration grammar and rejects values JavaScript cannot count exactly.
pub fn read_duration(value: &str) -> Option<Duration> {
    let value = value.trim();
    let negative = value.starts_with('-');
    let unsigned = value.strip_prefix(['+', '-']).unwrap_or(value);
    let mut rest = unsigned.strip_prefix('P')?;
    if rest.is_empty() {
        return None;
    }
    let weeks = amount(&mut rest, 'W')?;
    if value.contains('W') && !rest.is_empty() {
        return None;
    }
    let days = if value.ends_with('W') {
        0
    } else {
        amount(&mut rest, 'D')?
    };
    let mut seconds = 0;
    if let Some(time) = rest.strip_prefix('T') {
        if time.is_empty() || value.contains('W') {
            return None;
        }
        rest = time;
        let hours = amount(&mut rest, 'H')?;
        let minutes = amount(&mut rest, 'M')?;
        seconds = hours
            .checked_mul(3600)?
            .checked_add(minutes.checked_mul(60)?)?
            .checked_add(amount(&mut rest, 'S')?)?;
    }
    if !rest.is_empty() {
        return None;
    }
    let days = weeks.checked_mul(7)?.checked_add(days)?;
    if days.checked_mul(86400)?.checked_add(seconds)? > (1 << 53) - 1 {
        return None;
    }
    Some(Duration {
        days,
        seconds,
        negative,
    })
}

// Adds source-zone calendar days before exact seconds. Unknown zones keep their source clock.
pub fn end_from_duration(start: &CalendarDate, duration: &Duration) -> Option<CalendarDate> {
    if duration.negative || duration.days == 0 && duration.seconds == 0 {
        return None;
    }
    let value = match start {
        CalendarDate::Date(value) | CalendarDate::DateTime { value, .. } => value,
    };
    let first = days_from_civil(
        value[..4].parse().ok()?,
        value[4..6].parse().ok()?,
        value[6..8].parse().ok()?,
    );
    let day = day_key(first.checked_add(i64::try_from(duration.days).ok()?)?).replace('-', "");
    if day.len() != 8 {
        return None;
    }
    let CalendarDate::DateTime { zone, utc, .. } = start else {
        return (duration.seconds == 0).then_some(CalendarDate::Date(day));
    };
    let known = *utc || zone.as_deref().is_none_or(zone_known);
    let source_zone = if known {
        source_zone(zone.as_deref(), *utc)
    } else {
        Some("UTC")
    };
    let next = format!("{day}{}", &value[8..]);
    let seconds =
        instant_of(&next, source_zone)?.checked_add(i64::try_from(duration.seconds).ok()?)?;
    let clock = source_clock(seconds, source_zone)?;
    let params = zone
        .as_ref()
        .map(|name| vec![("TZID".to_owned(), name.clone())])
        .unwrap_or_default();
    calendar_date(&format!("{clock}{}", if *utc { "Z" } else { "" }), &params)
}
