# HUD

The mod's one screen surface: the act's text readouts (the cue/hearts line, the readiness/preference
line, the auto readout, the `End` tint and the control card), the single toast line, the game
caption's act-only move to the top, and the one-time act-key notice. The card itself is
`hud/service.gd`; the style rules are this doc. The readiness values are `docs/readiness.md`; the
close window is `docs/afterglow.md`.

## Ownership

| File | Role |
|---|---|
| `hud/lines.gd` | pure text and tint: `cue_line`, `readiness_line`, `auto_text`, `y_pink`, `auto_panel_label` |
| `hud/service.gd` | the facade and the scene card: rows, key caps, prompt row, visibility, the act wiring, the borrowed quick-slot card, the toast line and the caption tracking and move |
| `docs/hud.md` | this contract |

The service owns:

| Member | What it owns |
|---|---|
| `update_from(view)`, `show_act()`, `hide_act()`, `hide_all()`, `show_prompt()`, `hide_prompt()` | the act card and the offer hint's fallback row |
| `set_act_key(label)`, `apply_settings()` | the act-key row's cap and the cached caption mode, re-read on every settings edit |
| `toast(text, seconds)` / `anatomy_status(text, seconds)` | the one toast line; the only sink the rest of the mod uses |
| `caption_node(node)` / `caption_tick(state)` | the game's `SpeechCaption` tracking and its act-only move to the top |
| `on_world()` / `on_world_closed()` / `on_player(body)` | the world scoped begin and end, and the once-per-world Dance Mod key notice |
| `set_inventory_hidden()`, `inventory_hidden()`, `ensure_act_inventory_visible(owner)` | the borrowed quick-slot card and the idle safety that restores it |

`act/view.gd` fills the typed act view (`shared/act_facts.gd`) with the live values: state, climax
count and limit, cue, close hint, summary, heat, the raw `close_earned` flag, the auto values and
the anatomy row gates. `hud/lines.gd` formats the text, the `End` tint and the auto readout. The
entry calls `runtime.act.facts()` once per rendered frame and passes that object to
`hud/service.gd`, which reads fields and never probes the runtime for a method. The control visibility reads `view.pose_view.family` (`bed` for missionary, `standing` for
standing) instead of a raw pose id. The pure module has no Node, tree, `Settings` or game access,
so the formats are testable without a scene.

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

Two declaration comments in `settings/service.gd` describe the card's two switches. With the
control card off, the cue, readiness line and close prompt remain.
- Top to bottom: cue line `❤ N/limit | cue` (or `❤ N/∞` when the climax limit is unlimited),
  readiness line `Wants: intensity & pattern | You: intensity & pattern`, the (always empty) form
  row, auto readout `Auto · 20–80% · 1.50/s · Normal` while auto is on, blank separator, controls.
- The form-change row stays in the card for layout compatibility but the runtime never fills it.
  A release must not name the reveal or the gift: the player discovers both from her own words and
  behaviour. **Enable debug** writes the state to the run log through `docs/runtime.md`, not to
  `view.form_hint`; the row is empty outside a manually supplied view string. It is independent of
  `hud_readouts` and `hud_controls`.
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
  directions. `Kiss` only shows in the standing pose. Only the `Hold` rows carry the modifier
  column, so an icon is followed by its words with no reserved blank space.
- The control card stays at full opacity while Anon leans or leans in for a kiss and returns after
  it; the cue and readiness readouts stay at full opacity.
- The pose title is the spec's `presentation.hud_label`; the internal bed face-sit says `Face-sit`
  with the same missionary presentation profile.
- Afterglow shows `❤ N/limit | close hint` instead of `Wants`/`You`. Missionary keeps only the
  act-key row; standing keeps lean, reach, caress, caress movement, kiss and the act-key row;
  thrust, auto and smack are hidden.
- `set_act_key(label)` swaps the act-key row's cap when the captured key changes, so the glyph
  follows any key without rebuilding the card.
- Captions move to the top of the screen only while an act is in `POSING_IN`, `ACTIVE` or
  `CLIMAX`, and only when the player picked **Move captions to top** (`captions_on_top`) and the
  game's own speech setting is the explicit bottom caption; afterglow returns them to the bottom.
  The entry registers one `Mods.on_node` hook on `CAPTION_PATH` and forwards every caption to
  `caption_node()`, which tracks it by weak reference and places it at once if an act is live.
  `caption_tick(state)` is the per-frame move: the entry reports the live act state and the HUD
  decides whether anything moves. It sets the caption's private `_card` position to
  `CAPTION_TOP_MARGIN` rounded, scaled by the caption's own `_scale`, which lands after the
  caption's own `_process` because the entry runs at process priority 100. It leaves the
  settings-page preview alone and does nothing if the card fields disappear. The HUD owns the
  game `Settings.changed` subscription: only `access/speech_text` re-applies the mode.
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
caption line. `offer/service.gd` resolves the hints node and that row once per world and
re-resolves them only when the row leaves the tree, and an unchanged hint text is not re-applied,
so a steady frame touches neither the tree nor the row.

