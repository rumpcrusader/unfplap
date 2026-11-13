# Settings: one declaration, one accessor

Every global setting in the mod is declared **once**, in `settings/service.gd`, and read through a typed
accessor on that setting. There is no second schema, no path-keyed read and no default constant
anywhere else. The General, Anatomy and World panels are drawn from the declarations by
`settings/ui.gd` in the settings page's own menu style: row cards, `Faint` help, switch plus
state, Segment pills for a few short choices and the `Tab` look for a collapsible section heading.
The tab pills, sidebar row, the hand-built Characters preference tab and the catalog-driven
Integrations tab are added by the injection in `settings/ui.gd`. The Characters form itself is in
`settings/characters_ui.gd`; the consent and participation semantics are in
`docs/eligibility.md`; the supported-mod catalog is `shared/integrations.gd`.

> If you are about to write a `SpinBox`, `CheckButton`, `OptionButton`, a default constant, a
> restore/normalise function or a save function for a setting, stop. Declare the setting instead.

Per-character profiles (`default`/`characters` templates, preferences, prompts, consent) and the
pose catalog overrides (`poses.*`) are not global settings: they live in the same file but are read
through `SETTINGS.preferences(id)`, `SETTINGS.pose(id, pose_id)` and the other profile functions.
The identity facts discovery scans read (`SETTINGS.profile_identity(id)`) are memoized per settings
generation and provider registry revision, so a scan does not rebuild the whole template per mare.
The resolved consent block (`SETTINGS.consent(id)`) is memoized on the same two keys and returns a
detached copy, so an act gate pays a lookup instead of a template build.

## Ownership

`settings/service.gd` owns the declaration catalog, the JSON file, the typed accessors and the
per-mare profiles. The catalog is the settings service's internal public API: a service contributes
a setting with a literal declaration there and then reads the typed handle.

`settings/ui.gd` is the only file that draws the declaration rows; it also owns the settings-page
injection and the Debug block visibility. `settings/characters_ui.gd` is the interim home of the
Characters form. `main.gd` keeps the `Mods` hook and the `_apply_settings_changed()` callback. The
runtime takes the settings service's typed `ActSnapshot` in `_snapshot_settings()`; the settings
file never reads a live act.

## Contributing a setting

1. Add the declaration in `settings/service.gd`, in the tab and group where the player should see
   it. The declaration owns the path, default, label, help, bounds and debug flag.
2. Document the behavior in the owning service's `## Settings` section.
3. Depend on `settings/service.gd` and use the typed handle.

There is no `<service>/settings.gd` module, no registration call and no second layout list. The
catalog order is the panel order.

## Reading and writing

```gdscript
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")

if SETTINGS.act_climax.get_bool(): ...
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

Every setting also has `get_value()`, `set_value(v)`, `reset()`, `name`, `path`, `label`, `help`,
`tab`, `group`, `default` and `debug`.

A wrong accessor does not compile: `SETTINGS.act_climax.get_num()` is a parse error, and so is a
mistyped name. That is the main safety net; the tests only cover what the compiler cannot see.

**Per-act snapshot.** `SETTINGS.act_snapshot(pose_id)` returns one typed `ActSnapshot` with every
value an act reads per stroke or per frame: the feature dictionary, thrust, auto stroke, cue/talk
pacing, jiggle, camera thrust, the pose presentation block and the climax face. The runtime takes
it in `_snapshot_settings()` and re-runs it in `apply_live_settings()`. There is no path-keyed read
outside the settings service and no second cache.

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
   panel draws every declaration. Update the owning service's `## Settings` section in the same
   commit; a setting contributed by a service is documented there, not only here.

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
| `as_hidden` | keep it out of the declaration rows; a hand-built `settings/ui.gd` control (the placement target pill) owns the widget |
Declarations render **in file order**, and a section is created where it first appears. Put a line
where a player would look for it, next to the setting it belongs to; do not add a "misc" section.

## Naming

The identifier is the JSON path's last segment: `thrust.travel` → `travel`,
`features.act_climax` → `act_climax`. Only on a collision with another setting does it gain the parent
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
  **World** (relationships, cycle, witnesses, pony behaviour), **Characters** (the per-mare form)
  and **Integrations** (supported mods and their switches).
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
  dock 2), `anon.*` (the player part) and partial `<mare id>.*` overrides. `shared/anatomy_placement.gd`
  owns the shipped per-mare `MARE_DEFAULTS` (the tuned tail/dock rows) and resolves override,
  shipped default, then global default. The old `anatomy_place.json` and `anon_place.json` import
  once and are renamed `.migrated`. The old `anatomy.tail_seat.<id>` rows and the tail/dock
  millimetre globals migrate into the same block on load.
