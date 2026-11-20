#!/usr/bin/env python3
"""scripts/pack_report.py reports the shipped GDScript size and the composition of a source tree
or a built .pck.

Code lines still carry code once a comment is removed, so blank lines, `#`/`##` blocks and tail
comments do not count; `#` inside a string literal is not a comment, and JSON and shaders use `//`
and `/* */` (JSONC) with the same string awareness. A source report measures the tree; a pck report
measures the packed bytes, where imported textures and audio appear as `.ctex`/`.sample`.

Usage:
  scripts/pack_report.py [ROOT] [--scope shipped|non-shipped|total] [--format text|markdown]
  scripts/pack_report.py --pck FILE [--format text|markdown] [--strict]
  scripts/pack_report.py --self-test
"""

from __future__ import annotations

import argparse
import collections
import pathlib
import re
import struct
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True

SCOPE_SHIPPED = "shipped"
SCOPE_NON_SHIPPED = "non-shipped"
SCOPE_TOTAL = "total"

BINARY_SUFFIXES = {".scn", ".tscn", ".tres", ".res", ".png", ".jpg", ".jpeg", ".svg", ".wav",
                   ".ogg", ".mp3", ".ttf", ".otf", ".exr", ".hdr", ".blend", ".glb", ".gltf",
                   ".ctex", ".sample", ".fontdata"}
SIDECAR_SUFFIXES = {".import"}
GD = "gdscript"
SHADER = "gdshader"
JSON = "json"
OTHER = "other"
BINARY = "binary"
SIDECAR = "sidecar"
CATEGORIES = (
    (GD, "gdscript (.gd)"),
    (SHADER, "gdshader (.gdshader/.gdshaderinc)"),
    (JSON, "json (.json)"),
    (OTHER, "other text"),
    (BINARY, "binary media"),
    (SIDECAR, "import sidecars (.import)"),
)
CATEGORY_HEADERS = ("category", "entries", "size", "code", "raw", "code %", "comments", "blanks")
GENERATED = "mod.built.json"
PCK_MAGIC = b"GDPC"
PCK_FORMAT_WITH_FLAGS = 3


def fail(why: str) -> None:
    raise SystemExit("LOC_FAIL " + why)


def suffix_of(path: str) -> str:
    return pathlib.PurePosixPath(path).suffix.lower()


def category(path: str) -> str:
    suffix = suffix_of(path)
    if suffix == ".gd":
        return GD
    if suffix in (".gdshader", ".gdshaderinc"):
        return SHADER
    if suffix == ".json":
        return JSON
    if suffix in BINARY_SUFFIXES:
        return BINARY
    if suffix in SIDECAR_SUFFIXES:
        return SIDECAR
    return OTHER


def human(size: int) -> str:
    value = float(size)
    for unit in ("B", "KB", "MB", "GB"):
        if value < 1024 or unit == "GB":
            return ("%d B" % value) if unit == "B" else ("%.1f %s" % (value, unit))
        value /= 1024.0


def count_lines(text: str, style: str) -> dict[str, int]:
    """Raw, code, comment and blank lines for `hash` (#) or `slash` (// and /* */) comments."""
    raw = code = comment = blank = 0
    block = False
    quote: str | None = None
    triple: str | None = None
    for line in text.splitlines():
        raw += 1
        escaped = False
        index = 0
        cut = len(line)
        while index < len(line):
            if block:
                if line.startswith("*/", index):
                    block = False
                    index += 2
                    continue
                index += 1
                continue
            if triple:
                if triple in line[index:]:
                    triple = None
                index = len(line)
                continue
            char = line[index]
            if quote:
                if escaped:
                    escaped = False
                elif char == "\\":
                    escaped = True
                elif char == quote:
                    quote = None
                index += 1
                continue
            token = next((marker for marker in ('"""', "'''") if line.startswith(marker, index)), None)
            if token is not None:
                triple = token
                index += len(token)
                continue
            if char in "\"'":
                quote = char
                index += 1
                continue
            if style == "hash" and char == "#":
                cut = index
                break
            if style == "slash":
                if line.startswith("//", index):
                    cut = index
                    break
                if line.startswith("/*", index):
                    block = True
                    index += 2
                    continue
            index += 1
        if line[:cut].strip():
            code += 1
        elif line.strip():
            comment += 1
        else:
            blank += 1
    return {"raw": raw, "code": code, "comment": comment, "blank": blank}


