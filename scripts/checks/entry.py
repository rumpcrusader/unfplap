"""The entry, the runtime host, the ownership rule and the one-sink rule."""
from __future__ import annotations

import re
from pathlib import Path

from .context import ROOT, owner_of, read_text, shipped_sources
from .failure import Failure, rel
from .text import (
    CALLABLE_TARGET,
    INFERRED_VAR,
    MOD_EXTENDS,
    PRELOAD_CONST,
    TYPED_VAR,
    _code_lines,
    enclosing_function,
    function_offsets,
    line_of,
)

MAIN_CONST = re.compile(
    r'^const\s+([A-Z][A-Z0-9_]*)\s*:=\s*preload\("(res://[^"]+)"\)', re.MULTILINE)
MAIN_ADD = re.compile(r"_add\(\s*([A-Z][A-Z0-9_]*)\.new\(")
MAIN_ADD_HUD = re.compile(r"_add_hud\(\s*([A-Z][A-Z0-9_]*)\.new\(")
ENTRY_MEMBER = re.compile(r"(?<![\w.])main\.(?!gd\b)[A-Za-z_]\w*")
ENTRY_DECLARATION = re.compile(r"^\s*(?:var|const)\s+main\b", re.MULTILINE)
ENTRY_PRELOAD = re.compile(r'(?:preload|load)\(\s*"[^"]*main\.gd"')
ENTRY_ARGUMENT = re.compile(r"[(,]\s*main\s*[:,)]")
# The world facade is the scene read surface: the game, the player rig and the shared modules.
WORLD_ALLOWED = ("res://world/", "res://player/", "res://mods/unfplap/shared/",
                 "res://mods/unfplap/world/")
WORLD_IMPORT = re.compile(r'(?:preload|load)\("(res://[^"]+\.gd)"\)')
WORLD_EXTENDS = re.compile(r'^extends\s+"(res://[^"]+)"', re.MULTILINE)
# The lifecycle base is a no-behaviour contract; the HUD is the one non-base list service.
SERVICE_BASE = "shared/service.gd"
HUD_FACADE = "hud/service.gd"
# runtime.gd is the per-pony Node host: it owns lifetime and node operations and implements no
# system's rules. The state-writer rule, the fixed public surface and the settings/child-node
# allow-lists are the invariant. The allow-lists are compared both ways, so a new read or node
# fails and a row that no longer exists fails too.
RUNTIME_STATE_WRITER = "act/session.gd:_set_state"
RUNTIME_STATE_OWNER = ROOT / "act" / "session.gd"
# Every `SETTINGS.<member>` read, keyed by its enclosing function (`<module>` for the field block)
# and the reason it is a snapshot boundary rather than a per-frame read. A new read is a new row,
# added on purpose with the service that owns the value; removing a read removes its row.
RUNTIME_SETTINGS_READS = {}
# The act session's settings owner holds the one snapshot, so its boundaries are checked the same
# way: the bulk snapshot and the pre-edit preference refresh, never a per-frame read.
ACT_SETTINGS_OWNER = ROOT / "act" / "settings.gd"
ACT_SETTINGS_READS = {
    ("<module>", "ActSnapshot"): "the typed `snapshot` field's zeroed default",
    ("snapshot_values", "act_snapshot"): "the act's one bulk snapshot",
    ("live_preferences", "preferences"): "the live preference refresh",
}
# The runtime node parents no child: the act audio node and the pose-scope tail tuck are created by
# their owners. A row is added only for a system-owned node the host itself must add.
RUNTIME_CHILD_NODES = {}
# The runtime node's public functions: the entry's lifetime ops. `act`, `gate` and `pony` are
# properties, not rows. A new public function is a facade regrowth; the comparison runs both ways.
NODE_SURFACE = {
    "live_id": "the stable pony id the entry and ponies read",
    "attach_to_body": "the handover's reparent off the old body",
    "adopt_body": "the handover's reparent onto the new body",
}
# The runtime node's public properties: the two handles and the presented body. They are properties
# rather than rows because the entry reads them without a call; the comparison runs both ways.
NODE_PROPERTIES = {
    "act": "the act's one session handle",
    "scene": "the per-pony scene gate handle",
    "start": "the per-pony start handle",
    "presentation": "the per-pony presentation handle",
    "pony": "the presented body; its setter rebinds the bundle",
}
# A file over this many lines is reported as a smell, never as a failure. Size is a hint that a
# module may be mixing concerns; the ownership and boundary rules below are the hard gates.
LARGE_FILE_LINES = 1000
# One sink and one profiler: every other shipped script reaches them through `LOG` and `PERF`. A
# hand-written print, warning, timestamp or engine monitor is a second one.
LOG_MODULES = {"shared/log.gd", "shared/perf.gd"}
LOG_BLEED = (
    "print(",
    "printerr(",
    "push_warning(",
    "push_error(",
    '"[unfplap] "',
    "get_ticks_usec() -",
    "Performance.get_monitor",
    "Engine.get_frames_per_second",
    "RenderingServer.get_rendering_info",
)

