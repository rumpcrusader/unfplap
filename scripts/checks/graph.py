"""The preload graph: edges, layer and owner rules, re-exports and the exception ledger."""
from __future__ import annotations

import json
import re

from .context import (
    ARCH,
    EXCEPTIONS,
    ROOT,
    SERVICES,
    Owner,
    load_json,
    owner_of,
    read_text,
    shipped_sources,
)
from .failure import Failure
from .text import PRELOAD_CONST, _code_lines

# Service files another owner may extend or preload as a documented extension point. The source
# base is a provider contract, not a second facade; the anatomy body binding is the attachment
# contract the body-change service constructs from the anatomy facade it is handed.
PUBLIC_SERVICE_FILES = {"body_change/source.gd"}
# The game layer: the only services allowed to touch the base game. Membership is by approval only;
# `vr` is deferred. Each member owns exactly one `<service>/game.gd`, its only base-game boundary
# and the only home of a base-game import or autoload literal; only that service's files import it.
GAME_LAYER = {"world", "settings", "debug", "hud"}
# The accessor files the base-game import rule allows, one per game-layer member.
GAME_SOURCES = ("world/game.gd", "settings/game.gd", "debug/game.gd", "hud/game.gd")

ANATOMY_FACADE = "anatomy/api.gd"
ELIGIBILITY_SCENE = "eligibility/scene.gd"


def is_game(path: str) -> bool:
    return path.startswith("res://world/") or path.startswith("res://player/")


def game_rel(path: str) -> str:
    return path


def scan_edges() -> set[tuple[str, str]]:
    edges: set[tuple[str, str]] = set()
    preload = re.compile(r'(?:preload|load)\("(res://mods/unfplap/[^"]+\.gd)"\)')
    game = re.compile(r'(?:preload|load)\("(res://(?:world|player)/[^"]+\.gd)"\)')
    extends = re.compile(r'^extends\s+"(res://[^"]+)"', re.MULTILINE)
    for path in shipped_sources():
        text = read_text(str(path))
        src = path.relative_to(ROOT).as_posix()
        for match in preload.finditer(text):
            target = match.group(1).replace("res://mods/unfplap/", "")
            edges.add((src, target))
        for match in game.finditer(text):
            edges.add((src, match.group(1)))
        for match in extends.finditer(text):
            target = match.group(1)
            if target.startswith("res://mods/unfplap/"):
                edges.add((src, target.replace("res://mods/unfplap/", "")))
            elif target.startswith("res://world/") or target.startswith("res://player/"):
                edges.add((src, target))
    return edges


def edge_kind(src: str, tgt: str) -> tuple[str, Owner | None, Owner | None]:
    so = owner_of(src)
    to = owner_of(tgt)
    if is_game(tgt):
        return "game", so, None
    if to is None:
        return "external", so, None
    if so and to and so.id == to.id:
        return "self", so, to
    if to.kind == "service":
        if tgt in PUBLIC_SERVICE_FILES:
            return "service", so, to
        return ("service-private" if to.private else "service"), so, to
    if to.kind in ("shared", "store", "read model"):
        return to.kind, so, to
    if to.kind == "orchestrator":
        return "host", so, to
    return "external", so, to


def owns_game_accessor(src: str, tgt: str) -> bool:
    """A `*/game.gd` import belongs to the accessor's own game-layer service."""
    owner = tgt.split("/")[0]
    if owner not in GAME_LAYER:
        return False
    return src.split("/")[0] == owner


def is_allowed(src: str, tgt: str) -> tuple[bool, str, Owner | None, Owner | None]:
    kind, so, to = edge_kind(src, tgt)
    # One game boundary: only a game-layer accessor preloads a base-game module; every other
    # module reads the game through a facade.
    if kind == "game" and src not in GAME_SOURCES:
        return False, kind, so, to
    if so is None or to is None:
        return True, kind, so, to
    if so.kind == "orchestrator":
        return True, kind, so, to
    # One accessor per service: shared code takes values, and no service reads another's game.gd.
    if tgt.endswith("/game.gd") and not owns_game_accessor(src, tgt):
        return False, kind, so, to

    # Anatomy is a presentation leaf: every file reads the world facade; only the facade asks
    # eligibility or another mod service, and outside files may preload only api.gd.
    if src.startswith("anatomy/"):
        if kind in ("self", "shared", "store", "read model"):
            return True, kind, so, to
        if kind == "service" and to is not None:
            if to.id in ("anatomy", "settings", "world"):
                return True, kind, so, to
            if to.id == "eligibility" and src == ANATOMY_FACADE:
                return True, kind, so, to
        return False, kind, so, to
    # Eligibility is a leaf: identity, shared data, the registry store and its scene boundary.
    # The dynamic rows and every other service edge belong to act_gate.
    if src.startswith("eligibility/"):
        if src == ELIGIBILITY_SCENE and kind == "service" and to is not None:
            return to.id == "world", kind, so, to
        if kind in ("self", "shared", "store", "read model"):
            return True, kind, so, to
        if kind == "service" and to is not None and to.id == "settings":
            return True, kind, so, to
        return False, kind, so, to
    # The dynamic gate reads the identity answer; it never reads anatomy or estrus.
    if so.id == "act_gate" and to is not None and to.id in ("anatomy", "estrus"):
        return False, kind, so, to
    if to is not None and to.id == "anatomy":
        return tgt == ANATOMY_FACADE, kind, so, to
    if so.kind == "shared":
        # A shared module takes its values as arguments: it reads no game accessor.
        if kind in ("shared", "store", "read model", "self"):
            return True, kind, so, to
        # A shared store may read settings; a pure/read-model module may not.
        if so.kind == "store" and to.id == "settings" and kind == "service":
            return True, kind, so, to
        return False, kind, so, to
    if so.kind == "store":
        # A store reads shared data and settings, and takes no game accessor.
        if kind in ("self", "shared", "store", "read model"):
            return True, kind, so, to
        if kind == "service" and to is not None and to.id == "settings":
            return True, kind, so, to
        return False, kind, so, to
    if so.kind == "service":
        if kind in ("self", "service", "shared", "store", "read model"):
            # The settings service must not depend upward on a domain service. The current
            # registry dependency is recorded as migration debt.
            if so.id == "settings" and to.kind == "service" and to.id != "settings":
                return False, "layer", so, to
            # The two game-layer services are peers: neither reads the other's facade.
            if so.id == "world" and to.id == "settings":
                return False, "layer", so, to
            return True, kind, so, to
        return False, kind, so, to
    return True, kind, so, to


