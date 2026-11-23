"""Pure text helpers shared by the checks: comment stripping and function spans."""
from __future__ import annotations

import re

PRELOAD_CALL = re.compile(r"(?<![\w.])preload\(")
LOAD_CALL = re.compile(r"(?<![\w.])load\(")
GD_CONST = re.compile(
    r'^const\s+([A-Za-z_]\w*)\s*(?::\s*[\w.\[\]]+\s*)?(?::=|=)\s*'
    r'(?:preload\(\s*)?"([^"]+\.gd)"',
    re.MULTILINE,
)
GD_LITERAL = re.compile(r'^"([^"]+\.gd)"')
CALLABLE_TARGET = re.compile(
    r"Callable\(\s*([A-Za-z_]\w*)\s*,\s*\"([A-Za-z_]\w*)\"\s*\)")
PRELOAD_CONST = re.compile(
    r"^const\s+(\w+)\s*(?::\s*[\w.\[\]]+\s*)?(?::=|=)\s*preload\(\s*\"(res://[^\"]+\.gd)\"\s*\)",
    re.MULTILINE)
TYPED_VAR = re.compile(r"^var\s+(\w+)\s*:\s*([A-Za-z_]\w*)", re.MULTILINE)
INFERRED_VAR = re.compile(r"^var\s+(\w+)\s*:=\s*([A-Za-z_]\w*)\.new\(", re.MULTILINE)
MOD_EXTENDS = re.compile(r'^extends\s+"(res://mods/unfplap/[^"]+\.gd)"', re.MULTILINE)


def comment_index(line: str) -> int:
    """The index of the `#` that opens a comment, or -1; quotes are respected.

    Quotes are tracked one line at a time, so a `#` inside a multi-line string can truncate a
    line, which only makes the scan miss a site.
    """
    quote = ""
    index = 0
    while index < len(line):
        char = line[index]
        if quote:
            if char == "\\":
                index += 2
                continue
            if char == quote:
                quote = ""
        elif char in ("\"", "'"):
            quote = char
        elif char == "#":
            return index
        index += 1
    return -1


def _code_part(line: str) -> str:
    """The line up to an end-of-line comment, quotes respected."""
    cut = comment_index(line)
    return line if cut < 0 else line[:cut]


def _bracket_delta(line: str) -> int:
    """Open minus close brackets on a line, ignoring strings."""
    depth = 0
    quote = ""
    index = 0
    while index < len(line):
        char = line[index]
        if quote:
            if char == "\\":
                index += 2
                continue
            if char == quote:
                quote = ""
        elif char in ("\"", "'"):
            quote = char
        elif char == "#":
            break
        elif char in "([{":
            depth += 1
        elif char in ")]}":
            depth -= 1
        index += 1
    return depth


def _code_lines(text: str) -> str:
    """Source with comment lines and end-of-line comments removed, so a doc example is not a
    binding."""
    out: list[str] = []
    for line in text.splitlines():
        if line.lstrip().startswith("#"):
            continue
        cut = comment_index(line)
        out.append(line if cut < 0 else line[:cut])
    return "\n".join(out)


def mask_comments(text: str) -> str:
    """Comments blanked with the line structure kept, so offsets and line numbers stay valid."""
    out: list[str] = []
    for line in text.splitlines():
        cut = comment_index(line)
        out.append(line if cut < 0 else line[:cut] + " " * (len(line) - cut))
    return "\n".join(out)


def line_of(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


def function_body(text: str, name: str) -> str:
    match = re.search(r"^(?:static\s+)?func %s\(" % re.escape(name), text, re.MULTILINE)
    if not match:
        return ""
    rest = text[match.end():]
    next_func = re.search(r"^(?:static\s+)?func ", rest, re.MULTILINE)
    return rest[:next_func.start()] if next_func else rest


def call_lines(text: str, needle: str) -> list[str]:
    return [
        line for line in text.splitlines()
        if needle in line and not line.lstrip().startswith(("#", "func"))
    ]


def function_offsets(text: str) -> list[tuple[int, str]]:
    return [
        (match.start(), match.group(1))
        for match in re.finditer(r"^(?:static\s+)?func\s+(\w+)\(", text, re.MULTILINE)
    ]


def enclosing_function(offsets: list[tuple[int, str]], at: int) -> str:
    name = "<module>"
    for offset, func in offsets:
        if offset > at:
            break
        name = func
    return name
