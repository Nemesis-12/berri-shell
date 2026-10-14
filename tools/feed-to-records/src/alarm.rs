//! Alarms (VALARM blocks) and the minutes before the start that they give.

use crate::duration::read_duration;
use crate::text::Params;

/// One VALARM block while it is read. Only the simple form berri writes is used.
#[derive(Default)]
pub struct Alarm {
    trigger: Option<(Params, String)>,
    action: Option<String>,
    has_other_property: bool,
}

impl Alarm {
    // Notes one property of the block.
    pub fn read_property(&mut self, name: &str, params: &Params, value: &str) {
        match name {
            "TRIGGER" => self.trigger = Some((params.clone(), value.to_owned())),
            "ACTION" => self.action = Some(value.to_ascii_uppercase()),
            "DESCRIPTION" => {}
            _ => self.has_other_property = true,
        }
    }

    // Notes a line that is not a property. It makes the block not simple.
    pub fn read_other_line(&mut self) {
        self.has_other_property = true;
    }

    // Same rules as parseAlarm in logic/IcsRead.js: a display alarm with one
    // duration trigger before (or at) the start gives minutes. Anything else gives None.
    pub fn minutes(&self) -> Option<f64> {
        if self.has_other_property || self.action.as_deref() != Some("DISPLAY") {
            return None;
        }
        let (params, value) = self.trigger.as_ref()?;
        let param = |name: &str| params.iter().rev().find(|(key, _)| key == name).map(|(_, v)| v);
        if param("VALUE").is_some_and(|v| !v.eq_ignore_ascii_case("DURATION"))
            || param("RELATED").is_some_and(|v| !v.eq_ignore_ascii_case("START"))
        {
            return None;
        }
        alarm_minutes(value.trim())
    }
}

// Reads a trigger duration with exact seconds. Triggers after the start are not taken over.
fn alarm_minutes(value: &str) -> Option<f64> {
    let duration = read_duration(value)?;
    let seconds = duration.days * 86400 + duration.seconds;
    (duration.negative || seconds == 0).then_some(seconds as f64 / 60.0)
}
