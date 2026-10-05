//! Time conversion: source clocks in named zones to the local day and clock.

use std::{
    env,
    os::raw::{c_char, c_int, c_long},
    path::Path,
};

use crate::date::CalendarDate;

#[repr(C)]
#[derive(Default)]
pub struct Clock {
    pub second: c_int,
    pub minute: c_int,
    pub hour: c_int,
    pub day: c_int,
    pub month: c_int,
    pub year: c_int,
    pub weekday: c_int,
    pub yearday: c_int,
    pub daylight: c_int,
    pub offset: c_long,
    pub zone: *const c_char,
}

unsafe extern "C" {
    fn tzset();
    pub fn mktime(clock: *mut Clock) -> c_long;
    fn localtime_r(seconds: *const c_long, clock: *mut Clock) -> *mut Clock;
}

// Sets TZ for the life of the guard and puts the old value back when it drops,
// on every return path.
pub struct ZoneGuard(Option<std::ffi::OsString>);

impl ZoneGuard {
    pub fn set(zone: &str) -> Self {
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
pub fn zone_known(name: &str) -> bool {
    if name.is_empty() || name.starts_with('/') || name.split('/').any(|part| part == "..") {
        return false;
    }
    let root = env::var_os("TZDIR")
        .filter(|dir| !dir.is_empty())
        .unwrap_or_else(|| "/usr/share/zoneinfo".into());
    Path::new(&root).join(name).is_file()
}

// The zone in which a source clock is written: UTC, a named zone, or None for the system zone.
pub fn source_zone(zone: Option<&str>, utc: bool) -> Option<&str> {
    if utc {
        Some("UTC")
    } else {
        zone
    }
}

// The instant of a source clock "YYYYMMDDTHHMMSS" in `zone`, or in the system zone for None.
pub fn instant_of(value: &str, zone: Option<&str>) -> Option<c_long> {
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

// The written day and clock of a source date-time, without any zone conversion.
fn written_clock(value: &str) -> (String, Option<String>) {
    (
        format!("{}-{}-{}", &value[..4], &value[4..6], &value[6..8]),
        Some(format!("{}:{}", &value[9..11], &value[11..13])),
    )
}

// Converts a source clock through the Linux time-zone database to local time.
// A clock in an unknown zone stays as written, like the old JavaScript reader.
pub fn local_clock(date: &CalendarDate) -> Option<(String, Option<String>)> {
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
        return Some(written_clock(value));
    }
    let instant = instant_of(value, source_zone(zone.as_deref(), *utc))?;
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

// The local day of a source date, or None when it cannot be converted.
pub fn local_day(date: &CalendarDate) -> Option<String> {
    local_clock(date).map(|(day, _)| day)
}
