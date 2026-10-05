//! JSON writing without an external crate.

// Appends one escaped JSON string.
pub fn json_string(output: &mut String, value: &str) {
    output.push('"');
    for ch in value.chars() {
        match ch {
            '"' => output.push_str("\\\""),
            '\\' => output.push_str("\\\\"),
            '\n' => output.push_str("\\n"),
            '\r' => output.push_str("\\r"),
            '\t' => output.push_str("\\t"),
            ch if ch <= '\u{001f}' => output.push_str(&format!("\\u{:04x}", ch as u32)),
            _ => output.push(ch),
        }
    }
    output.push('"');
}

// Appends a named string value or null.
pub fn field(output: &mut String, name: &str, value: Option<&str>) {
    json_string(output, name);
    output.push(':');
    if let Some(value) = value {
        json_string(output, value);
    } else {
        output.push_str("null");
    }
    output.push(',');
}

// Appends a named number value or null.
pub fn number(output: &mut String, name: &str, value: Option<usize>) {
    json_string(output, name);
    output.push(':');
    if let Some(value) = value {
        output.push_str(&value.to_string());
    } else {
        output.push_str("null");
    }
    output.push(',');
}

// Appends a named list of already-written JSON values, or null when the list is empty.
pub fn list(output: &mut String, name: &str, values: &[String]) {
    json_string(output, name);
    output.push(':');
    if values.is_empty() {
        output.push_str("null,");
        return;
    }
    output.push('[');
    output.push_str(&values.join(","));
    output.push_str("],");
}

// Appends a named list of strings, or null when the list is empty.
pub fn string_list(output: &mut String, name: &str, values: &[String]) {
    let quoted: Vec<String> = values
        .iter()
        .map(|value| {
            let mut text = String::new();
            json_string(&mut text, value);
            text
        })
        .collect();
    list(output, name, &quoted);
}

// Appends a named list of numbers, or null when the list is empty.
pub fn number_list(output: &mut String, name: &str, values: &[usize]) {
    let numbers: Vec<String> = values.iter().map(usize::to_string).collect();
    list(output, name, &numbers);
}
