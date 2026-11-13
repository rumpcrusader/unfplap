# Act readiness, strength and auto thrust

This is the contract for the act's readiness loop: the measured stroke, the physical strength
value, satisfaction/mood/cues, the pony climax count, the touch/talk assist and the automatic
stroke. The long-term summary and history are `docs/summary.md`; cue admission and prompt assembly
are `docs/lines.md`; the HUD text is `docs/hud.md`; the camera response is `docs/camera.md`.

## Ownership

`readiness/service.gd` is the system facade. It owns the scoring state, the public act values
`satisfaction`, `mood`, `cue` and `pony_climaxes`, and the neglect-tolerance meter; the runtime
forwards the values and keeps the act state machine, the climax transition, the face beats and the
presentation of a tolerance decision. The runtime calls `readiness.stroke()`, `touch()`, `talk()`
and `tick()`; readiness owns the counters the summary reads and the one-second impact window. It
also owns the auto-thrust generator, the hold-X panel policy and their defaults.

`readiness/thrust.gd`, `readiness/auto_thrust.gd`, `readiness/auto_panel.gd` and
`readiness/tolerance.gd` are pure modules behind the facade. The runtime
keeps the input reads (`Input`, mouse motion, wheel, the shape key) and applies the depth through
`_thrust_move` so audio, camera, jiggle and presentation keep one path.

The auto surface:

| Facade call | Contract |
|---|---|
| `configure_auto(pace, max_depth, shape, min_depth)` | push the act's `auto_thrust.*` snapshot; `reset_auto()` returns to it |
| `reset_auto()` / `stop_auto()` | a fresh act / the act phases that end it |
| `toggle_auto(depth)` | `X`; starts the generator at the hand's current depth |
| `auto_step(delta)` | one generated depth, or `NAN` while off; the runtime applies it |
| `auto_wheel(direction)` | the wheel notch |
| `auto_panel_tick(delta, x_down, keys, depth)` | the hold-X policy; applies the row nudges and the tap, returns the remaining actions |
| `auto_panel_open()`, `auto_shape()`, `auto_*_depth()`, `auto_pace()` | the HUD and the settings-shape reads |
| `auto_set_shape(name)` | the runtime's `Z` settings write lands here too |

## What the player does

- Mouse vertical motion feeds the measured penetration in metres. `thrust.orientation` flips the
  direction; `"up"` (the default) means mouse up deepens. `thrust.pixels_per_cm` is the
  sensitivity, default `50` (20–400), so a full stroke is his shaft length and the `Back-out gap`
  sits below zero depth.
- `X` toggles auto thrust in `ACTIVE`/`CLIMAX` on a tap. `readiness/auto_thrust.gd` drives
  `wave(shape, phase)` at `pace` thrusts per second between `min_depth` and `max_depth`, and the
  runtime feeds the same depth tracker the mouse feeds. It adds no separate score or heat path:
  intensity, pattern, readiness, audio and presentation are the manual ones. The wheel sets pace;
  the hold-X layer sets the band and shape, and the mouse does nothing while auto runs. The band
  keeps the tracker travel at `max_depth - min_depth - 0.06` (`REVERSAL_HYSTERESIS`) and is never
  narrower than `0.18`, so every stroke still counts; the peak is at least `0.20`. `Auto shape`
  (debug) picks the stroke waveform: `Normal`, `Thrust`, `Tease`, `Saw` or `Hold`; it applies live
  and every shape returns to the bottom, so the tracker only ever sees depth.
- **Hold `X`** while auto is on and the control card swaps to the auto settings: `Q`/`A` min depth
  ±5 %, `W`/`S` max depth ±5 %, `E`/`D` pace ±0.25/s, `Z` cycles `Auto shape` (written to
  settings). The layer stays open while X is held, survives a re-press within `0.28 s` of release,
  and freezes the lean, the caress keys and the kiss while it is open. `R`/`F` are reserved for a
  future tail control.
- Mouse right or `G` smacks either cheek. See `docs/hands.md`.

## Stroke, impact and thrust

- A **stroke** is continuous movement in one direction. It closes on a real reversal
  (`REVERSAL_HYSTERESIS = 0.06`) or `STROKE_TIMEOUT_S = 0.18 s` without movement. Its **bottom**
  is a separate `impact` event: it fires on the reversal or after `IMPACT_STALL_S = 0.04 s` of no
  real progress, and it drives the jiggle, wings, blush, ear twitch and the plap, so the sound
  lands with the motion instead of 180 ms late. The close only scores.
- The **body slap is gated on contact**: `THRUST.contact_amount()` compares the stroke's peak
  penetration with `reach` and fades in over `thrust.contact_gap_m` (Contact gap, default `0 cm`),
  so only a stroke that actually brings his skin to her coat plaps, quieter the shorter it is. The
  slide and the bed fabric still play on every real thrust.
- A **thrust** is an inward stroke with `travel >= THRUST_MIN_TRAVEL = 0.12` and
  `duration >= MIN_THRUST_DURATION = 0.04 s`. The minimum auto peak travels 0.14 and therefore
  counts as a real soft thrust. Tiny jitter, pullbacks and outward strokes are presentation only:
  they do not update the axes or score readiness.
