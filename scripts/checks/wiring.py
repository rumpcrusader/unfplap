"""Single-place wiring: one `wire` per facade, called once by its scope root.

Each rule is a pure function over a path and its text so ``fixtures.py`` can drive both directions;
the ``check_*`` wrapper only feeds the real tree into them.
"""
from __future__ import annotations

import re

from .context import ROOT, SERVICES, facade_for, facade_scope, read_text, shipped_sources
from .failure import Failure, rel
from .text import (
    INFERRED_VAR,
    PRELOAD_CONST,
    TYPED_VAR,
    enclosing_function,
    function_offsets,
    line_of,
    mask_comments,
)

MOD_PREFIX = "res://mods/unfplap/"
# The one root per scope: the process and World services are wired by the entry, the Pony services
# by the runtime. `tests/` and `tools/` are not shipped, so they never reach this map.
ROOT_FOR_SCOPE = {"process": "main.gd", "world": "main.gd", "pony": "runtime.gd"}
# The composition verbs each root may call. The three roots construct, wire, name and attach; the
# Pony root also binds the act record's typed hosts, and `bind`/`bind_host` take a host or a value,
# `configure`/`from_dict` a value.
ROOT_CALLS = {
    "_build_process": frozenset({"new", "_add_node"}),
    "_build_world": frozenset({"new", "wire", "_build_record", "_attach", "connect"}),
    "_compose": frozenset({
        "new", "wire", "bind", "bind_host", "configure", "from_dict", "_attach"}),
}
# Values and predicates a root may use; they build or test a value, they run no behaviour.
ROOT_VALUE_CALLS = frozenset({"Callable", "is_instance_valid", "range", "str", "int", "float"})
# `wire` is the injection verb; `_init` is the constructor and the four hooks are the broadcast
# surface, so none of them is a second injection.
WIRING_EXEMPT = frozenset({
    "wire", "_init", "on_world", "on_player", "on_world_closed", "shutdown",
})
# A root may read nothing scene-wide and call nothing outside its composition verbs.
ROOT_READS = ("WORLD.", "SETTINGS.", "LOG.", "PERF.")
# A `wire` body takes peers and assigns them: no tree, no scene.
WIRE_TREE_CALLS = (
    "add_child", "get_tree", "get_node", "get_node_or_null", "is_inside_tree", "reparent",
    "queue_free", "set_process", "set_physics_process",
)
WIRE_READS = ("WORLD.", "SETTINGS.")
KEYWORDS = frozenset({
    "if", "elif", "else", "for", "while", "match", "return", "func", "and", "or", "not", "in",
    "is", "as", "assert", "pass", "var", "static", "break", "continue",
})

WIRE_DEFINITION = re.compile(r"^\s*(?:static\s+)?func\s+wire\s*\(", re.MULTILINE)
WIRE_CALL = re.compile(r"(?:([A-Za-z_]\w*)\s*\.\s*)?wire\s*\(")
SIGNATURE = re.compile(r"^func\s+([A-Za-z_]\w*)\s*\(([\s\S]*?)\)\s*(?:->[^\n:]+)?:", re.MULTILINE)
PARAM = re.compile(r"([A-Za-z_]\w*)\s*:\s*([A-Za-z_][\w.]*)")
CALL = re.compile(r"(?:([A-Za-z_]\w*)\s*\.\s*)?([A-Za-z_]\w*)\s*\(")
ASSIGN = re.compile(r"^\s*(?:self\.)?([A-Za-z_]\w*)\s*=\s*([A-Za-z_]\w*)\s*$", re.MULTILINE)
FUNCTION = re.compile(r"^(?:static\s+)?func\s+([A-Za-z_]\w*)\(")
# A function-local typed var: the composition roots build their services this way.
LOCAL_TYPED_VAR = re.compile(r"^[ \t]+var\s+([A-Za-z_]\w*)\s*:\s*([A-Za-z_]\w*)[ \t]*(?:=|$)",
                             re.MULTILINE)


def facade_map() -> dict[str, str]:
    """Facade path -> service id, the membership the rules read."""
    return {f"{sid}/{facade_for(sid)}": sid for sid in SERVICES}