RUNTIME_RAW_INPUT = (
    re.compile(r"\bInput\."),
    re.compile(r"\bInputMap\."),
    re.compile(r"\bInputEvent\w*"),
    re.compile(r"\bKEY_[A-Z0-9_]+\b"),
    re.compile(r"\bMOUSE_MODE_[A-Z0-9_]+\b"),
    re.compile(r"^func\s+_(?:unhandled_|gui_)?input\(", re.MULTILINE),
)


def _script_methods(path: Path, seen: set[Path]) -> tuple[bool, set[str]]:
    """(fully_scanned, functions) for one mod script and its mod ancestors."""
    if path in seen or not path.is_file():
        return False, set()
    seen.add(path)
    text = _code_lines(read_text(str(path)))
    names = set(re.findall(r"^(?:static\s+)?func\s+(\w+)\(", text, re.MULTILINE))
    parent = MOD_EXTENDS.search(text)
    if parent:
        target = ROOT / parent.group(1).replace("res://mods/unfplap/", "")
        nested, inherited = _script_methods(target, seen)
        return nested, names | inherited
    if re.search(r"^extends\b", text, re.MULTILINE):
        return False, names
    return True, names


def check_callable_targets(failure: Failure) -> None:
    """A named callback must name a method that exists.

    `Callable(self, "name")` is checked against the same file. `Callable(obj, "name")` is checked
    when `obj` is a module-level field or constant whose declared or inferred type is one of the
    mod's preloaded scripts; an unresolvable receiver is skipped. This is the guard that keeps a
    renamed helper from silently returning its fallback forever.
    """
    cache: dict[Path, tuple[bool, set[str]]] = {}
    for path in shipped_sources():
        text = _code_lines(read_text(str(path)))
        funcs = set(re.findall(r"^(?:static\s+)?func\s+(\w+)\(", text, re.MULTILINE))
        consts = {m.group(1): m.group(2) for m in PRELOAD_CONST.finditer(text)}
        types: dict[str, str] = {}
        for match in TYPED_VAR.finditer(text):
            name, declared = match.group(1), match.group(2)
            if declared in consts:
                types[name] = consts[declared]
        for match in INFERRED_VAR.finditer(text):
            name, declared = match.group(1), match.group(2)
            if declared in consts:
                types.setdefault(name, consts[declared])
        for match in CALLABLE_TARGET.finditer(text):
            receiver, method = match.group(1), match.group(2)
            line = line_of(text, match.start())
            if receiver == "self":
                if method not in funcs:
                    failure.add("%s:%d binds Callable(self, \"%s\") but defines no %s()" % (
                        rel(path), line, method, method))
                continue
            target = types.get(receiver)
            if not target:
                continue
            script = ROOT / target.replace("res://mods/unfplap/", "")
            if not script.is_file():
                continue
            if script not in cache:
                cache[script] = _script_methods(script, set())
            scanned, names = cache[script]
            if scanned and method not in names:
                failure.add("%s:%d binds Callable(%s, \"%s\") but %s defines no %s()" % (
                    rel(path), line, receiver, method, rel(script), method))

    # The composition root receives the runtime node as a parameter, so its node callables have no
    # typed field to resolve against. They name methods on `runtime.gd`; check them there, or a
    # renamed host method silently returns its fallback forever.
    builder = ROOT / "act" / "build.gd"
    runtime_path = ROOT / "runtime.gd"
    if builder.is_file() and runtime_path.is_file():
        runtime_funcs = set(re.findall(
            r"^(?:static\s+)?func\s+(\w+)\(",
            _code_lines(read_text(str(runtime_path))), re.MULTILINE))
        builder_text = _code_lines(read_text(str(builder)))
        for match in CALLABLE_TARGET.finditer(builder_text):
            if match.group(1) != "node":
                continue
            if match.group(2) not in runtime_funcs:
                failure.add(
                    "act/build.gd:%d binds Callable(node, \"%s\") but runtime.gd defines no %s()" % (
                        line_of(builder_text, match.start()), match.group(2), match.group(2)))


