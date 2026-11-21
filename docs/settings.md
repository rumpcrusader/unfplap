# Settings: one declaration, one shipped default, one accessor

Every global setting in the mod is declared **once**, in `settings/service.gd`, and read through a
typed accessor on that setting. The declaration owns the JSON path, label, help, tab, group,
bounds and options; the **default value lives in `settings/settings.json`**, never in the
declaration or in a second constant. There is no path-keyed read outside the settings service.

Three shipped documents and two player documents divide the data by kind:

| Document | Path | Writer | Contents |
|---|---|---|---|
| Shipped settings | `res://mods/unfplap/settings/settings.json` | git, read-only | the default value of every declared setting |
| Shipped characters | `res://mods/unfplap/settings/characters.json` | git, read-only | the global `default` profile, the per-mare profiles and the per-mare placement rows |
| Shipped prompts | `res://mods/unfplap/settings/prompts.json` | git, read-only | every prompt sent to a model; `docs/prompts.md` |
| Player settings | `user://mods/data/unfplap/settings.json` | the mod | the same declared settings plus `version` and `ui.sections` |
| Player characters | `user://mods/data/unfplap/characters.json` | the mod | the profile differences, the per-mare overrides and the placement rows; absent while the player has no character data |

The shipped settings document is a valid settings document; the player settings document is that
document with edits. Nothing else supplies the default of a declared setting. The characters
document is content rather than settings: its `default` block is the profile a mare starts from,
its `characters` block holds the shipped per-mare profiles, and its `anatomy.placement` block holds
the shipped placement rows. The prompts document is read by the modules listed in
`docs/prompts.md` and is never part of a player file.

The General, Anatomy, Poses and World panels are drawn from the declarations by `settings/ui.gd` in
the settings page's own menu style: row cards, `Faint` help, switch plus state, Segment pills for a
few short choices and the `Tab` look for a collapsible section heading. The tab pills, sidebar row,
the hand-built Characters preference tab, the catalog-driven Integrations tab and the debug-only
Poses tab are added by the injection in `settings/ui.gd`. The sidebar row is appended at the foot
of the sidebar, below the game's **More** group, with a heart icon. The Characters form itself is
in `settings/characters_ui.gd`; the consent and participation semantics are in
`docs/eligibility.md`; the supported-mod catalog is `shared/integrations.gd`.

> If you are about to write a `SpinBox`, `CheckButton`, `OptionButton`, a default constant, a
> restore/normalise function or a save function for a setting, stop. Declare the setting and add
> its one value to `settings/settings.json` instead.

Per-character profiles (`default`/`characters` profiles, preferences, consent) and the pose
catalog overrides (`poses.*`) are not global settings: they live in `settings/characters.json` and
the player's `characters.json`, and are read through `SETTINGS.preferences(id)`,
`SETTINGS.pose(id, pose_id)` and the other profile functions.
The identity facts discovery scans read (`SETTINGS.profile_identity(id)`) are memoized per settings
generation and provider registry revision, so a scan does not rebuild the whole template per mare.
The resolved consent block (`SETTINGS.consent(id)`) is memoized on the same two keys and returns a
detached copy, so an act gate pays a lookup instead of a template build.

## Ownership

`settings/service.gd` owns the declaration catalog, the shipped-data loaders, both player files,
the merge, the typed accessors and the per-mare profiles. `settings/settings.json`,
`settings/characters.json` and `settings/prompts.json` are shipped data, not code: they are tracked,
packed, read-only in a build and parsed once per process. The catalog is the settings service's
internal public API: a service contributes a setting with a literal declaration there, one value in
the shipped settings document, and then reads the typed handle.

`settings/ui.gd` is the only file that draws the declaration rows; it also owns the settings-page
injection and the Debug block visibility. `settings/characters_ui.gd` is the interim home of the
Characters form. The entry keeps the `Mods` hook to the settings page, the construction bindings the
page and the log sink read, and the one guard that refuses to install the mod when the shipped
document is invalid. An edit reaches the services through the change notification below, never
through the entry. The act session takes the settings service's typed `ActSnapshot` in
`act/session.gd:snapshot_settings()`; the settings file never reads a live act.

## Contributing a setting

1. Add the declaration in `settings/service.gd`, in the tab and group where the player should see
   it, with its one- or two-line `##` description above it. The declaration owns the path, label,
   help, bounds, options and debug flag — not the value.