def facade_scopes() -> dict[str, str]:
    """Facade path -> declared scope."""
    return {f"{sid}/{facade_for(sid)}": facade_scope(sid) for sid in SERVICES}


def type_map(text: str) -> dict[str, str]:
    """A file's preloaded consts and its typed vars, module-level first: name -> mod-relative path.

    A composition root builds several services in locals, so a local typed var must resolve for
    the wire-site rule to see the call.
    """
    consts = {
        match.group(1): match.group(2).removeprefix(MOD_PREFIX)
        for match in PRELOAD_CONST.finditer(text)
    }
    out: dict[str, str] = {}
    for match in TYPED_VAR.finditer(text):
        if match.group(2) in consts:
            out[match.group(1)] = consts[match.group(2)]
    for match in LOCAL_TYPED_VAR.finditer(text):
        if match.group(2) in consts:
            out.setdefault(match.group(1), consts[match.group(2)])
    for match in INFERRED_VAR.finditer(text):
        if match.group(2) in consts:
            out.setdefault(match.group(1), consts[match.group(2)])
    return out


def function_span(text: str, name: str) -> tuple[int, str]:
    """(body offset, body) of one function, so a finding keeps its line number."""
    match = re.search(r"^(?:static\s+)?func\s+%s\s*\(" % re.escape(name), text, re.MULTILINE)
    if not match:
        return -1, ""
    rest = text[match.end():]
    following = re.search(r"^(?:static\s+)?func\s+", rest, re.MULTILINE)
    return match.end(), rest[:following.start()] if following else rest


def signatures(text: str) -> list[tuple[str, str]]:
    """(function, parameter text) for every function in one file."""
    return [(match.group(1), match.group(2)) for match in SIGNATURE.finditer(text)]


def params_of(parameter_text: str) -> list[tuple[str, str]]:
    """(name, declared type) for every typed parameter."""
    return [(match.group(1), match.group(2)) for match in PARAM.finditer(parameter_text)]


def wire_defined(text: str) -> bool:
    """True when the file declares a `wire` function."""
    return bool(WIRE_DEFINITION.search(mask_comments(text)))


def wire_calls(text: str, scopes: dict[str, str] | None = None) -> list[tuple[int, str, str]]:
    """(line, receiver, facade path) for every `<receiver>.wire(` that wires a facade."""
    masked = mask_comments(text)
    types = type_map(text)
    scopes = facade_scopes() if scopes is None else scopes
    lines = masked.splitlines()
    out: list[tuple[int, str, str]] = []
    for match in WIRE_CALL.finditer(masked):
        line = line_of(masked, match.start())
        if lines[line - 1].lstrip().startswith("func "):
            continue
        receiver = match.group(1)
        if not receiver:
            continue
        target = types.get(receiver, "")
        if target not in scopes:
            continue
        out.append((line, receiver, target))
    return out


# --------------------------------------------------------------------------- rule 1: one wire


def wire_call_failures(path: str, text: str, scopes: dict[str, str] | None = None,
                       roots: dict[str, str] | None = None) -> list[str]:
    """A facade's `wire` is called by its scope's root and by no other file."""
    scopes = facade_scopes() if scopes is None else scopes
    roots = ROOT_FOR_SCOPE if roots is None else roots
    out: list[str] = []
    for line, receiver, target in wire_calls(text, scopes):
        scope = scopes[target]
        root = roots.get(scope, "")
        if path == root:
            continue
        out.append(
            "%s:%d calls %s.wire(); only %s wires a %s service" % (path, line, receiver, root,
                                                                   scope))
    return out


