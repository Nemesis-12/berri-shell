//! Repeat rules (RRULE) of a record.

use crate::date::calendar_date;
use crate::model::{Record, Repeat};

// Reads a BYDAY list of plain weekdays such as MO,WE. None when any item is not a weekday.
fn plain_weekdays(value: &str) -> Option<Vec<usize>> {
    value
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
        .collect()
}

// Reads one repeat rule into the fields that berri uses.
pub fn repeat_rule(record: &mut Record, value: &str) {
    let mut ordinal_day = None;
    let mut ordinal_part = None;
    let mut rest = Vec::new();
    for part in value.split(';') {
        let Some((key, value)) = part.split_once('=') else {
            rest.push(part);
            continue;
        };
        match key.to_ascii_uppercase().as_str() {
            "FREQ" => record.repeat = Repeat::from_frequency(value),
            "INTERVAL" => record.interval = value.parse::<usize>().unwrap_or(1).max(1),
            "COUNT" => record.count = value.parse::<usize>().ok().filter(|count| *count > 0),
            "UNTIL" => record.until = calendar_date(value, &[]),
            "BYDAY" => match plain_weekdays(value) {
                Some(days) => record.by_day = days,
                None => {
                    ordinal_day = ordinal_weekday(value);
                    if ordinal_day.is_some() {
                        ordinal_part = Some(part);
                    } else {
                        rest.push(part);
                    }
                }
            },
            _ => rest.push(part),
        }
    }
    // Only monthly ordinals have a dedicated field. Yearly ordinals stay in rule_rest.
    if record.repeat == Repeat::Monthly {
        record.month_weekday = ordinal_day;
    } else if let Some(part) = ordinal_part {
        rest.push(part);
    }
    record.rule_rest = (record.repeats() && !rest.is_empty()).then(|| rest.join(";"));
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
