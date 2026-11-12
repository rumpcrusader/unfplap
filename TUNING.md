# Settings: one declaration, one accessor

Every global setting in the mod is declared **once**, in `settings.gd`, and read through a typed
accessor on that setting. There is no second schema, no path-keyed read and no default constant
anywhere else. The General, Anatomy and World panels are drawn from the declarations by
`settings_ui.gd` in the settings page's own menu style: row cards, `Faint` help, switch plus state,
Segment pills for a few short choices and the `Tab` look for a collapsible section heading. The tab
pills, sidebar row and the hand-built Characters preference tab are added by the injection in
`main.gd`.

> If you are about to write a `SpinBox`, `CheckButton`, `OptionButton`, a default constant, a
> restore/normalise function or a save function for a setting, stop. Declare the setting instead.

Per-character profiles (`default`/`characters` templates, preferences, prompts, consent) and the
pose catalog overrides (`poses.*`) are not global settings: they live in the same file but are read
through `SETTINGS.preferences(id)`, `SETTINGS.pose(id, pose_id)` and the other profile functions.
Eligibility and consent gate semantics are in `docs/eligibility.md`; this file owns their storage.

## Reading and writing

```gdscript
const SETTINGS := preload("res://mods/unfplap/settings.gd")

if SETTINGS.act_vocals.get_bool(): ...
var raise_m: float = SETTINGS.raise_m.get_num()
var orientation: String = SETTINGS.orientation.get_choice()
var ignored: Array = SETTINGS.ignore.get_list()
var snapshot: Dictionary = SETTINGS.block("features.")   # per-act snapshot, see below

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

Every setting also has `get_value()`, `set_value(v)`, `reset()`, `name`, `path`, `label`, `help`,
`tab`, `group`, `default` and `debug`.

A wrong accessor does not compile: `SETTINGS.act_vocals.get_num()` is a parse error, and so is a
mistyped name. That is the main safety net; the tests only cover what the compiler cannot see.

**Bulk snapshots.** `SETTINGS.block(prefix)` returns the nested dictionary under a dotted prefix and
is the one place a path prefix is still used. Act code snapshots once per act in
`runtime._snapshot_settings()` and re-runs it in `apply_live_settings()`; do not add a second cache.

## Adding a setting: one line, then one read

1. **One declaration, where it should appear in the panel.**

   ```gdscript
   static var raise_m := num("raise_m", "presentation.standing.smack.raise_m", 0.3, "Max raise",
       "Hand lift at the top of the wind-up.", GENERAL, "Standing › Smack") \
       .with_unit("cm").with_step(0.5).with_scale(100.0).as_debug()
   ```

2. **One typed read at the use site.**

   ```gdscript
   var raise_m: float = SETTINGS.raise_m.get_num()
   ```

3. **Run `scripts/test_all.sh`.** It checks the registry, the file round-trip, coercion and that the
   panel draws every declaration.

Nothing else exists to update: the widget, unit, save, default, persistence and placement all come
from the declaration.

## Declaration reference

```gdscript
flag(n, path, default_on, label, help, tab, group)
num(n, path, default, label, help, tab, group)
    .with_unit("cm") .with_step(0.5) .with_scale(100.0) .with_range(low, high) .with_slider()
choice(n, path, default, options, labels, label, help, tab, group)
list(n, path, default, options, label, help, tab, group)
    .as_debug() on any kind
    .as_hidden() on any kind