- `anatomy.reseat_tails`, `anatomy.dock_color` and the tail/dock placement behavior are in
  `docs/anatomy.md`. The settings layer owns only their paths, defaults and the placement
  migration above.
- `settings/service.gd` owns the file. It parses once per process into `_cache`, writes on save, and
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
  contract is `docs/summary.md`. `tolerance.*` holds the mid-act warning/stop thresholds; the tier
  itself is a per-mare `preferences.tolerance`, not a global setting.
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

## Lifecycle

- Scope: world
- Constructed by: `main._ready()`
- Begin: registry load
- End: process exit
- Idempotent: yes


## Settings file shape

`settings.json` path: `user://mods/data/unfplap/settings.json`
(`~/.local/share/home-equestria-public/mods/data/unfplap/settings.json`).

The file is read once per process into memory (`SETTINGS._cache`) and written only when a value
changes. A read shares that cached view and must not mutate it; every setter starts from a detached
copy and ends at `_write()`, so a failed write never leaves a half-applied edit in the live cache.
Opening the Unfplap settings tab calls `SETTINGS.reload_file()`, so a hand-edited file applies when
the tab opens; otherwise it needs a restart.

Top level: `version`, `debug_mode`, `debug_perf`, `debug_hide_tails`, `features`,
`relationship`, `thrust`, `auto_thrust`, `jiggle`, `camera_thrust`, `presentation`, `history`,
`tolerance`, `cues`, `talk`, `player`, `anatomy`, `ui` (section open state), `default` template,
`characters` overrides.

## The settings tab

`Settings → Unfplap` has five sub-tabs: **General**, **Anatomy**, **World**, **Characters** and
**Integrations**.
Every setting row comes from one declaration in `settings/service.gd` — label, help, section,
bounds — and applies live.

**General**

One ungrouped list, in this order: **Starting Sex**, **Show controls**, **Show HUD readouts**,
**Show captions on top**, **Mute Ponese audio**, **Allow act lines**, **Show act expressions**,
**Caress quality** (`Fast` / `Precise`, default `Precise`), **Climax limit** (`0…20`,
default `3`; `0` is unlimited), **Sensitivity** in pixels per centimetre of hip
travel (`20…400`, default `50`), **Thrust direction** (which mouse direction deepens the stroke),
**Use Anon bed body**, **Use VR act**, **Allow hole switch**, **Allow oral**, **Allow finish
control** and **Enable debug** (the switch that reveals the Debug sections) at the bottom.

The audio switches, auto-thrust pace/bottom/peak/shape (`1.0…3.75/s`, `0…0.82`, `0.20…1`, five
waveforms), the body-slap **Contact gap** (`0…12 cm`, default `2 cm`), the hip
back-off (`0.25…2.0×`, default `0.5×`) and acts during cuddles live in General's Debug block.

**Starting Sex** chooses between When Available and Try Your Luck. The gate semantics — including
what Try Your Luck does and does not lift — are in `docs/eligibility.md`. The setting itself only
stores the choice.

**Anatomy**

The first rows have no heading: the **Anatomy** pill (**Never** / **During act only** / **Always**),
**Show tail docks**, **Show skin strip**, **Show teats**, **Show fluids** and **Skin tone**.
**Show tail docks** only shows or hides the dock; it never moves the anatomy. The behavior behind
these rows is in `docs/anatomy.md`.

- **Anon**: size, length, base/mid/head radius, throb and the back-out gap.

**World**

No headings: **Promiscuity**, the **Estrus cycle** switch, **Allow public offers**,
**Personalize lines during act** and **Add speech interjections**.

**Characters**

- The hand-built per-mare preference form described in `docs/preferences.md`, with one pony
  selector (filtered by name) shared by every field.

**Integrations**

- Every supported mod in `shared/integrations.gd`, in catalog order, whether or not the other mod
  is installed: `Mod by Author`, the Faint `Verified with version: ...` hint, then its switches. The
  Kissing entry and `Use Kissing reactions` are always listed; the behavior is in
  `docs/integrations.md`.

**Debug sections**