def count_bytes(path: str, data: bytes) -> dict[str, int] | None:
    suffix = suffix_of(path)
    if suffix == ".gd":
        return count_lines(data.decode("utf-8", "replace"), "hash")
    if suffix in (".gdshader", ".gdshaderinc", ".json"):
        return count_lines(data.decode("utf-8", "replace"), "slash")
    return None


def git_files(root: pathlib.Path) -> list[str]:
    try:
        out = subprocess.check_output(["git", "-C", str(root), "ls-files", "-z"],
                                      stderr=subprocess.PIPE)
    except (OSError, subprocess.CalledProcessError) as error:
        detail = error.stderr.decode("utf-8", "replace").strip() if hasattr(error, "stderr") else str(error)
        fail("git ls-files failed: " + detail)
    return [entry for entry in out.decode("utf-8", "replace").split("\0") if entry]


def manifest_files(root: pathlib.Path) -> list[str]:
    """The release pack list from the same tool the build uses (relative to the mod folder)."""
    try:
        result = subprocess.run([sys.executable, str(root / "scripts" / "build_manifest.py"), str(root)],
                                capture_output=True, text=True, check=True)
    except (OSError, subprocess.CalledProcessError) as error:
        detail = (error.stderr or "").strip().splitlines()
        fail("pack list unavailable (fetch the resource pack first): " + (detail[-1] if detail else str(error)))
    return [line for line in result.stdout.splitlines() if line]


def contract_sources(root: pathlib.Path) -> list[str]:
    """The fetched resource runtime the contract declares: sources whose artifacts ship."""
    path = root / "scripts" / "asset_pack.json"
    if not path.is_file():
        return []
    try:
        import json

        runtime = json.loads(path.read_text(encoding="utf-8")).get("runtime", {})
    except (OSError, ValueError):
        return []
    return sorted(runtime) if isinstance(runtime, dict) else []


def shipped_sources(root: pathlib.Path) -> list[str]:
    return sorted(set(manifest_files(root)) | set(contract_sources(root)))


def source_files(root: pathlib.Path, scope: str) -> list[str]:
    tracked = git_files(root)
    shipped = shipped_sources(root)
    if scope == SCOPE_SHIPPED:
        return shipped
    packed = set(shipped)
    non_shipped = [path for path in tracked if path not in packed]
    return non_shipped if scope == SCOPE_NON_SHIPPED else shipped + non_shipped


def source_rows(root: pathlib.Path, paths: list[str]) -> dict[str, dict]:
    rows: dict[str, dict] = {}
    for path in paths:
        file = root / path
        if not file.is_file():
            continue
        data = file.read_bytes()
        rows[path] = {"size": len(data), "lines": count_bytes(path, data)}
    return rows


def pck_entries(path: pathlib.Path) -> tuple[dict[str, bytes], int, str]:
    """Entry name -> bytes, the pack size, and its format. Format 3 puts the directory last."""
    try:
        data = path.read_bytes()
    except OSError as error:
        fail("cannot read %s: %s" % (path, error))
    if data[:4] != PCK_MAGIC:
        fail("%s is not a .pck (magic %r)" % (path, data[:4]))
    fmt = struct.unpack_from("<I", data, 4)[0]
    major, minor, patch = struct.unpack_from("<III", data, 8)
    if fmt >= PCK_FORMAT_WITH_FLAGS:
        file_base, dir_offset = struct.unpack_from("<QQ", data, 24)
    else:
        file_base = struct.unpack_from("<Q", data, 20)[0]
        dir_offset = 20 + 8 + 64
    if dir_offset + 4 > len(data):
        fail("%s has a directory offset past its end" % path)
    count = struct.unpack_from("<I", data, dir_offset)[0]
    offset = dir_offset + 4
    blobs: dict[str, bytes] = {}
    for _index in range(count):
        if offset + 4 > len(data):
            fail("%s directory is truncated" % path)
        length = struct.unpack_from("<I", data, offset)[0]
        offset += 4
        name = data[offset:offset + length].rstrip(b"\0").decode("utf-8", "replace")
        offset += length
        file_offset, size = struct.unpack_from("<QQ", data, offset)
        offset += 16 + 16
        if fmt >= PCK_FORMAT_WITH_FLAGS:
            offset += 4
        start = file_base + file_offset
        if start + size > len(data):
            fail("%s entry %s runs past the end of the pack" % (path, name))
        blobs[name] = data[start:start + size]
    return blobs, len(data), "format %d, engine %d.%d.%d" % (fmt, major, minor, patch)


