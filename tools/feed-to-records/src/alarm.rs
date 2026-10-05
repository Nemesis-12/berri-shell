//! Alarms (VALARM blocks) and the minutes before the start that they give.

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

    // Same rules as parseAlarm in logic/CalendarFormat.js: a display alarm with one
    // duration trigger before (or at) the start gives minutes. Anything else gives None.
    pub fn minutes(&self) -> Option<usize> {
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

// Takes "<digits><unit>" from the front of the text. Leaves the text alone when it does not fit.
fn take_amount(rest: &mut &str, unit: char) -> Option<usize> {
    let digits = rest.bytes().take_while(u8::is_ascii_digit).count();
    if digits == 0 || !rest[digits..].starts_with(unit) {
        return None;
    }
    let amount = rest[..digits].parse().ok()?;
    *rest = &rest[digits + 1..];
    Some(amount)
}

const MAX_EXACT_MINUTES: usize = (1 << 53) - 1;

// Reads a trigger duration such as -PT15M. Returns None for a trigger after the start.
fn alarm_minutes(value: &str) -> Option<usize> {
    let (before_start, mut rest) = match value.strip_prefix('-') {
        Some(rest) => (true, rest),
        None => (false, value),
    };
    rest = rest.strip_prefix('P')?;
    let weeks = take_amount(&mut rest, 'W').unwrap_or(0);
    let days = take_amount(&mut rest, 'D').unwrap_or(0);
    let (mut hours, mut minutes) = (0, 0);
    if let Some(time) = rest.strip_prefix('T') {
        rest = time;
        hours = take_amount(&mut rest, 'H').unwrap_or(0);
        minutes = take_amount(&mut rest, 'M').unwrap_or(0);
        take_amount(&mut rest, 'S');
    }
    if !rest.is_empty() {
        return None;
    }
    // A total above 2^53 - 1 cannot be counted exactly by the JavaScript reader, so it is not an alarm.
    let total = weeks
        .checked_mul(10080)?
        .checked_add(days.checked_mul(1440)?)?
        .checked_add(hours.checked_mul(60)?)?
        .checked_add(minutes)?;
    (total <= MAX_EXACT_MINUTES && (before_start || total == 0)).then_some(total)
}
