"""The one tree walk and identity table the checks share.

Every check reads files and asks who owns a path through this module, so a run walks the tree once
and caches each read, owner and facade lookup.
"""
from __future__ import annotations

import json
import re
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

# A service facade carries one name, `api.gd`, so an entry point is never ambiguous. The base class
# under `shared/` is not a facade and keeps its own name.
FACADE_NAMES = ("api.gd",)
# A store holds a resolved document another service reads directly, with no scene work of its own.
STORE_SERVICES = {"registry"}
ORCHESTRATORS = {"main.gd", "runtime.gd", "api.gd"}
# The two Other trees, owned by the runtime without being the runtime itself: the act modules and
# the VR act handle.
RUNTIME_MODULES = ("act/", "vr/")
SHARED_KINDS = {
    "act_history.gd": "store",
    "act_facts.gd": "read model",
}

# The one World facade that is not a Node: the static scene read surface. The header cannot say
# so, because staticness is a shape of the module, not a value a facade declares.
WORLD_STATIC = "world/api.gd"
# The two modules whose frozen header is their contract. They are the only non-facades allowed a
# declaration; editing either needs the user's explicit approval.
FROZEN_HEADERS = ("shared/log.gd", "shared/perf.gd")
# The three facade scopes. `Other` is derived from the path, never declared.
SCOPES = ("process", "world", "pony")
DECLARATION_FIELDS = ("Scope",)
# The removed fields: still a declaration when they survive, on a facade or elsewhere.
LEGACY_DECLARATION_FIELDS = ("Import", "Static")
DECLARATION = re.compile(r"^##\s+([A-Z][A-Za-z]*):\s*(.*?)\s*$", re.MULTILINE)
EXTENDS = re.compile(r"^extends\b.*$", re.MULTILINE)


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
    return "api.gd"


def declaration_block(text: str) -> str:
    """The contiguous `##` run directly under the file's `extends` line."""
    match = EXTENDS.search(text)
    if not match:
        return ""
    block: list[str] = []
    for line in text[match.end():].lstrip("\n").splitlines():
        if line.startswith("##"):
            block.append(line)
            continue
        break
    return "\n".join(block)


def declaration_of(text: str) -> dict[str, str]:
    """The declaration fields under `extends`, keyed by field name.

    A purpose sentence with a longer lead-in stays prose; only a single capitalized word before
    the colon is a declaration field, so `## The face owner: ...` is not one.
    """
    return {
        match.group(1): match.group(2)
        for match in DECLARATION.finditer(declaration_block(text))
    }


@lru_cache(maxsize=None)
def facade_scope(sid: str) -> str:
    path = ROOT / sid / facade_for(sid)
    if not path.is_file():
        return ""
    return declaration_of(read_text(str(path))).get("Scope", "")


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
    # The act modules are the runtime's own files and the VR act handle is the session's Other
    # module: they may preload services, and a service that preloads one is a host import, not an
    # edge.
    if path.startswith(RUNTIME_MODULES):
        return Owner("runtime", path, False, "other")
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