def mod_prefix(root: pathlib.Path) -> str:
    path = root / "mod.json"
    try:
        import json

        return "mods/%s/" % json.loads(path.read_text(encoding="utf-8"))["id"]
    except (OSError, ValueError, KeyError):
        return ""


def strip_prefix(name: str, prefix: str) -> str:
    return name[len(prefix):] if prefix and name.startswith(prefix) else name


def pck_rows(blobs: dict[str, bytes], prefix: str) -> dict[str, dict]:
    rows: dict[str, dict] = {}
    for name, data in blobs.items():
        display = strip_prefix(name, prefix)
        rows[display] = {"size": len(data), "lines": count_bytes(display, data)}
    return rows


def imported_targets(root: pathlib.Path, manifest: list[str]) -> set[str]:
    """Artifacts the packer adds for each manifest sidecar (`res://.godot/imported/...`)."""
    targets: set[str] = set()
    for path in manifest:
        if not path.endswith(".import"):
            continue
        try:
            text = (root / path).read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        targets.update(re.findall(r"res://\.godot/imported/[^\"]+", text))
    return {target[len("res://"):] for target in targets}


def summarize(rows: dict[str, dict]) -> tuple[dict[str, int], dict[str, int], dict[str, dict]]:
    entries: collections.Counter = collections.Counter()
    sizes: collections.Counter = collections.Counter()
    lines: dict[str, dict[str, int]] = {}
    for path, row in rows.items():
        name = category(path)
        entries[name] += 1
        sizes[name] += row["size"]
        if row["lines"]:
            acc = lines.setdefault(name, {"code": 0, "raw": 0, "comment": 0, "blank": 0})
            for key, value in row["lines"].items():
                acc[key] += value
    return entries, sizes, lines


def category_table(rows, entries, sizes, lines, total_size: int):
    body = []
    for name, _label in CATEGORIES:
        if not entries[name]:
            continue
        acc = lines.get(name)
        cells = [name, str(entries[name]), human(sizes[name])]
        if acc:
            share = 100.0 * acc["code"] / acc["raw"] if acc["raw"] else 0.0
            cells += [str(acc["code"]), str(acc["raw"]), "%.1f%%" % share,
                      str(acc["comment"]), str(acc["blank"])]
        else:
            cells += ["-"] * 5
        body.append(cells)
    total = {"code": 0, "raw": 0, "comment": 0, "blank": 0}
    for acc in lines.values():
        for key in total:
            total[key] += acc[key]
    share = 100.0 * total["code"] / total["raw"] if total["raw"] else 0.0
    totals = ["total", str(len(rows)), human(total_size), str(total["code"]), str(total["raw"]),
              "%.1f%%" % share, str(total["comment"]), str(total["blank"])]
    return list(CATEGORY_HEADERS), body, totals


def media_table(rows: dict[str, dict]):
    per_suffix: dict[str, list[int]] = {}
    for path, row in rows.items():
        if category(path) != BINARY:
            continue
        slot = per_suffix.setdefault(suffix_of(path) or "(none)", [0, 0])
        slot[0] += 1
        slot[1] += row["size"]
    if not per_suffix:
        return None
    body = [[suffix, str(count), human(size)]
            for suffix, (count, size) in sorted(per_suffix.items(), key=lambda item: -item[1][1])]
    return ["suffix", "files", "size"], body


def large_gd(rows: dict[str, dict], minimum: int) -> list[list[str]]:
    large = sorted(((row["lines"]["code"], path, row) for path, row in rows.items()
                    if category(path) == GD and row["lines"] and row["lines"]["code"] >= minimum))
    return [[str(code), str(row["lines"]["raw"]), path] for code, path, row in reversed(large)]


def top_json(rows: dict[str, dict], top: int) -> tuple[list[list[str]], str]:
    files = sorted(((row["lines"]["raw"], row["lines"]["code"], path) for path, row in rows.items()
                    if category(path) == JSON and row["lines"]), reverse=True)
    note = "JSON: %d files, %d lines, %d without comments; top %d" % (
        len(files), sum(raw for raw, _code, _path in files),
        sum(code for _raw, code, _path in files), min(top, len(files)))
    body = [[str(raw), str(code), path] for raw, code, path in files[:top]]
    return body, note


def other_files(rows: dict[str, dict], limit: int) -> tuple[list[str], int]:
    files = sorted(path for path in rows if category(path) == OTHER)
    return files[:limit], len(files) - min(limit, len(files))


