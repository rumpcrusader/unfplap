---
name: Sync settings
description: Compare the local Unfplap profile with the shipped settings defaults and let the user promote or keep each difference. Use only when the user invokes /sync-settings.
metadata:
  opencode/autoinvoke: false
---

# Unfplap sync settings

Run from the mod repository root (`mods/unfplap`). This is a development tool for the local
profile, not a player feature. The player's `settings.json` and the anatomy placement are
outside the repository and are never committed.

`settings.gd` remains the one source of shipped defaults. The command only compares and then
either promotes a value into the matching source default or keeps the local value.

## 0. Preflight

- The game must be closed. The analyzer refuses to write while a Godot process has this project
  open.
- `git status --short` should be clean or contain only the files this run will touch. Stop and
  ask the user if unrelated work is present.
- `godot` and `python3` must be on `PATH`.
- Never sync these paths: the list is `.opencode/skills/sync-settings/never_sync.json`
  (`debug_mode`, `debug_perf`, `anatomy.anatomy_mode`). Print the names on every run. The user can
  add paths; `version` and `ui.sections` are structural and always skipped.

## 1. Snapshot the shipped defaults

```bash
tmp=$(mktemp -d /tmp/opencode/unfplap-sync.XXXXXX)
mkdir -p "$tmp/snapshot"
XDG_DATA_HOME="$tmp/snapshot" godot --headless --xr-mode off --path ../.. \
  --script res://mods/unfplap/tools/settings_snapshot.gd > "$tmp/snapshot.log" 2>&1
grep '^SETTINGS_SNAPSHOT ' "$tmp/snapshot.log" | sed 's/^SETTINGS_SNAPSHOT //' > "$tmp/snapshot.json"
```

The snapshot is authoritative: it reads the current `settings.gd`, `PREFERENCES.DEFAULTS`,
`poses/catalog.gd`, `character_preferences.gd`, `anatomy_placement.gd` and
`SETTINGS.DEFAULT_ACT_PROMPTS`.

## 2. Migrate and analyze

```bash
python3 .opencode/skills/sync-settings/analyze.py --project-root ../.. \
  --snapshot "$tmp/snapshot.json" --migrate --apply-dead --prune-redundant \
  --json-out "$tmp/plan.json"
```

This step:

- backs up `settings.json`, `anatomy_place.json` and `anon_place.json` before writing;
- runs the schema migration and the one-time placement import;
- removes dead player keys and reports their names;
- removes redundant placement rows that already resolve to the shipped default;
- reports source dead keys separately (fix those in the template, not the player file);
- prints `never synced: …`;
- writes the machine-readable `plan.json`.

If the user only wants to inspect, use `--dry-run`; it writes nothing.

## 3. Show the comparison

Show the report: profile, schema, never-sync names, dead keys, source dead keys, every difference
with player value, shipped value and source location, and the placement groups. Do not dump raw
`plan.json`; summarize it. Keep long prompt text truncated in the table and use the full value
only in the question when needed.

## 4. Ask one question per difference

Use the OpenCode `question` API. One question object per `plan.json` `diffs` entry and per
`placement_groups` entry. Do not ask about dead keys, source dead keys or never-sync paths.

- Header: at most 30 characters, e.g. the setting label or short path.
- Question: the full path, the player value, the shipped value, and the source.
- Options:
  - **Promote** — write the player's value into the shipped default.
  - **Keep** — leave the source and the player value alone.

For a placement group:

- `GLOBAL DEFAULT` (the largest group of three or more mares): Promote writes the group values
  into the five `anatomy.placement.default.*` declarations.
- `PER-MARE DEFAULTS`: Promote writes the group values into `MARE_DEFAULTS` in
  `anatomy_placement.gd` as partial diffs.

Ask in one call when the list is small; chunk by area (General, Anatomy, World, default,
characters, placement) when it is long. Every answer still belongs to one path or one group.

## 5. Apply the answers

### Global settings

Edit the declaration default in `settings.gd` at the reported line. Keep the declaration's style,
units and bounds. Do not change the player value.

### `default.*`

- `default.preferences.*` → `preferences.gd` `DEFAULTS`
- `default.act_prompts.*` → `settings.gd` `DEFAULT_ACT_PROMPTS`
- `default.poses.*` → `poses/catalog.gd` `POSE_DEFAULTS`
- `default.smack_zone_radius` / `aftercare_min` / `cue_gap` / `event_prompts` →
  `settings.gd` `DEFAULT_TEMPLATE`

### `characters.<id>.*`

Edit that mare's block in `character_preferences.gd` `TEMPLATES`. Preserve custom
`event_prompts`, `poses`, `consent` and `act_prompts` keys. Do not reset the rest of the template.

### Placement

- **Global group**: first change the five `anatomy.placement.default.*` declarations to the group
  values, then update the local profile's global default and drop the now-redundant rows:

  ```bash
  python3 .opencode/skills/sync-settings/analyze.py --project-root ../.. \
    --snapshot "$tmp/snapshot.json" \
    --set-placement-default '<group values JSON>' \
    --drop-placement-ids '<comma-separated ids>'
  ```

  This is the one promoted case that changes a live player value, because the old global default
  would otherwise keep overriding the new source default.

- **Per-mare group**: add or merge the group's partial `diff` into
  `anatomy_placement.gd` `MARE_DEFAULTS`, then drop the player's rows:

  ```bash
  python3 .opencode/skills/sync-settings/analyze.py --project-root ../.. \
    --snapshot "$tmp/snapshot.json" --drop-placement-ids '<comma-separated ids>'
  ```

  If a global group was also promoted, compare the per-mare values against the new global
  default, not the old one.

- **Keep**: leave the source and the player rows alone.

### Docs

Update the matching contract text in `AGENTS.md` and, when the value is stated there,
`TUNING.md`/`PREFERENCES.md`/`HISTORY.md`. `README.md` changes only if the player-facing
FEATURES or CONTROLS wording changes. Do not leave an old default in the docs.

## 6. Verify

```bash
python3 .opencode/skills/sync-settings/analyze.py --project-root ../.. \
  --snapshot "$tmp/snapshot.json" --dry-run
scripts/check.sh --all
work=$(mktemp -d /tmp/opencode/unfplap-settings.XXXXXX)
XDG_DATA_HOME="$work" godot --headless --xr-mode off --path ../.. \
  --script res://mods/unfplap/tests/test_settings.gd
scripts/test_all.sh
```

The second analysis must show only kept differences and never-sync paths. Dead keys and
redundant placement rows must be gone. If source dead keys remain, report them; do not silently
edit a template.

## 7. Commit

Stage only the files the run changed. Player profile files are outside the repository. Use one
commit per area touched:

- `settings: promote local defaults`
- `settings: promote local character defaults`
- `anatomy: promote local placement defaults`

Include the contract docs in the matching commit. Do not push.

Finish with:

- promoted paths;
- kept paths;
- dead keys removed;
- source dead keys still present;
- never-sync names;
- backup paths;
- tests run.
