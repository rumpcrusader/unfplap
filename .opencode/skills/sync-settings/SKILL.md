---
name: Sync settings
description: Compare the local Unfplap profile with the shipped settings data and let the user promote or keep each difference. Use only when the user invokes /sync-settings.
metadata:
  opencode/autoinvoke: false
---

# Unfplap sync settings

Run from the mod repository root (`mods/unfplap`). This is a development tool for the local
profile, not a player feature. The player's `settings.json` and `characters.json` are outside the
repository and are never committed.

Three shipped documents, two promotion targets:

- `settings/settings.json` — the declared settings. This is the player-settings document.
- `settings/characters.json` — the global `default` profile, the shipped per-mare profiles and the
  shipped per-mare placement rows. It is never written to a player file.
- `settings/prompts.json` — every prompt sent to a model. It is read-only here: the tool has no
  mode for it, and a prompt edit is a hand edit of the shipped file.

The player's data splits the same way: `settings.json` holds the declared settings and
`characters.json` beside it holds the profile differences, the per-mare overrides and the
per-mare placement rows. That second file is absent while the player has no character data.

The tool only compares and then either promotes a value into the matching document or keeps the
local value.

## 0. Preflight

- The game must be closed. The tool reads the player's profile and writes the tracked data; a live
  game may be halfway through a save.
- `git status --short` should be clean or contain only the files this run will touch. Stop and
  ask the user if unrelated work is present.
- `python3` must be on `PATH`. No Godot process is needed.
- If the command was given `--dry-run`, add it to every `promote` call and stop after the report.
- If it was given `--settings PATH`, pass it to every call.
- Never sync these paths: the list is `.opencode/skills/sync-settings/never_sync.json`. The tool
  prints the names and refuses to promote them. The user can add paths.

## 1. Diff

The game materialises the declared defaults into the player's `settings.json` when it loads, so
launch it once and close it before diffing; the tool does not run the migration itself.

```bash
tmp=$(mktemp -d /tmp/opencode/unfplap-sync.XXXXXX)
python3 scripts/settings_sync.py diff --project-root ../.. --json "$tmp/plan.json"
python3 scripts/settings_sync.py diff --characters --project-root ../.. --json "$tmp/characters.json"
```

The settings report names the profile and the shipped document, then lists:

- `differences`: a shipped settings path where the player's value differs;
- `missing`: a shipped path the player's file does not have (the merge fills it; not a difference);
- `character overrides`: player leaves under `default.*`, `characters.*` or a per-mare
  `anatomy.placement.<id>` row. They are promotable only with `--characters`;
- `unknown player leaves`: keys with no declaration and no character target. Report them; do not
  promote them.

The character report lists `character differences` (a character path where the player's value
differs from `settings/characters.json`) and `missing from the character file` (a promotable
override the shipped file does not have yet). A player without a `characters.json` reports no
differences.

## 2. Show the comparison

Show both reports. Do not dump raw JSON; summarize it. Keep long prompt text truncated in the table
and use the full value only in the question when needed.

## 3. Ask one question per difference

Use the OpenCode `question` API. One question object per settings `diffs` entry and per character
`diffs` entry. Do not ask about missing paths, character overrides the user does not want to
promote, unknown leaves or never-sync paths.

- Header: at most 30 characters, e.g. the path's last segment.
- Question: the full path, the player value and the shipped value.
- Options:
  - **Promote** — write the player's value into the matching shipped document.
  - **Keep** — leave the shipped value and the player value alone.

Ask in one call when the list is small; chunk by top-level block when it is long. Every answer
still belongs to one path.

## 4. Apply the answers

```bash
python3 scripts/settings_sync.py promote <path> [<path> ...] --project-root ../..
python3 scripts/settings_sync.py promote --characters <path> [<path> ...] --project-root ../..
```

- Settings paths go to `settings/settings.json`; character paths go to `settings/characters.json`.
- A character path is `default.*`, `characters.<id>.*` or `anatomy.placement.<id>.*`. The tool
  reads the player value from the player's `characters.json` at the same path. It creates a missing
  block or key.
- `settings/prompts.json` is never a promotion target; the tool has no mode for it.
- The tool preserves the document's order and tab indentation.
- It never edits the player's profile: the player already has the value, and the merge keeps it.
- It refuses a never-sync path, a settings path the shipped document does not declare, a block
  path and a path the player does not have.
- A promoted default applies to fresh profiles and to keys the player does not have. A player who
  already has the old value keeps it; changing a materialised declared default is a migration, not
  a retroactive edit. A promoted character value reaches every player who did not override it.

Add `--dry-run` to print the intended writes without touching the file.

## 5. Verify the shipped data

```bash
python3 scripts/settings_sync.py diff --project-root ../..
python3 scripts/settings_sync.py diff --characters --project-root ../..
scripts/check.sh
scripts/test.sh test_settings
scripts/test.sh
```

The second diff must show only kept differences, missing paths, character overrides and never-sync
names. Unknown player leaves must be gone or reported. If the schema test fails, the shipped
document and the declarations disagree; fix the document, never the test's expectation.

## 6. Commit the shipped data

Stage only the shipped document the run changed. Player profile files are outside the repository.
Use one commit per area touched:

- `settings: promote local defaults`
- `settings: promote local character values`

Do not stage the doc yet.

## 7. Docs

After the data commit, update the owning doc when the promotion changes a contract:
`docs/settings.md` for a declared setting or a character profile,
`docs/poses.md` for a pose default and `docs/anatomy.md` for a placement row. A prompt value has
no promotion path: `settings/prompts.json` is edited by hand and owned by the settings service. Docs
name the setting and its bounds, never the shipped value; a default lives only in the shipped
document.

Run `scripts/check.sh` and, when `docs/api.md` changed, `scripts/test.sh test_api`. Commit
the doc in its own `docs:` commit:

- `docs: describe the promoted settings`

Do not push.

Finish with:

- promoted paths and their target document;
- kept paths;
- missing paths and unknown leaves still present;
- never-sync names;
- tests run.