def check_owners(failure: Failure) -> None:
    """Every shipped `.gd` must belong to a service, `shared/` or an orchestrator."""
    for path in shipped_sources():
        name = rel(path)
        if owner_of(name) is None:
            failure.add("%s has no owner: a shipped .gd belongs to a service, to shared/ or to "
                        "main.gd, runtime.gd, api.gd" % name)


def check_boundaries(failure: Failure) -> None:
    """The composition-root rules: nothing but the entry names the entry, no reach-in into the
    entry, and a scene-only world facade."""
    reach_in = re.compile(r'\b(?:main|runtime)\.(?:call|get)\("_')
    entry_rules = (
        (ENTRY_MEMBER, "a preloaded facade, a `WORLD` read or a host parameter"),
        (ENTRY_DECLARATION, "a preloaded facade, a `WORLD` read or a host parameter"),
        (ENTRY_PRELOAD, "the facade it needs or `WORLD`"),
        (ENTRY_ARGUMENT, "a typed host parameter"),
    )
    for path in shipped_sources():
        if path == ROOT / "main.gd":
            continue
        text = read_text(str(path))
        for match in reach_in.finditer(text):
            failure.add("%s:%d reaches into a private member: %s" % (
                rel(path), line_of(text, match.start()), match.group(0)))
        for pattern, instead in entry_rules:
            for match in pattern.finditer(text):
                failure.add(
                    "%s:%d names the entry (%s): use %s; only main.gd and tests/ may name `main`"
                    % (rel(path), line_of(text, match.start()), match.group(0).strip(), instead))

    # The world facade answers where and what from the scene alone: it imports the game and the
    # shared pure modules, never a service facade, the runtime or the entry.
    world = ROOT / "world" / "api.gd"
    if not world.is_file():
        failure.add("missing world/api.gd")
        return
    source = "\n".join(
        line for line in read_text(str(world)).splitlines()
        if not line.lstrip().startswith("#"))
    imports = [(m.group(1), m.start()) for m in WORLD_IMPORT.finditer(source)]
    imports += [(m.group(1), m.start()) for m in WORLD_EXTENDS.finditer(source)]
    for target, at in imports:
        if target.startswith(WORLD_ALLOWED):
            continue
        failure.add("world/api.gd:%d may not import %s" % (line_of(source, at), target))


