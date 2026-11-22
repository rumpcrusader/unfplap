"""The top preload block, the base-game accessor and the autoload literals."""
from __future__ import annotations

import re
from pathlib import Path

from .context import ROOT, all_sources, read_text, shipped_sources
from .failure import Failure, rel
from .graph import GAME_LAYER
from .text import GD_CONST, GD_LITERAL, LOAD_CALL, PRELOAD_CALL, _bracket_delta, _code_part


def preload_block_problems(text: str) -> list[tuple[int, str]]:
    """Where a script breaks the top preload block: a late or nested ``preload()`` and a script
    ``load()``. The block is the contiguous top-level const region below the doc header.

    Asset ``load(path)``, ``ANATOMY.MEMBER`` and a `.load()` method stay legal: only a script is a
    dependency the preload graph must carry.
    """
    lines = text.splitlines()
    out: list[tuple[int, str]] = []
    cursor = 0
    while cursor < len(lines) and (not lines[cursor].strip() or lines[cursor].startswith("@")):
        cursor += 1
    if cursor < len(lines) and lines[cursor].startswith("extends "):
        cursor += 1
    # The first `##` block before any other declaration is the file's doc header. A preload
    # above it is outside the block even though it is a top-level const.
    probe = cursor
    header_at = None
    while probe < len(lines):
        line = lines[probe]
        if not line.strip() or line.lstrip().startswith("#"):
            probe += 1
            continue
        if line.startswith("const "):
            probe += 1
            continue
        break
    for at in range(cursor, probe):
        if lines[at].startswith("##"):
            header_at = at
            break
    if header_at is not None:
        cursor = header_at
        while cursor < len(lines) and lines[cursor].startswith("##"):
            cursor += 1

    allowed: set[int] = set()
    while cursor < len(lines):
        line = lines[cursor]
        if not line.strip() or line.lstrip().startswith("#"):
            cursor += 1
            continue
        if not line.startswith("const "):
            break
        start = cursor
        depth = _bracket_delta(line)
        while depth > 0 or lines[cursor].rstrip().endswith("\\"):
            if cursor + 1 >= len(lines):
                break
            cursor += 1
            depth += _bracket_delta(lines[cursor])
        if not any(PRELOAD_CALL.search(_code_part(lines[at])) for at in range(start, cursor + 1)):
            break
        allowed.update(range(start, cursor + 1))
        cursor += 1

    for number, line in enumerate(lines, start=1):
        code = _code_part(line)
        for _match in PRELOAD_CALL.finditer(code):
            if number - 1 not in allowed:
                out.append((number, "preload() outside the leading const block: declare every "
                                   "script dependency directly below the doc header"))

    scripts = {match.group(1) for match in GD_CONST.finditer(text)}
    for number, line in enumerate(lines, start=1):
        code = _code_part(line)
        for match in LOAD_CALL.finditer(code):
            argument = code[match.end():].strip()
            literal = GD_LITERAL.match(argument)
            if literal:
                out.append((number, "load() of the script %s: preload it as a top-level const"
                            % literal.group(1)))
                continue
            name = re.match(r"([A-Za-z_]\w*)\s*[,)]", argument)
            if name and name.group(1) in scripts:
                out.append((number, "load() of the script const %s: preload it and call new()"
                            % name.group(1)))
    return out


def check_preloads(failure: Failure) -> None:
    for path in all_sources():
        for number, message in preload_block_problems(read_text(str(path))):
            failure.add("%s:%d %s" % (rel(path), number, message))


def check_game_layer(failure: Failure, sources: list[Path] | None = None) -> None:
    """An accessor file lives only in a game-layer service directory."""
    for path in shipped_sources() if sources is None else sources:
        if path.name != "game.gd":
            continue
        service = path.parent.name
        if service not in GAME_LAYER:
            failure.add("%s: game.gd belongs to a game-layer service (%s)"
                        % (rel(path), ", ".join(sorted(GAME_LAYER))))


# The base-game autoload paths obey the import rule: only the entry and a game-layer accessor may
# name one; every other file asks the owning service.
BASE_GAME_AUTOLOADS = ('"/root/Settings"', '"/root/Mods"')


def check_autoloads(failure: Failure) -> None:
    """A base-game autoload path is reached only through the owning game-layer accessor."""
    for path in shipped_sources():
        name = rel(path)
        if name == "main.gd" or (path.name == "game.gd" and path.parent.name in GAME_LAYER):
            continue
        text = read_text(str(path))
        for literal in BASE_GAME_AUTOLOADS:
            if literal in text:
                failure.add("%s names the base-game autoload %s: read it through the owning "
                            "service's game.gd or a facade" % (name, literal))
