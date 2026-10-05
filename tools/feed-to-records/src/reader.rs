//! Reads events and tasks from one calendar feed.

use crate::alarm::Alarm;
use crate::color::{category_color, clean_color};
use crate::date::calendar_date;
use crate::model::{Feed, Kind, Record, Status};
use crate::overrides::attach_overrides;
use crate::recurrence::repeat_rule;
use crate::text::{property, text_value, unfold, Params};
use crate::zone::local_clock;

/// The BEGIN names that are open at one line of the feed.
#[derive(Default)]
struct Nesting(Vec<String>);

impl Nesting {
    // True inside the calendar itself, outside every component.
    fn in_calendar(&self) -> bool {
        self.0.len() == 1 && self.0[0] == "VCALENDAR"
    }

    // True inside an event or a task, at the depth where its properties are.
    fn in_item(&self) -> bool {
        self.0.len() == 2
    }

    // True inside an alarm block at the depth where an event or a task has it.
    fn in_alarm(&self) -> bool {
        self.0.len() == 3 && self.0[2] == "VALARM"
    }

    // True when the innermost name is an event or a task of the calendar.
    fn at_item_start(&self) -> bool {
        self.in_item() && self.0[0] == "VCALENDAR"
    }
}

/// The state of a feed while its lines are read.
#[derive(Default)]
struct Reader {
    feed: Feed,
    nesting: Nesting,
    item: Option<Record>,
    alarm: Alarm,
}

// Reads events and tasks from one calendar feed.
pub fn read_feed(text: &str) -> Feed {
    let mut reader = Reader::default();
    for line in unfold(text) {
        reader.read_line(&line);
    }
    let mut feed = reader.feed;
    attach_overrides(&mut feed);
    feed.records.sort_by_cached_key(source_sort_key);
    feed
}

impl Reader {
    // Reads one unfolded line.
    fn read_line(&mut self, line: &str) {
        let Some((name, params, value)) = property(line) else {
            if self.nesting.in_alarm() {
                self.alarm.read_other_line();
            }
            return;
        };
        match name.as_str() {
            "BEGIN" => self.begin(value),
            "END" => self.end(),
            _ => self.read_property(&name, &params, value),
        }
    }

    // Opens a component. An event or a task starts a new record, and an alarm a new alarm.
    fn begin(&mut self, value: &str) {
        self.nesting.0.push(value.to_ascii_uppercase());
        let is_todo = value.eq_ignore_ascii_case("VTODO");
        if self.nesting.at_item_start() && (is_todo || value.eq_ignore_ascii_case("VEVENT")) {
            self.item = Some(Record::new(is_todo));
        }
        if self.nesting.in_alarm() {
            self.alarm = Alarm::default();
        }
    }

    // Closes a component. An alarm gives its minutes, and an event or a task joins the feed.
    fn end(&mut self) {
        if self.nesting.in_alarm() {
            if let Some(record) = self.item.as_mut().filter(|r| r.alarm_minutes.is_none()) {
                record.alarm_minutes = self.alarm.minutes();
            }
        } else if self.nesting.in_item() {
            if let Some(record) = self.item.take() {
                self.finish(record);
            }
        }
        self.nesting.0.pop();
    }

    // Puts a finished record in the feed, or in the overrides when it has a RECURRENCE-ID.
    fn finish(&mut self, mut record: Record) {
        if record.uid.is_empty() {
            record.uid = format!("missing-{}", self.feed.records.len());
        }
        if !record.repeats() {
            record.interval = 1;
            record.by_day.clear();
            record.until = None;
            record.count = None;
        }
        if record.override_event {
            self.feed.overrides.push(record);
        } else {
            self.feed.records.push(record);
        }
    }

    // Reads one property in the calendar, in an alarm, or in an event or a task.
    fn read_property(&mut self, name: &str, params: &Params, value: &str) {
        if self.nesting.in_calendar() && name == "X-WR-CALNAME" && self.feed.name.is_empty() {
            self.feed.name = text_value(value).trim().to_owned();
        }
        if self.nesting.in_alarm() {
            self.alarm.read_property(name, params, value);
        }
        if !self.nesting.in_item() {
            return;
        }
        if let Some(record) = self.item.as_mut() {
            read_item_property(record, name, params, value);
        }
    }
}

// Reads one property of an event or a task.
fn read_item_property(record: &mut Record, name: &str, params: &Params, value: &str) {
    match name {
        "UID" => record.uid = value.to_owned(),
        "RECURRENCE-ID" => {
            record.override_event = true;
            record.recurrence_id = calendar_date(value, params);
        }
        "SUMMARY" => record.title = text_value(value),
        "LOCATION" => record.location = text_value(value),
        "DTSTART" => record.start = calendar_date(value, params),
        "DTEND" if !record.is_todo => record.end_value = calendar_date(value, params),
        "DUE" if record.is_todo => record.end_value = calendar_date(value, params),
        "RRULE" => repeat_rule(record, value),
        "EXDATE" => record
            .exdates
            .extend(value.split(',').filter_map(|date| calendar_date(date, params))),
        "STATUS" => record.status = Some(Status::from_value(value)),
        _ => read_berri_property(record, name, value),
    }
}

// Reads the properties that berri adds to a component, and the old category colors.
fn read_berri_property(record: &mut Record, name: &str, value: &str) {
    match name {
        "X-BERRI-DONE" => record
            .done_dates
            .extend(value.split(',').filter_map(|date| calendar_date(date, &[]))),
        "X-BERRI-KIND" if value.eq_ignore_ascii_case("reminder") => record.kind = Kind::Reminder,
        "X-BERRI-COLOR" => {
            if let Some(color) = clean_color(value) {
                record.color = color;
                record.own_color = true;
            }
        }
        "CATEGORIES" if !record.own_color => {
            if let Some(color) = category_color(value) {
                record.color = color.to_owned();
            }
        }
        _ => {}
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
