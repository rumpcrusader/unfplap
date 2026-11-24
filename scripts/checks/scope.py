"""The scope tree: declarations, roots, attachment, groups and cross-scope edges.

Each rule is a pure function over a path and its text so ``fixtures.py`` can drive both
directions; the ``check_*`` wrappers only feed the real tree into them.
"""
from __future__ import annotations

import re

from .context import (
    DECLARATION_FIELDS,
    FROZEN_HEADERS,
    LEGACY_DECLARATION_FIELDS,
    ROOT,
    SCOPES,
    SERVICES,
    WORLD_STATIC,
    declaration_of,
    facade_for,
    facade_scope,
    owner_of,
    read_text,
    shipped_sources,
)
from .failure import Failure, rel
from .graph import PUBLIC_SERVICE_FILES
from .text import PRELOAD_CONST, enclosing_function, function_offsets, line_of

SERVICE_BASE = "shared/service.gd"
NODE_BASES = {"Node", "CanvasLayer", SERVICE_BASE}
NODE_SCOPES = {"world", "pony"}
# The one root per scope: the process and World services are constructed by the entry, the Pony
# services by the runtime. `tests/` and `tools/` are not shipped, so they never reach this map.
ROOT_FOR_SCOPE = {"process": "main.gd", "world": "main.gd", "pony": "runtime.gd"}
WORLD_GROUP = "unfplap_world"
PONY_GROUP = "unfplap_pony_service"
WORLD_HELPER = "_attach"
PONY_HELPER = "_attach"
WORLD_ROOT = "_build_world"
PONY_ROOT = "_compose"
FIXED_CHILD_NAMES = ("UnfplapRuntime", "UnfplapApi")
STATIC_VAR = re.compile(r"^static\s+var\s+(\w+)", re.MULTILINE)
WORLD_FACADE = "res://mods/unfplap/world/api.gd"

EXTENDS = re.compile(r"^extends\s+(.+)$", re.MULTILINE)
NEW_ASSIGN = re.compile(
    r"^\s*(?:var\s+)?([A-Za-z_]\w*)\s*(?::\s*[\w.\[\]]+\s*)?(?:=|:=)\s*"
    r"([A-Z][A-Z0-9_]*)\.new\(", re.MULTILINE)
NEW_CALL = re.compile(r"\b([A-Z][A-Z0-9_]*)\.new\(")
ATTACH = re.compile(r'\b_attach\(\s*([A-Za-z_]\w*)\s*,\s*"([A-Za-z_]\w*)"\s*\)')
ADD_CHILD = re.compile(r"\badd_child\(")
SELF_NAME = re.compile(r"^\s*(?:self\.)?name\s*=", re.MULTILINE)
GROUP_CALL = re.compile(
    r"(?:([A-Za-z_]\w*)\.)?add_to_group\(\s*([A-Za-z_]\w*|\"[^\"]*\")\s*\)")


def facade_paths() -> dict[str, str]:
    """Facade path -> service id, the one map the construction rule reads."""
    return {f"{sid}/{facade_for(sid)}": sid for sid in SERVICES}


def facade_scopes() -> dict[str, str]:
    """Facade path -> declared scope."""
    return {
        f"{sid}/{facade_for(sid)}": facade_scope(sid)
        for sid in SERVICES
    }


# --------------------------------------------------------------------------- the facade name


def facade_name_failures(path: str) -> list[str]:
    """The one facade name is `api.gd`; the base class under `shared/` keeps its name."""
    if not path.endswith("/service.gd") or path.startswith("shared/"):
        return []
    return ["%s: the facade name is api.gd" % path]


def check_scope_facade_names(failure: Failure) -> None:
    for path in shipped_sources():
        failure.extend(facade_name_failures(rel(path)))


def extends_parent(path: str) -> str:
    """The parent a mod file extends, as a mod-relative path or an engine type name."""
    target = ROOT / path
    if not target.is_file():
        return ""
    match = EXTENDS.search(read_text(str(target)))
    if not match:
        return ""
    value = match.group(1).strip()
    if value.startswith('"') and value.endswith('"'):
        value = value[1:-1]
        if value.startswith("res://mods/unfplap/"):
            return value.removeprefix("res://mods/unfplap/")
        return value
    return value


def base_chain(path: str) -> list[str]:
    """The `extends` chain above a mod file, engine base included as its last name."""
    chain: list[str] = []
    seen: set[str] = set()
    current = path
    while current and current not in seen:
        seen.add(current)
        parent = extends_parent(current)
        if not parent:
            break
        chain.append(parent)
        if not (ROOT / parent).is_file():
            break
        current = parent
    return chain


