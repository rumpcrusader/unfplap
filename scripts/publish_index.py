#!/usr/bin/env python3
"""Publish one release to the Home: Equestria mod index, or preview that submission.

  scripts/publish_index.py                              preview the latest release
  scripts/publish_index.py --tag v0.5.1                 preview that release
  scripts/publish_index.py --tag v0.5.1 --submit        update the listing
  scripts/publish_index.py --tag v0.5.1 --submit --create
                                                        create the listing (first run only)
  scripts/publish_index.py --tag v0.5.1 --submit --force
                                                        submit a same-version or older release
  scripts/publish_index.py --tag v0.5.1 --id 7          preview a specific listing id

A preview downloads the release pack and its .sha256, verifies both, reads the public listing,
and prints the exact payload and the action it would take. It never writes to the index.
--submit performs that action and prints INDEX_CREATED, INDEX_UPDATED or INDEX_SKIPPED.

The index keeps one listing per mod and one release revision per version or download change.
Its origin and the listing ID live in scripts/index_listing.json, so a workflow dispatch cannot
redirect HE_MOD_TOKEN at another host. The token manages only its owner's listings and cannot
approve them; a reviewer still checks every new release revision.

Environment: GITHUB_REPOSITORY (owner/repo) and GH_TOKEN (optional; both are set in Actions),
HE_MOD_TOKEN (submit only), HE_MOD_INDEX_URL (local testing only; ignored in Actions).
"""

import argparse
import hashlib
import http.client
import json
import os
import re
import shutil
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

