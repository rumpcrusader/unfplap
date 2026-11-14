# Act HUD contract

The act's text readouts: the cue/hearts line, the readiness/preference line, the auto readout, the
`End` tint and the control card. The card itself is `hud/service.gd`; the style rules are this doc. The
readiness values are `docs/readiness.md`; the close window is `docs/afterglow.md`.

## Ownership

| File | Role |
|---|---|
| `hud/lines.gd` | pure text and tint: `cue_line`, `readiness_line`, `auto_text`, `y_pink`, `auto_panel_label` |
| `hud/service.gd` | the scene card: rows, key caps, prompt row, visibility, the act wiring and the borrowed quick-slot card |
| `docs/hud.md` | this contract |

The runtime gathers the live values into the typed act view (`shared/act_facts.gd`): state, climax
count and limit, cue, close hint, summary, the preference axes, heat, the `End` tint, the auto
readout and the anatomy row gates. `main.gd` calls `runtime.act_view()` once per rendered frame and
passes that object to `hud/service.gd`, which reads fields and never probes the runtime for a
method. The pure module has no Node, tree, `Settings` or game access, so the formats are testable
without a scene.

## Lines

`cue_line(state, pony_climaxes, max_climaxes, cue, close_text, summary_hud, show_readouts)`:

```text
❤ N/M | cue
❤ N/∞ | cue        (0 = unlimited)
❤ N/M              (readouts off; hearts stay)
❤ N/M | Close: 6   (afterglow keeps the close prompt with readouts off)
```

An act outside `ACTIVE`/`CLIMAX`/`AFTERGLOW` has no line. The afterglow prefers the close prompt;
when the close prompt is empty it shows the summary instead. An empty cue becomes `—` when the
segment is shown.

`readiness_line(state, readouts, last_intensity, last_pattern, want_intensity, want_pattern,
heat, close_text, summary_hud)`:

```text
Wants: firm & steady | You: soft & quick
Wants: … | You: … | In heat
summary            (afterglow with the close prompt in the cue)
```

The line is empty when the readouts are off or outside `ACTIVE`/`CLIMAX`. In the afterglow it only
shows the summary when the cue already shows the close prompt.

`auto_text(min_depth, max_depth, pace, shape)`:

```text
Auto · 20–80% · 1.50/s · Normal
```

`y_pink(standing, afterglow, close_earned, pony_climaxes, max_climaxes)` returns the `End` shade:
one `Y_END_TINT_MAX = 0.75` step per climax, or `1.0` only after the earned standing afterglow
caress. An unlimited limit uses the 3-climax reference.

## Card

- `hud_readouts` (default `true`) shows the cue and the separate `Wants`/`You` line.
- `act_controls` (default `true`) shows the control card. Off hides only the card; the cue,
  readiness line and close prompt remain.
- Top to bottom: cue line `❤ N/limit | cue` (or `❤ N/∞` when the climax limit is unlimited),
  readiness line `Wants: intensity & pattern | You: intensity & pattern`, auto readout
  `Auto · 20–80% · 1.50/s · Normal` while auto is on, blank separator, controls.
- While the hold-X layer is open the control card is replaced by X (`Hold`, `Auto settings`),
  Q A (`Min depth N%`), W S (`Max depth N%`), E D (`Pace N/s`) and Z (`Shape: …`).
- When readouts are off, the hearts remain; the cue and readiness line are hidden.
- In afterglow the summary is always shown: missionary puts it in the cue line, standing keeps its
  close prompt in the cue and puts the summary on the readiness line. Early end shows no summary.
- There is no penetration/depth bar; the thrust mechanic, `thrust.orientation` and auto thrust
  still apply.
- The controls list keeps its act-key row dynamic: `End early` at 0 climaxes, then `End` in `ACTIVE`
  with 1+, `CLIMAX` and `AFTERGLOW`. `End` shades from ink toward the pink accent one step per
  climax, capped at 75%; only the earned standing afterglow caress reward makes it fully pink.
  The thrust row reads `Thrust` (manual only), the X row reads `Switch to auto` or
  `Switch to manual`, and a second X row (`Hold`, `Auto settings`) shows while auto is on. The
  pose rows read `Lean`, `Reach`, `Caress` and `Caress movement`; they do not spell out both
  directions. `Kiss` only shows in the standing pose, and the `Finish: in/out` row is built but
  hidden until the finish control has a visible effect (the `B` key still works). Only the `Hold`
  rows carry the modifier column, so an icon is followed by its words with no reserved blank
  space.