def scan_reexports() -> list[dict[str, str]]:
    """Cross-module preload-const reach-throughs: ``ALIAS.CONST`` where CONST is a preload in ALIAS's target.

    Enums, nested classes and plain consts stay reachable; only a preload const is a re-export,
    and a re-export is either removed or carried by the exception ledger.
    """
    text_of: dict[str, str] = {}
    aliases: dict[str, dict[str, str]] = {}
    for path in shipped_sources():
        name = path.relative_to(ROOT).as_posix()
        text = _code_lines(read_text(str(path)))
        text_of[name] = text
        aliases[name] = {match.group(1): match.group(2) for match in PRELOAD_CONST.finditer(text)}
    found: dict[tuple[str, str, str], dict[str, str]] = {}
    for src, consts in aliases.items():
        for alias, target in consts.items():
            if not target.startswith("res://mods/unfplap/"):
                continue
            target = target.removeprefix("res://mods/unfplap/")
            for const, const_target in aliases.get(target, {}).items():
                if not re.search(r"(?<![\w.])%s\.%s\b" % (re.escape(alias), re.escape(const)),
                                 text_of[src]):
                    continue
                owner = owner_of(src)
                to = const_target.removeprefix("res://mods/unfplap/")
                found[(src, to, "re-export")] = {
                    "from": src,
                    "to": to,
                    "kind": "re-export",
                    "owner": owner.id if owner else "",
                    "reason": "separation of concerns; deferred",
                    "expires": "phase-2",
                }
    return [found[key] for key in sorted(found)]


def scan_violations() -> list[dict[str, str]]:
    found: dict[tuple[str, str, str], dict[str, str]] = {}
    for src, tgt in sorted(scan_edges()):
        ok, kind, so, to = is_allowed(src, tgt)
        if ok:
            continue
        row_kind = "game-import" if kind == "game" else kind
        row = {
            "from": src,
            "to": tgt,
            "kind": row_kind,
            "owner": so.id if so else "",
            "reason": "migration baseline; fix in the boundary-cleanup phase",
            "expires": "phase-2",
        }
        if row_kind == "game-import":
            row["reason"] = "base-game import; drain through the GAME accessor in Task B"
            row.pop("expires", None)
            row["task"] = "B"
        found[(src, tgt, row_kind)] = row
    for row in scan_reexports():
        found[exception_key(row)] = row
    return [found[key] for key in sorted(found)]


def exception_key(row: dict) -> tuple[str, str, str]:
    return (str(row.get("from", "")), str(row.get("to", "")), str(row.get("kind", "")))


def check_exceptions(failure: Failure, violations: list[dict[str, str]]) -> int:
    rows = load_json(EXCEPTIONS, {"exceptions": []}).get("exceptions", [])
    allowed = {exception_key(row) for row in rows}
    current = {exception_key(row) for row in violations}
    for key in sorted(allowed - current):
        failure.add("stale architecture exception: %s -> %s (%s)" % key)
    for key in sorted(current - allowed):
        failure.add("new architecture violation: %s -> %s (%s)" % key)
    return len(rows)


def graph() -> None:
    print("graph TD")
    for sid in SERVICES:
        print('  %s["%s"]' % (sid, sid))
    for src, tgt in sorted(scan_edges()):
        so = owner_of(src)
        to = owner_of(tgt)
        if so is None or to is None or so.kind != "service" or to.kind != "service":
            continue
        if so.id == to.id:
            continue
        print("  %s --> %s" % (so.id, to.id))


def write_exceptions() -> None:
    ARCH.mkdir(exist_ok=True)
    rows = scan_violations()
    EXCEPTIONS.write_text(json.dumps({"exceptions": rows}, indent=2) + "\n", encoding="utf-8")
    print("ARCH_EXCEPTIONS_WRITTEN entries=%d" % len(rows))
    for row in rows:
        print("  %s -> %s (%s)" % (row["from"], row["to"], row["kind"]))