- `strength = clamp(travel × clamp(speed / 8.0, 0.15, 1.5), 0, 1)` is the physical impact value.
  The `0.15` floor lets a slow full-depth stroke stay soft on the physical axis; average speed
  drives strength, peak speed is logged and capped at `2 × average speed`, but one fast sample
  cannot saturate it by itself.
- The **intensity preference** is read from the stroke's travel: `soft` (< 0.35), `firm`
  (< 0.65), `rough`. The depth and tempo axes are independent, so a deep slow stroke is rough and
  a shallow fast stroke is soft. The physical strength above stays the plap/foley/impact/wobble
  value.
- Visual impact is `min(1, strength × 2.0)`, so normal and fast thrusts keep the tuned wing, ear
  and blush response while slow or shallow strokes stay lighter; the foley scales from `strength`
  directly. The rump/tail wobble is separate: `THRUST.jiggle_amount(travel, strength)` follows
  travel, so a full stroke wobbles the same at any speed, and the soft band fades the gentlest
  strokes to `0.04`. The camera is on its own speed-driven channel, not this impact value.
- `satisfaction` is her arousal/readiness 0–100. At 100 she climaxes; the player chooses afterglow
  separately. Readiness rises in discrete chunks from real thrusts, not on a passive timer.

## Pattern

Classified over the last 3–4 real inward thrusts. Fewer than 3 means “no pattern yet”; only the
intensity axis can match. Pattern is tempo only; depth does not decide the rhythm.

```text
teasing  mean duration > 0.45 s
quick    mean duration < 0.30 s
steady   otherwise
```

## Readiness

`satisfaction` is readiness. It starts at 0 and caps at 100. The optional HUD readouts
(`hud_readouts`, default `true`) show `Wants: firm & steady | You: …`.

```text
both axes match       +1.4 per real thrust × warmth
one axis matches      +0.7 per real thrust × warmth
neither matches       no gain; stopping and waiting simply pauses progress
liked touch / talk    +6.0 once, capped at ASSIST_CAP = 60
disliked touch/talk   -6.0 once and 1.2 s overwhelmed
```

- Real thrusts are rate-limited to one scored thrust every `0.2 s`; faster input is presentation.
- A liked touch or talk opens an 8 s receptive window: real thrusts gain `×1.25`.
- Touch shares one 4 s scoring cooldown. Alternating caress, kiss and smack does not bypass it.
  Talk has its own 8 s scoring cooldown.
- Touch/talk cannot take her past `ASSIST_CAP = 60`. At the cap, caress says “She needs more
  than your hands”; talk says “She needs you to move.”
- The pattern/intensity memory clears after 1.2 s without a real thrust.
- Readiness never decays on its own. Only a disliked touch or talk subtracts. No hard stop from
  a mismatch; stopping and waiting simply pauses progress.

## Mood and cues

```text
warming       readiness < 40
wanting       40 <= readiness < 65
close         readiness >= 65
climax        the pony is in her 5 s climax
overwhelmed   a disliked touch/talk landed recently
```

- `CLOSE_AT = 65` is only the “she is close” cue.
- `PONY_CLIMAX_AT = 100` triggers the pony's climax.
- Cue admission, stability, the shared slot and the prompt are `docs/lines.md`. The HUD shorthand
  is `docs/hud.md`.
- The base fallback cue is `She wants you to keep going.` A neutral touch sets no override; a
  neutral talk sets `She listens.` The two assist-cap lines mean the touch/talk assist is already
  at `ASSIST_CAP = 60` and only real thrusting can add more.
- `features.estrus_cycle` (default off) multiplies each real thrust chunk by `×1.6` while she is in
  heat; `shared/cycle.gd` derives the phase from the world day and her id. Diestrus blocks starting and
  offers. `warmth` and the receptive window still stack on top. The gate is in
  `docs/eligibility.md`.

## Pony climax

- At 100 readiness she climaxes. The user-facing `thrust.max_pony_climaxes` setting (default `3`)
  sets the limit; `0` is unlimited.
- The act enters `CLIMAX` for `CLIMAX_SECONDS = 5`.
- The player can keep thrusting during those 5 s. The thrust is presentation only: it does not
  update intensity, pattern or readiness.
- Each climax sends a unique world-context event and a unique generated reaction.
- When the 5 s ends:
  - below the configured limit, or unlimited: return to `ACTIVE`, set readiness to `0`, clear
    pattern;
  - at a non-zero configured limit: enter `AFTERGLOW` automatically.

The afterglow phase and the standing close window are `docs/afterglow.md`.

## Neglect tolerance

`preferences.tolerance` is per mare: `forgiving`, `normal` or `strict`. The Characters sub-tab
edits it as **Neglect tolerance**. The default is normal; Rarity is strict and Fluttershy is
forgiving. The old `timid`/`neutral` values still resolve to `forgiving`/`normal`.

`readiness/tolerance.gd` is a pure per-act meter. It runs only during `POSING_IN`/`ACTIVE`:

