//! The records that berri reads from a feed.

use crate::date::CalendarDate;
use crate::overrides::ChangedOccurrence;

/// What a record is for the user.
#[derive(Clone, Copy, Default, PartialEq)]
pub enum Kind {
    #[default]
    Event,
    Task,
    Reminder,
}

impl Kind {
    pub fn name(self) -> &'static str {
        match self {
            Kind::Event => "event",
            Kind::Task => "task",
            Kind::Reminder => "reminder",
        }
    }
}

/// How often a record repeats.
#[derive(Clone, Copy, Default, PartialEq)]
pub enum Repeat {
    #[default]
    None,
    Daily,
    Weekly,
    Monthly,
    Yearly,
}

impl Repeat {
    // Reads a FREQ value. Any other value is no repeat.
    pub fn from_frequency(value: &str) -> Self {
        match value.to_ascii_uppercase().as_str() {
            "DAILY" => Repeat::Daily,
            "WEEKLY" => Repeat::Weekly,
            "MONTHLY" => Repeat::Monthly,
            "YEARLY" => Repeat::Yearly,
            _ => Repeat::None,
        }
    }

    pub fn name(self) -> &'static str {
        match self {
            Repeat::None => "none",
            Repeat::Daily => "daily",
            Repeat::Weekly => "weekly",
            Repeat::Monthly => "monthly",
            Repeat::Yearly => "yearly",
        }
    }
}

/// The STATUS of a component.
#[derive(Clone, PartialEq)]
pub enum Status {
    Cancelled,
    Completed,
    NeedsAction,
    Other(String),
}

impl Status {
    pub fn from_value(value: &str) -> Self {
        let value = value.to_ascii_uppercase();
        match value.as_str() {
            "CANCELLED" => Status::Cancelled,
            "COMPLETED" => Status::Completed,
            "NEEDS-ACTION" => Status::NeedsAction,
            _ => Status::Other(value),
        }
    }

    // The text that berri shows. Completed and needs-action are not shown.
    pub fn shown(&self) -> Option<&str> {
        match self {
            Status::Cancelled => Some("CANCELLED"),
            Status::Other(value) => Some(value),
            Status::Completed | Status::NeedsAction => None,
        }
    }
}

#[derive(Default)]
pub struct Record {
    pub uid: String,
    pub kind: Kind,
    pub is_todo: bool,
    pub title: String,
    pub location: String,
    pub start: Option<CalendarDate>,
    pub end_value: Option<CalendarDate>,
    pub color: String,
    pub own_color: bool,
    pub repeat: Repeat,
    pub interval: usize,
    pub by_day: Vec<usize>,
    // Week number (1 to 5, or -1 for the last) and weekday (0 = Sunday) of a monthly rule such as BYDAY=2TU.
    pub month_weekday: Option<(i32, usize)>,
    pub until: Option<CalendarDate>,
    pub count: Option<usize>,
    pub exdates: Vec<CalendarDate>,
    pub done_dates: Vec<CalendarDate>,
    pub alarm_minutes: Option<usize>,
    pub status: Option<Status>,
    // Set on a RECURRENCE-ID component: the start of the occurrence it replaces.
    pub recurrence_id: Option<CalendarDate>,
    pub override_event: bool,
    pub changed: Vec<ChangedOccurrence>,
}

impl Record {
    // A new event or task with the defaults of a feed component.
    pub fn new(is_todo: bool) -> Self {
        Record {
            kind: if is_todo { Kind::Task } else { Kind::Event },
            is_todo,
            color: "accent".to_owned(),
            interval: 1,
            ..Record::default()
        }
    }

    // True for a repeating event.
    pub fn repeats(&self) -> bool {
        self.repeat != Repeat::None
    }
}

#[derive(Default)]
pub struct Feed {
    pub name: String,
    pub records: Vec<Record>,
    // RECURRENCE-ID components, until they are attached to their repeating event.
    pub overrides: Vec<Record>,
}
