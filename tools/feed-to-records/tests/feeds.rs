use std::{fs, process::Command};

// Runs the program on one input path. Returns the exit success and the JSON, if any.
fn run(input: &str) -> (bool, Option<String>) {
    run_in_zone(input, "UTC")
}

// Runs the program with the system zone set to `zone`.
fn run_in_zone(input: &str, zone: &str) -> (bool, Option<String>) {
    let output = std::env::temp_dir().join(format!(
        "berri-records-{}-{}.json",
        std::process::id(),
        std::thread::current().name().unwrap_or("test")
    ));
    let status = Command::new(env!("CARGO_BIN_EXE_feed-to-records"))
        .args([input, output.to_str().unwrap()])
        .env("TZ", zone)
        .status()
        .unwrap();
    let json = fs::read_to_string(&output).ok();
    let _ = fs::remove_file(output);
    (status.success(), json)
}

// Runs the program on a good input and returns its JSON.
fn convert(input: &str) -> String {
    let (success, json) = run(input);
    assert!(success);
    json.unwrap()
}

// Writes feed text to a file named after the test, converts it, and returns the JSON.
fn convert_text(name: &str, text: &str) -> String {
    let input = std::env::temp_dir().join(format!("berri-feed-{}-{name}.ics", std::process::id()));
    fs::write(&input, text).unwrap();
    let json = convert(input.to_str().unwrap());
    fs::remove_file(input).unwrap();
    json
}

// Both real fixture feeds must produce the event fields used by berri.
#[test]
fn fixture_feeds() {
    for name in ["bayern.ics", "dortmund.ics"] {
        let path = format!("{}/../../tests/fixtures/{name}", env!("CARGO_MANIFEST_DIR"));
        let json = convert(&path);
        assert_eq!(json.matches("\"uid\":").count(), 2);
        assert!(json.contains("\"title\":\"Bayern München - Borussia Dortmund\""));
        assert!(json.contains("\"date\":\"2026-10-31\",\"time\":\"17:30\""));
    }
}

// Folded lines, text escapes, dates, and a named zone survive conversion.
#[test]
fn common_feed_fields() {
    let input = std::env::temp_dir().join(format!("berri-feed-{}.ics", std::process::id()));
    fs::write(&input, "BEGIN:VCALENDAR\r\nX-WR-CALNAME:My\\, feed\r\nBEGIN:VEVENT\r\nUID:one\r\nDTSTART;VALUE=DATE:20261005\r\nDTEND;VALUE=DATE:20261007\r\nSUMMARY:Hello\\,\r\n world\\nAgain\r\nLOCATION:Room\\; A\r\nEND:VEVENT\r\nBEGIN:VEVENT\r\nUID:two\r\nDTSTART;TZID=Europe/Berlin:20261005T090000\r\nSUMMARY:Timed\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n").unwrap();
    let json = convert(input.to_str().unwrap());
    fs::remove_file(input).unwrap();
    assert!(json.contains("\"name\":\"My, feed\""));
    assert!(json.contains("\"title\":\"Hello,world\\nAgain\""));
    assert!(json.contains("\"location\":\"Room; A\""));
    assert!(json.contains("\"endDate\":\"2026-10-06\""));
    assert!(json.contains("\"uid\":\"two\""));
    assert!(json.contains("\"uid\":\"two\",\"kind\":\"event\",\"title\":\"Timed\",\"location\":\"\",\"date\":\"2026-10-05\",\"time\":\"07:00\""));
}

// A feed with no events gives an empty record list and keeps its name.
#[test]
fn feed_without_events() {
    let json = convert_text(
        "empty",
        "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nX-WR-CALNAME:Empty\r\nEND:VCALENDAR\r\n",
    );
    assert_eq!(json, "{\"name\":\"Empty\",\"records\":[]}");
}