def manifest_diff(root: pathlib.Path, packed: set[str], prefix: str) -> tuple[list[str], list[str]]:
    """Expected = manifest + imported artifacts + mod.built.json; the rest is drift."""
    manifest = manifest_files(root)
    expected = {prefix + path for path in manifest}
    expected |= imported_targets(root, manifest)
    expected.add(prefix + GENERATED)
    missing = sorted(strip_prefix(name, prefix) for name in expected - packed)
    extra = sorted(strip_prefix(name, prefix) for name in packed - expected)
    return missing, extra


def render(widths: tuple[int, ...], cells: list[str]) -> str:
    """Pad every column but the last, so a file name never trails spaces."""
    return "  ".join(cell if index == len(cells) - 1 else cell.ljust(widths[index])
                     for index, cell in enumerate(cells))


def print_sections(titles: list[str], rows, entries, sizes, lines, args, total_size, diff) -> None:
    """The one layout, used for a text log and for a markdown job summary."""
    markdown = args.format == "markdown"
    headers, body, totals = category_table(rows, entries, sizes, lines, total_size)
    widths = (12, 7, 10, 8, 8, 7, 8, 7)

    def table(header: list[str], body_rows: list[list[str]], totals_row: list[str] | None = None):
        if markdown:
            print("| " + " | ".join(header) + " |")
            print("|" + "|".join("---" for _ in header) + "|")
            for cells in body_rows + ([totals_row] if totals_row else []):
                print("| " + " | ".join(cells) + " |")
        else:
            print(render(widths, header))
            for cells in body_rows + ([totals_row] if totals_row else []):
                print(render(widths, cells))

    if markdown:
        print("**%s**" % " · ".join(titles))
    else:
        for title in titles:
            print(title)
    print()
    table(headers, body, totals)

    media = media_table(rows)
    if media:
        print("\n**Binary media**\n" if markdown else "\nBINARY MEDIA")
        table(media[0], media[1])

    large = large_gd(rows, args.min_lines)
    print("\n**GDScript at or above %d code lines:** %d file(s)\n" % (args.min_lines, len(large))
          if markdown else "\nGDSCRIPT >= %d CODE LINES: %d file(s)" % (args.min_lines, len(large)))
    table(["code", "raw", "file"], large)

    json_body, json_note = top_json(rows, args.top_json)
    print("\n**%s**\n" % json_note if markdown else "\n" + json_note.upper())
    table(["lines", "code", "file"], json_body)

    others, hidden = other_files(rows, args.list_other)
    print("\n**Other:** %d file(s)" % (len(others) + hidden) if markdown
          else "\nOTHER: %d file(s)" % (len(others) + hidden))
    for path in others:
        print("- `%s`" % path if markdown else "  " + path)
    if hidden:
        print("- ... and %d more" % hidden if markdown else "  ... and %d more" % hidden)

    if diff is None:
        return
    missing, extra = diff
    print("\n**Manifest diff (pack vs tree):** %d missing, %d extra" % (len(missing), len(extra))
          if markdown else "\nMANIFEST DIFF (pack vs tree): %d missing, %d extra" % (
              len(missing), len(extra)))
    for label, names in (("missing", missing), ("extra", extra)):
        for name in names[:10]:
            print("- %s `%s`" % (label, name) if markdown else "  %-7s %s" % (label, name))
        if len(names) > 10:
            print("- ... and %d more %s" % (len(names) - 10, label) if markdown
                  else "  ... and %d more %s" % (len(names) - 10, label))


def report_source(root: pathlib.Path, args: argparse.Namespace) -> int:
    rows = source_rows(root, source_files(root, args.scope))
    entries, sizes, lines = summarize(rows)
    total_size = sum(sizes.values())
    titles = ["SOURCE scope=%s: %d entries, %s total" % (args.scope, len(rows), human(total_size))]
    print_sections(titles, rows, entries, sizes, lines, args, total_size, None)
    return 0


def report_pck(root: pathlib.Path, pack: pathlib.Path, args: argparse.Namespace) -> int:
    blobs, pack_size, label = pck_entries(pack)
    prefix = mod_prefix(root)
    rows = pck_rows(blobs, prefix)
    entries, sizes, lines = summarize(rows)
    total_size = sum(sizes.values())
    titles = ["PACK %s (%s): %d entries, %s in entries, %s in the file" % (
        pack, label, len(rows), human(total_size), human(pack_size))]
    diff = None if args.no_manifest else manifest_diff(root, set(blobs), prefix)
    print_sections(titles, rows, entries, sizes, lines, args, total_size, diff)
    if args.strict and diff and (diff[0] or diff[1]):
        print("LOC_FAIL the pack does not match the tree: %d missing, %d extra" % (
            len(diff[0]), len(diff[1])), file=sys.stderr)
        return 1
    return 0


