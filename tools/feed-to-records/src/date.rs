//! Source dates and the day arithmetic on them.

/// A source date or date-time, as written in the feed.
#[derive(Clone)]
pub enum CalendarDate {
    Date(String),
    DateTime {
        value: String,
        zone: Option<String>,
        utc: bool,
    },
}

// Reads a source date and keeps its date or date-time form.
pub fn calendar_date(value: &str, params: &[(String, String)]) -> Option<CalendarDate> {
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

// Moves an ISO date one day backward for exclusive all-day event ends.
pub fn previous_day(date: &str) -> String {
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

// Days since 1970-01-01 of a calendar day (Howard Hinnant's civil-days algorithm).
pub fn days_from_civil(year: i64, month: i64, day: i64) -> i64 {
    let year = if month <= 2 { year - 1 } else { year };
    let era = year.div_euclid(400);
    let year_of_era = year - era * 400;
    let day_of_year = (153 * (month + if month > 2 { -3 } else { 9 }) + 2) / 5 + day - 1;
    let day_of_era = year_of_era * 365 + year_of_era / 4 - year_of_era / 100 + day_of_year;
    era * 146097 + day_of_era - 719468
}

// The calendar day (year, month, day) of a day count from days_from_civil.
pub fn civil_from_days(days: i64) -> (i64, i64, i64) {
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

// The ISO text of a day count from days_from_civil.
pub fn day_key(days: i64) -> String {
    let (year, month, day) = civil_from_days(days);
    format!("{year:04}-{month:02}-{day:02}")
}
