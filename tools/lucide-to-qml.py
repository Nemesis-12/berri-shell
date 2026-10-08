#!/usr/bin/env python3
"""
Converts Lucide SVG icons (assets/icons/lucide/*.svg) into a JS module
(Icons.js) mapping icon name -> one SVG path string, so QML's PathSvg can
draw any Lucide icon without loading SVG files at runtime.

Each icon's SVG elements (path, circle, rect, line, polyline, polygon,
ellipse) are converted to path-data subpaths and joined with spaces, since
a single PathSvg path string may contain multiple "M ..." subpaths. All
icons share Lucide's 24x24 viewBox, so no scaling is needed here; Icon.qml
scales the 24-unit path to the requested pixel size.

Run after adding new SVGs to assets/icons/lucide/:
    python3 tools/lucide-to-qml.py
"""
import re
import sys
from pathlib import Path
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
ICONS_DIR = ROOT / "assets" / "icons" / "lucide"
OUT_FILE = ROOT / "common/Icons.js"

SVG_NS = "{http://www.w3.org/2000/svg}"
COMMANDS = "MmLlHhVvCcSsQqTtAaZz"


def num(v: str) -> float:
    return float(v)


def circle_to_path(el) -> str:
    cx, cy, r = num(el.get("cx", "0")), num(el.get("cy", "0")), num(el.get("r", "0"))
    # Two arcs make a full circle; a single 360-degree arc is degenerate in SVG.
    return (
        f"M{cx - r} {cy}A{r} {r} 0 1 0 {cx + r} {cy}"
        f"A{r} {r} 0 1 0 {cx - r} {cy}Z"
    )


def ellipse_to_path(el) -> str:
    cx, cy = num(el.get("cx", "0")), num(el.get("cy", "0"))
    rx, ry = num(el.get("rx", "0")), num(el.get("ry", "0"))
    return (
        f"M{cx - rx} {cy}A{rx} {ry} 0 1 0 {cx + rx} {cy}"
        f"A{rx} {ry} 0 1 0 {cx - rx} {cy}Z"
    )


def rect_to_path(el) -> str:
    x, y = num(el.get("x", "0")), num(el.get("y", "0"))
    w, h = num(el.get("width", "0")), num(el.get("height", "0"))
    rx = el.get("rx")
    ry = el.get("ry")
    rx = num(rx) if rx is not None else (num(ry) if ry is not None else 0)
    ry = num(ry) if ry is not None else rx
    if rx <= 0 or ry <= 0:
        return f"M{x} {y}H{x + w}V{y + h}H{x}Z"
    # Rounded rect: straight edges + quarter-ellipse arcs at each corner.
    return (
        f"M{x + rx} {y}"
        f"H{x + w - rx}A{rx} {ry} 0 0 1 {x + w} {y + ry}"
        f"V{y + h - ry}A{rx} {ry} 0 0 1 {x + w - rx} {y + h}"
        f"H{x + rx}A{rx} {ry} 0 0 1 {x} {y + h - ry}"
        f"V{y + ry}A{rx} {ry} 0 0 1 {x + rx} {y}Z"
    )


def line_to_path(el) -> str:
    x1, y1 = num(el.get("x1", "0")), num(el.get("y1", "0"))
    x2, y2 = num(el.get("x2", "0")), num(el.get("y2", "0"))
    return f"M{x1} {y1}L{x2} {y2}"


def points_to_coords(points: str):
    nums = [float(n) for n in re.split(r"[,\s]+", points.strip()) if n]
    return list(zip(nums[0::2], nums[1::2]))


def polyline_to_path(el) -> str:
    coords = points_to_coords(el.get("points", ""))
    if not coords:
        return ""
    parts = [f"M{coords[0][0]} {coords[0][1]}"]
    parts += [f"L{x} {y}" for x, y in coords[1:]]
    return "".join(parts)


def polygon_to_path(el) -> str:
    return polyline_to_path(el) + "Z"


CONVERTERS = {
    "path": lambda el: el.get("d", ""),
    "circle": circle_to_path,
    "rect": rect_to_path,
    "line": line_to_path,
    "polyline": polyline_to_path,
    "polygon": polygon_to_path,
    "ellipse": ellipse_to_path,
}


class UnsupportedPathError(ValueError):
    """An SVG path holds a character the generator cannot read."""


def skip_digits(d: str, i: int) -> tuple[int, bool]:
    """Returns the index after a run of digits and whether the run held any."""
    start = i
    while i < len(d) and d[i].isdigit():
        i += 1
    return i, i > start


def read_number(d: str, i: int, source: str) -> tuple[str, int]:
    """Reads one number (optional sign, digits, decimal point, exponent) at index i; returns its text and the next index."""
    start = i
    if i < len(d) and d[i] in '+-':
        i += 1
    i, has_digits = skip_digits(d, i)
    if i < len(d) and d[i] == '.':
        i += 1
        i, more = skip_digits(d, i)
        has_digits = has_digits or more
    if has_digits and i < len(d) and d[i] in 'eE':
        i += 1
        if i < len(d) and d[i] in '+-':
            i += 1
        i, _ = skip_digits(d, i)
    if i == start:
        raise UnsupportedPathError(
            f"{source}: unsupported character {d[i]!r} at position {i + 1}"
        )
    return d[start:i], i


def tokenize_path(d: str, source: str = "path") -> list:
    """Tokenize SVG path string into commands and number tokens.

    Handles numbers with optional +/-, digits, decimal points, and exponents.
    Raises UnsupportedPathError, naming the character, its 1-based position
    and `source`, for any other character.
    """
    tokens = []
    i = 0
    while i < len(d):
        # Skip whitespace and commas
        while i < len(d) and d[i] in ' \t\n\r,':
            i += 1
        if i >= len(d):
            break
        if d[i] in COMMANDS:
            tokens.append(d[i])
            i += 1
            continue
        number, after = read_number(d, i, source)
        # A lone sign is dropped; a signed number or a number with digits is kept.
        if after == i + 1 or any(c.isdigit() for c in number):
            tokens.append(number)
        i = after
    return tokens