// Zoned times become the local clock (TZ=UTC here), and the winter and summer offsets differ.
#[test]
fn time_zones_follow_the_zone_database() {
    let event = |uid: &str, start: &str| {
        format!("BEGIN:VEVENT\r\nUID:{uid}\r\nDTSTART{start}\r\nSUMMARY:{uid}\r\nEND:VEVENT\r\n")
    };
    let text = format!(
        "BEGIN:VCALENDAR\r\n{}{}{}{}{}END:VCALENDAR\r\n",
        event("summer", ";TZID=America/New_York:20261031T120000"),
        event("winter", ";TZID=America/New_York:20261102T120000"),
        event("nextday", ";TZID=America/New_York:20261105T233000"),
        event("utc", ":20261101T100000Z"),
        event("floating", ":20261101T100000"),
    );
    let json = convert_text("zones", &text);
    assert!(json.contains("\"uid\":\"summer\",\"kind\":\"event\",\"title\":\"summer\",\"location\":\"\",\"date\":\"2026-10-31\",\"time\":\"16:00\""));
    assert!(json.contains("\"uid\":\"winter\",\"kind\":\"event\",\"title\":\"winter\",\"location\":\"\",\"date\":\"2026-11-02\",\"time\":\"17:00\""));
    assert!(json.contains("\"uid\":\"nextday\",\"kind\":\"event\",\"title\":\"nextday\",\"location\":\"\",\"date\":\"2026-11-06\",\"time\":\"04:30\""));
    assert!(json.contains("\"uid\":\"utc\",\"kind\":\"event\",\"title\":\"utc\",\"location\":\"\",\"date\":\"2026-11-01\",\"time\":\"10:00\""));
    assert!(json.contains("\"uid\":\"floating\",\"kind\":\"event\",\"title\":\"floating\",\"location\":\"\",\"date\":\"2026-11-01\",\"time\":\"10:00\""));
}

// An all-day event has no time. Its end date is exclusive in the feed and inclusive in the record.
#[test]
fn all_day_dates() {
    let json = convert_text(
        "allday",
        "BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:one\nDTSTART;VALUE=DATE:20261231\nDTEND;VALUE=DATE:20270101\nSUMMARY:Single\nEND:VEVENT\nBEGIN:VEVENT\nUID:two\nDTSTART;VALUE=DATE:20261230\nDTEND;VALUE=DATE:20270102\nSUMMARY:Across\nEND:VEVENT\nEND:VCALENDAR\n",
    );
    assert!(json.contains("\"uid\":\"one\",\"kind\":\"event\",\"title\":\"Single\",\"location\":\"\",\"date\":\"2026-12-31\",\"time\":null,\"end\":null,\"endDate\":null"));
    assert!(json.contains("\"uid\":\"two\",\"kind\":\"event\",\"title\":\"Across\",\"location\":\"\",\"date\":\"2026-12-30\",\"time\":null,\"end\":null,\"endDate\":\"2027-01-01\""));
}

// Text escapes, a tab fold, and quote and backslash escaping in the JSON output.
#[test]
fn text_escapes_and_json_output() {
    let json = convert_text(
        "escapes",
        "BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:esc\r\nDTSTART;VALUE=DATE:20261005\r\nSUMMARY:A\\\\B \"quoted\"\r\nLOCATION:Hall 1\\; Gate 2\\, North\r\n\tstreet\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n",
    );
    assert!(json.contains("\"title\":\"A\\\\B \\\"quoted\\\"\""));
    assert!(json.contains("\"location\":\"Hall 1; Gate 2, Northstreet\""));
}

// Repeat rules are kept, and an edited single occurrence (RECURRENCE-ID) is not a second event.
#[test]
fn repeat_rule_and_overrides() {
    let json = convert_text(
        "repeat",
        "BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:r\r\nDTSTART;VALUE=DATE:20261005\r\nRRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE;COUNT=5\r\nEXDATE;VALUE=DATE:20261007\r\nSUMMARY:Gym\r\nEND:VEVENT\r\nBEGIN:VEVENT\r\nUID:r\r\nRECURRENCE-ID;VALUE=DATE:20261019\r\nDTSTART;VALUE=DATE:20261020\r\nSUMMARY:Moved\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n",
    );
    assert_eq!(json.matches("\"uid\":").count(), 1);
    assert!(json.contains("\"repeat\":\"weekly\",\"interval\":2,\"byDay\":[1,3],\"until\":null,\"count\":5,\"exdates\":[\"2026-10-07\"]"));
}