Turning on **Enable debug** (General's last row) adds one collapsed **Debug** section at the
bottom of General, Anatomy and World; each section keeps the groups it belongs to, plus the
**Actions** buttons at the end of the tab's own group, in compact rows. Its settings are mostly act
tuning:

- **Talk & cues**: override lifetime (default `10 s`), base/override stability, shared line gap,
  demand gap/repeat, cue/reaction max age, release hold, overwhelmed duration, and the touch/talk
  cooldowns plus receptive window.
- **World › Debug**: **History** (points, score, offers) and **Neglect tolerance**.
- **Anatomy › Debug**: **Holes** (grip padding, lip shape, coat spread, the vulva coat hole and
  still zones), plus the ungrouped cock forward, pelvis gap, skin-strip scale, aim points and
  **Hide tails**.
- **Camera**: idle camera sway, plus the two `0…100%` camera-thrust amounts, defaulting to Surge
  `100%` and Bob `35%`. Surge is the forward camera travel, Bob the vertical dip; both follow the
  filtered thrust **speed**, not depth, with one smooth critically damped response.
- **Missionary**: body motion, **Anon size match**, a **Size** dropdown over the six per-size
  values (the three vulva trims, **Vulva hug**, head clearance, gaze height),
  **Disable fold coloring**, camera mode, free look and third-person views.
- **Standing → Motion**: glance-back speed (`0.25…3.0×`), Anon torso lean.
- **Standing → Kiss**: mouth right/down/forward, camera yaw, side/forward/drop lean.
- **Standing → Caress**: see `docs/hands.md`.
- **Standing → Smack**: max raise (`0.30 m`), hind offset (`0.10 m`), height (`-0.03 m`), palm
  arc (`0.06 m`), palm pitch (`12°`), raise speed (`2.0 m/s`) and return speed (`6.0 m/s`).
- **Thrust jiggle**: radius, center height/back, thrust and smack intensity.

The declaration-drawn pages have no Save buttons: each edit writes its value and applies to the
active act immediately. The hand-built Characters form is the exception; its preset changes are
written by **Save preset**. Debug settings are never clamped; only the player-facing contract
bounds listed above are enforced. The framing, pitch and torso controls remain experimental and
unbounded.

## Feature flags

Feature flags are ordinary settings under `features.*` and are read through their typed accessor.
The runtime snapshots them with every other act value in `_snapshot_settings()` at act start, and
`apply_live_settings()` re-runs that snapshot after any settings edit.

| Flag | Default | Gates |
|---|---|---|
| `hud_readouts` | `true` | mood cue and `Wants`/`You` segments; hearts and the close prompt stay |
| `act_controls` | `true` | act control card; the cue and close prompt stay |
| `act_lines` | `true` | cue lines and climax/early-end reactions; off keeps normal dialogue and the HUD cue |
| `act_faces` | `true` | act face beats and `{face_note}` prompt hints; off keeps the current act faces; the blush arc and post-act mood face are separate |
| `blush_arc` | `true` | readiness-ramped act blush; off restores full blush from the first frame |
| `face_debug` | `false` | print act face changes, the climax score and the mood-face start/end |
| `idle_camera_sway` | `true` | slow idle breathing when not leaning; false removes the drift |
| `captions_on_top` | `true` | move the explicit bottom caption to the top; applies immediately |
| `standing_body_sway` | `true` | standing body sway modifier; Anon's pinned hip follows the same offset |
| `missionary_body_motion` | `true` | missionary torso slide and head nod on the thrust |
| `thrust_ear_twitch` | `true` | standing thrust ear-twitch modifier |
| `standing_plant_feet` | `false` | hold Anon's hip and both foot targets at their act-start positions, feet 15 cm behind; true enables it |
| `standing_stool` | `true` | a live reach gap over `stool_gap_m` needs enough `goods:footstool` stacks of `stool_height_m`; the shop or house drops supply them |
| `estrus_cycle` | `false` | 30-day heat/diestrus cycle: heat warms faster, offers sooner and ignores privacy; diestrus blocks sex |
| `act_line_angles` | `true` | personalizes cue lines with a fresh angle and shared-history hint; widens recent-line recall to eight |
| `act_speech_feel` | `false` | thrust-paced interjection instruction in cue lines |
| `act_public_offer` | `false` | per-mare public consent affects offers; see `docs/eligibility.md` |
| `allow_act_during_cuddle` | `true` | allow starting an act while the stock cuddle session is active |
| `mute_ponese_audio` | `true` | mute a Ponese-only act voice but keep its text |
| `act_climax` | `false` | pack wet finish layer |
| `kissing_reactions` | `true` | Kissing's horn, wing and earth-pony reaction bridge during the act; see `docs/integrations.md` |

Always on: act history and its per-act summary, standing afterglow stay-close window, lean-camera
inertia smoothing and strong-thrust rump blush. Unknown settings keys are ignored. Caress feature
flags and debug values are in `docs/hands.md`; anatomy feature flags and debug values are in
`docs/anatomy.md`.

## Settings authoring rules for agents

- Add a setting with one declaration line in `settings/service.gd` and read it with its typed accessor;
  never add a widget, a default constant, a path-keyed read or a save function anywhere else.
- Contribute the setting from its owning service: edit the catalog literally, document it in that
  service's contract and depend on the settings facade. Do not add a private settings module.
- `SETTINGS.act_snapshot(pose_id)` is the one bulk read. There is no path-keyed gameplay read and
  no second cache; a new per-act value belongs on `ActSnapshot`, not in a new `SETTINGS.block`.
- **Do not add per-setting tests.** A declaration is compile-checked (name, accessor and kind), so
  the only assertions are the ones in `tests/test_settings.gd`: registry integrity, defaults, the
  file round-trip, clamping versus debug bypass, validation, section state, the panel drawing every
  declaration, migration and the per-mare merge. Extend that file only for new API behaviour.
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
  buttons then edit the selected target; Default stages a preview until Save, and Save writes the
  ten `anatomy.placement.default.*` settings.
- **A boolean label starts with a verb**: Show, Allow, Use, Play, Print, Hide, Pin, Sway, Twitch,
  Remember, Mute. Label the action the switch performs, not the noun it controls
  (“Show controls”, “Allow act lines”, “Use VR act”). Choices and numbers keep
  their noun label. Push back if a verb label reads worse than the noun; say so in the review
  rather than forcing it.

## Debug actions and hotkeys

Debug commands are entries in `debug/service.gd`:

```gdscript
"bed_offer": {
    "label": "Trigger bed offer",
    "help": "Force a missionary offer for the aimed or nearest mare.",
    "method": "action_bed_offer",
},
```

The **Debug** block of the tab named by the entry's `tab` (`general` by default, or `anatomy`/
`world`) draws a button for it and calls `method` on the entry node. Entries that share `"row"` are
drawn compactly on one line under that caption (`"short"` is the button text), so related actions
 stay together; adding an action is one entry plus one method. The registry declares no global