## Toast and act-key notice

`toast(text, seconds)` is the mod's only toast: a short line in the corner for four seconds unless
the caller passes its own duration, replaced by the next one. It is an instance method; a caller
holds the HUD and guards for its absence, so a bare runtime with no HUD is a quiet no-op. Callers:
the Negotiation host's player feedback and the offer's block notes (four seconds), the wheel's
one-line result (three), the runtime's form status (2.5) and `anatomy_status(text, seconds)`, the
anatomy status line at two seconds, which falls back to the debug log on a HUD that is not in the
tree.

The act-key notice is one toast per world: when the bundled Dance Mod is active and the act key is
not its `Y`, the HUD says so once, as soon as the player exists. The note is re-armed on every
world enter and never repeats inside one world.

## Gates

- `features.hud_readouts` hides the cue and readiness segments; the hearts and the
  close prompt stay. The form-change hint is not a readout and stays visible.
- `features.act_controls` hides the whole control card; the cue, readiness and close
  prompt stay.
- The afterglow summary is independent of `hud_readouts` and is always shown.
- The quick-slot inventory HUD is hidden for the whole act via `inventory.hud_hidden` and the
  hotbar's `set_hud_visible(false)`. `hud/service.gd` owns the borrowed state
  (`set_inventory_hidden()`, `inventory_hidden()`) and restores exactly what it found, so the act
  start and the one exit call it unconditionally. The idle safety is the HUD's too:
  `ensure_act_inventory_visible(owner)` restores the card only while the registry's live act owner
  is absent or `IDLE`, because every idle sibling runtime sees the same borrowed flag and must not
  take it from a running act. Each idle runtime passes `PONIES.active()` in its idle tick; the HUD
  reads that owner's public `state` and does not import the registry.

## Dependencies

### Uses

| Kind | Target | Entry point | Purpose |
|---|---|---|---|
| service | settings | `settings/service.gd` | settings declarations and live values |
| service | world | `world/game.gd` | service dependency |
| service | world | `world/service.gd` | live scene reads |
| shared | act_keys | `shared/act_keys.gd` | shared data |
| shared | act_state | `shared/act_state.gd` | shared data |
| shared | log | `shared/log.gd` | log sink |
| shared | settings_change | `shared/settings_change.gd` | settings change notification |

## Lifecycle

- Scope: world
- Base: the one list service that is a `CanvasLayer`; it defines the four hooks itself instead of
  extending `shared/service.gd`
- Constructed by: the entry's service list, before any player exists; the entry keeps it and passes
  it to the runtime, `offer`, `negotiation`, `anatomy` and `debug/actions`
- Begin: `_ready()` builds the card; `apply_settings()` applies the act key and the caption mode
- World: `on_world(host)` and `on_world_closed()` (the notice is armed again and the card is hidden)
- Player: `on_player(body)` shows the once-per-world key notice
- Settings: `_ready()` joins the settings change notification, so `apply_settings()` runs on every
  edit without the entry; `_exit_tree()` leaves it
- End: `_exit_tree()` unsubscribes from the game setting; the entry frees the node
- Idempotent: yes


## Tests

`tests/hud/test_hud_lines.gd` covers the formats, the afterglow precedence, heat, the auto
readout and the tint. `tests/hud/test_hud.gd` covers the card rows, the style helpers and the
form-change hint. `tests/hud/test_caption.gd` covers the caption move's five conditions (the mode,
the three act states, the game's speech setting, the settings-page preview and a live card), the
scale rounding, the moved-caption tracking, the two toast durations, the toast line's own timer, the
once-per-world key notice and the base-game accessors' absent answers. `tests/afterglow/test_afterglow.gd` drives the runtime's HUD
forwards. `tests/test_runtime_teardown.gd` drives the idle inventory safety against a live act
owner inside the fixture.

## Related docs

- `docs/readiness.md` — the cue, readiness and auto values.
- `docs/afterglow.md` — the close prompt and the summary.
- `docs/settings.md` — `hud_readouts`, `act_controls`, `captions_on_top`.
- `docs/dialogue.md` — the cue text the HUD shortens.
- `docs/input.md` — the act key the card and the notice name.
- `docs/anatomy.md` — the status line it shows.