def build_fixture(fmt: int, files: list[tuple[str, bytes]]) -> bytes:
    """A minimal pack in one of Godot's two directory layouts, for --self-test."""
    entries = bytearray()
    body = b""
    for name, data in files:
        raw = name.encode()
        raw += b"\0" * (-len(raw) % 4)
        entries += struct.pack("<I", len(raw)) + raw
        entries += struct.pack("<QQ", len(body), len(data)) + b"\0" * 16
        if fmt >= PCK_FORMAT_WITH_FLAGS:
            entries += struct.pack("<I", 0)
        body += data
    if fmt >= PCK_FORMAT_WITH_FLAGS:
        base = 64
        dir_offset = base + len(body)
        header = bytearray(PCK_MAGIC + struct.pack("<IIIII", fmt, 4, 5, 2, 2))
        header += struct.pack("<QQ", base, dir_offset)
        header += b"\0" * (base - len(header))
        return bytes(header) + body + struct.pack("<I", len(files)) + bytes(entries)
    base = 96 + len(entries)
    header = bytearray(PCK_MAGIC + struct.pack("<IIII", fmt, 4, 1, 4))
    header += struct.pack("<Q", base)
    header += b"\0" * 64
    header += struct.pack("<I", len(files))
    return bytes(header) + bytes(entries) + body


def self_test() -> None:
    files = [("mods/x/a.gd", b"extends Node\n## doc\n\nfunc f():\n\tprint('a#b')\n"),
             ("mods/x/b.json", b'{"p": "res://a"}\n// note\n'),
             ("mods/x/c.txt", b"")]
    for fmt in (2, PCK_FORMAT_WITH_FLAGS):
        with tempfile.NamedTemporaryFile(suffix=".pck", delete=False) as handle:
            handle.write(build_fixture(fmt, files))
            path = pathlib.Path(handle.name)
        try:
            blobs, size, label = pck_entries(path)
            assert blobs == dict(files), (fmt, blobs)
            assert size == path.stat().st_size, (fmt, size)
            assert "format %d" % fmt in label, label
            probe = count_lines(files[0][1].decode(), "hash")
            assert probe == {"raw": 5, "code": 3, "comment": 1, "blank": 1}, probe
            probe = count_lines(files[1][1].decode(), "slash")
            assert probe == {"raw": 2, "code": 1, "comment": 1, "blank": 0}, probe
        finally:
            path.unlink()
    bad = pathlib.Path(tempfile.mktemp(suffix=".pck"))
    bad.write_bytes(b"nope")
    try:
        pck_entries(bad)
    except SystemExit:
        pass
    else:
        raise AssertionError("a non-pck was accepted")
    finally:
        bad.unlink()
    print("LOC_SELFTEST_PASS")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("root", nargs="?", default=".", type=pathlib.Path,
                        help="the mod tree (default: the working directory)")
    parser.add_argument("--pck", type=pathlib.Path, metavar="FILE",
                        help="measure this .pck instead of the source tree; the path is required")
    parser.add_argument("--scope", choices=(SCOPE_SHIPPED, SCOPE_NON_SHIPPED, SCOPE_TOTAL),
                        default=SCOPE_SHIPPED, help="source report: which files to measure")
    parser.add_argument("--format", choices=("text", "markdown"), default="text")
    parser.add_argument("--min-lines", type=int, default=1000)
    parser.add_argument("--top-json", type=int, default=5)
    parser.add_argument("--list-other", type=int, default=10)
    parser.add_argument("--strict", action="store_true",
                        help="pck report: fail when the pack does not match the tree's manifest")
    parser.add_argument("--no-manifest", action="store_true", help="pck report: skip the diff")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    args.root = args.root.resolve()
    if args.pck is None:
        sys.exit(report_source(args.root, args))
    pack = args.pck if args.pck.is_absolute() else (args.root / args.pck).resolve()
    if not pack.is_file():
        fail("no such pack: %s" % pack)
    sys.exit(report_pck(args.root, pack, args))


if __name__ == "__main__":
    main()
