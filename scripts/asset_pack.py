#!/usr/bin/env python3
"""Build, verify and fetch the external runtime asset pack.

The mod's audio and anatomy files are not tracked. They live in one zip on pone.rs. The archive
has two trees:

    runtime/    extracted into assets/ and packed into the mod .pck
    sources/    editable originals, never packed

`scripts/pack_assets.sh` builds and uploads the archive and writes the committed contract
`scripts/asset_pack.json`. `scripts/fetch_assets.sh` downloads the archive, verifies it against
that contract and extracts the runtime tree into its ignored working paths. `build.sh` calls
`verify` and refuses a missing or stale set.

Usage:
    scripts/asset_pack.py verify [--root DIR]
    scripts/asset_pack.py pack [--root DIR] [--out FILE] [--upload]
    scripts/asset_pack.py fetch [--root DIR] [--sources] [--force]
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile

SCHEMA = 1
CONTRACT_PATH = "scripts/asset_pack.json"
UPLOAD_ENDPOINT = "https://pone.rs/upload"
ARCHIVE_PATTERN = re.compile(r"^https://u\.pone\.rs/[a-z0-9]+\.zip$")
SHA_PATTERN = re.compile(r"^[0-9a-f]{64}$")

CRITICAL_RUNTIME = [
    "assets/anatomy/mare/mare_bits_v2.scn",
    "assets/anatomy/mare/teats.scn",
    "assets/anatomy/mare/skin_bridge.scn",
    "assets/anatomy/anon/anon_part.scn",
    "assets/anatomy/anon/anon_part_albedo.png",
    "assets/anatomy/anon/anon_part_ao.png",
    "assets/anatomy/anon/anon_part_nrm.png",
]
RUNTIME_SUFFIXES = {
    ".scn", ".tscn", ".res", ".tres", ".png", ".jpg", ".jpeg", ".webp", ".svg",
    ".wav", ".ogg", ".mp3", ".import",
}
IMPORTED_SUFFIXES = {".png", ".jpg", ".jpeg", ".webp", ".svg", ".wav", ".ogg", ".mp3"}
JUNK_SUFFIXES = (".blend1", ".tmp", ".bak", ".orig")
JUNK_NAMES = {".DS_Store", "Thumbs.db"}
## Source trees never scanned for `assets/` literals: build output, VCS and the unpacked originals.
SCAN_SKIP = {".git", ".godot", "dist", "build", "sources", "__pycache__"}


class AssetError(Exception):
    pass


def fail(why: str) -> None:
    raise AssetError(why)


def repo_root(path: str | os.PathLike[str] | None = None) -> pathlib.Path:
    if path is not None:
        return pathlib.Path(path).resolve()
    return pathlib.Path(__file__).resolve().parent.parent


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def entry_for(path: pathlib.Path, base: pathlib.Path) -> dict:
    rel = path.relative_to(base).as_posix()
    return {"size": path.stat().st_size, "sha256": sha256_file(path)}


def _walk(base: pathlib.Path):
    if not base.is_dir():
        return
    for path in sorted(base.rglob("*")):
        if path.is_file() and not path.is_symlink():
            yield path


def _is_junk(path: pathlib.Path) -> bool:
    name = path.name
    if name in JUNK_NAMES or name.startswith(".") or name.endswith("~"):
        return True
    return name.endswith(JUNK_SUFFIXES)


def collect_runtime(root: pathlib.Path) -> dict:
    """Return the repository-relative runtime files with their hashes."""
    files: dict[str, dict] = {}
    for path in _walk(root / "assets"):
        if _is_junk(path):
            continue
        if path.suffix.lower() not in RUNTIME_SUFFIXES:
            continue
        rel = path.relative_to(root).as_posix()
        files[rel] = entry_for(path, root)

    _check_import_pairs(files)
    return dict(sorted(files.items()))


def _check_import_pairs(files: dict) -> None:
    for rel in files:
        source = rel[:-len(".import")] if rel.endswith(".import") else rel
        suffix = pathlib.PurePosixPath(source).suffix.lower()
        if rel.endswith(".import"):
            if source not in files:
                fail("orphan import sidecar: " + rel)
            if suffix not in IMPORTED_SUFFIXES:
                fail("unexpected import sidecar: " + rel)
            continue
        if suffix in IMPORTED_SUFFIXES and source + ".import" not in files:
            fail("missing import sidecar: " + rel)


def collect_sources(root: pathlib.Path) -> dict:
    base = root / "sources"
    files: dict[str, dict] = {}
    for path in _walk(base):
        if _is_junk(path) or "work" in path.relative_to(base).parts:
            continue
        files[path.relative_to(base).as_posix()] = entry_for(path, base)
    if not files:
        fail(
            "sources/ is empty; put the V2 Blender source in "
            "sources/anatomy/mare_bits_v2.blend"
        )
    if "anatomy/mare_bits_v2.blend" not in files:
        fail("sources/anatomy/mare_bits_v2.blend is missing")
    return dict(sorted(files.items()))


def _check_catalogue_refs(root: pathlib.Path, runtime: dict) -> None:
    """Every `assets/` literal in a script must name a runtime file.

    A directory prefix (a trailing slash) is skipped, and so is a path built by concatenation:
    those are not literals. The anatomy tests that load the meshes cover the concatenated ones.
    """
    pattern = re.compile(r'res://mods/unfplap/(assets/[A-Za-z0-9_./-]+)')
    for path in _scripts(root):
        text = path.read_text(encoding="utf-8")
        for match in pattern.finditer(text):
            rel = match.group(1)
            if rel.endswith("/"):
                continue
            if rel not in runtime:
                fail(f"{path.relative_to(root)} references an unlisted asset: {rel}")


def _scripts(root: pathlib.Path):
    """Yield every project script, skipping build output, VCS and the unpacked originals."""
    for child in sorted(root.iterdir()):
        if child.is_dir():
            if child.name in SCAN_SKIP:
                continue
            for path in _walk(child):
                if path.suffix == ".gd":
                    yield path
        elif child.suffix == ".gd":
            yield child


def validate_runtime(root: pathlib.Path, runtime: dict) -> None:
    for rel in CRITICAL_RUNTIME:
        if rel not in runtime:
            fail("missing critical runtime asset: " + rel)
    _check_catalogue_refs(root, runtime)


def _check_table(name: str, table: dict) -> None:
    for rel, meta in table.items():
        if not isinstance(rel, str) or not rel:
            fail(f"{CONTRACT_PATH} has an invalid {name} path")
        pure = pathlib.PurePosixPath(rel)
        if pure.is_absolute() or ".." in pure.parts:
            fail(f"{CONTRACT_PATH} has an unsafe {name} path: {rel}")
        if not isinstance(meta, dict):
            fail(f"{CONTRACT_PATH} has no hash entry for {name}/{rel}")
        try:
            size = int(meta.get("size", -1))
        except (TypeError, ValueError):
            size = -1
        if size < 0 or not SHA_PATTERN.fullmatch(str(meta.get("sha256", ""))):
            fail(f"{CONTRACT_PATH} has a bad hash entry for {name}/{rel}")


def validate_archive(archive: dict) -> tuple[str, str, int]:
    url = str(archive.get("url", ""))
    digest = str(archive.get("sha256", ""))
    try:
        size = int(archive.get("size", -1))
    except (TypeError, ValueError):
        size = -1
    if not ARCHIVE_PATTERN.fullmatch(url):
        fail(f"{CONTRACT_PATH} has no valid pone.rs archive URL")
    if not SHA_PATTERN.fullmatch(digest):
        fail(f"{CONTRACT_PATH} has no valid archive sha256")
    if size <= 0:
        fail(f"{CONTRACT_PATH} has no valid archive size")
    return url, digest, size


def load_contract(root: pathlib.Path) -> dict:
    path = root / CONTRACT_PATH
    if not path.is_file():
        fail(f"{CONTRACT_PATH} is missing; run scripts/pack_assets.sh --upload")
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        fail(f"cannot read {CONTRACT_PATH}: {error}")
    if not isinstance(data, dict) or data.get("schema") != SCHEMA:
        fail(f"{CONTRACT_PATH} has an unsupported schema")
    archive = data.get("archive")
    if not isinstance(archive, dict):
        fail(f"{CONTRACT_PATH} has no archive block")
    validate_archive(archive)
    runtime = data.get("runtime")
    if not isinstance(runtime, dict) or not runtime:
        fail(f"{CONTRACT_PATH} has no runtime manifest")
    sources = data.get("sources")
    if not isinstance(sources, dict):
        fail(f"{CONTRACT_PATH} has no sources manifest")
    _check_table("runtime", runtime)
    _check_table("sources", sources)
    return data


def verify_runtime(root: pathlib.Path, contract: dict, quiet: bool = False) -> bool:
    runtime = contract["runtime"]
    missing: list[str] = []
    stale: list[str] = []
    for rel, meta in runtime.items():
        path = root / rel
        if not path.is_file() or path.stat().st_size == 0:
            missing.append(rel)
            continue
        if path.stat().st_size != int(meta.get("size", -1)):
            stale.append(rel)
            continue
        if sha256_file(path) != str(meta.get("sha256", "")):
            stale.append(rel)
    try:
        actual = collect_runtime(root)
    except AssetError as error:
        if not quiet:
            print("ASSETS_FAIL " + str(error), file=sys.stderr)
        return False
    extra = sorted(set(actual) - set(runtime))
    if missing or stale or extra:
        if not quiet:
            def report(label: str, rows: list[str]) -> None:
                for rel in rows[:12]:
                    print(f"{label} {rel}", file=sys.stderr)
                if len(rows) > 12:
                    print(f"{label} ... and {len(rows) - 12} more", file=sys.stderr)

            report("ASSETS_MISSING", missing)
            report("ASSETS_STALE", stale)
            report("ASSETS_EXTRA", extra)
            print(
                "ASSETS_FAIL runtime asset set does not match "
                f"{CONTRACT_PATH}; run scripts/fetch_assets.sh",
                file=sys.stderr,
            )
        return False
    if not quiet:
        print(f"ASSETS_OK files={len(runtime)}")
    return True


def _manifest(runtime: dict, sources: dict) -> dict:
    return {"schema": SCHEMA, "runtime": runtime, "sources": sources}


def _write_zip(path: pathlib.Path, root: pathlib.Path, runtime: dict, sources: dict) -> None:
    manifest = _manifest(runtime, sources)
    manifest_bytes = (
        json.dumps(manifest, indent="\t", sort_keys=True, ensure_ascii=False) + "\n"
    ).encode("utf-8")
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    stamp = (1980, 1, 1, 0, 0, 0)

    def add(zf: zipfile.ZipFile, name: str, data: bytes) -> None:
        info = zipfile.ZipInfo(name, stamp)
        info.compress_type = zipfile.ZIP_DEFLATED
        info.create_system = 3
        info.external_attr = 0o644 << 16
        zf.writestr(info, data)

    try:
        with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
            add(zf, "manifest.json", manifest_bytes)
            for rel in sorted(runtime):
                add(zf, "runtime/" + rel, (root / rel).read_bytes())
            for rel in sorted(sources):
                add(zf, "sources/" + rel, (root / "sources" / rel).read_bytes())
        os.replace(tmp, path)
    finally:
        if tmp.exists():
            tmp.unlink()


def _upload(path: pathlib.Path) -> str:
    if shutil.which("curl") is None:
        fail("curl is needed to upload the archive")
    response = subprocess.run(
        [
            "curl",
            "--fail-with-body",
            "--silent",
            "--show-error",
            "--form",
            f"files[]=@{path}",
            UPLOAD_ENDPOINT,
        ],
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if response.returncode != 0:
        fail("upload failed: " + (response.stderr.strip() or "curl error"))
    try:
        data = json.loads(response.stdout)
    except json.JSONDecodeError:
        fail("upload did not answer with json: " + response.stdout)
    files = data.get("files") if isinstance(data, dict) else None
    if not data.get("success") or not files or not isinstance(files[0], dict):
        fail("upload failed: " + response.stdout)
    url = str(files[0].get("url", ""))
    if not ARCHIVE_PATTERN.fullmatch(url):
        fail("upload answered with an unexpected URL: " + url)

    with tempfile.TemporaryDirectory(prefix="unfplap-assets-") as tmp:
        mirror = pathlib.Path(tmp) / "mirror.zip"
        result = subprocess.run(
            [
                "curl",
                "--fail-with-body",
                "--silent",
                "--show-error",
                "--location",
                "--retry",
                "3",
                "--output",
                str(mirror),
                url,
            ],
            check=False,
        )
        if result.returncode != 0:
            fail("could not download the uploaded archive for verification")
        if mirror.stat().st_size != path.stat().st_size:
            fail(
                "upload check failed: host serves %d bytes, archive is %d"
                % (mirror.stat().st_size, path.stat().st_size)
            )
        if sha256_file(mirror) != sha256_file(path):
            fail("upload check failed: host serves different bytes")
    return url


def write_contract(root: pathlib.Path, url: str, archive: pathlib.Path, runtime: dict, sources: dict) -> bool:
    contract = {
        "schema": SCHEMA,
        "archive": {
            "url": url,
            "sha256": sha256_file(archive),
            "size": archive.stat().st_size,
        },
        "runtime": runtime,
        "sources": sources,
    }
    text = json.dumps(contract, indent="\t", ensure_ascii=False) + "\n"
    path = root / CONTRACT_PATH
    if path.is_file() and path.read_text(encoding="utf-8") == text:
        print(f"ASSET_PACK_CONFIG_UNCHANGED {path}")
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    print(f"ASSET_PACK_CONFIG_UPDATED {path}")
    return True


def command_verify(args) -> int:
    root = repo_root(args.root)
    contract = load_contract(root)
    try:
        validate_runtime(root, contract["runtime"])
    except AssetError as error:
        print("ASSETS_FAIL " + str(error), file=sys.stderr)
        return 1
    return 0 if verify_runtime(root, contract) else 1


def command_pack(args) -> int:
    root = repo_root(args.root)
    runtime = collect_runtime(root)
    validate_runtime(root, runtime)
    sources = collect_sources(root)

    if args.out:
        archive = pathlib.Path(args.out).resolve()
    else:
        archive = root / "dist" / "unfplap-assets.zip"
    _write_zip(archive, root, runtime, sources)
    digest = sha256_file(archive)
    if not args.out:
        named = archive.with_name(f"unfplap-assets-{digest[:12]}.zip")
        if named != archive:
            if named.exists():
                named.unlink()
            archive.replace(named)
        archive = named
    print(f"ASSET_PACK_BUILT {archive}")
    print(f"ASSET_PACK_SHA256 {digest}")
    print(f"ASSET_PACK_FILES runtime={len(runtime)} sources={len(sources)}")

    if not args.upload:
        print("Next: scripts/pack_assets.sh --upload")
        return 0

    url = _upload(archive)
    print(f"ASSET_PACK_UPLOADED {url}")
    if write_contract(root, url, archive, runtime, sources):
        print("Commit scripts/asset_pack.json with the asset change.")
    return 0


def _read_manifest(zf: zipfile.ZipFile) -> dict:
    try:
        raw = zf.read("manifest.json")
    except KeyError:
        fail("archive has no manifest.json")
    try:
        data = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        fail("archive manifest is not valid json: " + str(error))
    if not isinstance(data, dict) or data.get("schema") != SCHEMA:
        fail("archive manifest has an unsupported schema")
    if not isinstance(data.get("runtime"), dict) or not isinstance(data.get("sources"), dict):
        fail("archive manifest has no runtime or sources table")
    return data


def _safe_rel(name: str) -> str:
    pure = pathlib.PurePosixPath(name)
    if pure.is_absolute() or ".." in pure.parts or not pure.parts:
        fail("archive contains an unsafe path: " + name)
    return pure.as_posix()


def _check_archive(zf: zipfile.ZipFile, manifest: dict, contract: dict) -> None:
    if manifest["runtime"] != contract["runtime"]:
        fail("archive runtime manifest does not match " + CONTRACT_PATH)
    if manifest["sources"] != contract["sources"]:
        fail("archive sources manifest does not match " + CONTRACT_PATH)

    expected = {"manifest.json"}
    expected.update("runtime/" + rel for rel in manifest["runtime"])
    expected.update("sources/" + rel for rel in manifest["sources"])
    actual = set()
    for info in zf.infolist():
        if info.is_dir():
            continue
        name = _safe_rel(info.filename)
        if name in actual:
            fail("archive has a duplicate entry: " + name)
        actual.add(name)
    extra = sorted(actual - expected)
    missing = sorted(expected - actual)
    if missing:
        fail("archive is missing entries: " + ", ".join(missing[:8]))
    if extra:
        fail("archive has unexpected entries: " + ", ".join(extra[:8]))

    for tree in ("runtime", "sources"):
        for rel, meta in manifest[tree].items():
            name = tree + "/" + rel
            info = zf.getinfo(name)
            if info.file_size != int(meta.get("size", -1)):
                fail("archive entry size does not match its manifest: " + name)
            digest = hashlib.sha256(zf.read(info)).hexdigest()
            if digest != str(meta.get("sha256", "")):
                fail("archive entry hash does not match its manifest: " + name)


def _plan_extract(
    root: pathlib.Path,
    zf: zipfile.ZipFile,
    table: dict,
    prefix: str,
    dest_base: pathlib.Path,
) -> tuple[list[tuple[pathlib.Path, bytes]], list[str]]:
    writes: list[tuple[pathlib.Path, bytes]] = []
    changed: list[str] = []
    for rel in sorted(table):
        target = dest_base / pathlib.PurePosixPath(_safe_rel(rel))
        if target.is_file():
            if sha256_file(target) == table[rel]["sha256"]:
                continue
            changed.append(target.relative_to(root).as_posix())
        writes.append((target, zf.read(prefix + rel)))
    return writes, changed


def _apply_extract(writes: list[tuple[pathlib.Path, bytes]]) -> int:
    for target, data in writes:
        target.parent.mkdir(parents=True, exist_ok=True)
        tmp = target.with_name(target.name + ".fetch")
        tmp.write_bytes(data)
        os.replace(tmp, target)
    return len(writes)


def command_fetch(args) -> int:
    root = repo_root(args.root)
    if shutil.which("curl") is None:
        fail("curl is needed to download the archive")
    contract = load_contract(root)
    archive = contract["archive"]
    url = str(archive["url"])
    digest = str(archive["sha256"])
    size = int(archive["size"])

    with tempfile.TemporaryDirectory(prefix="unfplap-assets-") as tmp:
        download = pathlib.Path(tmp) / "assets.zip"
        result = subprocess.run(
            [
                "curl",
                "--fail-with-body",
                "--silent",
                "--show-error",
                "--location",
                "--retry",
                "3",
                "--output",
                str(download),
                url,
            ],
            check=False,
        )
        if result.returncode != 0:
            fail("could not download " + url)
        if download.stat().st_size != size:
            fail(
                "downloaded archive is %d bytes, expected %d"
                % (download.stat().st_size, size)
            )
        if sha256_file(download) != digest:
            fail("downloaded archive sha256 does not match " + CONTRACT_PATH)
        try:
            with zipfile.ZipFile(download) as zf:
                manifest = _read_manifest(zf)
                _check_archive(zf, manifest, contract)
                runtime_writes, runtime_changed = _plan_extract(
                    root, zf, manifest["runtime"], "runtime/", root
                )
                source_writes: list[tuple[pathlib.Path, bytes]] = []
                source_changed: list[str] = []
                if args.sources:
                    source_writes, source_changed = _plan_extract(
                        root, zf, manifest["sources"], "sources/", root / "sources"
                    )
        except zipfile.BadZipFile:
            fail("downloaded archive is not a zip file")

    changed = runtime_changed + source_changed
    if changed and not args.force:
        for rel in changed[:12]:
            print("ASSETS_LOCAL_CHANGED " + rel, file=sys.stderr)
        if len(changed) > 12:
            print(f"ASSETS_LOCAL_CHANGED ... and {len(changed) - 12} more", file=sys.stderr)
        fail("refusing to overwrite local changes; rerun with --force")

    runtime_written = _apply_extract(runtime_writes)
    source_written = _apply_extract(source_writes)
    print(f"ASSETS_FETCHED runtime={runtime_written} sources={source_written}")
    if args.sources:
        print(f"ASSETS_SOURCES {root / 'sources'}")
    try:
        validate_runtime(root, contract["runtime"])
    except AssetError as error:
        print("ASSETS_FAIL " + str(error), file=sys.stderr)
        return 1
    if not verify_runtime(root, contract):
        return 1
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    verify = sub.add_parser("verify", help="check the local runtime files against the contract")
    verify.add_argument("--root", default=None)
    verify.set_defaults(func=command_verify)

    pack = sub.add_parser("pack", help="build the resource archive")
    pack.add_argument("--root", default=None)
    pack.add_argument("--out", default=None)
    pack.add_argument("--upload", action="store_true", help="upload and rewrite scripts/asset_pack.json")
    pack.set_defaults(func=command_pack)

    fetch = sub.add_parser("fetch", help="download and extract the resource archive")
    fetch.add_argument("--root", default=None)
    fetch.add_argument("--sources", action="store_true", help="also extract sources/")
    fetch.add_argument("--force", action="store_true", help="overwrite changed local files")
    fetch.set_defaults(func=command_fetch)
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        return args.func(args)
    except AssetError as error:
        print("ASSETS_FAIL " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
