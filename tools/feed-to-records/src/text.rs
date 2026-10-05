//! Lines and text values of an iCalendar feed.

/// The parameters of a property, with upper-case names.
pub type Params = Vec<(String, String)>;

// Joins physical lines that start with a space or tab.
pub fn unfold(text: &str) -> Vec<String> {
    let mut lines: Vec<String> = Vec::new();
    for part in text.split(['\r', '\n']) {
        if let Some(rest) = part.strip_prefix([' ', '\t']) {
            if let Some(last) = lines.last_mut() {
                last.push_str(rest);
            }
        } else if !part.is_empty() {
            lines.push(part.to_owned());
        }
    }
    lines
}

// Splits an iCalendar property while quoted parameters can contain punctuation.
pub fn property(line: &str) -> Option<(String, Params, &str)> {
    let mut quote = false;
    let mut colon = None;
    let mut cuts = Vec::new();
    for (index, ch) in line.char_indices() {
        if ch == '"' {
            quote = !quote;
        } else if !quote && ch == ';' {
            cuts.push(index);
        } else if !quote && ch == ':' {
            colon = Some(index);
            break;
        }
    }
    let colon = colon?;
    let mut pieces = Vec::new();
    let mut start = 0;
    for cut in cuts {
        pieces.push(&line[start..cut]);
        start = cut + 1;
    }
    pieces.push(&line[start..colon]);
    let params = pieces[1..]
        .iter()
        .filter_map(|part| part.split_once('='))
        .map(|(key, value)| (key.to_ascii_uppercase(), value.trim_matches('"').to_owned()))
        .collect();
    Some((pieces[0].to_ascii_uppercase(), params, &line[colon + 1..]))
}

// Removes the text escapes defined by iCalendar.
pub fn text_value(value: &str) -> String {
    let mut output = String::new();
    let mut chars = value.chars();
    while let Some(ch) = chars.next() {
        if ch != '\\' {
            output.push(ch);
            continue;
        }
        match chars.next() {
            Some('n' | 'N') => output.push('\n'),
            Some(next @ ('\\' | ',' | ';')) => output.push(next),
            Some(next) => {
                output.push('\\');
                output.push(next);
            }
            None => output.push('\\'),
        }
    }
    output
}