def check_runtime_shape(failure: Failure) -> None:
    """The thin-runtime invariant: a host composes and orders; it implements no system's rules."""
    path = ROOT / "runtime.gd"
    if not path.is_file():
        failure.add("missing runtime.gd")
        return
    text = read_text(str(path))
    offsets = function_offsets(text)

    # The act state has one owner: `act/session.gd` declares it and only `_set_state()` writes it.
    session_path = RUNTIME_STATE_OWNER
    if not session_path.is_file():
        failure.add("missing act/session.gd: it owns the act state")
    else:
        session_text = read_text(str(session_path))
        session_offsets = function_offsets(session_text)
        if len(re.findall(r"^func _set_state\(", session_text, re.MULTILINE)) != 1:
            failure.add("act/session.gd must define exactly one _set_state()")
        if not re.search(r"^var state:\s*int\b", session_text, re.MULTILINE):
            failure.add("act/session.gd must declare the typed `state` field once")
        for match in re.finditer(r"^\s*(?:self\.)?state\s*=(?!=)", session_text,
                                 re.MULTILINE):
            if enclosing_function(session_offsets, match.start()) != "_set_state":
                failure.add(
                    "act/session.gd:%d assigns `state` outside %s(); it is the one writer" % (
                        line_of(session_text, match.start()), RUNTIME_STATE_WRITER))
    for match in re.finditer(r"^\s*(?:self\.)?state\s*=(?!=)", text, re.MULTILINE):
        failure.add("runtime.gd:%d assigns `state`; %s is the one writer" % (
            line_of(text, match.start()), RUNTIME_STATE_WRITER))

    # The node's public surface is the entry's lifetime ops; a new public function is a facade
    # regression. The allow-list is compared both ways.
    public_funcs = set(re.findall(r"^func ([A-Za-z]\w*)\(", text, re.MULTILINE))
    for name in sorted(public_funcs - set(NODE_SURFACE)):
        failure.add("runtime.gd:%s() is a new public function; the node surface is fixed" % name)
    for name, reason in sorted(NODE_SURFACE.items()):
        if name not in public_funcs:
            failure.add("the node surface allow-list row %s is stale (%s)" % (name, reason))

    # The same both-ways rule for the node's properties.
    properties = set(re.findall(r"^var ([A-Za-z]\w*)\s*:", text, re.MULTILINE))
    for name in sorted(properties - set(NODE_PROPERTIES)):
        failure.add("runtime.gd:%s is a new public property; the node surface is fixed" % name)
    for name, reason in sorted(NODE_PROPERTIES.items()):
        if name not in properties:
            failure.add("the node property allow-list row %s is stale (%s)" % (name, reason))

    # Raw input has one owner: input/service.gd owns it.
    for pattern in RUNTIME_RAW_INPUT:
        for match in pattern.finditer(text):
            failure.add("runtime.gd:%d decodes raw input (%s); input/service.gd owns it" % (
                line_of(text, match.start()), match.group(0).strip()))

    # Settings arrive once per act and again on apply_live_settings(), never per frame.
    reads: dict[tuple[str, str], int] = {}
    for match in re.finditer(r"SETTINGS\.(\w+)", text):
        key = (enclosing_function(offsets, match.start()), match.group(1))
        reads.setdefault(key, line_of(text, match.start()))
    for key, line in sorted(reads.items()):
        if key not in RUNTIME_SETTINGS_READS:
            failure.add(
                "runtime.gd:%d reads SETTINGS.%s in %s(); take a snapshot value or add an "
                "allow-list row only at an act boundary" % (line, key[1], key[0]))
    for key, reason in sorted(RUNTIME_SETTINGS_READS.items()):
        if key not in reads:
            failure.add("the runtime settings allow-list row %s -> %s is stale (%s)" % (
                key[0], key[1], reason))

    # The act's settings snapshot has the same boundary rule.
    settings_path = ACT_SETTINGS_OWNER
    if not settings_path.is_file():
        failure.add("missing act/settings.gd: it owns the act's settings snapshot")
    else:
        settings_text = read_text(str(settings_path))
        settings_offsets = function_offsets(settings_text)
        settings_reads: dict[tuple[str, str], int] = {}
        for match in re.finditer(r"SETTINGS\.(\w+)", settings_text):
            key = (enclosing_function(settings_offsets, match.start()), match.group(1))
            settings_reads.setdefault(key, line_of(settings_text, match.start()))
        for key, line in sorted(settings_reads.items()):
            if key not in ACT_SETTINGS_READS:
                failure.add(
                    "act/settings.gd:%d reads SETTINGS.%s in %s(); take a snapshot value or add "
                    "an allow-list row only at an act boundary" % (line, key[1], key[0]))
        for key, reason in sorted(ACT_SETTINGS_READS.items()):
            if key not in settings_reads:
                failure.add("the act settings allow-list row %s -> %s is stale (%s)" % (
                    key[0], key[1], reason))

    # The runtime parents only the nodes a system owns; it constructs no scene of its own.
    children: dict[str, int] = {}
    for match in re.finditer(r"\badd_child\(", text):
        owner = enclosing_function(offsets, match.start())
        children.setdefault(owner, line_of(text, match.start()))
    for owner, line in sorted(children.items()):
        if owner not in RUNTIME_CHILD_NODES:
            failure.add("runtime.gd:%d creates a child node in %s(); only the documented "
                        "system-owned nodes are parented here" % (line, owner))
    for owner, reason in sorted(RUNTIME_CHILD_NODES.items()):
        if owner not in children:
            failure.add("the runtime child allow-list row %s is stale (%s)" % (owner, reason))


