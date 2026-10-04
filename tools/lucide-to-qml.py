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

        # Command letter
        if d[i] in 'MmLlHhVvCcSsQqTtAaZz':
            tokens.append(d[i])
            i += 1
        else:
            # Parse number: [+-]? (\d+\.?\d* | \.\d+) ([eE][+-]?\d+)?
            start = i
            if i < len(d) and d[i] in '+-':
                i += 1

            has_digits = False
            while i < len(d) and d[i].isdigit():
                has_digits = True
                i += 1

            if i < len(d) and d[i] == '.':
                i += 1
                while i < len(d) and d[i].isdigit():
                    has_digits = True
                    i += 1

            if has_digits and i < len(d) and d[i] in 'eE':
                i += 1
                if i < len(d) and d[i] in '+-':
                    i += 1
                while i < len(d) and d[i].isdigit():
                    i += 1

            if i == start:
                raise UnsupportedPathError(
                    f"{source}: unsupported character {d[i]!r} at position {i + 1}"
                )
            if i == start + 1 or has_digits:
                tokens.append(d[start:i])

    return tokens


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

        if token in 'Aa':
            normalized.append(token)
            i += 1

            # Process arc arguments (7 per arc: rx ry rotation large-arc-flag sweep-flag x y)
            while i < len(tokens) and tokens[i] not in 'MmLlHhVvCcSsQqTtAaZz':
                arc_args = []

                # rx, ry, rotation (first 3 args)
                for _ in range(3):
                    if i < len(tokens) and tokens[i] not in 'MmLlHhVvCcSsQqTtAaZz':
                        arc_args.append(tokens[i])
                        i += 1
                    else:
                        break

                # large-arc-flag, sweep-flag (args 3-4, must be single digits 0 or 1)
                for _ in range(2):
                    if i < len(tokens) and tokens[i] not in 'MmLlHhVvCcSsQqTtAaZz':
                        token_str = tokens[i]
                        if token_str and token_str[0] in '01':
                            arc_args.append(token_str[0])
                            remainder = token_str[1:]
                            i += 1
                            if remainder:
                                # Insert remainder back for next iteration
                                tokens.insert(i, remainder)
                        else:
                            # Shouldn't happen in valid SVG, but handle gracefully
                            arc_args.append(token_str)
                            i += 1
                    else:
                        break

                # x, y (args 5-6)
                for _ in range(2):
                    if i < len(tokens) and tokens[i] not in 'MmLlHhVvCcSsQqTtAaZz':
                        arc_args.append(tokens[i])
                        i += 1
                    else:
                        break

                normalized.extend(arc_args)

                # If we couldn't read a full 7-arg arc, stop this sequence
                if len(arc_args) < 7:
                    break
        else:
            normalized.append(token)
            i += 1

    # Serialize with single space between command and args
    result = ""
    for token in normalized:
        if token in 'MmLlHhVvCcSsQqTtAaZz':
            result += token
        else:
            result += " " + token

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