USER_AGENT = "unfplap-publish-index"
ROOT = Path(__file__).resolve().parent.parent
STATE_FILE = ROOT / "scripts" / "index_listing.json"
REPO = os.environ.get("GITHUB_REPOSITORY") or "rumpcrusader/unfplap"
GITHUB_TOKEN = (os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN") or "").strip()
INDEX_TOKEN = os.environ.get("HE_MOD_TOKEN", "").strip()
VERSION_RE = re.compile(r"^\d+(?:\.\d+)*$")


def fail(message):
    print(message, file=sys.stderr)
    raise SystemExit(1)


def summary_line(text):
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    if path:
        with open(path, "a", encoding="utf-8") as handle:
            handle.write(text + "\n")


def http_request(url, *, method="GET", headers=None, data=None, timeout=180):
    request = urllib.request.Request(url, data=data, headers=headers or {}, method=method)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return response.status, response.headers, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.headers, error.read()
    except (urllib.error.URLError, http.client.HTTPException) as error:
        fail(f"Could not reach {url}: {error}")


def github_json(url):
    headers = {"Accept": "application/vnd.github+json", "User-Agent": USER_AGENT}
    if GITHUB_TOKEN:
        headers["Authorization"] = f"Bearer {GITHUB_TOKEN}"
    status, _, body = http_request(url, headers=headers)
    if status != 200:
        detail = body[:200].decode("utf-8", "replace")
        fail(f"GitHub answered HTTP {status} for {url}: {detail}")
    try:
        return json.loads(body)
    except json.JSONDecodeError as error:
        fail(f"GitHub answered with invalid JSON for {url}: {error}")


def download(url, path):
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(request, timeout=300) as response, open(path, "wb") as handle:
            shutil.copyfileobj(response, handle)
    except (urllib.error.URLError, OSError, http.client.HTTPException) as error:
        fail(f"Could not download {url}: {error}")


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_state():
    try:
        data = json.loads(STATE_FILE.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"scripts/index_listing.json is invalid: {error}")
    if not isinstance(data, dict):
        fail("scripts/index_listing.json must contain a JSON object.")
    url = data.get("url")
    listing_id = data.get("id")
    if not isinstance(url, str):
        fail("scripts/index_listing.json: url must be a string.")
    if not isinstance(listing_id, int) or isinstance(listing_id, bool) or listing_id < 0:
        fail("scripts/index_listing.json: id must be a non-negative integer.")
    return url, listing_id


def validate_origin(raw):
    if not raw:
        fail("INDEX_UNCONFIGURED scripts/index_listing.json has no url; set the index origin first.")
    parts = urllib.parse.urlsplit(raw)
    if parts.scheme not in ("http", "https") or not parts.netloc or not parts.hostname:
        fail(f"INDEX_UNCONFIGURED {raw!r} is not an http(s) origin.")
    if parts.path:
        fail(f"INDEX_UNCONFIGURED {raw!r} must be an origin without a path.")
    if parts.query or parts.fragment or parts.username or parts.password:
        fail(f"INDEX_UNCONFIGURED {raw!r} must be a bare origin without credentials, query or fragment.")
    if raw.endswith("/"):
        fail(f"INDEX_UNCONFIGURED {raw!r} must not end with a slash.")
    if parts.scheme == "http":
        loopback = parts.hostname in ("127.0.0.1", "localhost", "::1")
        if os.environ.get("GITHUB_ACTIONS") == "true" or not loopback:
            fail(f"INDEX_UNCONFIGURED {raw!r} must use https outside a local test.")


def resolve_tag(tag):
    if not tag:
        release = github_json(f"https://api.github.com/repos/{REPO}/releases/latest")
        if not isinstance(release, dict):
            fail("GitHub returned an unexpected latest-release response.")
        tag = str(release.get("tag_name", ""))
        print(f"latest release is {tag}")
    if not tag.startswith("v"):
        fail(f"release tags start with v: {tag}")
    version = tag[1:]
    if not VERSION_RE.fullmatch(version):
        fail(f"unexpected release version: {version}")
    return tag, version


def release_assets(tag, version):
    release = github_json(f"https://api.github.com/repos/{REPO}/releases/tags/{tag}")
    if not isinstance(release, dict):
        fail(f"GitHub returned an unexpected release response for {tag}.")
    if release.get("tag_name") != tag:
        fail(f"release tag {release.get('tag_name')} does not match {tag}.")
    wanted = [f"unfplap-{version}.pck", f"unfplap-{version}.pck.sha256"]
    by_name = {asset.get("name"): asset for asset in release.get("assets", [])}
    missing = [name for name in wanted if name not in by_name]
    if missing:
        fail(f"{tag} is missing asset(s): {', '.join(missing)}")
    return [by_name[name] for name in wanted]


def fetch_release(work, tag, version):
    assets = release_assets(tag, version)
    paths = {}
    for asset in assets:
        path = work / asset["name"]
        download(asset["browser_download_url"], path)
        if path.stat().st_size != asset["size"]:
            fail(f"Downloaded {asset['name']} is {path.stat().st_size} bytes, release asset is {asset['size']}.")
        paths[asset["name"]] = path
    pack = paths[f"unfplap-{version}.pck"]
    checksum = paths[f"unfplap-{version}.pck.sha256"]
    try:
        released_sha = checksum.read_text(encoding="utf-8").split()[0]
    except (OSError, IndexError):
        fail(f"{checksum.name} has no sha256 value.")
    local_sha = sha256_file(pack)
    if local_sha != released_sha:
        fail(f"Downloaded pack sha256 {local_sha} does not match release checksum {released_sha}.")
    return assets


def read_mod(tag, version):
    url = f"https://raw.githubusercontent.com/{REPO}/{tag}/mod.json"
    status, _, body = http_request(url)
    if status != 200:
        fail(f"Could not read mod.json at {tag} (HTTP {status}).")
    try:
        mod = json.loads(body)
    except json.JSONDecodeError as error:
        fail(f"mod.json at {tag} is not JSON: {error}")
    if not isinstance(mod, dict):
        fail(f"mod.json at {tag} is not a JSON object.")
    if mod.get("version") != version:
        fail(f"mod.json version {mod.get('version')} does not match tag {version}.")
    return mod


def byte_length(value):
    return len(value.encode("utf-8"))


def build_payload(mod, version, assets, image_url):
    name = str(mod.get("name", "")).strip()
    game_version = str(mod.get("game_version", "")).strip()
    description = str(mod.get("description", "")).strip()
    if not name or byte_length(name) > 100:
        fail("INDEX_INVALID mod.json name must be 1-100 bytes.")
    if byte_length(version) > 64 or byte_length(game_version) > 64:
        fail("INDEX_INVALID version and game_version must be at most 64 bytes.")
    if not description:
        fail("INDEX_INVALID mod.json description is needed for short_description.")
    if byte_length(description) > 240:
        fail("INDEX_INVALID mod.json description is longer than the index's 240-byte short_description.")
    downloads = []
    seen = set()
    for asset in assets:
        filename = str(asset.get("name", ""))
        url = str(asset.get("browser_download_url", ""))
        if (not filename or byte_length(filename) > 180 or "/" in filename or "\\" in filename
                or any(ord(ch) < 32 or ord(ch) == 127 for ch in filename)):
            fail(f"INDEX_INVALID download filename {filename!r} is not valid for the index.")
        if len(url) > 2048 or urllib.parse.urlsplit(url).scheme not in ("http", "https"):
            fail(f"INDEX_INVALID download URL {url!r} is not a valid http(s) URL.")
        if url in seen:
            fail("INDEX_INVALID download URLs must be unique.")
        seen.add(url)
        downloads.append({"filename": filename, "url": url})
    if not 1 <= len(downloads) <= 20:
        fail("INDEX_INVALID the index needs 1-20 downloads.")
    return {
        "name": name,
        "version": version,
        "game_version": game_version,
        "downloads": downloads,
        "repository_url": f"https://github.com/{REPO}",
        "short_description": description,
        "description": description,
        "image_url": image_url,
    }


def index_request(origin, method, path, payload=None):
    data = None
    headers = {"Accept": "application/json", "User-Agent": USER_AGENT}
    if payload is not None:
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        headers["Content-Type"] = "application/json"
    if INDEX_TOKEN and method != "GET":
        headers["Authorization"] = f"Bearer {INDEX_TOKEN}"
    return http_request(origin + path, method=method, headers=headers, data=data)


def error_message(body):
    try:
        data = json.loads(body)
    except (json.JSONDecodeError, UnicodeDecodeError):
        return body[:200].decode("utf-8", "replace") or "no error message"
    if isinstance(data, dict):
        return str(data.get("error", "no error message"))
    return "no error message"


def auth_failure(origin):
    fail(
        "INDEX_UNAUTHORIZED the index rejected HE_MOD_TOKEN.\n"
        f"Create a new upload token at {origin}/account and replace the HE_MOD_TOKEN secret in the\n"
        "mod-index environment. Upload tokens expire after one year."
    )


def wait_retry(headers):
    raw = headers.get("Retry-After") if headers else None
    try:
        seconds = int(raw)
    except (TypeError, ValueError):
        seconds = None
    if seconds is None or seconds < 0 or seconds > 60:
        fail(f"INDEX_RATE_LIMITED the index did not accept the request now; Retry-After is {raw!r}.")
    print(f"the index rate-limited the request; waiting {seconds} s.", file=sys.stderr)
    time.sleep(seconds)


def parse_json(body, what):
    try:
        data = json.loads(body)
    except json.JSONDecodeError:
        fail(f"INDEX_FAILED the {what} response is not JSON.")
    if not isinstance(data, dict):
        fail(f"INDEX_FAILED the {what} response is not a JSON object.")
    return data


def read_listing(origin, listing_id):
    status, _, body = index_request(origin, "GET", f"/api/mods/{listing_id}")
    if status == 404:
        fail(f"INDEX_MISSING id={listing_id} was not found; check scripts/index_listing.json.")
    if status != 200:
        fail(f"INDEX_FAILED read answered HTTP {status}: {error_message(body)}")
    return parse_json(body, "read")


def version_key(value):
    parts = value.split(".")
    if not parts or not all(part.isdigit() for part in parts):
        return None
    return tuple(int(part) for part in parts)


def choose_action(listing, version, asset_urls):
    current_version = str(listing.get("version", ""))
    current_urls = sorted(str(item.get("url", "")) for item in listing.get("downloads") or [])
    new_urls = sorted(asset_urls)
    if current_version == version:
        return ("skip" if current_urls == new_urls else "conflict"), current_version
    current, new = version_key(current_version), version_key(version)
    if current is None or new is None:
        return "unknown", current_version
    if current > new:
        return "downgrade", current_version
    return "update", current_version


def submit_guard(action, listed_version, version, listing_id, force):
    if action == "skip" and not force:
        print(f"INDEX_SKIPPED id={listing_id} version={version} is already listed with the same downloads.")
        summary_line("- Result: `INDEX_SKIPPED`")
        raise SystemExit(0)
    if action == "conflict" and not force:
        fail(
            f"INDEX_CONFLICT id={listing_id} lists version {listed_version} with a different download set; "
            "publish a new patch release or rerun with --force."
        )
    if action == "downgrade" and not force:
        fail(f"INDEX_DOWNGRADE id={listing_id} lists newer version {listed_version}; rerun with --force to replace it.")
    if action == "unknown" and not force:
        fail(
            f"INDEX_CONFLICT id={listing_id} lists version {listed_version}, which cannot be compared with "
            f"{version}; rerun with --force to replace it."
        )


def create_listing(origin, payload):
    rate_retry = False
    while True:
        status, headers, body = index_request(origin, "POST", "/api/mods", payload)
        if status == 201:
            return parse_json(body, "create")
        if status == 401:
            auth_failure(origin)
        if status == 403:
            fail("INDEX_FORBIDDEN the token cannot create this listing.")
        if status == 429:
            if rate_retry:
                fail("INDEX_RATE_LIMITED the index did not accept the create now.")
            wait_retry(headers)
            rate_retry = True
            continue
        fail(f"INDEX_FAILED create answered HTTP {status}: {error_message(body)}")


def update_listing(origin, listing_id, payload, mod, assets, version, force):
    conflict_retry = False
    rate_retry = False
    while True:
        status, headers, body = index_request(origin, "PUT", f"/api/mods/{listing_id}", payload)
        if status == 200:
            return parse_json(body, "update")
        if status == 401:
            auth_failure(origin)
        if status == 403:
            fail(f"INDEX_FORBIDDEN id={listing_id} belongs to another account.")
        if status == 404:
            fail(f"INDEX_MISSING id={listing_id} was not found; check scripts/index_listing.json.")
        if status == 409:
            if conflict_retry:
                fail("INDEX_CONFLICT the listing kept changing; try again.")
            print("the listing changed while submitting; reloading and retrying once.", file=sys.stderr)
            listing = read_listing(origin, listing_id)
            action, listed_version = choose_action(
                listing, version, [asset["browser_download_url"] for asset in assets]
            )
            submit_guard(action, listed_version, version, listing_id, force)
            payload = build_payload(mod, version, assets, str(listing.get("image_url", "") or ""))
            conflict_retry = True
            continue
        if status == 429:
            if rate_retry:
                fail("INDEX_RATE_LIMITED the index did not accept the update now.")
            wait_retry(headers)
            rate_retry = True
            continue
        fail(f"INDEX_FAILED update answered HTTP {status}: {error_message(body)}")


def print_report(origin, listing_id, listed_version, approval, tag, version, action, payload):
    print(f"index: {origin}")
    if listing_id:
        print(f"listing: {origin}/mod/{listing_id}")
        print(f"listed version: {listed_version or 'unknown'}")
        print(f"approval: {approval or 'unknown'}")
    else:
        print("listing: not created yet")
    print(f"tag: {tag}")
    print(f"version: {version}")
    print(f"action: {action}")
    print("payload:")
    print(json.dumps(payload, indent=2))


def write_summary(origin, listing_id, listed_version, approval, tag, version, action, payload):
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    if not path:
        return
    with open(path, "a", encoding="utf-8") as handle:
        handle.write("### Mod index\n\n")
        handle.write(f"- Tag: `{tag}`\n")
        handle.write(f"- Version: `{version}`\n")
        if listing_id:
            handle.write(
                f"- Listing: {origin}/mod/{listing_id} (listed version `{listed_version or 'unknown'}`, "
                f"approval `{approval or 'unknown'}`)\n"
            )
        else:
            handle.write("- Listing: not created yet\n")
        handle.write(f"- Action: `{action}`\n\n")
        handle.write("```json\n")
        handle.write(json.dumps(payload, indent=2))
        handle.write("\n```\n")


def write_outputs(tag, version, action, listing_id):
    path = os.environ.get("GITHUB_OUTPUT")
    if not path:
        return
    with open(path, "a", encoding="utf-8") as handle:
        handle.write(f"tag={tag}\nversion={version}\naction={action}\nid={listing_id}\n")


def parse_args():
    parser = argparse.ArgumentParser(
        description="Publish one release to the Home: Equestria mod index.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "A preview never writes to the index. --submit needs HE_MOD_TOKEN; --create is only for\n"
            "the first run, when scripts/index_listing.json has id 0."
        ),
    )
    parser.add_argument("--tag", default="", help="release tag (empty uses the latest release)")
    parser.add_argument("--submit", action="store_true", help="write to the index")
    parser.add_argument("--force", action="store_true", help="submit a same-version or older release")
    parser.add_argument("--create", action="store_true", help="create the listing (first run only)")
    parser.add_argument("--id", type=int, default=None, help="listing id override for local tests")
    return parser.parse_args()