- every actual disliked touch/talk adds `tolerance.dislike_amount` (1);
- every actual liked touch/talk subtracts `tolerance.like_relief` (1);
- a held caress is a discrete action; its five-second meter is in `docs/hands.md`;
- passive decay subtracts 1 every 25 s;
- warning stages are one-shot per act; compensation can lower distress and avoid a stop but does
  not replay a warning.

| Tier | Warnings | Stop |
|---|---|---|
| Forgiving | one at 4 | never |
| Normal | at 1, then 4 | 10 |
| Strict | at 1 | 3 |

Readiness queues at most one decision per frame (`take_tolerance_decision()`); the runtime presents
it. A warning sets a HUD cue and queues one short spoken warning; a stop runs the runtime's
`_stop_with_her`. Warnings and the stop line speak even when `features.act_lines` is off. The
stop's summary, memory note, cooldown and mood are in `docs/summary.md`; its buck/push is
`docs/scene_gate.md`.

The **Force neglect warning** and **Force neglect stop** debug actions drive the live act for
testing.

## Auto thrust

- `readiness/auto_thrust.gd` is a pure generator: `pace` (1.0–3.75/s), `min_depth` (0–0.82),
  `max_depth` (0.20–1), `curve` (`cosine`, `thrust`, `tease`, `saw`, `hold`). Every shape starts
  at the bottom and returns to the bottom.
- `readiness/auto_panel.gd` is the pure hold-X layer: tap/hold detection, the 0.28 s grace, key repeats and
  the four live rows.
- The runtime reads `Input` and passes the key states to readiness; readiness returns the actions
  and the generated depth. The mouse does nothing while auto is on. The wheel sets pace.
- The panel's `toggle` and min/max/pace nudges are applied inside readiness. The one remaining
  action is `shape_next`: the runtime writes `SETTINGS.curve` and calls `auto_set_shape()`.
- The debug log prints one `auto layer` line per player adjustment, never per frame; a shape
  change adds its own `auto shape` line.
- `X` is live in `ACTIVE`/`CLIMAX`; `_afterglow_begin()`, `_restore_begin()` and `_end_session()`
  stop it, and `_reset_thrust_state()` restores the act-start defaults.
- The auto readout is `Auto · 20–80% · 1.50/s · Normal` (see `docs/hud.md`).

## Lifecycle

- Scope: per-act
- Constructed by: `runtime._init()`
- Begin: `configure()`
- End: `reset()`
- Idempotent: yes


## Settings

Player-facing: `thrust.orientation`, `thrust.pixels_per_cm`, `thrust.travel`,
`thrust.max_pony_climaxes`, `thrust.contact_gap_m`. Debug: `auto_thrust.pace`,
`auto_thrust.min_depth`, `auto_thrust.max_depth`, `auto_thrust.curve`, the touch/talk cooldowns,
the receptive window and the cue pacing under Talk & cues. See `docs/settings.md`; the values are
declared once in `settings/service.gd`.

The per-mare neglect-tolerance tier is a preference field, not a global setting: edit it in
**Characters**. The thresholds, like relief, decay and stop cooldowns, are the `tolerance.*` debug
settings.

## Dependencies

### Uses

| Kind | Target | Entry point | Purpose |
|---|---|---|---|
| service | settings | `settings/service.gd` | settings declarations and live values |
| shared | preferences | `shared/preferences.gd` | profile math and defaults |

## Tests

- `tests/readiness/test_readiness.gd` — facade: stroke scoring, both/one/neither axes, rated
  limit, touch/talk, receptive window, overwhelmed, climax count, the tolerance meter and reset.
- `tests/readiness/test_act_tolerance.gd` — tier thresholds, every-event counting, like relief,
  25 s decay, warning monotonicity and stop cooldowns.
- `tests/readiness/test_act_stop.gd` — neutral/strict stop teardown, history cooldown, no/yes buck
  and request space.
- `tests/readiness/test_thrust.gd` — reversal hysteresis, impact stall, travel, speed, strength,
  contact and jiggle amount.
- `tests/readiness/test_preferences.gd` — profile merge, likes/dislikes, classification.
- `tests/readiness/test_auto_thrust.gd` — every waveform, pace, band, inverse phase and reset.
- `tests/readiness/test_auto_panel.gd` — tap/hold, grace, repeats and the shape cycle.
- `tests/readiness/test_readiness_auto.gd` — the facade: defaults, toggle, step, wheel, the panel
  actions and the reset.

## Verification / lab

- Manual stroke: slow/fast, shallow/deep, the intensity and pattern axes, the readiness line and
  the climax limit.
- Auto: tap X, hold X, the four rows, the wheel, shape cycle, mouse lockout and reset between acts.
- Touch/talk: liked/disliked, the cap, the receptive window and the overwhelmed beat.

## Related docs

- `docs/lines.md` — cue admission, prompt assembly, reactions.
- `docs/hud.md` — cue, readiness and auto text.
- `docs/preferences.md` — the per-mare profile and the two axes.
- `docs/summary.md` — the act summary and the long-term history.
- `docs/afterglow.md` — the post-act phase.