// Input that is not a calendar, or is missing, fails and leaves no JSON file.
#[test]
fn bad_input_fails_without_output() {
    let input = std::env::temp_dir().join(format!("berri-feed-{}-bad.ics", std::process::id()));
    fs::write(&input, "<html>Not found</html>").unwrap();
    assert_eq!(run(input.to_str().unwrap()), (false, None));
    fs::remove_file(input).unwrap();
    assert_eq!(run("/nonexistent/berri-feed.ics"), (false, None));
}

// Wraps alarm blocks in one all-day event and returns the alarm field of its record.
fn alarm_field(name: &str, alarms: &[&str]) -> String {
    let text = format!(
        "BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:x\r\nDTSTART;VALUE=DATE:20261005\r\nSUMMARY:S\r\n{}END:VEVENT\r\nEND:VCALENDAR\r\n",
        alarms.concat()
    );
    let json = convert_text(name, &text);
    let start = json.find("\"alarmMinutes\":").unwrap() + "\"alarmMinutes\":".len();
    json[start..].split([',', '}']).next().unwrap().to_owned()
}

const DISPLAY_15: &str = "BEGIN:VALARM\r\nACTION:DISPLAY\r\nTRIGGER:-PT15M\r\nDESCRIPTION:x\r\nEND:VALARM\r\n";

// A display alarm with a description is a simple alarm.
#[test]
fn alarm_with_description_gives_minutes() {
    assert_eq!(alarm_field("alarm-display", &[DISPLAY_15]), "15");
}

// An alarm without ACTION is not a simple alarm.
#[test]
fn alarm_without_action_is_ignored() {
    assert_eq!(alarm_field("alarm-noaction", &["BEGIN:VALARM\r\nTRIGGER:-PT15M\r\nEND:VALARM\r\n"]), "null");
}

// A trigger at the start time is 0 minutes, not "no alarm".
#[test]
fn alarm_at_start_is_zero() {
    assert_eq!(alarm_field("alarm-zero", &["BEGIN:VALARM\r\nACTION:DISPLAY\r\nTRIGGER:PT0S\r\nEND:VALARM\r\n"]), "0");
}

// The first simple alarm wins. Later alarms are ignored.
#[test]
fn first_simple_alarm_wins() {
    let second = "BEGIN:VALARM\r\nACTION:DISPLAY\r\nTRIGGER:-PT5M\r\nEND:VALARM\r\n";
    let first = "BEGIN:VALARM\r\nACTION:DISPLAY\r\nTRIGGER:-PT10M\r\nEND:VALARM\r\n";
    assert_eq!(alarm_field("alarm-two", &[first, second]), "10");
    let email = "BEGIN:VALARM\r\nACTION:EMAIL\r\nTRIGGER:-PT10M\r\nEND:VALARM\r\n";
    assert_eq!(alarm_field("alarm-skip", &[email, second]), "5");
}

// A zone name that is not in the zone database keeps the clock as written, like the old parser.
// The system zone is America/Chicago here, so a wrong conversion would show 05:00.
#[test]
fn unknown_zone_keeps_the_written_clock() {
    let event = |uid: &str, zone: &str| {
        format!("BEGIN:VEVENT\r\nUID:{uid}\r\nDTSTART;TZID={zone}:20261005T100000\r\nDTEND;TZID={zone}:20261005T113000\r\nSUMMARY:{uid}\r\nEND:VEVENT\r\n")
    };
    let text = format!(
        "BEGIN:VCALENDAR\r\n{}{}{}END:VCALENDAR\r\n",
        event("windows", "Eastern Standard Time"),
        event("escape", "../../etc/passwd"),
        event("berlin", "Europe/Berlin"),
    );
    let input = std::env::temp_dir().join(format!("berri-feed-{}-unknown-zone.ics", std::process::id()));
    fs::write(&input, text).unwrap();
    let (success, json) = run_in_zone(input.to_str().unwrap(), "America/Chicago");
    fs::remove_file(input).unwrap();
    assert!(success);
    let json = json.unwrap();
    for uid in ["windows", "escape"] {
        assert!(json.contains(&format!("\"uid\":\"{uid}\",\"kind\":\"event\",\"title\":\"{uid}\",\"location\":\"\",\"date\":\"2026-10-05\",\"time\":\"10:00\",\"end\":\"11:30\"")), "{uid}: {json}");
    }
    assert!(json.contains("\"uid\":\"berlin\",\"kind\":\"event\",\"title\":\"berlin\",\"location\":\"\",\"date\":\"2026-10-05\",\"time\":\"03:00\""));
}