- The control card stays at full opacity while Anon leans or leans in for a kiss and returns after
  it; the cue and readiness readouts stay at full opacity.
- Afterglow shows `❤ N/limit | close hint` instead of `Wants`/`You`. Missionary keeps only the
  act-key row; standing keeps lean, reach, caress, caress movement, kiss and the act-key row;
  thrust, auto and smack are hidden.
- `set_act_key(label)` swaps the act-key row's cap when the captured key changes, so the glyph
  follows any key without rebuilding the card.
- Captions move to the top of the screen only while an act is in `POSING_IN`, `ACTIVE` or `CLIMAX`
  and only when the game's speech setting is the explicit bottom caption; `captions_on_top`
  defaults to `true`, and afterglow returns them to the bottom. The mod owns this: `main.gd` finds
  each `SpeechCaption` through `Mods.on_node`, then moves its private `_card` to the top margin
  after the caption's own layout pass (process priority 100), scaled by the caption's own `_scale`.
  It leaves the settings-page preview alone and does nothing if the card fields disappear.
- **Enable debug** gates the detailed overlay and the mod's logging, not the HUD.
  **Print perf logs** separately gates the per-second performance block and needs it on too.

The card uses the game's own prompt row (`world/ui/interaction_hints.gd`) and its
`player/cradle_controls.gd` style: the game's `prompts/<name>.png` icons where it has one, a dark
drawn key cap for keys it does not (W/S/A/D/Z, `↕`), ink words in `#f4f1ff` with a `#1a1624`
outline, and muted `#f4f1ff` at 60% for modifiers. `hud/service.gd` exposes `text_label()`, `keycap(key, scale)`,
`button_icon()` and `prompt_row(icon, text, cap)` as the one style source. The offer hint is
`OFFER_HINT = "Make love"` in the game's own prompt row: a drawn act-key cap at the row's 52 px
scale beside 30 px words, placed by `hud.prompt_row()` so it sits beside base prompts. The game
has no `key_6.png`, so the cap is drawn by `hud.keycap()` at the prompt-row scale. Without that row
(VR or no `InteractionHints`) the same row is built into the HUD's own centered prompt above the
caption line.

## Gates

- `features.hud_readouts` (default on) hides the cue and readiness segments; the hearts and the
  close prompt stay.
- `features.act_controls` (default on) hides the whole control card; the cue, readiness and close
  prompt stay.
- The afterglow summary is independent of `hud_readouts` and is always shown.
- The quick-slot inventory HUD is hidden for the whole act via `inventory.hud_hidden` and the
  hotbar's `set_hud_visible(false)`. `hud/service.gd` owns the borrowed state
  (`set_inventory_hidden()`, `inventory_hidden()`) and restores exactly what it found, so every exit
  path can call it unconditionally. The runtime's idle safety check restores it only while no other
  runtime is mid-act, because every idle sibling sees the same borrowed flag.

## Dependencies

### Uses

| Kind | Target | Entry point | Purpose |
|---|---|---|---|
| shared | pose_catalog | `shared/pose_catalog.gd` | pose ids and defaults |

## Lifecycle

- Scope: world
- Constructed by: `main._ready()`
- Begin: `_ready()`
- End: freed with main
- Idempotent: yes


## Tests

`tests/hud/test_hud_lines.gd` covers the formats, the afterglow precedence, heat, the auto
readout and the tint. `tests/hud/test_hud.gd` covers the card rows and the style helpers.
`tests/afterglow/test_afterglow.gd` drives the runtime's HUD forwards.

## Related docs

- `docs/readiness.md` — the cue, readiness and auto values.
- `docs/afterglow.md` — the close prompt and the summary.
- `docs/settings.md` — `hud_readouts`, `act_controls`, `captions_on_top`.
- `docs/lines.md` — the cue text the HUD shortens.