def main():
    args = parse_args()
    origin, listing_id = read_state()
    override = os.environ.get("HE_MOD_INDEX_URL", "")
    if override:
        if os.environ.get("GITHUB_ACTIONS") == "true":
            print("note: HE_MOD_INDEX_URL is ignored in Actions; the origin comes from scripts/index_listing.json.", file=sys.stderr)
        else:
            origin = override.rstrip("/")
    validate_origin(origin)
    if args.id is not None:
        if args.id < 0:
            fail("--id must be a non-negative integer.")
        listing_id = args.id
    if args.create and listing_id != 0:
        fail(f"--create is only for a checkout with no listing id; scripts/index_listing.json already has id {listing_id}.")
    if args.submit and listing_id == 0 and not args.create:
        fail("INDEX_UNCONFIGURED no listing id yet; rerun with --create once, then commit the id it prints.")

    tag, version = resolve_tag(args.tag)
    with tempfile.TemporaryDirectory(prefix="unfplap-index-") as work_dir:
        work = Path(work_dir)
        assets = fetch_release(work, tag, version)
        mod = read_mod(tag, version)
        listing = read_listing(origin, listing_id) if listing_id else None
        if listing is None:
            action, listed_version, approval, image_url = "create", "", "", ""
        else:
            action, listed_version = choose_action(
                listing, version, [asset["browser_download_url"] for asset in assets]
            )
            approval = str(listing.get("approval", ""))
            image_url = str(listing.get("image_url", "") or "")
        payload = build_payload(mod, version, assets, image_url)
        print_report(origin, listing_id, listed_version, approval, tag, version, action, payload)
        write_summary(origin, listing_id, listed_version, approval, tag, version, action, payload)
        write_outputs(tag, version, action, listing_id)

        if not args.submit:
            print(f"INDEX_PREVIEW_ONLY nothing was written to the index; rerun with --submit to {action}.")
            return

        submit_guard(action, listed_version, version, listing_id, args.force)
        if action == "create":
            created = create_listing(origin, payload)
            created_id = created.get("id")
            if not isinstance(created_id, int) or isinstance(created_id, bool):
                fail("INDEX_FAILED create returned no listing id.")
            print(f"INDEX_CREATED id={created_id} version={version}")
            print("The listing is unapproved until an index reviewer checks it.")
            print("Commit scripts/index_listing.json with:")
            print(json.dumps({"url": origin, "id": created_id}, indent="\t"))
            summary_line(f"- Result: `INDEX_CREATED` id `{created_id}`")
            return

        updated = update_listing(origin, listing_id, payload, mod, assets, version, args.force)
        updated_approval = str(updated.get("approval", "unknown"))
        print(f"INDEX_UPDATED id={listing_id} version={version} approval={updated_approval}")
        summary_line(f"- Result: `INDEX_UPDATED` approval `{updated_approval}`")
        if updated_approval != "current":
            print("A reviewer must approve the listing in the index.")


if __name__ == "__main__":
    main()