// A leading byte-order mark and one invalid text byte do not reject the feed.
#[test]
fn byte_order_mark_and_invalid_bytes() {
    for (name, bytes) in [
        ("bom", b"\xef\xbb\xbfBEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:a\r\nDTSTART:20261005T090000\r\nSUMMARY:Hi\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n".as_slice()),
        ("bad-byte", b"BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:a\r\nDTSTART:20261005T090000\r\nSUMMARY:Hi \xff\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n".as_slice()),
    ] {
        let input = std::env::temp_dir().join(format!("berri-feed-{}-{name}.ics", std::process::id()));
        fs::write(&input, bytes).unwrap();
        let json = convert(input.to_str().unwrap());
        fs::remove_file(input).unwrap();
        assert_eq!(json.matches("\"uid\":").count(), 1, "{name}");
    }
}

// An alarm too large to count exactly gives no alarm. It must not wrap in a release build or panic in a debug build.
#[test]
fn too_large_alarm_gives_no_alarm() {
    for trigger in ["-P99999999999999999W", "-P999999999999999999999999W", "-P1000000000000000W"] {
        assert!(alarm_field(trigger, &[&format!("BEGIN:VALARM\r\nACTION:DISPLAY\r\nTRIGGER:{trigger}\r\nEND:VALARM\r\n")]).ends_with("null"), "{trigger}");
    }
}

// A cancelled occurrence and a moved occurrence become short entries of their repeating event.
#[test]
fn changed_occurrences_and_zone_data() {
    let json = convert_text(
        "changed",
        "BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:w\r\nDTSTART;TZID=Europe/Berlin:20261005T090000\r\nDTEND;TZID=Europe/Berlin:20261005T100000\r\nRRULE:FREQ=WEEKLY\r\nSUMMARY:W\r\nEND:VEVENT\r\nBEGIN:VEVENT\r\nUID:w\r\nRECURRENCE-ID;TZID=Europe/Berlin:20261012T090000\r\nDTSTART;TZID=Europe/Berlin:20261013T150000\r\nSUMMARY:Moved\r\nEND:VEVENT\r\nBEGIN:VEVENT\r\nUID:w\r\nRECURRENCE-ID;TZID=Europe/Berlin:20261019T090000\r\nSTATUS:CANCELLED\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n",
    );
    assert!(json.contains("\"changedOccurrences\":[{\"from\":\"2026-10-12\",\"cancelled\":false,\"title\":\"Moved\",\"date\":\"2026-10-13\",\"time\":\"13:00\",\"end\":null,\"endDate\":null},{\"from\":\"2026-10-19\",\"cancelled\":true,\"title\":null,\"date\":null,\"time\":null,\"end\":null,\"endDate\":null}]"), "{json}");
    assert!(json.contains("\"zoned\":{\"date\":\"2026-10-05\",\"time\":\"09:00\",\"length\":60,\"offsets\":[[\"2026-10-05\",7200],[\"2026-10-25\",3600],"), "{json}");
}

// UTC repeats need a zero-offset source clock so local DST cannot change their instant.
#[test]
fn utc_repeat_keeps_its_source_clock() {
    let json = convert_text("utc-repeat", "BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:utc\nDTSTART:20261026T140000Z\nDTEND:20261026T150000Z\nRRULE:FREQ=WEEKLY;COUNT=2\nEND:VEVENT\nEND:VCALENDAR\n");
    assert!(json.contains("\"zoned\":{\"date\":\"2026-10-26\",\"time\":\"14:00\",\"length\":60,\"offsets\":[[\"2026-10-26\",0]]}"), "{json}");
}