hotkeys, so the game's own dev keys (`F4`, `F9`, `F10`, `F11`) stay usable while the mod is loaded;
`input/service.gd` still routes a declared `"hotkey"` for a future action that must fire while the
world is unpaused. The action list and per-service debug actions are in `docs/debug.md`.

## Perf probes

**Print perf logs** (with **Enable debug**) turns on both debug probes. During an act, timed chunks
call `perf_note(chunk, usec)`; `shared/perf.gd` holds the window, the chunk rows and the header
facts and prints one per-pony `perf` summary a second. Outside an act, `shared/perf_idle.gd` prints
one aggregated `perf idle` block a second with each chunk's total, average and worst pony. Both are
off and allocation-free when either switch is off; the act window resets outside an act and the idle
window resets when an act starts. They are debug tools, not settings: no declaration, no persisted
value. See `docs/perf.md`.

## Dependencies

### Uses

| Kind | Target | Entry point | Purpose |
|---|---|---|---|
| shared | anatomy_placement | `shared/anatomy_placement.gd` | placement defaults |
| shared | character_preferences | `shared/character_preferences.gd` | character templates |
| shared | consent | `shared/consent.gd` | consent defaults |
| shared | integrations | `shared/integrations.gd` | verified mod catalog and tab rows |
| shared | participation | `shared/participation.gd` | participation defaults |
| shared | pose_catalog | `shared/pose_catalog.gd` | pose ids and defaults |
| shared | preferences | `shared/preferences.gd` | profile math and defaults |

## Tests

- `tests/test_settings.gd` is the API contract, tested once: unique names and paths, a tab/group/
  label/help on every declaration, defaults, the file round-trip, clamping and debug bypass,
  choice/list validation, section state, the panel drawing every declaration in its tab (and the
  Debug block only in debug mode), built-in name clashes, the per-mare merge and the consent
  cache's detached copy/invalidation.
- `tests/test_source_hygiene.gd` checks that no file imports the removed tunable shims and that no
  settings widget is created outside `settings/ui.gd` and `settings/characters_ui.gd`.
- `tests/integrations/` covers the catalog and reaction bridge; the Settings panel check includes
  the Integrations tab.
- Keep the feature-flag table in this file current when adding a flag.

## Related docs

- `docs/preferences.md` — the Characters form and the per-mare profiles.
- `docs/eligibility.md` — consent and participation storage and gates.
- `docs/debug.md` — the Debug actions and the console.
- `docs/perf.md` — the perf probe.
- `docs/readiness.md`, `docs/poses.md`, `docs/camera.md`, `docs/hands.md`, `docs/anatomy.md` —
  the behavior behind the rows.