def report_large_files() -> None:
    """Report files over the smell threshold. Size is information, not a gate."""
    for path in sorted(shipped_sources()):
        lines = len(read_text(str(path)).splitlines())
        if lines > LARGE_FILE_LINES:
            print("SMELL large file: %s (%d lines)" % (rel(path), lines))


def check_entry_shape(failure: Failure) -> None:
    """The entry constructs and binds; it never dispatches by string or assigns a service's fields."""
    main_path = ROOT / "main.gd"
    if not main_path.is_file():
        failure.add("missing main.gd")
        return
    text = read_text(str(main_path))
    for needle in (".call(", '.get("', '.set("'):
        for match in re.finditer(re.escape(needle), text):
            failure.add(
                "main.gd:%d dispatches by string (%s); name the typed member"
                % (line_of(text, match.start()), needle))
    for match in re.finditer(r"\baction_[A-Za-z0-9_]", text):
        failure.add(
            "main.gd:%d registers an action handler; the debug service owns its actions"
            % line_of(text, match.start()))


def check_static_instances(failure: Failure) -> None:
    """A service is injected, never reached through a static `instance` handle."""
    pattern = re.compile(r"^\s*static var\s+instance\b", re.MULTILINE)
    for path in shipped_sources():
        if pattern.search(read_text(str(path))):
            failure.add("%s declares a static service instance; pass the facade instead" % rel(path))


def check_service_bases(failure: Failure) -> None:
    """Every service the entry adds is a `shared/service.gd` descendant; the HUD is the exception."""
    main_path = ROOT / "main.gd"
    if not main_path.is_file():
        return
    text = read_text(str(main_path))
    consts = {
        match.group(1): match.group(2).replace("res://mods/unfplap/", "")
        for match in MAIN_CONST.finditer(text)
    }

    def chain(name: str) -> set[str]:
        seen: set[str] = set()
        while name and name not in seen:
            seen.add(name)
            current = ROOT / name
            if not current.is_file():
                break
            match = MOD_EXTENDS.search(read_text(str(current)))
            name = match.group(1).replace("res://mods/unfplap/", "") if match else ""
        return seen

    for match in MAIN_ADD.finditer(text):
        const = match.group(1)
        name = consts.get(const, "")
        if not name:
            failure.add("main.gd adds %s but no preloaded const resolves it" % const)
        elif name == HUD_FACADE:
            failure.add("main.gd adds the HUD with _add(); use _add_hud()")
        elif SERVICE_BASE not in chain(name):
            failure.add("%s does not extend %s; the typed service list requires it" % (
                name, SERVICE_BASE))
    for match in MAIN_ADD_HUD.finditer(text):
        const = match.group(1)
        if consts.get(const, "") != HUD_FACADE:
            failure.add("main.gd adds %s with _add_hud(); only the HUD uses it" % const)
    hud_path = ROOT / HUD_FACADE
    if hud_path.is_file():
        hud_text = read_text(str(hud_path))
        for hook in ("on_world", "on_world_closed", "on_player", "shutdown"):
            if not re.search(r"^func %s\(" % hook, hud_text, re.MULTILINE):
                failure.add(
                    "hud/service.gd is missing %s(); it is the one non-base list service" % hook)


def check_log_bleed(failure: Failure) -> None:
    """Only the log sink prints and only the profiler reads a clock or an engine monitor."""
    for path in shipped_sources():
        name = rel(path)
        if name in LOG_MODULES:
            continue
        for number, line in enumerate(read_text(str(path)).splitlines(), start=1):
            if line.lstrip().startswith("#"):
                continue
            for needle in LOG_BLEED:
                if needle in line:
                    failure.add("%s:%d writes outside the one sink (%s): use LOG or PERF" % (
                        name, number, needle))