// Compact records must keep a timed UNTIL instant for the occurrence query.
#[test]
fn timed_until_keeps_its_inclusive_instant() {
    let json = convert_text("timed-until", "BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:until\nDTSTART:20261008T140000Z\nRRULE:FREQ=DAILY;UNTIL=20261009T135959Z\nEND:VEVENT\nEND:VCALENDAR\n");
    assert!(json.contains("\"untilMs\":1791554399000"), "{json}");
}

// Unsupported recurrence lines remain in compact records for the source note.
#[test]
fn unsupported_recurrence_lines_reach_the_source_note() {
    let json = convert_text("unsupported-repeat", "BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:unsupported\nDTSTART:20261008T090000\nRDATE:20261012T090000\nEXRULE:FREQ=WEEKLY;BYDAY=MO\nEND:VEVENT\nEND:VCALENDAR\n");
    assert!(json.contains("\"raw\":[\"RDATE:20261012T090000\",\"EXRULE:FREQ=WEEKLY;BYDAY=MO\"]"), "{json}");
}

// UNTIL comparisons must use DTSTART seconds even though the view shows minutes.
#[test]
fn timed_until_keeps_start_seconds() {
    let json = convert_text("start-seconds", "BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:seconds\nDTSTART:20261008T140030Z\nRRULE:FREQ=DAILY;UNTIL=20261009T140015Z\nEND:VEVENT\nEND:VCALENDAR\n");
    assert!(json.contains("\"startSecond\":30"), "{json}");
}

// Monthly date limits and positions must reach the same expansion used by editable files.
#[test]
fn monthly_limits_reach_the_occurrence_query() {
    let json = convert_text("monthly-limits", "BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:limits\nDTSTART:20261001T090000\nRRULE:FREQ=MONTHLY;BYDAY=MO,TU;BYMONTH=10;BYMONTHDAY=1,2,3;BYSETPOS=-1;WKST=SU\nEND:VEVENT\nEND:VCALENDAR\n");
    assert!(json.contains("\"byDay\":[1,2]"), "{json}");
    assert!(json.contains("\"ruleRest\":\"BYMONTH=10;BYMONTHDAY=1,2,3;BYSETPOS=-1;WKST=SU\""), "{json}");
}

// An unsupported frequency must not populate retained rule parts.
#[test]
fn unsupported_frequency_has_no_rule_rest() {
    for (freq, repeat, rest) in [
        ("HOURLY", "none", "null"),
        ("YEARLY", "yearly", "\"BYMONTH=10\""),
    ] {
        let text = format!("BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:frequency\nDTSTART:20261005T090000\nRRULE:FREQ={freq};BYMONTH=10\nEND:VEVENT\nEND:VCALENDAR\n");
        let json = convert_text(&format!("frequency-{freq}"), &text);
        assert!(json.contains(&format!("\"repeat\":\"{repeat}\"")), "{json}");
        assert!(json.contains(&format!("\"ruleRest\":{rest}")), "{json}");
    }
}

// DURATION supplies the exclusive event end, including calendar days across DST.
#[test]
fn duration_supplies_event_end() {
    let path = format!("{}/../../tests/fixtures/feeds/duration.ics", env!("CARGO_MANIFEST_DIR"));
    let json = convert(&path);
    assert!(json.contains("\"date\":\"2026-10-08\",\"time\":null,\"end\":null,\"endDate\":\"2026-10-10\""), "{json}");
    assert!(json.contains("\"time\":\"23:00\",\"end\":\"00:31\",\"endDate\":\"2026-10-09\""), "{json}");
    assert!(json.contains("\"time\":\"07:00\",\"end\":\"08:00\",\"endDate\":\"2026-10-25\""), "{json}");
    assert!(json.contains("\"time\":\"07:00\",\"end\":\"07:00\",\"endDate\":\"2026-10-25\""), "{json}");
}