# --------------------------------------------------------------------------- rule 1: declarations


def declaration_failures(path: str, text: str, sid: str | None) -> list[str]:
    """A facade declares all three fields; a non-facade declares none (frozen headers excepted)."""
    fields = declaration_of(text)
    if sid is None:
        found = [
            field for field in DECLARATION_FIELDS + LEGACY_DECLARATION_FIELDS
            if field in fields
        ]
        return [
            "%s: a non-facade carries a declaration field ## %s:" % (path, field)
            for field in found
        ]
    out: list[str] = []
    for field in DECLARATION_FIELDS:
        if field not in fields:
            out.append("%s: a facade is missing the ## %s: field" % (path, field))
    for field in fields:
        if field not in DECLARATION_FIELDS:
            out.append("%s: a facade declares an unknown field ## %s:" % (path, field))
    service = fields.get("Service", "")
    if service and service != sid:
        out.append("%s: ## Service: is %s, expected its directory %s" % (path, service, sid))
    scope = fields.get("Scope", "")
    if scope and scope not in SCOPES:
        out.append(
            "%s: ## Scope: is %s, expected one of %s" % (path, scope, "|".join(SCOPES)))
    contract = fields.get("Contract", "")
    expected = "docs/%s.md" % sid
    if contract and contract != expected:
        out.append("%s: ## Contract: is %s, expected %s" % (path, contract, expected))
    return out


def check_scope_declarations(failure: Failure) -> None:
    facades = facade_paths()
    for path in shipped_sources():
        name = rel(path)
        if name in FROZEN_HEADERS:
            continue
        failure.extend(declaration_failures(name, read_text(str(path)), facades.get(name)))


# --------------------------------------------------------------------------- rule 2: the Node base


def node_base_failures(path: str, scope: str, chain: list[str]) -> list[str]:
    """A World or Pony facade is a Node; a process facade may be anything, and the static World
    read facade is the named exception."""
    if scope not in NODE_SCOPES or path == WORLD_STATIC:
        return []
    if any(base in NODE_BASES for base in chain):
        return []
    found = chain[0] if chain else "no extends"
    return [
        "%s: a %s facade must extend Node, CanvasLayer or %s (found %s)" % (
            path, scope, SERVICE_BASE, found)
    ]


def check_scope_bases(failure: Failure) -> None:
    for sid in SERVICES:
        path = f"{sid}/{facade_for(sid)}"
        failure.extend(node_base_failures(path, facade_scope(sid), base_chain(path)))


# --------------------------------------------------------------------------- rule 3: construction


def facade_constructions(text: str, facades: dict[str, str]) -> list[tuple[int, str, str]]:
    """(line, const, facade) for every `<FACADE_CONST>.new(` site in one file."""
    consts = {
        match.group(1): match.group(2).removeprefix("res://mods/unfplap/")
        for match in PRELOAD_CONST.finditer(text)
    }
    out: list[tuple[int, str, str]] = []
    for match in NEW_CALL.finditer(text):
        target = consts.get(match.group(1), "")
        if target in facades:
            out.append((line_of(text, match.start()), match.group(1), target))
    return out


def construction_failures(path: str, text: str,
                          facade_scopes_by_path: dict[str, str] | None = None,
                          roots: dict[str, str] | None = None) -> list[str]:
    """A service is constructed only by its scope's root; an Other helper is not a facade."""
    scopes = facade_scopes() if facade_scopes_by_path is None else facade_scopes_by_path
    roots = ROOT_FOR_SCOPE if roots is None else roots
    out: list[str] = []
    for line, _const, target in facade_constructions(text, scopes):
        scope = scopes[target]
        root = roots.get(scope)
        if root is None or path == root:
            continue
        out.append(
            "%s:%d constructs the %s facade %s; only %s constructs a %s service" % (
                path, line, scope, target, root, scope))
    return out


def check_scope_construction(failure: Failure) -> None:
    scopes = facade_scopes()
    for path in shipped_sources():
        name = rel(path)
        failure.extend(construction_failures(name, read_text(str(path)), scopes))


# --------------------------------------------------------------------------- rule 4: attachment


