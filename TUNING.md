# Tunables: the only correct way to add a setting

Every global setting in the mod is a **tunable**: one line in `tunables_schema.gd`, keyed by its
`settings.json` path. Read and write tunables only through `tunables.gd`. The Settings and Debug
panels are drawn from the schema by `tunables_ui.gd`, in the settings page's own menu style: row
cards, `Faint` help, switch plus state, Segment pills for a few short choices and the `Tab` look for
a collapsible section heading. The tab pills, sidebar row and the hand-built Characters preference
tab are added by the injection in `main.gd`.

> If you are about to write a `SpinBox`, `CheckButton`, `OptionButton`, a default constant, a
> restore/normalize function or a save function for a setting, stop. Add a schema line instead.

Two file kinds are not tunables and keep their own editors: the per-character profile
(`default`/`characters` templates, preference, prompts) and the pose catalog per-mare overrides
(`poses.*`). Everything global — feature flags, numbers, choices — is a tunable.
Per-mare anatomy consent (`consent.public`, `consent.anal`, `consent.oral`) lives in the character
profile, not in the tunable schema, and is saved by `settings.gd` from the Characters form.
`public` is opt-in and off by default; `anal` and `oral` stay deterministic from her id.
`anatomy.act_only` is a normal user-facing flag in the Anatomy section; it only changes visibility,
not attachment.
`presentation.lean_back_m` is the player-facing back-lean distance; it is read live with the other
presentation values.

## Reading a value

```gdscript
var raise_m := TUNABLES.get_float("presentation.standing.smack.raise_m")
if TUNABLES.get_bool("features.act_foley"): ...
var orientation := TUNABLES.get_string("thrust.orientation")
var ignored := TUNABLES.get_list("presentation.standing.caress.ignore")
var snapshot := TUNABLES.block("features.")   # {"act_foley": true, ...} nested by path
```

| Function | Returns |
|---|---|
| `get_bool(path)` | `bool`; an unknown path is `false`, never `true` |
| `get_float(path)` / `get_int(path)` | number; unknown path is `0` |
| `get_string(path)` | string; unknown path is `""` |
| `get_list(path)` | filtered array of allowed options |
| `get_value(path)` | the typed value for the entry kind |
| `block(prefix)` | nested dictionary of every value under a dotted prefix |

Reads are flat dictionary lookups. Values resolve once per settings generation and rebuild after
a save or `TUNABLES.reload_settings()`, so a read is cheap enough for a per-frame call.

Act code snapshots what it reads every stroke in `runtime._snapshot_settings()` and re-runs it in
`apply_live_settings()`. Do not add a second settings cache anywhere.

## Writing a value

```gdscript
TUNABLES.set_value("camera_thrust.surge", 0.5)
TUNABLES.reset_value("camera_thrust.surge")   # back to the schema default
```

`set_value` coerces to the entry kind, saves the file and refreshes the cached values. Every
settings-tab edit calls `main._apply_settings_changed()`, which refreshes the cached flags, the
caption position and the active act. A new control does not need its own handler.

## Adding a parameter: three steps

1. **One schema line in `tunables_schema.gd`, where it should appear in the panel.**

   ```gdscript
   "presentation.standing.smack.raise_m": num(0.30, "Max raise",
       "Hand lift at the top of the wind-up.", "Standing › Smack", "cm", 0.5, 100.0),
   ```

2. **One read at the use site.**

   ```gdscript
   var raise_m := TUNABLES.get_float("presentation.standing.smack.raise_m")
   ```

3. **Check it.** `scripts/test_all.sh` asserts that every path is reachable and rendered; then
   open **Settings → Unfplap → Debug** and confirm the row sits in the right section.

Nothing else is needed: the widget, its unit, its save, its default, its persistence and its
placement all come from the schema entry. Adding a flag is shorter still —
`flag(true, "Label", "Help.", "Section")`.

## Schema entry fields