2. Add the same dotted path to `settings/settings.json` with its default value. The schema test
   fails when a declaration and the shipped document disagree.
3. Depend on `settings/service.gd` and use the typed handle; do not restate the row in the owning
   service's doc.

There is no `<service>/settings.gd` module, no registration call and no second layout list. The
catalog order is the panel order. A setting whose value cannot be one of the generic widgets is
declared hidden and drawn by hand in `settings/ui.gd`; `act_key` (a physical-key capture) is the
player-facing example, and the anatomy placement target is the hidden debug one.

## Reading and writing

```gdscript
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")

if SETTINGS.mute_ponese_audio.get_bool(): ...
var raise_m: float = SETTINGS.raise_m.get_num()
var orientation: String = SETTINGS.orientation.get_choice()
var ignored: Array = SETTINGS.ignore.get_list()
var snapshot := SETTINGS.act_snapshot("missionary")   # typed per-act snapshot, see below

SETTINGS.raise_m.set_num(0.25)
SETTINGS.orientation.set_choice("down")
SETTINGS.radius.reset()
```

| Kind | Declaration | Accessors |
|---|---|---|
| flag | `flag(...)` | `get_bool()`, `set_bool(v)` |
| number | `num(...)` | `get_num()`, `set_num(v)` |
| choice | `choice(...)` | `get_choice()`, `set_choice(v)` |
| list | `list(...)` | `get_list()`, `set_list(v)`, `toggle(item)` |
| colour | `color(...)` | `get_color()`, `set_color(v)` |

Every setting also has `get_value()`, `set_value(v)`, `reset()`, `name`, `path`, `label`, `help`,
`tab`, `group`, `default` and `debug`. `default` is the shipped value the declaration bound at
start-up; `reset()` writes it back.

A wrong accessor does not compile: `SETTINGS.mute_ponese_audio.get_num()` is a parse error, and so is a
mistyped name. That is the main safety net; the tests only cover what the compiler cannot see.

**Per-act snapshot.** `SETTINGS.act_snapshot(group)` returns one typed `ActSnapshot` with every
value an act reads per stroke or per frame: the feature dictionary, thrust, auto stroke, cue/talk
pacing, jiggle, camera thrust, the presentation block for that settings group and the climax face.
The act session takes it in `act/session.gd:snapshot_settings()` with the start spec's
`settings_group` and re-runs it in `apply_live_settings()`. An internal pose (`standing_test`,
`standing_oral`) shares the standing group and has no `presentation` block or `default.poses` row
of its own. There is no path-keyed read outside the settings service and no second cache. The
session owns the snapshot and consumers read `snapshot.<value>` at the use site: `snapshot_settings()`
is its only writer, a consumer indexes the complete snapshot block, and no second field copies a
snapshot scalar.

## Adding a setting: one declaration, one shipped value, one read

1. **One declaration, where it should appear in the panel, with the row's one description.**

   ```gdscript
   ## Hand lift at the top of the wind-up, scaled by the hand's smack body scale.
   static var raise_m := num("raise_m", "presentation.standing.smack.raise_m", "Max raise",
       "Hand lift at the top of the wind-up.", POSES, "Standing › Smack") \
       .with_unit("cm").with_step(0.5).with_scale(100.0).as_debug()
   ```

   The `##` block is one or two lines and says what the setting is and what its hint does not: who
   reads it, when an edit lands, or what a boundary value does. It is the only place that
   description lives — no `.md` restates the row.

2. **One value in the shipped document.** Add `raise_m` under `presentation.standing.smack` in
   `settings/settings.json`. The nesting mirrors the dotted path; the value's JSON type must match
   the declaration kind. Do not add a second copy anywhere.

3. **One typed read at the use site.**

   ```gdscript
   var raise_m: float = SETTINGS.raise_m.get_num()
   ```

4. **Run `scripts/test_all.sh`.** It checks the registry, the shipped document's schema, the file
   round-trip, coercion and that the panel draws every declaration.

Nothing else exists to update: the widget, unit, save, persistence and placement all come from the
declaration; the value comes from the shipped document; the description is the comment above it.

## Declaration reference

```gdscript
flag(n, path, label, help, tab, group)
num(n, path, label, help, tab, group)
    .with_unit("cm") .with_step(0.5) .with_scale(100.0) .with_range(low, high) .with_slider()
choice(n, path, options, labels, label, help, tab, group)
list(n, path, options, label, help, tab, group)
color(n, path, label, help, tab, group)
    .as_debug() on any kind
    .as_hidden() on any kind
```