def attach_failures(path: str, text: str, expected: dict[str, str],
                    helper: str = WORLD_HELPER,
                    function: str = WORLD_ROOT) -> list[str]:
    """The root preloads, constructs and attaches every service of its scope, and names it."""
    out: list[str] = []
    consts = {
        match.group(1): match.group(2).removeprefix("res://mods/unfplap/")
        for match in PRELOAD_CONST.finditer(text)
    }
    offsets = function_offsets(text)
    assigned: dict[str, str] = {}
    for match in NEW_ASSIGN.finditer(text):
        if enclosing_function(offsets, match.start()) == function:
            assigned[match.group(1)] = match.group(2)
    attached: dict[str, tuple[int, str]] = {}
    for match in ATTACH.finditer(text):
        if enclosing_function(offsets, match.start()) != function:
            out.append(
                "%s:%d attaches a service in %s(); %s is the only caller" % (
                    path, line_of(text, match.start()),
                    enclosing_function(offsets, match.start()), function))
            continue
        attached.setdefault(match.group(1), (line_of(text, match.start()), match.group(2)))
    for const, sid in sorted(expected.items()):
        if const not in consts:
            out.append("%s: the root does not preload the %s facade" % (path, sid))
            continue
        local = next((name for name, used in assigned.items() if used == const), "")
        if not local:
            out.append(
                "%s: %s does not construct the %s facade (%s)" % (path, function, sid, const))
            continue
        if local not in attached:
            out.append(
                "%s: %s does not attach the %s service (%s)" % (
                    path, function, sid, local))
            continue
        line, node_name = attached[local]
        if not node_name:
            out.append("%s:%d attaches the %s service without a name" % (path, line, sid))
    return out


def child_site_failures(path: str, text: str, helpers: set[str]) -> list[str]:
    """Only the attach helper may parent a service."""
    offsets = function_offsets(text)
    out: list[str] = []
    for match in ADD_CHILD.finditer(text):
        owner = enclosing_function(offsets, match.start())
        if owner in helpers:
            continue
        out.append(
            "%s:%d creates a child node in %s(); %s is the one attach site" % (
                path, line_of(text, match.start()), owner, " and ".join(sorted(helpers))))
    return out


def entry_name_failures(path: str, text: str) -> list[str]:
    """The loader owns the host name; the entry never renames itself."""
    return [
        "%s:%d renames the entry; the loader defines the host name" % (
            path, line_of(text, match.start()))
        for match in SELF_NAME.finditer(text)
    ]


def fixed_name_failures(path: str, text: str,
                        names: tuple[str, ...] = FIXED_CHILD_NAMES) -> list[str]:
    """The process node and the runtime keep their fixed child names."""
    out: list[str] = []
    for name in names:
        assigned = (
            re.search(r'\.name\s*=\s*"%s"' % re.escape(name), text)
            or re.search(r'_add_node\([^,]+,\s*"%s"\)' % re.escape(name), text)
        )
        if not assigned:
            out.append("%s: the fixed child name %s is never assigned" % (path, name))
    return out


def facade_consts(text: str, scope: str) -> dict[str, str]:
    """The preloaded facades of one scope, keyed by their const name."""
    out: dict[str, str] = {}
    for match in PRELOAD_CONST.finditer(text):
        target = match.group(2).removeprefix("res://mods/unfplap/")
        if target == WORLD_STATIC:
            continue
        if target in facade_paths() and facade_scope(facade_paths()[target]) == scope:
            out[match.group(1)] = facade_paths()[target]
    return out


def check_scope_attachment(failure: Failure) -> None:
    main_path = ROOT / "main.gd"
    runtime_path = ROOT / "runtime.gd"
    if not main_path.is_file():
        failure.add("missing main.gd")
        return
    main_text = read_text(str(main_path))
    failure.extend(entry_name_failures("main.gd", main_text))
    failure.extend(fixed_name_failures("main.gd", main_text))
    failure.extend(child_site_failures("main.gd", main_text, {"_attach", "_add_node"}))
    failure.extend(attach_failures(
        "main.gd", main_text, facade_consts(main_text, "world"), WORLD_HELPER, WORLD_ROOT))
    if not runtime_path.is_file():
        failure.add("missing runtime.gd")
        return
    runtime_text = read_text(str(runtime_path))
    failure.extend(child_site_failures("runtime.gd", runtime_text, {PONY_HELPER}))
    failure.extend(attach_failures(
        "runtime.gd", runtime_text, facade_consts(runtime_text, "pony"),
        PONY_HELPER, PONY_ROOT))


# --------------------------------------------------------------------------- rule 6: groups