def is_argument(tokens: list, i: int) -> bool:
    return i < len(tokens) and tokens[i] not in COMMANDS


def take_plain_args(tokens: list, i: int, count: int, args: list) -> int:
    """Copies up to `count` argument tokens into args; returns the next index."""
    for _ in range(count):
        if not is_argument(tokens, i):
            break
        args.append(tokens[i])
        i += 1
    return i


def take_flags(tokens: list, i: int, args: list) -> int:
    """Copies the two arc flags as single digits. A flag glued to the next number is split off."""
    for _ in range(2):
        if not is_argument(tokens, i):
            break
        token = tokens[i]
        if token and token[0] in '01':
            args.append(token[0])
            i += 1
            if token[1:]:
                tokens.insert(i, token[1:])  # the rest is the next argument
        else:
            args.append(token)  # not valid SVG, kept as it is
            i += 1
    return i


def take_arc(tokens: list, i: int) -> tuple[list, int]:
    """Reads one arc: rx ry rotation large-arc-flag sweep-flag x y. A short arc has fewer than 7 args."""
    args = []
    i = take_plain_args(tokens, i, 3, args)
    i = take_flags(tokens, i, args)
    i = take_plain_args(tokens, i, 2, args)
    return args, i


def normalize_arc_commands(d: str, source: str = "path") -> str:
    """Normalize arc commands to proper spacing and flag extraction.

    Re-serializes arc commands (A/a) so that flags are single digits
    separated by spaces from other arguments. Handles compact arc syntax
    like "0010" where "00" are two flags and "10" is the next number.
    """
    tokens = tokenize_path(d, source)
    normalized = []
    i = 0
    while i < len(tokens):
        token = tokens[i]
        normalized.append(token)
        i += 1
        if token not in 'Aa':
            continue
        while is_argument(tokens, i):
            arc_args, i = take_arc(tokens, i)
            normalized.extend(arc_args)
            if len(arc_args) < 7:
                break
    return serialize_tokens(normalized)


def serialize_tokens(tokens: list) -> str:
    """One space before each number; commands stay glued to the text before them."""
    result = ""
    for token in tokens:
        result += token if token in COMMANDS else " " + token
    return result.strip()


def normalize_first_move(path_d: str) -> str:
    """Ensure the first move command is absolute (M not m).

    When converting 'm' to 'M', any additional coordinate pairs in the same
    move command that were implicit relative linetos must be made explicit
    as 'l' commands to preserve their relative meaning.
    """
    if not path_d or path_d[0] != 'm':
        return path_d

    # Find where the first move command ends (at the next command letter or EOL)
    first_cmd_end = len(path_d)
    for i in range(1, len(path_d)):
        if path_d[i] in 'MmLlHhVvCcSsQqTtAaZz':
            first_cmd_end = i
            break

    # Extract the move command part and remainder
    move_part = path_d[1:first_cmd_end]  # Everything after 'm'
    remainder = path_d[first_cmd_end:]

    # Parse numbers from move_part
    numbers = [float(n) for n in re.findall(r'[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?', move_part)]

    if len(numbers) < 2:
        # No valid coordinates
        return path_d

    # Build result: M for first pair, l for additional pairs
    result = f'M{numbers[0]:g} {numbers[1]:g}'
    for i in range(2, len(numbers), 2):
        if i + 1 < len(numbers):
            result += f' l{numbers[i]:g} {numbers[i+1]:g}'

    result += remainder
    return result


def svg_to_path_string(svg_path: Path) -> str:
    tree = ET.parse(svg_path)
    subpaths = []
    for el in tree.getroot().iter():
        tag = el.tag.removeprefix(SVG_NS)
        converter = CONVERTERS.get(tag)
        if converter is None:
            continue
        d = converter(el)
        if d:
            d = normalize_first_move(d)
            d = normalize_arc_commands(d, svg_path.name)
            subpaths.append(d)
    return " ".join(subpaths)


def build_icons_js(icons_dir: Path) -> tuple[str, int]:
    """Returns the Icons.js text and the icon count for every SVG in icons_dir."""
    svgs = sorted(icons_dir.glob("*.svg"))
    if not svgs:
        raise FileNotFoundError(f"no SVGs found in {icons_dir}")

    entries = [(svg_path.stem, svg_to_path_string(svg_path)) for svg_path in svgs]

    lines = [
        "// Auto-generated by tools/lucide-to-qml.py. Do not edit by hand.",
        "// Maps a Lucide icon name to one SVG path string (24x24 viewBox).",
        "// To add an icon: drop its SVG into assets/icons/lucide/ and re-run the script.",
        ".pragma library",
        "",
        "var paths = {",
    ]
    for name, path_string in entries:
        escaped = path_string.replace("\\", "\\\\").replace('"', '\\"')
        lines.append(f'    "{name}": "{escaped}",')
    lines.append("};")
    lines.append("")
    return "\n".join(lines), len(entries)


def main():
    if not ICONS_DIR.is_dir():
        sys.exit(f"no such directory: {ICONS_DIR}")

    try:
        text, count = build_icons_js(ICONS_DIR)
    except (FileNotFoundError, UnsupportedPathError) as error:
        sys.exit(str(error))

    OUT_FILE.write_text(text)
    print(f"wrote {count} icons to {OUT_FILE}")


if __name__ == "__main__":
    main()