| Argument | Meaning |
|---|---|
| `n` | the identifier, `SETTINGS.<n>` |
| `path` | the path in both the shipped and the player document; the only string, and it lives here |
| `label`, `help` | the row text and the line under it. A boolean label starts with a verb (Show, Allow, Use, Play, Print, Hide, Pin, Sway, Twitch, Remember, Mute); a choice or number keeps its noun |
| `tab` | `GENERAL`, `ANATOMY`, `POSES` or `WORLD` |
| `group` | the panel section; `"Standing › Smack"` is a subheading under `Standing`. A group needs at least 3 related settings: fewer, and pass `""` so the setting sits in the tab with no heading (a small subgroup merges into its parent). A pose feature flag left in General keeps its old pose group even when Poses took the rest of the section |
| `options`, `labels` | the accepted values and their display text for a choice or list |
| `with_unit`, `with_step`, `with_scale` | display unit, spin step and display multiplier (`m` shown as `cm` = `100`) |
| `with_range` | the player-facing contract bounds; a debug row uses them only as its spin-box span and is never clamped |
| `with_slider` | draw a themed HSlider instead of a spin box |
| `as_debug` | show it in the tab's Debug block only, and never clamp it |
| `as_hidden` | keep it out of the declaration rows; a hand-built `settings/ui.gd` control (the placement target pill) owns the widget |

Declarations render **in file order**, and a section is created where it first appears. Put a line
where a player would look for it, next to the setting it belongs to; do not add a "misc" section.

## Naming

The identifier is the JSON path's last segment: `thrust.travel` → `travel`,
`features.mute_ponese_audio` → `mute_ponese_audio`. Only on a collision with another setting does it gain the parent
segment as a prefix (`jiggle.intensity` → `intensity`; a second `intensity` would become
`jiggle_intensity`). Keep names short; the panel group carries the context. Do not add group
prefixes pre-emptively.

## Clamping

- A player-facing `num` clamps to `with_range(low, high)`. That bound is part of the contract, so it
  is the only clamp a consumer may rely on: sensitivity, hip back-off, auto pace/depth, camera
  surge/bob, glance-back speed, genital tone.
- A debug number (`.as_debug()`) is stored and returned **verbatim**; `with_range` only shapes the
  spin box, and a debug row that needs the full range should omit it. Moving a setting to or from
  debug is the `as_debug()` call alone.
- Moving a debug setting to player-facing starts clamping its stored value. Check the saved range
  when you do it.
- Do not add a clamp in a consumer "to be safe". If a value must stay playable, give it
  `with_range` and say why in its help text.
- `choice` ignores an unknown string and `list` drops unknown options. That is validation, not
  clamping. A non-finite number falls back to the shipped default.

## Tabs, groups and debug

- Tabs, in panel order: **General** (interface, audio, cycle, thrust, act tuning), **Anatomy**,
  **Poses** (the two pose switches and the pose tuning page), **World** (relationships, cycle,
  witnesses, pony behaviour), **Characters** (the per-mare form) and **Integrations** (supported
  mods and their switches).
- **Poses** is injected after Anatomy and is always in the bar. Its player rows are **Enable Oral**
  and **Enable Anal**, with no heading. The `presentation.missionary.*` and `presentation.standing.*`
  tuning rows live in the tab's Debug block, so they still need **Enable debug**; the JSON paths and
  values do not move. A `features.*` flag that belongs to a pose section is a Poses row in that
  section. General keeps `presentation.act.climax_mode`.
- General opens with the **Act Key** capture row. Its `act_key` declaration is a hidden numeric
  setting (a physical keycode) because a key capture is not one of the declaration widgets;
  `settings/ui.gd` draws the row by hand. It still has no section heading.
