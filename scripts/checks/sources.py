"""The source-tree invariants that are not an act, body, release or entry rule."""
from __future__ import annotations

import re

from .act import check_act
from .body import check_body
from .context import ROOT, SERVICES, facade_for, read_text, shipped_sources
from .docs import doc_path
from .failure import Failure, rel
from .release import check_release

SETTINGS_DECLARATION = re.compile(
    r"^\s*static var \w+.*:=\s*(?:flag|num|choice|list|color)\(", re.MULTILINE)

# The base mechanism never names the installed provider's characters or its mesh marker. The
# provider and its policy are the only source files that may; the base roster catalog names a
# base-game mare and is game data, not integration vocabulary.
CHANGELINGS_VOCAB = re.compile(
    r"chrysalis|shoeshine|queen_chrysalis|chrysalis_own", re.IGNORECASE)
CHANGELINGS_SOURCE = "integrations/changelings"
CHANGELINGS_CATALOG = {"shared/character_preferences.gd"}


def check_sources(failure: Failure) -> None:
    check_act(failure)
    check_body(failure)

    # The base mechanism never names the installed provider's characters or its mesh marker.
    for path in shipped_sources():
        name = rel(path)
        if name.startswith(CHANGELINGS_SOURCE) or name in CHANGELINGS_CATALOG:
            continue
        match = CHANGELINGS_VOCAB.search(read_text(str(path)))
        if match:
            failure.add("%s names changelings vocabulary outside its provider: %s" % (
                name, match.group(0)))

    check_release(failure)

    # One settings declaration module, one facade per assignment and no root composition shim.
    settings = read_text(str(ROOT / "settings" / "api.gd"))
    if "static func all_settings() -> Array[Setting]" not in settings:
        failure.add("settings/api.gd must expose all_settings() -> Array[Setting]")
    declaring: list[str] = []
    for path in shipped_sources():
        source = read_text(str(path))
        if SETTINGS_DECLARATION.search(source):
            declaring.append(rel(path))
        # `act/settings.gd` is the act's snapshot owner, not a declaration module: it holds the
        # one bulk copy of the act tunables and the live apply. Any other `settings.gd` outside
        # `settings/` is a second declaration surface.
        if path.name == "settings.gd" and path.parent.name not in ("settings", "act"):
            failure.add("no per-service settings module: %s" % rel(path))
    if declaring != ["settings/api.gd"]:
        failure.add("only settings/api.gd may declare settings (found %s)" % declaring)
    for name in ("settings_page.gd", "settings_layout.gd"):
        if (ROOT / name).exists():
            failure.add("no root settings composition file: %s" % name)

    # A service contract names its facade. The index row owns the contract and test router.
    for sid in SERVICES:
        path = doc_path(sid)
        if not path.exists():
            continue
        text = path.read_text(encoding="utf-8")
        if f"{sid}/{facade_for(sid)}" not in text:
            failure.add("docs/%s.md does not name %s/%s" % (sid, sid, facade_for(sid)))
