#!/usr/bin/env python3
"""Print the runtime files a release pack must contain.

The list combines the tracked runtime tree with the external resource pack's runtime manifest, so
a clean release commit, the fetched assets and the pack cannot drift. Every imported source maps
to its .import sidecar, and anything not listed is rejected by tools/pack.gd.

Usage: scripts/build_manifest.py [ROOT]
"""
import json
import pathlib
import subprocess
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import asset_pack

ALLOWED_SUFFIXES = {
    ".gd", ".gdshader", ".gdshaderinc", ".json", ".scn", ".tscn", ".tres", ".res",
    ".wav", ".ogg", ".mp3", ".png", ".jpg", ".jpeg", ".svg", ".ttf", ".otf",
}
CRITICAL = [
    "mod.json",
    "changelog.txt",
    "AUDIO_CREDITS.md",
]


def fail(why):
    raise SystemExit("BUILD_MANIFEST_FAIL " + why)


def runtime_source(path):
    if path in ("mod.json", "changelog.txt", "AUDIO_CREDITS.md"):
        return True
    parts = path.split("/")
    name = parts[-1]
    if name.startswith("."):
        return False
    if path.startswith(("assets/", "audio/", "poses/")):
        if "backups" in parts:
            return False
        return pathlib.PurePosixPath(path).suffix in ALLOWED_SUFFIXES
    return len(parts) == 1 and pathlib.PurePosixPath(path).suffix in ALLOWED_SUFFIXES


def main():
    root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else pathlib.Path.cwd())
    try:
        raw = subprocess.check_output(
            ["git", "-C", str(root), "ls-files", "-z"],
            stderr=subprocess.PIPE,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        message = error.stderr.decode("utf-8", "replace").strip() if isinstance(error, subprocess.CalledProcessError) else str(error)
        fail("git ls-files failed: " + message)
    tracked = {str(pathlib.PurePosixPath(p)) for p in raw.decode("utf-8", "replace").split("\0") if p}
    for path in CRITICAL:
        if path not in tracked:
            fail("critical runtime file is not tracked: " + path)

    try:
        contract = asset_pack.load_contract(root)
        resource_runtime = contract["runtime"]
        asset_pack.validate_runtime(root, resource_runtime)
        if not asset_pack.verify_runtime(root, contract, quiet=True):
            fail("resource runtime is missing, stale or has extra files; run scripts/fetch_assets.sh")
    except asset_pack.AssetError as error:
        fail(str(error))

    mod = json.loads((root / "mod.json").read_text(encoding="utf-8"))
    mod_id = str(mod.get("id", ""))
    entry = str(mod.get("entry", ""))
    prefix = "res://mods/%s/" % mod_id
    if not entry.startswith(prefix):
        fail("mod.json entry is not under " + prefix)
    entry_rel = entry[len(prefix):]
    if entry_rel not in tracked:
        fail("entry script is not tracked: " + entry_rel)

    expected = set()
    mapped_imports = set()
    for path in tracked:
        if not runtime_source(path):
            continue
        if path.endswith(".import"):
            continue
        sidecar = path + ".import"
        if sidecar in tracked:
            expected.add(sidecar)
            mapped_imports.add(sidecar)
        else:
            expected.add(path)

    for path in resource_runtime:
        if path.endswith(".import"):
            continue
        sidecar = path + ".import"
        if sidecar in resource_runtime:
            expected.add(sidecar)
        else:
            expected.add(path)

    for path in tracked:
        if not path.endswith(".import") or not path.startswith(("assets/", "audio/", "poses/")):
            continue
        source = path[:-len(".import")]
        if source not in tracked:
            fail("orphan import sidecar: " + path)
        if path not in mapped_imports:
            fail("import sidecar has no runtime source: " + path)

    print("\n".join(sorted(expected)))


if __name__ == "__main__":
    main()