| Field | Meaning |
|---|---|
| key | the `settings.json` path, e.g. `presentation.standing.kiss.lean_side` |
| `kind` | `bool`, `num`, `choice`, `list` |
| `default` | the stored default; also what `reset_value` restores |
| `label`, `help` | the row text and the help line under it |
| `group` | the panel section; `"Standing › Smack"` is a subheading under `Standing` |
| `tab` | `"settings"` for the player-facing page, `"debug"` (the default) otherwise |
| `unit`, `step`, `scale` | display unit, spin step and display multiplier (`m` shown as `cm` = `100`) |
| `low`, `high` | spin-box arrows only, unless the entry is a `user_num` |
| `options`, `labels` | `choice` values and their display text; `list` allowed values |

Constructors: `flag`, `num`, `user_num`, `choice`, `list`.

Entries render **in file order**, and a section is created where it first appears. Put a line
where a player would look for it, next to the flag or numbers it belongs to; do not add a "misc"
section. A flag that gates a modifier belongs in that modifier's section.

## Never clamp a debug setting

- `num` is stored and returned **verbatim**. `low`/`high` only shape the spin box.
- `user_num` clamps to `low`/`high`, and only because that bound is part of the player-facing
  contract: sensitivity, hip back-off, auto pace/depth, camera surge/bob, glance-back speed.
- Do not add a clamp in a consumer "to be safe". If a value must stay playable, make it a
  `user_num` and say why in its help text.
- `choice` falls back to the default for an unknown string; `list` drops unknown options. That is
  validation, not clamping.

## Debug actions and hotkeys

Debug commands are entries in `TUNABLES.ACTIONS`:

```gdscript
"bed_offer": {
    "label": "Trigger bed offer",
    "help": "Force a missionary offer for the aimed or nearest mare.",
    "method": "action_bed_offer",
},
```

The Debug tab draws a button per entry and calls `method` on the entry node. Adding an action is
one entry plus one method.

**A hotkey is the exception.** Add `"hotkey": KEY_X` only when the action must fire while the
world is unpaused and you are looking at the scene, where opening the settings page would end the
moment (the F10 skeleton overlay is the only one). Use `"panel": false` for a hotkey-only action.
`input.gd` routes declared hotkeys only; never add an ad-hoc key handler for a debug action.

## Persistence, cache and defaults

- The schema key **is** the `settings.json` path, so a new tunable needs no migration.
- `settings.gd` owns the file. It parses once per process into `_cache`, writes on save, and
  `TUNABLES.reload_settings()` re-reads it; the settings page reloads when it opens.
- Defaults for `features`, `relationship`, `thrust`, `auto_thrust`, `jiggle`, `camera_thrust`,
  `presentation`, `history`, `tolerance`, `cues` and `talk` are generated from the schema. Do not
  create a second defaults table.
- `history.*` holds the act-history score weights, point thresholds, decay and offer weighting.
  It is debug-only unless a player-facing threshold is added deliberately; the contract is
  `HISTORY.md`. The `num` entries are never clamped, so a hand-edited value applies.
- `tolerance.*` holds the mid-act warning/stop thresholds, like relief, decay and stop cooldowns.
  The tier itself is a per-mare `preferences.tolerance` value in the Characters sub-tab, not a tunable.
- Unknown keys in the file are ignored on load.
- Never name a settings function `reload` or `set_path`: `Script` already has both, and a
  preloaded script constant calls the built-in instead. `tests/test_settings.gd` guards this.

## Guards

- `tests/test_settings.gd` checks that every entry has a kind, default, label, help, group and
  tab, that both schema tabs render every entry, and that debug numbers are not clamped.
- `tests/test_source_hygiene.gd` checks that every literal path used with `TUNABLES` exists in the
  schema, and that no settings widget is created outside `tunables_ui.gd` (the Characters preference
  form in `main.gd` is the one allowed exception).
- Keep `AGENTS.md`'s flag table current when adding a feature flag, and update `README.md`
  CONTROLS or FEATURES only for player-facing changes.