```

| Argument | Meaning |
|---|---|
| `n` | the identifier, `SETTINGS.<n>` |
| `path` | the `settings.json` path; the only string, and it lives here |
| `label`, `help` | the row text and the line under it. A boolean label starts with a verb (Show, Allow, Use, Play, Print, Hide, Pin, Sway, Twitch, Remember, Mute); a choice or number keeps its noun |
| `tab` | `GENERAL`, `ANATOMY` or `WORLD` |
| `group` | the panel section; `"Standing › Smack"` is a subheading under `Standing`. A group needs at least 3 related settings: fewer, and pass `""` so the setting sits in the tab with no heading (a small subgroup merges into its parent) |
| `with_unit`, `with_step`, `with_scale` | display unit, spin step and display multiplier (`m` shown as `cm` = `100`) |
| `with_range` | the contract bounds; only applied when the setting is not debug |
| `with_slider` | draw a themed HSlider instead of a spin box |
| `as_debug` | show it in the tab's Debug block only, and never clamp it |
| `as_hidden` | keep it out of the declaration rows; a hand-built `settings_ui.gd` control (the placement target pill) owns the widget |

Declarations render **in file order**, and a section is created where it first appears. Put a line
where a player would look for it, next to the setting it belongs to; do not add a "misc" section.

## Naming

The identifier is the JSON path's last segment: `thrust.travel` → `travel`,
`features.act_vocals` → `act_vocals`. Only on a collision with another setting does it gain the parent
segment as a prefix (`jiggle.intensity` → `intensity`; a second `intensity` would become
`jiggle_intensity`). Keep names short; the panel group carries the context. Do not add group
prefixes pre-emptively.

## Clamping

- A player-facing `num` clamps to `with_range(low, high)`. That bound is part of the contract, so it
  is the only clamp a consumer may rely on: sensitivity, hip back-off, auto pace/depth, camera
  surge/bob, glance-back speed, genital tone.
- A debug number (`.as_debug()`) is stored and returned **verbatim**; `with_range` only shapes the
  spin box. Moving a setting to or from debug is the `as_debug()` call alone.
- Moving a debug setting to player-facing starts clamping its stored value. Check the saved range
  when you do it.
- Do not add a clamp in a consumer "to be safe". If a value must stay playable, give it
  `with_range` and say why in its help text.
- `choice` ignores an unknown string and `list` drops unknown options. That is validation, not
  clamping. A non-finite number falls back to the default.

## Tabs, groups and debug

- Tabs, in panel order: **General** (interface, audio, cycle, thrust, act tuning), **Anatomy**,
  **World** (relationships, cycle, witnesses, pony behaviour), **Characters** (the per-mare form).
- Player-facing settings come first in their tab. When **Enable debug** (General's last row) is
  on, the tab ends with one **Debug** section holding that tab's debug settings under the same
  group names. A section name draws one heading; interleaved declarations fold back into it.
- Every section remembers whether it is open in `settings.json` under `ui.sections`, keyed
  `tab/group`; the Debug block and its subsections use the `Debug/` prefix. Read and write that
  state through `SETTINGS.section_open(tab, group)` and `SETTINGS.set_section_open(tab, group, open)`.

## Persistence, defaults and migration

- The declaration's `path` **is** the `settings.json` path; the default is the declaration's value.
  Defaults are generated from the registry, so there is no second defaults table.
- `anatomy.placement` is one block with `default.*` (ten debug declarations: anatomy 5, tail 3,
  dock 2), `anon.*` (the player part) and partial `<mare id>.*` overrides. `anatomy_placement.gd`
  owns the shipped per-mare `MARE_DEFAULTS` (the tuned tail/dock rows) and resolves override,
  shipped default, then global default. The old `anatomy_place.json` and `anon_place.json` import once and are renamed
  `.migrated`. The old `anatomy.tail_seat.<id>` rows and the tail/dock millimetre globals migrate
  into the same block on load.
- `anatomy.reseat_tails`, `anatomy.dock_color` and the tail/dock placement behavior are in
  `docs/anatomy.md`. The settings layer owns only their paths, defaults and the placement
  migration above.
- `settings.gd` owns the file. It parses once per process into `_cache`, writes on save, and
  `SETTINGS.reload_file()` re-reads it; the settings page reloads when it opens. Flat reads are
  cached per generation, so a per-frame read is cheap.
- **Migrations.** The file carries `version`. Add a step to `_migrate()` for a structural change
  and bump `SCHEMA_VERSION`; a current file skips the chain. The old normalisers (pose ids, feature
  names, presentation split, tolerance tiers, prompts, anatomy keys) run inside it.
- **Deprecations.** Declare a retired setting next to its replacement:

  ```gdscript
  static var _deprecated := [
      deprecated("anatomy.genital_yaw_deg", func(_value): return {}),
      deprecated("cues.old_override_seconds", func(value): return {"cues.override_seconds": value}),
  ]
  ```

  The loader reads the old path once, merges the returned dictionary and erases the old key, so a
  retired setting cannot linger in the file.
- `history.*` holds the act-history score weights, thresholds, decay and offer weighting; the
  contract is `HISTORY.md`. `tolerance.*` holds the mid-act warning/stop thresholds; the tier itself
  is a per-mare `preferences.tolerance`, not a global setting.
- Built-in act prompts live in `SETTINGS.DEFAULT_ACT_PROMPTS`; `act_prompts` stores only overrides.
  **Reset act prompts** (General › Enable debug › Debug › Actions) clears them.
- `characters.<id>.profile` is a sparse per-mare participation layer. `profile.participation` holds
  `acts`, `anatomy` and `tail`; only differences from the resolved default are stored. A provider's
  `adult` assertion is top-level and never a player value. The `characters` block is the same
  per-mare block as the preference, consent, prompt and pose overrides.
- Unknown keys are ignored on load.
- Never name a settings API function after a `Script`/`Object` built-in (`reload`, `set_path`,
  `get`, `set`): a preloaded script constant resolves the built-in instead. `tests/test_settings.gd`
  guards this.

## Debug actions and hotkeys

Debug commands are entries in `debug_actions.gd`:

```gdscript
"bed_offer": {
    "label": "Trigger bed offer",
    "help": "Force a missionary offer for the aimed or nearest mare.",
    "method": "action_bed_offer",
},
```

The **Debug** block of the tab named by the entry's `tab` (`general` by default, or `anatomy`/
`world`) draws a button for it and calls `method` on the entry node. Entries that share `"row"` are drawn compactly on one line under that caption
(`"short"` is the button text), so related actions stay together; adding an action is one entry
plus one method. A hotkey (`"hotkey": KEY_X`) is the exception, only for an
action that must fire while the world is unpaused and you are looking at the scene (the F10
skeleton overlay is the only one); use `"panel": false` for hotkey-only. `input.gd` routes declared
hotkeys only.

## Guards

- `tests/test_settings.gd` is the API contract, tested once: unique names and paths, a tab/group/
  label/help on every declaration, defaults, the file round-trip, clamping and debug bypass,
  choice/list validation, section state, the panel drawing every declaration in its tab (and the
  Debug block only in debug mode), built-in name clashes, and the per-mare merge.
- `tests/test_source_hygiene.gd` checks that no file imports the removed tunable shims and that no
  settings widget is created outside `settings_ui.gd` (the Characters form in `main.gd` is the one
  allowed exception).
- Keep `AGENTS.md`'s flag table current when adding a feature flag, and update `README.md`
  CONTROLS or FEATURES only for player-facing changes.
