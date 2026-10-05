//! The colors that a feed can give to a record.

// Accepts the color keys and hex colors that berri can show.
pub fn clean_color(value: &str) -> Option<String> {
    let color = value.trim().to_ascii_lowercase();
    if [
        "accent", "blue", "green", "yellow", "red", "cyan", "magenta", "orange",
    ]
    .contains(&color.as_str())
    {
        return Some(color);
    }
    let hex = color.strip_prefix('#')?;
    if ![3, 6].contains(&hex.len()) || !hex.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        return None;
    }
    if hex.len() == 6 {
        return Some(color);
    }
    let mut full = String::from("#");
    for ch in hex.chars() {
        full.push(ch);
        full.push(ch);
    }
    Some(full)
}

// The color of an old CATEGORIES value, or None for any other category.
pub fn category_color(value: &str) -> Option<&'static str> {
    match value.trim().to_ascii_lowercase().as_str() {
        "personal" => Some("accent"),
        "work" => Some("blue"),
        "health" => Some("green"),
        "home" => Some("yellow"),
        _ => None,
    }
}
