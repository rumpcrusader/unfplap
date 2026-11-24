"""Typing debt, the weak-signature scan and the string-dispatch baseline."""
from __future__ import annotations

import json
import re
from pathlib import Path

from .context import (
    ARCH,
    DUCK_TYPING,
    ROOT,
    SERVICES,
    TYPING_DEBT,
    facade_for,
    load_json,
    owner_of,
    read_text,
    shipped_sources,
)
from .failure import Failure, rel

# A public accessor module outside a facade joins the weak-signature scan.
TYPING_EXTRA = ("world/game.gd", "settings/game.gd", "debug/game.gd", "hud/game.gd")

DUCK_CALL = re.compile(r'\.call\("[A-Za-z_]')
DUCK_SET = re.compile(r'\.set\("')
# The per-pony handles are read through `runtime.get("...")`; a new site is a locator a typed
# accessor should replace.
DUCK_GET = re.compile(r'\b(?:runtime|main)\.get\("')


def file_public_functions(service: str, path: Path) -> list[dict[str, str]]:
    if not path.exists():
        return []
    lines = path.read_text(encoding="utf-8").splitlines()
    out: list[dict[str, str]] = []
    i = 0
    while i < len(lines):
        line = lines[i]
        m = re.match(r"^(static )?func ([A-Za-z0-9_]+)\(", line)
        if not m or m.group(2).startswith("_"):
            i += 1
            continue
        name = m.group(2)
        signature = line.rstrip()
        while not signature.rstrip().endswith(":") and i + 1 < len(lines):
            i += 1
            signature += " " + lines[i].strip()
        out.append({"service": service, "func": name, "signature": signature.strip()})
        i += 1
    return out


def public_functions(service: str) -> list[dict[str, str]]:
    return file_public_functions(service, ROOT / service / facade_for(service))


def weak_signature(signature: str) -> bool:
    m = re.search(r"func\s+[A-Za-z0-9_]+\((.*?)\)\s*(?:->\s*([^:]+))?:", signature)
    if not m:
        return True
    params, ret = m.group(1), (m.group(2) or "").strip()
    if not ret:
        return True
    if ret.split("[")[0] in ("Variant", "Dictionary", "Callable"):
        return True
    if ret == "Array":
        return True
    for param in params.split(","):
        param = param.strip()
        if not param:
            continue
        if ":" not in param:
            return True
        typ = param.split(":", 1)[1].strip().split("=")[0].strip()
        if typ.split("[")[0] in ("Variant", "Dictionary", "Callable"):
            return True
        if typ == "Array":
            return True
    return False


def typing_debt() -> list[dict[str, str]]:
    debt = []
    for sid in SERVICES:
        for row in public_functions(sid):
            if weak_signature(row["signature"]):
                debt.append(row)
    for name in TYPING_EXTRA:
        owner = owner_of(name)
        label = owner.id if owner is not None else name
        for row in file_public_functions(label, ROOT / name):
            if weak_signature(row["signature"]):
                debt.append(row)
    return sorted(debt, key=lambda r: (r["service"], r["func"]))


def write_debt() -> None:
    ARCH.mkdir(exist_ok=True)
    TYPING_DEBT.write_text(json.dumps({"debt": typing_debt()}, indent=2) + "\n", encoding="utf-8")
    print("ARCH_TYPING_DEBT_WRITTEN entries=%d" % len(typing_debt()))


def check_typing(failure: Failure) -> int:
    saved = load_json(TYPING_DEBT, {"debt": []}).get("debt", [])
    saved_keys = {(r["service"], r["func"], r["signature"]) for r in saved}
    current = typing_debt()
    current_keys = {(r["service"], r["func"], r["signature"]) for r in current}
    for key in sorted(current_keys - saved_keys):
        failure.add("new weak public signature: %s.%s" % (key[0], key[1]))
    for key in sorted(saved_keys - current_keys):
        failure.add("stale typing debt (remove it): %s.%s" % (key[0], key[1]))
    return 0


def duck_sites(text: str) -> int:
    """Non-comment lines that dispatch by string: `.call("`, `.set("` or a runtime `.get("`."""
    return sum(
        1 for line in text.splitlines()
        if not line.lstrip().startswith("#")
        and (DUCK_CALL.search(line) or DUCK_SET.search(line) or DUCK_GET.search(line))
    )


def duck_config() -> dict:
    return load_json(DUCK_TYPING, {"allowed": [], "baseline": []})


def duck_typing() -> list[dict[str, object]]:
    """The current string-dispatch count per shipped file, with the accessors left out."""
    allowed = {str(name) for name in duck_config().get("allowed", [])}
    rows: list[dict[str, object]] = []
    for path in shipped_sources():
        name = rel(path)
        if name in allowed:
            continue
        count = duck_sites(read_text(str(path)))
        if count:
            rows.append({"file": name, "count": count})
    rows.sort(key=lambda row: str(row["file"]))
    return rows


def check_duck_typing(failure: Failure) -> None:
    """String dispatch may only shrink outside the allowlisted accessor modules.

    A new file, a grown file and a stale baseline row all fail, so a reflection site is either
    removed, moved into an accessor, or added on purpose with a fresh baseline.
    """
    config = duck_config()
    allowed = {str(name) for name in config.get("allowed", [])}
    baseline = {
        str(row.get("file", "")): int(row.get("count", 0))
        for row in config.get("baseline", [])
    }
    current = {str(row["file"]): int(row["count"]) for row in duck_typing()}
    for name in sorted(current):
        if name not in baseline:
            failure.add("%s has new string dispatch (%d sites): use a typed accessor or add a "
                        "baseline row" % (name, current[name]))
        elif current[name] > baseline[name]:
            failure.add("%s grew its string dispatch (%d sites, baseline %d)" % (
                name, current[name], baseline[name]))
    for name in sorted(baseline):
        if name in allowed:
            failure.add("duck-typing baseline row for an allowlisted accessor: %s" % name)
        elif name not in current:
            failure.add("stale duck-typing baseline row (remove it): %s" % name)


def write_duck_typing() -> None:
    ARCH.mkdir(exist_ok=True)
    config = duck_config()
    rows = duck_typing()
    payload = {
        "allowed": list(config.get("allowed", [])),
        "baseline": rows,
    }
    DUCK_TYPING.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print("ARCH_DUCK_TYPING_WRITTEN files=%d sites=%d allowed=%d" % (
        len(rows), sum(int(row["count"]) for row in rows), len(payload["allowed"])))
