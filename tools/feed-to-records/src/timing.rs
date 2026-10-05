//! The shown date and clock of a record.

use crate::date::{previous_day, CalendarDate};
use crate::model::Record;
use crate::zone::local_clock;

/// The shown date and clock of a record: start day and time, end time, and last day of a longer event.
#[derive(Default)]
pub struct Timing {
    pub date: Option<String>,
    pub time: Option<String>,
    pub end: Option<String>,
    pub end_date: Option<String>,
}

// The shown start, end and last day of a record, as the JavaScript reader gives them.
pub fn timing(record: &Record) -> Timing {
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