def group_failures(path: str, text: str, group: str, helper: str) -> list[str]:
    """A scope group is added by its attach helper, to the service it is attaching."""
    consts = {
        match.group(1): match.group(2)
        for match in re.finditer(r'^const\s+(\w+)\s*:=\s*"([^"]+)"', text, re.MULTILINE)
    }
    offsets = function_offsets(text)
    out: list[str] = []
    hits = 0
    for match in GROUP_CALL.finditer(text):
        argument = match.group(2)
        value = consts.get(argument, argument.strip('"'))
        if value != group:
            continue
        hits += 1
        owner = enclosing_function(offsets, match.start())
        if owner != helper:
            out.append(
                "%s:%d adds the %s scope group in %s(); %s is the one site" % (
                    path, line_of(text, match.start()), group, owner, helper))
        if not match.group(1):
            out.append(
                "%s:%d adds the %s scope group to the file's own node" % (
                    path, line_of(text, match.start()), group))
    if hits == 0:
        out.append("%s: %s never adds the %s scope group" % (path, helper, group))
    return out


def check_scope_groups(failure: Failure) -> None:
    main_path = ROOT / "main.gd"
    runtime_path = ROOT / "runtime.gd"
    if not main_path.is_file() or not runtime_path.is_file():
        return
    failure.extend(group_failures(
        "main.gd", read_text(str(main_path)), WORLD_GROUP, WORLD_HELPER))
    failure.extend(group_failures(
        "runtime.gd", read_text(str(runtime_path)), PONY_GROUP, PONY_HELPER))


# --------------------------------------------------------------------------- rule 7: cross-scope


def file_scope(path: str) -> str:
    """The scope a shipped path belongs to; `Other`, `shared/` and the API root answer ""."""
    if path == "main.gd":
        return "world"
    if path == "runtime.gd":
        return "pony"
    if path == "api.gd":
        return "process"
    owner = owner_of(path)
    if owner is None or owner.kind not in ("service", "store"):
        return ""
    return facade_scope(owner.id)


def cross_scope_failures(path: str, text: str, scope_of=None,
                         facades: dict[str, str] | None = None) -> list[str]:
    """A facade is public across scopes; a private file is not, except the typed records.

    A root composes its scope's Other helpers, so the private-file rule applies to services
    only; the construction rule names the one root a service may be built in.
    """
    scope_of = file_scope if scope_of is None else scope_of
    facades = facade_paths() if facades is None else facades
    source = scope_of(path)
    if not source:
        return []
    owner = owner_of(path)
    out: list[str] = []
    for match in PRELOAD_CONST.finditer(text):
        target = match.group(2).removeprefix("res://mods/unfplap/")
        target_scope = scope_of(target)
        if not target_scope or target_scope == source:
            continue
        if target in facades or target in PUBLIC_SERVICE_FILES:
            continue
        if owner is None or owner.kind != "service":
            continue
        out.append(
            "%s:%d preloads the %s file %s from the %s scope" % (
                path, line_of(text, match.start()), target_scope, target, source))
    return out


def check_scope_cross(failure: Failure) -> None:
    facades = facade_paths()
    for path in shipped_sources():
        name = rel(path)
        failure.extend(cross_scope_failures(name, read_text(str(path)), facades=facades))


# --------------------------------------------------------------------------- rule 8: static state


def static_state_failures(path: str, scope: str, text: str) -> list[str]:
    """A world or pony facade is an instance; static state belongs to the process class and the one
    static read facade."""
    if scope not in NODE_SCOPES or path == WORLD_STATIC:
        return []
    out: list[str] = []
    for match in STATIC_VAR.finditer(text):
        out.append(
            "%s:%d declares `static var %s`; a %s facade is an instance, not a registry" % (
                path, line_of(text, match.start()), match.group(1), scope))
    return out


def world_alias_failures(path: str, text: str) -> list[str]:
    """`WORLD` may name only the static read facade; a non-preload const (the settings section
    name) is not an alias."""
    out: list[str] = []
    for match in PRELOAD_CONST.finditer(text):
        if match.group(1) == "WORLD" and match.group(2) != WORLD_FACADE:
            out.append(
                "%s:%d aliases WORLD to %s; %s is the one static read facade" % (
                    path, line_of(text, match.start()), match.group(2), WORLD_FACADE))
    return out


def check_scope_statics(failure: Failure) -> None:
    scopes = facade_scopes()
    for path in shipped_sources():
        name = rel(path)
        text = read_text(str(path))
        scope = scopes.get(name)
        if scope is not None:
            failure.extend(static_state_failures(name, scope, text))
        failure.extend(world_alias_failures(name, text))
