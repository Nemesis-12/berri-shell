#!/usr/bin/env python3
"""
Static icon-name scan. Finds every icon name written as a string in the QML
and JS files and fails when a name has no SVG in assets/icons/lucide/.

Checked places: `name:` inside an `Icon { ... }` block, and the properties
`icon:`, `iconName:` and `fallbackName:`. Every string literal in the value
counts, so a ternary like `a ? "x" : "y"` checks both names. A literal that
only takes part in a comparison (`kind === "HDMI"`) is skipped. The icon helper
functions (iconForGroup, outputIcon, signalIcon) are scanned for `return`
literals.

Usage: python3 tools/check-icon-names.py [source-root]
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SKIP_PARTS = {"tests", "scratchpad", "tools", "node_modules"}
ICON_PROPERTY = re.compile(r"\b(?:icon|iconName|fallbackName)\s*:([^,}]*)")
ICON_BLOCK_NAME = re.compile(r"\bname\s*:([^,;}]*)")
COMPARISON = re.compile(r'[=!]==\s*"[^"]*"')
ICON_BLOCK_START = re.compile(r"\bIcon\s*\{")
ICON_FUNCTION = re.compile(r"function\s+(?:iconFor\w*|outputIcon|signalIcon)\b")
LITERAL = re.compile(r'"([^"\\]*)"')
RETURN_LITERAL = re.compile(r"\breturn\b(.*)")


def known_names(icons_dir: Path) -> set:
    return {svg.stem for svg in icons_dir.glob("*.svg")}


def source_files(root: Path):
    for path in sorted(root.rglob("*")):
        if path.suffix not in (".qml", ".js") or path.name == "Icons.js":
            continue
        if SKIP_PARTS & set(path.relative_to(root).parts):
            continue
        yield path


def literals(text: str) -> list:
    """String literals in text, without the ones that only take part in a comparison."""
    return [name for name in LITERAL.findall(COMPARISON.sub("", text)) if name]


def used_names(path: Path):
    """Yields (line number, icon name) for every icon name literal in path."""
    block_depth = None  # brace depth of the Icon block being read
    depth = 0
    function_depth = None  # brace depth of the icon helper function being read
    for number, line in enumerate(path.read_text().splitlines(), 1):
        code = line.split("//", 1)[0]
        if block_depth is None and ICON_BLOCK_START.search(code):
            block_depth = depth
        if function_depth is None and ICON_FUNCTION.search(code):
            function_depth = depth

        match = ICON_PROPERTY.search(code)
        if match is None and block_depth is not None:
            match = ICON_BLOCK_NAME.search(code)
        if match is None and function_depth is not None:
            match = RETURN_LITERAL.search(code)
        if match is not None:
            for name in literals(match.group(1)):
                yield number, name

        depth += code.count("{") - code.count("}")
        if block_depth is not None and depth <= block_depth:
            block_depth = None
        if function_depth is not None and depth <= function_depth:
            function_depth = None


def find_unknown(root: Path, icons_dir: Path) -> list:
    """Returns 'file:line: name' for each icon name with no SVG."""
    known = known_names(icons_dir)
    problems = []
    for path in source_files(root):
        for number, name in used_names(path):
            if name not in known:
                problems.append(f"{path.relative_to(root)}:{number}: unknown icon '{name}'")
    return problems


def main():
    root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else ROOT
    problems = find_unknown(root, root / "assets" / "icons" / "lucide")
    for problem in problems:
        print(problem)
    if problems:
        sys.exit(1)
    print("all icon names exist")


if __name__ == "__main__":
    main()