- Player-facing settings come first in their tab. When **Enable debug** (General's last row) is
  on, the tab ends with one **Debug** section holding that tab's debug settings under the same
  group names. A section name draws one heading; interleaved declarations fold back into it.
- Every section remembers whether it is open in the player file under `ui.sections`, keyed
  `tab/group`; the Debug block and its subsections use the `Debug/` prefix. Read and write that
  state through `SETTINGS.section_open(tab, group)` and `SETTINGS.set_section_open(tab, group, open)`.

## Change notification

Every edit ends in one pass, and that pass is the only way a settings change reaches a service.
`shared/settings_change.gd` holds one static listener list — GDScript has no static signals — and
`SETTINGS.apply_live()` notifies it:

```gdscript
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const CHANGE := preload("res://mods/unfplap/shared/settings_change.gd")

CHANGE.on_changed(Callable(self, "apply_settings"))    # construction
CHANGE.off_changed(Callable(self, "apply_settings"))   # shutdown
SETTINGS.apply_live()                                  # one pass, after the value is written
```

| Rule | Meaning |
|---|---|
| One pass | `SETTINGS.apply_live()` is the edit's one notification; no service fans an edit out and the entry never relays one |
| Registration order | listeners are called in the order they registered, which is the construction order of the service list |
| One place per callable | the same callable registered twice keeps one place; an empty or freed callable is never registered |
| A release is free | `off_changed()` drops the place; a listener that is freed without leaving is dropped on the next pass instead of called |
| Safe mid-pass | a listener that leaves during the pass is not called in that pass |

The subscribers, in construction order: `log` (the two debug switches, through the reads the entry
binds), `hud` (the act-key cap and the caption mode), `offer`, `input` (the act action and the
shield), `anatomy` (the player part, every live controller and the tail seats), `body_change` (the
source's tail wrapper for every live body), `pantyhose`, `stock_smack`, `ponies` (every runtime, and
the act a pending body swap has taken out of the registry), the debug actions (the wheel and the
skeleton overlay) and the settings UI (the Debug blocks). `stool`, `initiation` and `negotiation`
read their settings live and subscribe to nothing.

`api.gd`, `eligibility.set_profile()` and a provider's settled body change call
`SETTINGS.apply_live()` too: a provider layer is a live input like a panel edit. The list lives in
`shared/` rather than in `settings/service.gd` because a shared module may not import a service and
the log sink joins the same list.

## Persistence, defaults and migration

- `settings/settings.json` is the only source of a declared setting's default. It is tracked,
  packed and read-only in a build. `_bind()` reads one value per declaration at static
  initialisation, so the shipped settings document is process-static: `SETTINGS.reload_file()`
  reloads only the two player files.
- `settings/characters.json` holds the content the profile resolution reads: the global `default`
  block (the profile, its preferences and the pose defaults), the shipped `characters.<id>`
  profiles and the shipped per-mare `anatomy.placement.<id>` rows. It is tracked and read-only too.
  `settings/prompts.json` holds every prompt and is owned by `docs/prompts.md`.
- `shared/defaults_data.gd` is the one parser for all three documents: `document()`,
  `characters()` and `prompts()`, each parsed once per process, plus `settings_block()`,
  `characters_block()` and `prompts_block()` for a detached block. It preloads nothing, so the pure
  modules (`preferences`, `pose_catalog`, `character_preferences`, `prompt_text` consumers) and
  `settings/service.gd` read it without a cycle.
- `SETTINGS.defaults()` returns the base a fresh profile starts from: the shipped declared
  settings, the one block that still lives in code (`ui.sections`) and the shipped `default`
  profile, detached and with no player values. `SETTINGS.data()` returns that base with the
  player's declared settings, `default` differences, `characters` overrides and placement rows
  merged on top, detached. These are the only two public loaders; `_shipped()`, `_characters()`
  and `_filled_default()` are internal.
- On mod load, the entry's `_ready()` calls `SETTINGS.load_settings()` before any getter: both
  player files are parsed, the character data is imported and migrated, the result is merged over
  the defaults (the player wins, and an absent player key is filled from the default) and written
  back once. Declared settings are therefore materialised in `settings.json` on first run.
  **A changed shipped declared default is a migration event for an existing player**: their
  materialised value keeps winning. Promote a player value into the shipped document with
  `scripts/settings_sync.py`; see `.opencode/skills/sync-settings/SKILL.md`.
- `scripts/settings_sync.py diff` compares the player's `settings.json` with
  `settings/settings.json`; `diff --characters` compares the player's `characters.json` with
  `settings/characters.json` (the `default` differences, the per-mare overrides and the per-mare
  placement rows). The settings report lists character-only player leaves as overrides promotable
  with `--characters`. `promote` and `promote --characters` write into the matching document and
  never touch a player file; `prompts.json` has no mode.
- The `default` profile is resolved at read time from the shipped characters document, then the
  provider layers, then the player's saved differences. The player file stores only the
  differences the player made, so a changed shipped profile or a cross-mod provider layer reaches
  every player who did not override it. The per-mare `anatomy.placement` rows work the same way: a
  row equal to the resolved default is never written, and a `default` or `anon` row is a declared
  setting, never a character row.
- A player file with absent keys is filled from the defaults; the merge never requires every key.
  A player file that cannot be read, is empty, is not a JSON object, or was written by a newer
  schema is preserved as `<path>.<timestamp>.invalid` (for example
  `settings.json.20261114-155724.invalid`), logged with the original and backup paths, and replaced
  by a fresh document built from the shipped defaults. Hand-editing is still unsupported; the
  backup is the recovery path. The two files are checked separately, so a bad `characters.json`
  does not discard `settings.json`. A missing or malformed value in `settings/settings.json` or
  `settings/characters.json` is a **shipped-data** error: `_shipped()`/`_characters()` log the first
  problem, `defaults()` and `data()` return an empty document, `_load()` refuses to write and the
  entry's `_ready()` logs one line and installs no hooks. The game keeps running.
- The schema test `_check_shipped_defaults()` enforces the exact declared path set on
  `settings/settings.json` (every declaration has a value and there is no undeclared path), the
  exact JSON type per kind, a choice/list value inside its declared options, a colour in
  `rrggbb`/`rrggbbaa` form and a player-facing number inside its declared bounds. It never asserts
  a value, so changing a shipped default does not touch the test. `_check_characters()` does the
  same for `settings/characters.json`: the global `default` block (its three numbers, the
  `PREFERENCES.KEYS` preference schema and the `CATALOG.POSE_KEYS` pose schema), every roster
  profile against `REGISTRY.TEMPLATE_KEYS`, and the per-mare placement keys. `tests/test_prompts.gd`
  is the graph check for `settings/prompts.json`.
- `default.*` is not a declared setting and is no longer in the shipped settings document. The
  schema test reads it from the characters document as a block and excludes it from the declared
  path set.
- The old `controls.act_key` choice strings (`o`, `y`) are converted to physical keycodes on load;
  `ACT_KEYS.DEFAULT_CODE` is only the legacy/invalid-code fallback, not the shipped default.
- `anatomy.placement` is one block with `default.*` (the global default: its declarations are
  hidden, and only the Placement actions write them), `anon.*` (the player part's visible
  Debug rows) and partial `<mare id>.*` overrides. The shipped per-mare rows (the tuned tail/dock
  values) live in `settings/characters.json` under `anatomy.placement`; `shared/anatomy_placement.gd`
  owns the schema and resolves override, provider, shipped row, then global default. Only a row
  that differs from that resolved default is stored, in the player's `characters.json`. The old
  `anatomy_place.json` and `anon_place.json` import once and are renamed `.migrated`. The old
  `anatomy.tail_seat.<id>` rows and the tail/dock millimetre globals migrate into the same block on
  load.
- `anatomy.dock_style` and the tail/dock placement behavior are in `docs/anatomy.md`. The
  settings layer owns only its path, default and the placement migration above.
- `settings/service.gd` owns both player files. `SETTINGS.load_settings()` parses them once per
  process into `_cache` and writes the merged result; the typed getters only read the
  generation-cached flat table, so a per-frame read never touches the disk.
  `SETTINGS.reload_file()` resets both loaded flags, bumps the generation once and re-reads both
  files immediately; the settings page calls it when it opens.
- A write goes `Setting.set_value()` → `_store()` → `_sanitize()` → `_write_path()` → `_write()` →
  `_write_files()`. The settings document is the merged view with `default`, `characters` and the
  per-mare placement rows removed; the characters document is the `default` difference, the
  `characters` overrides and the per-mare rows, each file carrying `version`. A player with no
  character data has no `characters.json`. Each file is written through a temporary file and a
  rename, falling back to a direct write; the pair is not atomic, and the next write rebuilds both
  from the one in-memory view. When a route fails it logs the path and both errors; `_write()` adds
  that the new value is live in memory but was not saved. The live cache keeps the edit either way.
- **Migrations.** `version` is the schema of the pair. `_migrate()` runs the `deprecated()` entries
  and erases `RETIRED_PATHS` on every file, then the one version-gated step: `_migrate_to_11()`
  drops the prompt overrides and reduces a saved character block to real differences. The split
  itself runs before the migration: `_import_player()` reads a schema-10 document's `default` and
  `characters` blocks and its per-mare placement rows into the character document and erases them
  from the settings document; a present `characters.json` always wins over the old copies, and the
  recovery is logged. `_normalize_anatomy_placement()` runs on every load, so a legacy placement
  file that appears later still imports. A file older than schema 10 keeps its old keys and those
  settings fall back to their defaults; that data loss is accepted. When a migration actually
  changes the player document, `_load()` logs the schema change and the concrete changed, added and
  removed leaf paths; a fresh profile and a current file stay silent. The log runs before the
  defaults merge, so materialising a default is not reported as a migration.
- **Deprecations.** Declare a retired setting next to its replacement:

  ```gdscript
  static var _deprecated := [
      deprecated("anatomy.genital_yaw_deg", func(_value): return {}),
      deprecated("cues.old_override_seconds", func(value): return {"cues.override_seconds": value}),
  ]
  ```

  The loader reads the old path once, merges the returned dictionary and erases the old key, so a
  retired setting cannot linger in the file. `RETIRED_PATHS` lists the keys the mod no longer reads
  at all; they are erased on load so an ignored key cannot persist forever.
- `history.*` holds the act-history score weights, thresholds, decay and offer weighting; the
  contract is `docs/summary.md`. `tolerance.*` holds the mid-act warning/stop thresholds; the tier
  itself is a per-mare `preferences.tolerance`, not a global setting.
- Prompt text is not a setting and has no override: `settings/prompts.json` is the only copy, and
  `docs/prompts.md` owns it. The **Reset act prompts** action is gone with the overrides.
- `characters.<id>.profile` is a sparse per-mare participation layer. `profile.participation` holds
  `acts` and `anatomy`; the deprecated `tail` key is still accepted and returned but no capability
  reads it, and the Characters form has no Tail row. Only differences from the resolved default are
  stored. A provider's
  `eligible` assertion is top-level and never a player value, because a player cannot age a
  character up. The `characters` block is the same per-mare block as the preference, consent and
  pose overrides.
- Unknown keys are ignored on load.
- Never name a settings API function after a `Script`/`Object` built-in (`reload`, `set_path`,
  `get`, `set`): a preloaded script constant resolves the built-in instead. `tests/test_settings.gd`
  guards this.

## Settings file shape

Shipped settings: `res://mods/unfplap/settings/settings.json`. One nested block per dotted path and
one value per declared setting; no `version`, no `ui`, and no profile or prompt block.

Shipped characters: `res://mods/unfplap/settings/characters.json`:

```json
{
	"default": {"preferences": {...}, "poses": {...}, "cue_gap": ...,
		"aftercare_min": ..., "smack_zone_radius": ...},
	"characters": {"<mare id>": {"preferences": {...}, "poses": {...}}},
	"anatomy": {"placement": {"<mare id>": {...}}}
}
```

`default` is the whole block a fresh profile starts from; `characters` holds each mare's shipped
profile as an overlay on it, and `anatomy.placement` the shipped placement rows. There is no
`version`, no `act_prompts`, no `event_prompts` and no `character_templates` key.

Shipped prompts: `res://mods/unfplap/settings/prompts.json`, the prompt document in
`docs/prompts.md`; `version` plus one group per feature.

Player settings: `user://mods/data/unfplap/settings.json`
(`~/.local/share/home-equestria-public/mods/data/unfplap/settings.json`). The declared blocks plus
`version`, `ui.sections` and the `default`/`anon` `anatomy.placement` rows.

Player characters: `user://mods/data/unfplap/characters.json`, beside it. The same three blocks as
the shipped characters document, each sparse, plus `version`; the file is absent while the player
has no character data.

Both player files are loaded once at mod load (`SETTINGS.load_settings()`) and kept in memory
(`SETTINGS._cache`); they are written when a value changes or the merged document differs from the
files. A read shares that cached view and must not mutate it; every setter starts from a detached
copy and ends at `_write()`, so a failed write never leaves a half-applied edit in the live cache
and the failure is logged. Opening the Unfplap settings tab calls `SETTINGS.reload_file()`, which
re-reads both files immediately, so a hand edit applies when the tab opens; otherwise it needs a
restart. A shipped document never reloads mid-process.

The merged view (`SETTINGS.data()`) carries `version`, `debug_mode`, `debug_perf`,
`debug_hide_tails`, `debug`, `controls`, `features`, `relationship`, `thrust`, `auto_thrust`,
`caress`, `jiggle`, `camera_thrust`, `presentation`, `history`, `tolerance`, `cues`, `talk`,
`player`, `anatomy` (with the per-mare placement rows), `ui` (section open state), `default` (the
player's differences from the shipped profile) and `characters` overrides. The settings document on
disk carries the declared blocks and `ui` only; `default`, `characters` and the per-mare rows are
split out into the character document on every write.

## The settings tab

`Settings → Unfplap` has six sub-tabs: **General**, **Anatomy**, **Poses**, **World**,
**Characters** and **Integrations**. **Poses** sits after Anatomy.
Every setting row comes from one declaration in `settings/service.gd` — label, help, section,
bounds — and applies live. Which row sits in which tab, section and order is the declaration's, so
this doc does not list them; the `##` comment above each declaration describes it.

A declaration-drawn page has no Save button: each edit writes its value and applies immediately.
The hand-built Characters form is the exception; its preset changes are written by **Save preset**.
Debug settings are never clamped; only the player-facing contract bounds are.

One panel rule lives in `settings/ui.gd` rather than the declarations: the Anatomy tab dims and
disables its rows while the Anatomy pill is **Never**, with a short note under it.

**Characters** is the per-mare preference form in `docs/preferences.md`. **Integrations** is built
from `shared/integrations.gd`: one Experimental box, one collapsible section per supported mod with
its verified-version hint, and its own Debug block; `docs/integrations.md` owns it.

Turning on **Enable debug** (General's last player row) adds one collapsed **Debug** section at the
bottom of General, Anatomy, Poses, World and Integrations, which keeps the same group names and
ends with that tab's **Actions** rows. The Poses tab's tuning rows are its Debug block; its two
pose switches sit above it.

## Feature flags

Feature flags are ordinary settings under `features.*` and are read through their typed accessor.
The act session snapshots them with every other act value in `act/session.gd:snapshot_settings()`
at act start, and `apply_live_settings()` re-runs that snapshot after any settings edit. Their
default values live in `settings/settings.json`.

Every flag is a `features.*` declaration whose `##` comment says what it gates; this doc does not
keep a second list.

Always on: act history and its per-act summary, act face beats and `{face_note}` prompt hints,
unprompted act lines with their fresh-angle wording, starting an act through an active cuddle,
standing afterglow stay-close window, lean-camera inertia smoothing and strong-thrust rump blush.
Unknown settings keys are ignored.

## Settings authoring rules for agents

- Add a setting with one declaration in `settings/service.gd` and its `##` description above it,
  one value in `settings/settings.json`, and read it with its typed accessor; never add a widget, a
  default constant, a path-keyed read or a save function anywhere else.
- Contribute the setting from its owning service: add the declaration and its description, add its
  shipped value, and depend on the settings facade. Do not add a private settings module, and do
  not describe the row in the owning doc.
- `SETTINGS.act_snapshot(group)` is the one bulk read. There is no path-keyed gameplay read and
  no second cache; a new per-act value belongs on `ActSnapshot`, not in a new `SETTINGS.block`.
- **A consumer carries no default.** Do not declare a field, constant or argument default with a
  value the setting also ships; the declaration and `settings/settings.json` are the only source.
  Where a fallback is genuinely needed, read `SETTINGS.<name>.default` or the shipped block
  (`PREFERENCES.defaults()`, `CATALOG.defaults(pose_id)`, `DEFAULTS.settings_block(...)`), never a
  literal.
  A complete settings block is indexed (`block["key"]`); do not soften it with
  `.get("key", literal)`, which only hides a missing or stale copy.
- **A rule table or a constant set is a default copy too.** When several settings form one policy
  table, build it from the declared handles at the call site (the tolerance, score and history
  `rules()` functions) instead of declaring a table of values. A constant that is a true baseline
  for a computation or a bake (the standing recipe's six reference constants, the kiss's bed lean
  geometry) is not a default copy: it is the reference the live setting is applied against.
- **Do not add per-setting tests.** A declaration is compile-checked (name, accessor and kind), so
  the only assertions are the ones in `tests/test_settings.gd`: registry integrity, the shipped
  document's schema (key set, types, options and bounds — never values), the file round-trip,
  clamping versus debug bypass, validation, section state, the panel drawing every declaration,
  the Poses tab's player rows and Debug block, migration and the per-mare merge. Extend that file
  only for new API behaviour.
- A retired setting is one `deprecated()` entry in `settings/service.gd` with its mapping; bump
  `SCHEMA_VERSION` only for a structural change in `_migrate()`. Neither needs a manual file edit.
- **A group needs at least three related settings.** Fewer, and the setting goes directly in the
  tab (or its Debug block) with `group` empty and no heading; a subgroup that small merges into its
  parent section. `tests/test_settings.gd` enforces the rule.
- The Debug block is gated by `debug_mode` and toggles live: `settings/ui.gd` keeps the block and
  shows or hides it. Put new debug-only settings behind `.as_debug()`; the Actions buttons live
  inside the Debug block of the action's tab.
- A debug action that belongs with others shares a `row` caption and a `short` label in
  `debug/service.gd`; consecutive entries with the same row render on one line.
- The Anatomy Actions block starts with the **Placement target** pill (`Default` / `Pointed
  mare`), backed by the persisted hidden `anatomy.placement_target` setting. The Placement
  buttons then write the selected target immediately: Default persists the
  `anatomy.placement.default.*` declarations, and Pointed mare writes her override. **Reset**
  returns the Default block to its shipped values, or drops the pointed mare's override.
- **A boolean label starts with a verb**: Show, Enable, Move, Allow, Use, Play, Print, Hide, Pin,
  Sway, Twitch, Remember, Mute. Label the action the switch performs, not the noun it controls
  (“Show controls”, “Enable footstool”, “Move captions to top”). Choices and numbers keep
  their noun label. Push back if a verb label reads worse than the noun; say so in the review
  rather than forcing it.
- **Help is optional.** The label carries the row when the action is self-explanatory; add help
  when the row needs a reason, a range or a warning. An empty help string draws no Faint line.
- **The declaration carries the row; a doc carries the behaviour.** The label, help, bounds and the
  one `##` description live at the declaration, and a `.md` never enumerates or describes a row. A
  default lives only in `settings/settings.json`.
- **One description per setting.** A `##` block of one or two lines above the declaration, saying
  what the setting is and what its hint does not: who reads it, when an edit lands, or what a
  boundary value does. `scripts/comments.py --check` enforces the shape.
- Promote a player value with `scripts/settings_sync.py promote` (a declared setting) or
  `scripts/settings_sync.py promote --characters` (a profile difference, a per-mare override or a
  placement row); never hand-edit the shipped document to copy a local value.

## Debug actions and hotkeys

Debug commands are entries in `debug/service.gd`:

```gdscript
"give_stool": {
    "label": "Give footstool",
    "help": "Add a footstool to Anon's briefcase.",
    "method": "action_give_stool",
},
```

The **Debug** block of the tab named by the entry's `tab` (`general` by default, or `anatomy`/
`world`/`integrations`; the Poses tab carries none) draws a button for it and calls `method` on the
debug actions node the entry adds. An action on a wheel page sets
`"panel": false`; the Debug block skips it, so the settings blocks draw only the settings-only
actions. Entries that share `"row"` are drawn compactly on one line under that caption (`"short"`
is the button text), so related settings-only actions stay together; adding an action is one entry
plus one method. An entry with `"phase"` and
`"match_label"`/`"match_short"` changes its label while the aimed mare is already in that phase;
the settings buttons and the wheel both resolve it through `action_label()`/`action_short()`.

The registry declares no global hotkeys, so the game's own dev keys (`F4`, `F9`, `F10`, `F11`) stay
usable while the mod is loaded; `input/service.gd` still routes a declared `"hotkey"` for a future
action that must fire while the world is unpaused. The action list, the wheel pages and
per-service debug actions are in `docs/debug.md`.

## Perf probe

**Print perf logs** (with **Enable debug**) turns on `shared/perf.gd`. Its chunks open and close
around the work they measure, one window covers an act and the idle time alike, and it prints one
`perf` block a second. Rows nest under the frame a chunk opened in and sort largest first inside
their level, and a parent's unmeasured remainder prints as a `self` row. The profiler is off and
allocation-free when either switch is off. It is a debug tool, not a setting: no declaration, no
persisted value. The block's rows and panel are `docs/debug.md`'s.

## Facade

The document and per-mare profile functions return typed views rather than raw dictionaries, so a
caller reads a block through a named accessor. `settings/rows.gd` wraps one settings document:
`of()`/`raw()` are the JSON edge, and `has()`, `bool_value()`, `num()`, `str_value()`, `rows()` and
`keys()` read it. A caller that needs the plain document — a pose node, a cross-mod payload, a test
comparison — calls `raw()` at that boundary, and a writer takes the view the reader returned.
`settings/profile.gd` carries the four facets of one resolved profile; `settings/deprecation.gd`
carries one retired key, with `into()` moving the stored value and `mapped()` replacing it.
