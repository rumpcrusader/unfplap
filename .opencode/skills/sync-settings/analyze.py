#!/usr/bin/env python3
"""Compare the local Unfplap profile with the shipped settings defaults.

The script is intentionally read-only unless one of the apply flags is passed. It prints a
human report and can write a JSON plan for the agent. `settings.gd` remains the only source of
shipped defaults; this tool only compares and prepares the promote/keep questions.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any

MISSING = object()
PLACEMENT_KEYS = ["offset_x", "offset_y", "offset_z", "pitch_deg", "scale"]
PREFERENCE_KEYS = ["intensity", "pattern", "touch", "dislikes", "talk", "warmth", "tolerance", "notes"]
CONSENT_KEYS = ["public", "anal", "oral"]
CHARACTER_SCALARS = ["smack_zone_radius", "aftercare_min", "cue_gap"]
PLACEMENT_RESERVED = {"default", "anon"}


def read_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        raise SystemExit(f"not a JSON object: {path}")
    return value


def write_json(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(data, handle, ensure_ascii=False, indent="\t")
        handle.write("\n")


def backup(path: Path) -> Path | None:
    if not path.exists():
        return None
    stamp = time.strftime("%Y%m%d-%H%M%S")
    target = path.with_name(f"{path.name}.sync-{stamp}.bak")
    index = 1
    while target.exists():
        index += 1
        target = path.with_name(f"{path.name}.sync-{stamp}-{index}.bak")
    shutil.copy2(path, target)
    return target


def get_path(data: Any, path: str) -> Any:
    node = data
    for part in path.split("."):
        if not isinstance(node, dict) or part not in node:
            return MISSING
        node = node[part]
    return node


def set_path(data: dict[str, Any], path: str, value: Any) -> None:
    parts = path.split(".")
    node = data
    for part in parts[:-1]:
        child = node.get(part)
        if not isinstance(child, dict):
            child = {}
            node[part] = child
        node = child
    node[parts[-1]] = value


def remove_path(data: dict[str, Any], path: str) -> bool:
    parts = path.split(".")
    node: Any = data
    stack: list[tuple[dict[str, Any], str]] = []
    for part in parts[:-1]:
        if not isinstance(node, dict) or part not in node:
            return False
        stack.append((node, part))
        node = node[part]
    if not isinstance(node, dict) or parts[-1] not in node:
        return False
    del node[parts[-1]]
    for parent, key in reversed(stack):
        child = parent.get(key)
        if isinstance(child, dict) and not child:
            del parent[key]
        else:
            break
    return True


def flatten(value: Any, prefix: str = "") -> list[tuple[str, Any]]:
    out: list[tuple[str, Any]] = []
    if isinstance(value, dict):
        for key, child in value.items():
            path = f"{prefix}.{key}" if prefix else str(key)
            out.extend(flatten(child, path))
    else:
        out.append((prefix, value))
    return out


def almost(a: Any, b: Any) -> bool:
    try:
        return abs(float(a) - float(b)) <= 1e-6
    except (TypeError, ValueError):
        return False


def color_key(value: Any) -> str | None:
    if not isinstance(value, str):
        return None
    text = value.strip().lstrip("#").lower()
    if not re.fullmatch(r"[0-9a-f]{6}([0-9a-f]{2})?", text):
        return None
    if len(text) == 6:
        text += "ff"
    return text


def equal_value(a: Any, b: Any, path: str = "") -> bool:
    if isinstance(a, bool) or isinstance(b, bool):
        return a is b or (isinstance(a, bool) and isinstance(b, bool) and a == b)
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        return almost(a, b)
    ca, cb = color_key(a), color_key(b)
    if ca is not None and cb is not None:
        return ca == cb
    if isinstance(a, list) and isinstance(b, list):
        set_paths = ("preferences.touch", "preferences.talk", "preferences.dislikes",
                     "caress.ignore", "presentation.standing.caress.ignore")
        is_set = any(path.endswith(suffix) for suffix in set_paths)
        if is_set:
            return sorted(str(x) for x in a) == sorted(str(x) for x in b)
        return len(a) == len(b) and all(equal_value(x, y, path) for x, y in zip(a, b))
    if isinstance(a, dict) and isinstance(b, dict):
        return set(a.keys()) == set(b.keys()) and all(
            equal_value(a[key], b[key], f"{path}.{key}" if path else key) for key in a
        )
    return a == b


def placement_sanitize(raw: Any, fallback: dict[str, Any]) -> dict[str, float]:
    out: dict[str, float] = {}
    for key in PLACEMENT_KEYS:
        value = fallback.get(key, 0.0)
        if isinstance(raw, dict) and key in raw:
            candidate = raw[key]
            if isinstance(candidate, (int, float)) and not isinstance(candidate, bool):
                value = float(candidate)
        out[key] = float(value)
    out["scale"] = max(0.05, out["scale"])
    return out


def placement_merge(base: dict[str, Any], over: Any) -> dict[str, float]:
    return placement_sanitize(over if isinstance(over, dict) else {}, placement_sanitize(base, {}))


def placement_same(a: dict[str, Any], b: dict[str, Any]) -> bool:
    return all(almost(a.get(key, 0.0), b.get(key, 0.0)) for key in PLACEMENT_KEYS)


def placement_diff(values: dict[str, Any], base: dict[str, Any]) -> dict[str, float]:
    return {
        key: float(values[key])
        for key in PLACEMENT_KEYS
        if not almost(values.get(key, 0.0), base.get(key, 0.0))
    }


def placement_key(values: dict[str, Any]) -> tuple[float, ...]:
    return tuple(round(float(values.get(key, 0.0)), 6) for key in PLACEMENT_KEYS)


def short(value: Any, limit: int = 120) -> str:
    text = json.dumps(value, ensure_ascii=False, sort_keys=True)
    return text if len(text) <= limit else text[: limit - 1] + "…"


def resolve_profile(settings_arg: str | None) -> Path:
    if settings_arg:
        return Path(settings_arg).expanduser().resolve()
    candidates: list[Path] = []
    xdg = os.environ.get("XDG_DATA_HOME")
    if xdg:
        candidates.append(Path(xdg) / "home-equestria-public/mods/data/unfplap/settings.json")
    candidates.append(Path.home() / ".local/share/home-equestria-public/mods/data/unfplap/settings.json")
    appdata = os.environ.get("APPDATA")
    if appdata:
        candidates.append(Path(appdata) / "home-equestria-public/mods/data/unfplap/settings.json")
    candidates.append(
        Path.home() / "Library/Application Support/home-equestria-public/mods/data/unfplap/settings.json"
    )
    for candidate in candidates:
        if candidate.exists():
            return candidate.resolve()
    raise SystemExit("settings.json not found; pass --settings PATH")


def project_root_default() -> Path:
    return Path(__file__).resolve().parents[5]


def xdg_root_for(settings_path: Path) -> Path | None:
    parts = settings_path.parts
    if len(parts) >= 5 and parts[-5:-1] == ("home-equestria-public", "mods", "data", "unfplap"):
        return settings_path.parents[4]
    if "home-equestria-public" in parts:
        index = parts.index("home-equestria-public")
        return Path(*parts[:index])
    return None


def game_running(project_root: Path) -> bool:
    proc = Path("/proc")
    if not proc.exists():
        return False
    root = str(project_root)
    for entry in proc.iterdir():
        if not entry.name.isdigit():
            continue
        try:
            raw = (entry / "cmdline").read_bytes().replace(b"\0", b" ").decode("utf-8", "replace")
        except OSError:
            continue
        if "godot" in raw.lower() and root in raw and "settings_migrate" not in raw \
                and "settings_snapshot" not in raw:
            return True
    return False


def run_snapshot(project_root: Path) -> dict[str, Any]:
    godot = shutil.which("godot")
    if not godot:
        raise SystemExit("godot not found on PATH")
    scratch_root = "/tmp/opencode" if Path("/tmp/opencode").is_dir() else None
    scratch = tempfile.mkdtemp(prefix="unfplap-settings-", dir=scratch_root)
    env = os.environ.copy()
    env["XDG_DATA_HOME"] = scratch
    command = [
        godot, "--headless", "--xr-mode", "off", "--path", str(project_root),
        "--script", "res://mods/unfplap/tools/settings_snapshot.gd",
    ]
    try:
        result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=120)
    finally:
        shutil.rmtree(scratch, ignore_errors=True)
    for line in reversed((result.stdout + "\n" + result.stderr).splitlines()):
        if line.startswith("SETTINGS_SNAPSHOT "):
            return json.loads(line[len("SETTINGS_SNAPSHOT "):])
    raise SystemExit("settings snapshot did not print SETTINGS_SNAPSHOT:\n" + result.stderr[-2000:])


def run_migration(project_root: Path, settings_path: Path, dry_run: bool) -> None:
    xdg_root = xdg_root_for(settings_path)
    if xdg_root is None:
        raise SystemExit(
            "automatic migration needs the standard home-equestria-public profile path; "
            "launch the game once instead"
        )
    godot = shutil.which("godot")
    if not godot:
        raise SystemExit("godot not found on PATH")
    if game_running(project_root):
        raise SystemExit("the game is running; close it before migration")
    profile_dir = settings_path.parent
    backups = []
    for name in ("settings.json", "anatomy_place.json", "anon_place.json"):
        result = backup(profile_dir / name)
        if result:
            backups.append(result)
    if dry_run:
        print("DRY RUN migration would use", xdg_root)
        return
    env = os.environ.copy()
    env["XDG_DATA_HOME"] = str(xdg_root)
    command = [
        godot, "--headless", "--xr-mode", "off", "--path", str(project_root),
        "--script", "res://mods/unfplap/tools/settings_migrate.gd",
    ]
    result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=120)
    if result.returncode != 0 or "SETTINGS_MIGRATED" not in result.stdout:
        raise SystemExit("settings migration failed:\n" + (result.stderr or result.stdout)[-2000:])
    for path in backups:
        print("backup", path)


def known_schema(snapshot: dict[str, Any]) -> tuple[set[str], set[str]]:
    defaults = snapshot.get("defaults", {})
    default_block = defaults.get("default", {})
    characters = defaults.get("characters", {})
    order = snapshot.get("order", list(characters))
    exact: set[str] = {"version"}
    for setting in snapshot.get("settings", []):
        exact.add(str(setting["path"]))
    for path, _ in flatten(default_block, "default"):
        exact.add(path)
    pose_keys: dict[str, set[str]] = {
        str(pose): set(values.keys()) for pose, values in default_block.get("poses", {}).items()
    }
    preference_keys = set(default_block.get("preferences", {}).keys()) | set(PREFERENCE_KEYS)
    act_keys = set(default_block.get("act_prompts", {}).keys())
    event_keys = set(default_block.get("event_prompts", {}).keys())
    for pony_id in order:
        base = f"characters.{pony_id}"
        for key in preference_keys:
            exact.add(f"{base}.preferences.{key}")
        for pose, keys in pose_keys.items():
            for key in keys:
                exact.add(f"{base}.poses.{pose}.{key}")
        for key in event_keys:
            exact.add(f"{base}.event_prompts.{key}")
        for key in act_keys:
            exact.add(f"{base}.act_prompts.{key}")
        for key in CONSENT_KEYS:
            exact.add(f"{base}.consent.{key}")
        for key in CHARACTER_SCALARS:
            exact.add(f"{base}.{key}")
    placement = defaults.get("anatomy", {}).get("placement", {})
    for key in PLACEMENT_KEYS:
        exact.add(f"anatomy.placement.default.{key}")
        exact.add(f"anatomy.placement.anon.{key}")
    for pony_id in set(order) | set(placement.keys()):
        if pony_id in PLACEMENT_RESERVED:
            continue
        for key in PLACEMENT_KEYS:
            exact.add(f"anatomy.placement.{pony_id}.{key}")
    prefixes = {"ui.sections"}
    return exact, prefixes


def is_known(path: str, exact: set[str], prefixes: set[str]) -> bool:
    if path in exact:
        return True
    return any(path == prefix or path.startswith(prefix + ".") for prefix in prefixes)


def source_line(mod_root: Path, path: str) -> str:
    source = mod_root / "settings.gd"
    try:
        lines = source.read_text(encoding="utf-8").splitlines()
    except OSError:
        return "settings.gd"
    needle = f'"{path}"'
    for index, line in enumerate(lines, 1):
        if needle in line:
            return f"settings.gd:{index}"
    return "settings.gd"


def source_hint(mod_root: Path, kind: str, path: str) -> str:
    if kind == "setting":
        return source_line(mod_root, path)
    if kind == "default":
        rest = path[len("default."):]
        if rest.startswith("preferences."):
            return "preferences.gd DEFAULTS." + rest.split(".", 1)[1]
        if rest.startswith("act_prompts."):
            return "settings.gd DEFAULT_ACT_PROMPTS." + rest.split(".", 1)[1]
        if rest.startswith("poses."):
            return "poses/catalog.gd POSE_DEFAULTS." + rest[len("poses."):]
        return "settings.gd DEFAULT_TEMPLATE." + rest
    if kind == "character":
        return "character_preferences.gd TEMPLATES." + path[len("characters."):]
    if kind in ("placement_global", "placement_anon"):
        return "settings.gd anatomy.placement." + ("default.*" if kind == "placement_global" else "anon.*")
    if kind == "placement_group":
        return "anatomy_placement.gd MARE_DEFAULTS"
    return ""


def expected_character(snapshot: dict[str, Any], pony_id: str, path: str) -> Any:
    defaults = snapshot.get("defaults", {})
    default_block = defaults.get("default", {})
    entry = defaults.get("characters", {}).get(pony_id, {})
    parts = path.split(".")
    rest = parts[2:]
    if not rest:
        return MISSING
    section = rest[0]
    if section == "preferences":
        key = rest[1] if len(rest) > 1 else ""
        return entry.get("preferences", {}).get(key, default_block.get("preferences", {}).get(key, MISSING))
    if section == "poses" and len(rest) >= 3:
        pose, key = rest[1], rest[2]
        value = entry.get("poses", {}).get(pose, {})
        if isinstance(value, dict) and key in value:
            return value[key]
        return default_block.get("poses", {}).get(pose, {}).get(key, MISSING)
    if section == "event_prompts":
        key = rest[1] if len(rest) > 1 else ""
        return entry.get("event_prompts", {}).get(key, "")
    if section == "act_prompts":
        key = rest[1] if len(rest) > 1 else ""
        return entry.get("act_prompts", {}).get(
            key, default_block.get("act_prompts", {}).get(key, MISSING)
        )
    if section == "consent":
        key = rest[1] if len(rest) > 1 else ""
        return entry.get("consent", {}).get(
            key, snapshot.get("consent", {}).get(pony_id, {}).get(key, False)
        )
    if len(rest) == 1 and section in CHARACTER_SCALARS:
        return entry.get(section, default_block.get(section, MISSING))
    return MISSING


def analyse(
    snapshot: dict[str, Any],
    player: dict[str, Any],
    never: set[str],
    mod_root: Path,
    order: list[str],
) -> dict[str, Any]:
    exact, prefixes = known_schema(snapshot)
    defaults = snapshot.get("defaults", {})
    default_block = defaults.get("default", {})
    characters = defaults.get("characters", {})
    placement_defaults = defaults.get("anatomy", {}).get("placement", {})

    # Dead keys: unknown leaves in the player. A dead key that also exists in the shipped
    # templates is a source dead key; removing it from the player would only make it return on
    # the next load, so report it separately.
    source_exact, _ = known_schema(snapshot)
    source_dead = [path for path, _ in flatten(defaults) if not is_known(path, source_exact, set())]
    source_dead_set = set(source_dead)
    dead: list[str] = []
    for path, _ in flatten(player):
        if is_known(path, exact, prefixes):
            continue
        if path in source_dead_set:
            continue
        dead.append(path)

    diffs: list[dict[str, Any]] = []

    # Declared global settings.
    for setting in snapshot.get("settings", []):
        path = str(setting["path"])
        if path in never:
            continue
        player_value = get_path(player, path)
        if player_value is MISSING:
            continue
        shipped = setting.get("default", MISSING)
        if shipped is MISSING or equal_value(player_value, shipped, path):
            continue
        diffs.append({
            "kind": "setting",
            "path": path,
            "label": str(setting.get("label", path)),
            "player": player_value,
            "shipped": shipped,
            "source": source_hint(mod_root, "setting", path),
        })

    # Default profile block.
    for path, shipped in flatten(default_block, "default"):
        player_value = get_path(player, path)
        if player_value is MISSING or equal_value(player_value, shipped, path):
            continue
        diffs.append({
            "kind": "default",
            "path": path,
            "label": path,
            "player": player_value,
            "shipped": shipped,
            "source": source_hint(mod_root, "default", path),
        })

    # Per-character profiles.
    player_characters = player.get("characters", {})
    if isinstance(player_characters, dict):
        for pony_id in order:
            entry = player_characters.get(pony_id)
            if not isinstance(entry, dict):
                continue
            for leaf, player_value in flatten(entry, f"characters.{pony_id}"):
                if not is_known(leaf, exact, prefixes):
                    continue
                shipped = expected_character(snapshot, pony_id, leaf)
                if shipped is MISSING or equal_value(player_value, shipped, leaf):
                    continue
                diffs.append({
                    "kind": "character",
                    "path": leaf,
                    "label": leaf,
                    "player": player_value,
                    "shipped": shipped,
                    "source": source_hint(mod_root, "character", leaf),
                })

    # Placement. The global default and anon blocks are five-value units.
    player_placement = get_path(player, "anatomy.placement")
    if not isinstance(player_placement, dict):
        player_placement = {}
    player_default = player_placement.get("default")
    shipped_default = placement_defaults.get("default", {})
    if isinstance(player_default, dict):
        resolved_default = placement_merge(shipped_default, player_default)
        if not placement_same(resolved_default, shipped_default):
            diffs.append({
                "kind": "placement_global",
                "path": "anatomy.placement.default",
                "label": "Default placement",
                "player": resolved_default,
                "shipped": placement_sanitize(shipped_default, {}),
                "source": source_hint(mod_root, "placement_global", ""),
            })
    else:
        resolved_default = placement_sanitize(shipped_default, {})

    player_anon = player_placement.get("anon")
    shipped_anon = placement_defaults.get("anon", {})
    if isinstance(player_anon, dict):
        resolved_anon = placement_merge(shipped_anon, player_anon)
        if not placement_same(resolved_anon, shipped_anon):
            diffs.append({
                "kind": "placement_anon",
                "path": "anatomy.placement.anon",
                "label": "Anon placement",
                "player": resolved_anon,
                "shipped": placement_sanitize(shipped_anon, {}),
                "source": source_hint(mod_root, "placement_anon", ""),
            })

    groups: dict[tuple[float, ...], dict[str, Any]] = {}
    redundant: list[str] = []
    for pony_id, row in player_placement.items():
        if pony_id in PLACEMENT_RESERVED or not isinstance(row, dict):
            continue
        if pony_id not in order:
            continue
        shipped = placement_merge(resolved_default, placement_defaults.get(pony_id, {}))
        resolved = placement_merge(shipped, row)
        if placement_same(resolved, shipped):
            redundant.append(pony_id)
            continue
        key = placement_key(resolved)
        group = groups.setdefault(key, {"values": resolved, "ids": []})
        group["ids"].append(pony_id)

    ordered_groups = sorted(groups.values(), key=lambda group: (-len(group["ids"]), group["ids"][0]))
    placement_groups = []
    global_values = resolved_default
    if ordered_groups and len(ordered_groups[0]["ids"]) >= 3:
        global_values = ordered_groups[0]["values"]
    for index, group in enumerate(ordered_groups):
        ids = group["ids"]
        target = "global" if index == 0 and len(ids) >= 3 else "mare"
        placement_groups.append({
            "kind": "placement_group",
            "path": "anatomy.placement",
            "label": "Placement group",
            "ids": ids,
            "count": len(ids),
            "player": group["values"],
            "shipped": placement_sanitize(shipped_default, {}),
            "target": target,
            # `diff` is what MARE_DEFAULTS needs after the global group (when present) is promoted.
            "diff": placement_diff(group["values"], global_values),
            "diff_vs_live": placement_diff(group["values"], resolved_default),
            "source": source_hint(mod_root, "placement_group", ""),
        })

    return {
        "diffs": diffs,
        "dead": dead,
        "source_dead": source_dead,
        "redundant": redundant,
        "placement_groups": placement_groups,
        "never": sorted(never),
    }


def report(
    settings_path: Path,
    snapshot: dict[str, Any],
    player_version: int,
    result: dict[str, Any],
) -> None:
    print(f"profile: {settings_path}")
    print(f"schema: player {player_version}, shipped {snapshot.get('schema')}")
    print("never synced: " + ", ".join(result["never"]))
    if result["dead"]:
        print(f"dead keys removed: {len(result['dead'])}")
        for path in result["dead"]:
            print("  - " + path)
    else:
        print("dead keys removed: none")
    if result["redundant"]:
        print(f"redundant placement overrides removed: {len(result['redundant'])}")
        print("  " + ", ".join(result["redundant"][:20]) + (" …" if len(result["redundant"]) > 20 else ""))
    if result["source_dead"]:
        print(f"source dead keys (fix in templates, not player): {len(result['source_dead'])}")
        for path in result["source_dead"][:12]:
            print("  - " + path)
        if len(result["source_dead"]) > 12:
            print("  …")
    print(f"differences: {len(result['diffs'])}")
    for index, item in enumerate(result["diffs"], 1):
        print(f"  {index}. [{item['kind']}] {item['path']}")
        print(f"     player: {short(item['player'])}")
        print(f"     shipped: {short(item['shipped'])}")
        print(f"     source: {item['source']}")
    print(f"placement groups: {len(result['placement_groups'])}")
    for index, group in enumerate(result["placement_groups"], 1):
        target = "GLOBAL DEFAULT" if group["target"] == "global" else "PER-MARE DEFAULTS"
        ids = ", ".join(group["ids"][:8])
        if group["count"] > 8:
            ids += " …"
        print(f"  {index}. {target}: {group['count']} mares ({ids})")
        print(f"     values: {short(group['player'])}")
        print(f"     diff vs live global: {short(group['diff_vs_live'])}")
        if group["target"] == "mare" and group["diff"] != group["diff_vs_live"]:
            print(f"     diff after a global promotion: {short(group['diff'])}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", default=str(project_root_default()))
    parser.add_argument("--settings", default=None)
    parser.add_argument("--snapshot", default=None, help="snapshot JSON; run Godot when omitted")
    parser.add_argument("--never", default=str(Path(__file__).with_name("never_sync.json")))
    parser.add_argument("--json-out", default=None)
    parser.add_argument("--migrate", action="store_true", help="run the settings migration first")
    parser.add_argument("--apply-dead", action="store_true", help="remove dead player keys")
    parser.add_argument("--prune-redundant", action="store_true", help="remove redundant placement rows")
    parser.add_argument("--set-placement-default", default=None, help="JSON values for the global default")
    parser.add_argument("--drop-placement-ids", default=None, help="comma-separated mare ids")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    project_root = Path(args.project_root).expanduser().resolve()
    settings_path = resolve_profile(args.settings)
    mod_root = project_root / "mods/unfplap"
    if args.migrate:
        run_migration(project_root, settings_path, args.dry_run)

    if args.snapshot:
        snapshot = read_json(Path(args.snapshot).expanduser())
    else:
        snapshot = run_snapshot(project_root)

    player = read_json(settings_path)
    player_version = int(player.get("version", 0))
    never_data = read_json(Path(args.never).expanduser())
    never = set(str(path) for path in never_data.get("paths", []))
    order = [str(pony_id) for pony_id in snapshot.get("order", [])]
    dirty = False
    backups: list[Path] = []

    if (args.set_placement_default or args.drop_placement_ids) and not args.dry_run:
        if game_running(project_root):
            raise SystemExit("the game is running; close it before writing the profile")
        placement = player.setdefault("anatomy", {}).setdefault("placement", {})
        if not isinstance(placement, dict):
            placement = {}
            player["anatomy"]["placement"] = placement
        if args.set_placement_default:
            values = json.loads(args.set_placement_default)
            placement["default"] = placement_sanitize(values, placement.get("default", {}))
            dirty = True
        if args.drop_placement_ids:
            for pony_id in [part.strip() for part in args.drop_placement_ids.split(",") if part.strip()]:
                placement.pop(pony_id, None)
            dirty = True
        if dirty:
            result = backup(settings_path)
            if result:
                backups.append(result)

    result = analyse(snapshot, player, never, mod_root, order)
    dead_removed = list(result["dead"]) if args.apply_dead else []

    if args.apply_dead and result["dead"] and not args.dry_run:
        if game_running(project_root):
            raise SystemExit("the game is running; close it before writing the profile")
        for path in result["dead"]:
            remove_path(player, path)
        dirty = True

    # Re-run after removals so the report and the groups use the player the agent will see.
    if dirty:
        result = analyse(snapshot, player, never, mod_root, order)
    redundant_removed = list(result["redundant"]) if args.prune_redundant else []
    if args.prune_redundant and result["redundant"] and not args.dry_run:
        for pony_id in result["redundant"]:
            remove_path(player, f"anatomy.placement.{pony_id}")
        result = analyse(snapshot, player, never, mod_root, order)
        dirty = True
    if dead_removed:
        result["dead"] = dead_removed
    if redundant_removed:
        result["redundant"] = redundant_removed

    if dirty and not args.dry_run:
        # A set/drop action already backed up; use the same backup list.
        if not backups:
            result_backup = backup(settings_path)
            if result_backup:
                backups.append(result_backup)
        write_json(settings_path, player)
        for path in backups:
            print("backup", path)

    report(settings_path, snapshot, player_version, result)
    if args.dry_run:
        print("dry run: no files written")
    if backups:
        print("backups:")
        for path in backups:
            print("  " + str(path))

    if args.json_out:
        payload = {
            "profile": str(settings_path),
            "schema": {"player": player_version, "shipped": snapshot.get("schema")},
            "never": result["never"],
            "dead": result["dead"],
            "source_dead": result["source_dead"],
            "redundant": result["redundant"],
            "diffs": result["diffs"],
            "placement_groups": result["placement_groups"],
            "dry_run": args.dry_run,
        }
        write_json(Path(args.json_out).expanduser(), payload)
        print("plan", args.json_out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
