---
name: Sync settings
description: Compare the local Unfplap profile with the shipped settings defaults and let the user promote or keep each difference. Use only when the user invokes /sync-settings.
metadata:
  opencode/autoinvoke: false
---

# Unfplap sync settings

Run from the mod repository root (`mods/unfplap`). This is a development tool for the local
profile, not a player feature. The player's `settings.json` and the anatomy placement are outside
the repository and are never committed.

`settings/defaults.json` is the one source of every declared setting's default. The command only
compares and then either promotes a value into that file or keeps the local value.

## 0. Preflight

- The game must be closed. The tool reads the player's profile and writes the tracked defaults;
  a live game may be halfway through a save.
- `git status --short` should be clean or contain only the files this run will touch. Stop and
  ask the user if unrelated work is present.
- `python3` must be on `PATH`. No Godot process is needed.
- If the command was given `--dry-run`, add it to the `promote` call and stop after the report.
- If it was given `--settings PATH`, pass it to every call.
- Never sync these paths: the list is `.opencode/skills/sync-settings/never_sync.json`
  (`debug_mode`, `debug_perf`, `anatomy.anatomy_mode`). The tool prints the names and refuses to
  promote them. The user can add paths.

## 1. Diff

The game materialises the merged defaults into the player's file when it loads, so launch it once
and close it before diffing; the tool does not run the migration itself.

```bash
tmp=$(mktemp -d /tmp/opencode/unfplap-sync.XXXXXX)
python3 scripts/settings_sync.py diff --project-root ../.. --json "$tmp/plan.json"
```

The report names the profile and the shipped document, then lists:

- `differences`: a shipped path where the player's value differs;
- `missing`: a shipped path the player's file does not have (the merge fills it; not a difference);
- `player-only leaves in code-owned blocks`: `default.*`, `characters.*` and per-mare placement
  rows. These are not in the shipped document yet and are not promotable;
- `unknown player leaves`: keys with no declaration. Report them; do not promote them.

## 2. Show the comparison

Show the report. Do not dump raw `plan.json`; summarize it. Keep long prompt text truncated in the
table and use the full value only in the question when needed.

## 3. Ask one question per difference

Use the OpenCode `question` API. One question object per `plan.json` `diffs` entry. Do not ask
about missing paths, code-owned leaves, unknown leaves or never-sync paths.

- Header: at most 30 characters, e.g. the path's last segment.
- Question: the full path, the player value and the shipped value.
- Options:
  - **Promote** — write the player's value into `settings/defaults.json`.
  - **Keep** — leave the shipped default and the player value alone.

Ask in one call when the list is small; chunk by top-level block when it is long. Every answer
still belongs to one path.

## 4. Apply the answers

```bash
python3 scripts/settings_sync.py promote <path> [<path> ...] --project-root ../..
```

- The tool writes the player's value into `settings/defaults.json` at each path and preserves the
  document's order and tab indentation.
- It never edits the player's profile: the player already has the value, and the merge keeps it.
- It refuses a never-sync path, a path the shipped document does not declare, a block path and a
  path the player does not have.
- A promoted default applies to fresh profiles and to keys the player does not have. A player who
  already has the old value keeps it; changing a materialised default is a migration, not a
  retroactive edit.

Add `--dry-run` to print the intended writes without touching the file.

## 5. Docs

Update the owning doc when the promotion changes a contract: `docs/settings.md` for a declared
setting, and the service doc (`docs/readiness.md`, `docs/summary.md`, `docs/poses.md`,
`docs/camera.md`, ...) when the setting belongs to that service. Docs name the setting and its
bounds, never the shipped value; a default lives only in `settings/defaults.json`.

## 6. Verify

```bash
python3 scripts/settings_sync.py diff --project-root ../..
scripts/check.sh --all
scripts/test.sh test_settings test_source_hygiene
scripts/test_all.sh
```

The second diff must show only kept differences, missing paths, code-owned leaves and never-sync
names. Unknown player leaves must be gone or reported. If the schema test fails, the shipped
document and the declarations disagree; fix the document, never the test's expectation.

## 7. Commit

Stage only the files the run changed: `settings/defaults.json` and the matching doc. Player
profile files are outside the repository. Use one commit per area touched:

- `settings: promote local defaults`
- `anatomy: promote local placement defaults` (phase 2, when placement rows move into the file)

Do not push.

Finish with:

- promoted paths;
- kept paths;
- missing paths and unknown leaves still present;
- never-sync names;
- tests run.
