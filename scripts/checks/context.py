"""The one tree walk and identity table the checks share.

Every check reads files and asks who owns a path through this module, so a run walks the tree once
and caches each read, owner and facade lookup.
"""
from __future__ import annotations

import json
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
DOCS = ROOT / "docs"
ARCH = ROOT / "architecture"
EXCEPTIONS = ARCH / "exceptions.json"
TYPING_DEBT = ARCH / "typing_debt.json"
DUCK_TYPING = ARCH / "duck_typing.json"
TESTS = ROOT / "tests"

SOURCE_SKIP_DIRS = {
    ".git", "dist", "assets", "sources", "tests", "tools", "scripts", "docs", ".godot",
}
# Every `.gd` in the repository: only the generated and fetched trees are not source.
ALL_SOURCE_SKIP_DIRS = {".git", ".godot", "dist", "assets", "sources"}

# A service facade is `api.gd` when present, otherwise the legacy `service.gd`. The preference is
# explicit so a non-facade `api.gd` is never mistaken for a service entry point.
FACADE_NAMES = ("api.gd", "service.gd")
# A store holds a resolved document another service reads directly, with no scene work of its own.
STORE_SERVICES = {"registry"}
ORCHESTRATORS = {"main.gd", "runtime.gd", "api.gd"}
SHARED_KINDS = {
    "act_history.gd": "store",
    "act_facts.gd": "read model",
}


@dataclass(frozen=True)
class Owner:
    id: str
    path: str
    private: bool
    kind: str


@lru_cache(maxsize=None)
def read_text(path: str) -> str:
    return Path(path).read_text(encoding="utf-8")


def load_json(path: Path, default):
    if not path.exists():
        return default
    return json.loads(path.read_text(encoding="utf-8"))


@lru_cache(maxsize=None)
def facade_for(sid: str) -> str:
    for name in FACADE_NAMES:
        if (ROOT / sid / name).is_file():
            return name
    return "service.gd"


def service_ids() -> list[str]:
    found: set[str] = set()
    for name in FACADE_NAMES:
        found.update(
            p.parent.name
            for p in ROOT.glob(f"*/{name}")
            if not p.parent.name.startswith(".") and p.parent.name != "shared"
        )
    return sorted(found)


SERVICES = service_ids()


@lru_cache(maxsize=None)
def owner_of(path: str) -> Owner | None:
    path = path.strip().lstrip("./")
    if path in ORCHESTRATORS:
        return Owner(path[:-3], path, False, "orchestrator")
    # The act modules are the runtime's own files: they may preload services, and a service that
    # preloads them is a host import, not a service edge.
    if path.startswith("act/"):
        return Owner("runtime", path, False, "orchestrator")
    if path.startswith("shared/"):
        name = path.split("/")[-1]
        kind = SHARED_KINDS.get(name, "shared")
        return Owner("shared:" + name, path, False, kind)
    for sid in SERVICES:
        if path == f"{sid}/{facade_for(sid)}":
            kind = "store" if sid in STORE_SERVICES else "service"
            return Owner(sid, path, False, kind)
        if path.startswith(f"{sid}/"):
            return Owner(sid, path, True, "service")
    return None


@lru_cache(maxsize=1)
def _shipped_sources() -> tuple[Path, ...]:
    return tuple(sorted(
        path for path in ROOT.rglob("*.gd")
        if not (set(path.relative_to(ROOT).parts) & SOURCE_SKIP_DIRS)
    ))


def shipped_sources() -> list[Path]:
    return list(_shipped_sources())


@lru_cache(maxsize=1)
def _all_sources() -> tuple[Path, ...]:
    return tuple(sorted(
        path for path in ROOT.rglob("*.gd")
        if not (set(path.relative_to(ROOT).parts) & ALL_SOURCE_SKIP_DIRS)
    ))


def all_sources() -> list[Path]:
    return list(_all_sources())