def wire_sites_failures(sites: dict[str, list[str]], definitions: list[str],
                        scopes: dict[str, str] | None = None,
                        roots: dict[str, str] | None = None) -> list[str]:
    """Every facade that defines `wire` is wired exactly once, by its scope root."""
    scopes = facade_scopes() if scopes is None else scopes
    roots = ROOT_FOR_SCOPE if roots is None else roots
    out: list[str] = []
    for target in sorted(set(definitions) | set(sites)):
        root = roots.get(scopes.get(target, ""), "")
        found = sites.get(target, [])
        if target not in definitions:
            out.append("%s is wired but defines no wire()" % target)
            continue
        if found == [root]:
            continue
        if not found:
            out.append(
                "%s defines wire() but no composition root calls it (expected %s)" % (target,
                                                                                     root))
        else:
            out.append(
                "%s wire() must be called once by %s, found: %s" % (
                    target, root, ", ".join(found)))
    return out


# ------------------------------------------------------------------------ rule 2: one injection


def peer_param_failures(path: str, text: str, facades: dict[str, str] | None = None) -> list[str]:
    """A facade that wires takes peers only in its one `wire`.

    The four lifecycle hooks and `_init` are excepted: they take the scene host or the record,
    not a peer.
    """
    facades = facade_map() if facades is None else facades
    if path not in facades or not wire_defined(text):
        return []
    consts = {
        match.group(1): match.group(2).removeprefix(MOD_PREFIX)
        for match in PRELOAD_CONST.finditer(text)
    }
    out: list[str] = []
    for name, parameter_text in signatures(mask_comments(text)):
        if name in WIRING_EXEMPT:
            continue
        for param, declared in params_of(parameter_text):
            if consts.get(declared, "") in facades:
                out.append(
                    "%s: %s(%s: %s) takes a peer outside wire()" % (path, name, param, declared))
    return out


def _injection_member(body: str, peer_params: set[str]) -> bool:
    """True when the member stores one of its facade-typed parameters in a field."""
    for match in ASSIGN.finditer(body):
        if match.group(1) in peer_params or match.group(2) in peer_params:
            return True
    return False


def injection_failures(path: str, text: str, facades: dict[str, str] | None = None) -> list[str]:
    """The one member that stores a facade-typed parameter is the facade's `wire`."""
    facades = facade_map() if facades is None else facades
    if path not in facades:
        return []
    masked = mask_comments(text)
    consts = {
        match.group(1): match.group(2).removeprefix(MOD_PREFIX)
        for match in PRELOAD_CONST.finditer(text)
    }
    stray: list[str] = []
    for name, parameter_text in signatures(masked):
        if name in WIRING_EXEMPT:
            continue
        peer_params = {
            param for param, declared in params_of(parameter_text)
            if consts.get(declared, "") in facades
        }
        if not peer_params:
            continue
        _start, body = function_span(masked, name)
        if _injection_member(body, peer_params):
            stray.append(name)
    if not stray:
        return []
    return [
        "%s stores a peer in %s(); the one peer-injection member is wire()" % (
            path, ", ".join(sorted(stray)))
    ]


# --------------------------------------------------------------------- rule 3: root purity


def _wire_argument_spans(body: str) -> list[tuple[int, int]]:
    """Offsets of every balanced argument list of a `wire(...)` call in one body."""
    spans: list[tuple[int, int]] = []
    for match in re.finditer(r"\.\s*wire\s*\(", body):
        opening = match.end() - 1
        depth = 0
        for index in range(opening, len(body)):
            if body[index] == "(":
                depth += 1
            elif body[index] == ")":
                depth -= 1
                if depth == 0:
                    spans.append((opening, index))
                    break
    return spans


def _is_peer_extraction(body: str, match: re.Match[str], types: dict[str, str],
                        facades: set[str], spans: list[tuple[int, int]]) -> bool:
    """A zero-argument read on a root-built facade, passed straight to `wire`."""
    receiver = match.group(1)
    if not receiver or types.get(receiver) not in facades:
        return False
    tail = body[match.end():].lstrip()
    if not tail.startswith(")"):
        return False
    return any(start < match.start() < end for start, end in spans)


