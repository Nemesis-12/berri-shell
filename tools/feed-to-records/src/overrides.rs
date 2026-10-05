//! Changes that RECURRENCE-ID components make to single occurrences.

use crate::model::{Feed, Status};
use crate::timing::{timing, Timing};
use crate::zone::local_day;

/// What a feed changed in one occurrence of a repeating event. Date and clock fields are None for a cancelled occurrence.
pub struct ChangedOccurrence {
    pub from: String,
    pub cancelled: bool,
    pub title: Option<String>,
    pub timing: Timing,
}

// Gives each repeating event the changes that RECURRENCE-ID components make to its occurrences.
pub fn attach_overrides(feed: &mut Feed) {
    for over in std::mem::take(&mut feed.overrides) {
        let Some(from) = over.recurrence_id.as_ref().and_then(local_day) else {
            continue;
        };
        let cancelled = over.status == Some(Status::Cancelled);
        let timing = if cancelled {
            Timing::default()
        } else {
            timing(&over)
        };
        let title = (!cancelled && !over.title.is_empty()).then(|| over.title.clone());
        let series = feed
            .records
            .iter_mut()
            .find(|record| record.uid == over.uid && record.repeats());
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