def root_purity_failures(path: str, text: str, function: str,
                         allowed: frozenset[str] | None = None,
                         reads: tuple[str, ...] = ROOT_READS,
                         facades: dict[str, str] | None = None) -> list[str]:
    """A root constructs, wires, names and attaches; it runs no behaviour and reads no scene."""
    allowed = ROOT_CALLS.get(function, frozenset()) if allowed is None else allowed
    facades = facade_map() if facades is None else facades
    masked = mask_comments(text)
    start, body = function_span(masked, function)
    if not body:
        return ["%s: the composition root %s() is missing" % (path, function)]
    types = type_map(text)
    spans = _wire_argument_spans(body)
    out: list[str] = []
    for match in CALL.finditer(body):
        name = match.group(2)
        if name in KEYWORDS or name in ROOT_VALUE_CALLS or name in allowed:
            continue
        if _is_peer_extraction(body, match, types, set(facades), spans):
            continue
        out.append(
            "%s:%d calls %s() in %s(); only the composition verbs are allowed" % (
                path, line_of(masked, start + match.start()), name, function))
    for read in reads:
        for match in re.finditer(r"\b%s" % re.escape(read), body):
            out.append(
                "%s:%d reads %s in %s(); the root reads no scene" % (
                    path, line_of(masked, start + match.start()), read.rstrip("."), function))
    return out


# --------------------------------------------------------------------- rule 4: wire purity


def wire_purity_failures(path: str, text: str) -> list[str]:
    """A `wire` body takes peers: no tree access and no scene read."""
    masked = mask_comments(text)
    start, body = function_span(masked, "wire")
    if not body:
        return []
    out: list[str] = []
    for word in WIRE_TREE_CALLS:
        for match in re.finditer(r"\b%s\s*\(" % word, body):
            out.append(
                "%s:%d calls %s() in wire(); wiring takes no tree access" % (
                    path, line_of(masked, start + match.start()), word))
    for read in WIRE_READS:
        for match in re.finditer(r"\b%s" % re.escape(read), body):
            out.append(
                "%s:%d reads %s in wire(); wiring reads no scene" % (
                    path, line_of(masked, start + match.start()), read.rstrip(".")))
    return out


# ------------------------------------------------------------------- rule 5: peer fields


def peer_field_failures(path: str, text: str) -> list[str]:
    """A field set from a wire parameter is written by `wire` and cleared by `shutdown` only."""
    masked = mask_comments(text)
    signature = re.search(r"^func\s+wire\s*\(([\s\S]*?)\)\s*->", masked, re.MULTILINE)
    start, body = function_span(masked, "wire")
    if not signature or not body:
        return []
    params = {name for name, _declared in params_of(signature.group(1))}
    fields = {
        match.group(1) for match in ASSIGN.finditer(body) if match.group(2) in params
    }
    offsets = function_offsets(masked)
    out: list[str] = []
    for field in sorted(fields):
        pattern = re.compile(r"^\s*(?:self\.)?%s\s*=(?!=)" % re.escape(field), re.MULTILINE)
        for match in pattern.finditer(masked):
            owner = enclosing_function(offsets, match.start())
            if owner in ("wire", "shutdown"):
                continue
            out.append(
                "%s:%d assigns the peer field %s in %s(); wire() sets it and shutdown() clears it" % (
                    path, line_of(masked, match.start()), field, owner))
    return out


# --------------------------------------------------------------------------- the real tree


def check_wiring(failure: Failure) -> None:
    facades = facade_map()
    sites: dict[str, list[str]] = {}
    definitions: list[str] = []
    for path in shipped_sources():
        name = rel(path)
        text = read_text(str(path))
        if name in facades and wire_defined(text):
            definitions.append(name)
        for _line, _receiver, target in wire_calls(text):
            sites.setdefault(target, []).append(name)
        failure.extend(wire_call_failures(name, text))
        failure.extend(peer_param_failures(name, text))
        failure.extend(injection_failures(name, text))
        failure.extend(wire_purity_failures(name, text))
        failure.extend(peer_field_failures(name, text))
    failure.extend(wire_sites_failures(sites, definitions))
    for path, function in (
            ("main.gd", "_build_process"),
            ("main.gd", "_build_world"),
            ("runtime.gd", "_compose"),
    ):
        target = ROOT / path
        if target.is_file():
            failure.extend(root_purity_failures(path, read_text(str(target)), function))
