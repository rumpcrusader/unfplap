# Taste, readiness and climax contract (`unfplap` 0.1.2)

This file covers the ACTIVE-stage scoring, the pony's climaxes, and the player's afterglow
choice. Camera/pose mechanics and aftercare are outside it.

## What the player does

- Mouse vertical motion feeds raw depth. `thrust.orientation` flips the direction; `"up"`
  (the default) means mouse up deepens. `thrust.pixels_per_full` defaults to `1000`.
- `X` toggles auto thrust in `ACTIVE`/`CLIMAX`. `auto_thrust.gd` drives a raised cosine at
  `pace` thrusts per second from 0 to `max_depth`, and the runtime feeds the same depth tracker
  the mouse feeds. It adds no separate score or heat path: intensity, pattern, readiness, audio
  and presentation are the manual ones. The wheel sets pace; mouse ↕ sets the peak depth.
  `max_depth` is the peak, so after the first stroke the tracker travel is `max_depth - 0.06`
  (`REVERSAL_HYSTERESIS`); the minimum peak is `0.32`.
- A **stroke** is continuous movement in one direction. It closes on a real reversal
  (`REVERSAL_HYSTERESIS = 0.06`) or `STROKE_TIMEOUT_S = 0.18 s` without movement.
- A **thrust** is an inward stroke with `travel >= THRUST_MIN_TRAVEL = 0.25` and
  `duration >= MIN_THRUST_DURATION = 0.04 s`. Tiny jitter, pullbacks and outward strokes are
  presentation only: they do not update the axes or score readiness.
- `strength = clamp(travel × clamp(speed / 8.0, 0.15, 1.5), 0, 1)` is the intensity value.
  The `0.15` floor lets a slow full-depth stroke read as soft. Average speed drives intensity;
  peak speed is logged and capped at `2 × average speed`, but one fast sample cannot saturate
  the score by itself.
- Visual impact is `min(1, strength × 2.0)`, so normal and fast thrusts keep the tuned jiggle
  and wing response while slow or shallow strokes stay lighter. The camera is on its own
  speed-driven channel, not this impact value.
- `satisfaction` is her arousal/readiness 0–100. At 100 she climaxes; the player chooses
  afterglow separately. Readiness now rises in discrete chunks from real thrusts, not on a
  passive timer.

## Taste profile

```gdscript
{
    "intensity": "firm",          # soft | firm | rough
    "pattern": "steady",          # steady | teasing | quick
    "touch": ["caress"],          # liked: smack, caress, kiss
    "dislikes": [],               # touch or talk dislike
    "talk": ["reassurance"],      # empty = talk does not score for her
    "warmth": "normal",           # quick | normal | slow
    "recovery": 20,               # readiness after a climax, 0..80
    "notes": "private attitude for the AI"
}
```

- `warmth` scales readiness gain: `quick` ×1.25, `normal` ×1.0, `slow` ×0.8.
- `recovery` is where readiness restarts after each pony climax:
  - `0` means she must be built up from nothing;
  - `20` is the baseline;
  - `35` means she starts the next cycle already warm;
  - cap is `80` so nobody instantly re-climaxes.
- `touch`/`talk` are likes; `dislikes` cannot overlap a like.

## Settings editor

`Settings → Unfplap` is drawn from the tunable schema (`tunables_schema.gd`); every row has a
label and a help line, sits in a named section, and applies live during an act. Adding or
reading a setting goes through `tunables.gd` only — see `TUNING.md`.

**Settings tab**

- **Controls**: HUD readouts, control hints, captions on top, Promiscuity, Starting Sex, mute
  Ponese audio.
- **Thrust**: mouse-up direction, sensitivity in pixels per full thrust (`240…1200`, default
  `1000`), hip back-off (`0.25…2.0×`, default `0.5×`), and auto-thrust pace (`0.5…5/s`, default
  `1.5/s`, quarter steps) and peak depth (`0.32…1`, default `0.9`). The auto values are act-start
  defaults; the wheel and mouse adjust them for one act.
- **Character taste**: the per-mare form described below.

**Debug tab**

- **Audio**: act foley, act vocals, wet climax layer, bed creaks.
- **Camera**: idle camera sway, plus the two `0…100%` camera-thrust amounts, defaulting to Surge
  `100%` and Bob `35%`. Surge is the forward camera travel, Bob the vertical dip; both follow the
  filtered thrust **speed**, not depth, with one smooth critically damped response.
- **Missionary**: forward, height, side, pullback, side-lean forward (`side_lean`, default
  `0.10 m`), pitch (`pitch_deg`, default `-15°`; positive looks up) and the five neck angles
  (neck 1/2, neck roll, head pitch, head roll).
- **Standing → Motion**: glance-back speed (`0.25…3.0×`), Anon torso lean, idle side sway.
- **Standing → Kiss**: mouth right/down/forward, camera yaw, side/forward/drop lean, forelegs.
- **Standing → Caress**: palm distance (`0.04 m`), oval across/up (`5.36 cm` / `2.89 cm`), palm
  scale per body-size preset (Canon `0.75`, mounting `0.9`, same height `1.0`, Hoers `1.0`), and
  ignored body parts (tail and wing by default).
- **Standing → Smack**: max raise (`0.30 m`), hind offset (`0.10 m`), height (`-0.03 m`), palm
  arc (`0.06 m`), palm pitch (`12°`), raise speed (`2.0 m/s`) and return speed (`6.0 m/s`).

There are no Save buttons: each edit writes its value and applies to the active act immediately.
Debug numbers are never clamped; only the player-facing contract bounds listed above are
enforced. The framing, pitch and torso controls remain experimental and unbounded.

The **Character taste** section exposes one pony selector and one form:

- intensity, pattern, warmth;
- recovery `0…80`;
- liked touch and talk;
- disliked touch and talk;
- private notes.

Taste edits save automatically and apply live during an act. `Reset to default` removes only the
taste override and preserves that character's custom `event_prompts` and pose settings.
`hud_readouts` is a normal feature toggle in the same tab; the standing close window is always on.

## The two continuous axes

### Intensity

From the last real inward thrust's strength:

```text
soft   strength < 0.33
firm   0.33 <= strength < 0.66
rough  strength >= 0.66
```

### Pattern

Classified over the last 3–4 real inward thrusts. Fewer than 3 means “no pattern yet”; only
the intensity axis can match.

```text
teasing  mean travel < 0.38 and mean duration > 0.75 s
quick    mean duration < 0.42 s and mean travel < 0.62
steady   otherwise
```

## Readiness

`satisfaction` is readiness. It starts at 0 and caps at 100. The optional HUD readouts
(`hud_readouts`, default `true`) show a short bar plus `Wants: firm & steady | You: …`.

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

- `CLOSE_AT = 65` is only the “she's close” cue.
- `PONY_CLIMAX_AT = 100` triggers the pony's climax.
- Cue lines are event-driven, not a timer. `utterance_scheduler.gd` owns admission:
  - a base cue must stay unchanged for `CUE_STABLE_S = 2 s`;
  - a live touch/talk override only needs `CUE_OVERRIDE_STABLE_S = 0.5 s`, so an event cue can
    speak inside its 2.5 s HUD lifetime; if the override ends first, the queued line is dropped;
  - the per-mare `cue_gap` (default `12`, clamped `8..30`) and the shared 18 s utterance gap must
    both have elapsed;
  - demand cues get a 28 s demand budget and a 45 s same-text repeat lock;
  - the same text as the last queued cue is not repeated, but may return after another cue;
  - a cue or reaction owns one slot at a time. Reactions bypass the cue gates but reset the 18 s
    gap. A queued or generating row is dropped at 20 s (cue) or 30 s (reaction); a row already
    speaking is never cut. A quiet or unchanged act may produce no cue line.
- Every cue line gets a private relationship note and tone: friendship/love level, stage,
  first-time/repeat, mood, then `tender`/`warm`/`ardent`/`open`/`careful`. The functional cue
  text is unchanged, and the model is not told to repeat specific names.
- One unused shared memory may ride with a cue. A stored peak memory is preferred; otherwise
  the story journal (a cue-word match, then the most recent player exchange), then older
  world-context events. Intimacy events and private brain notes are skipped. The memory is
  colour, not a script. A peak memory quotes her answer only when she spoke during the act.
- Talk is scored when the player actually uses the game's talk turn. There is no act
  talk-invitation line or HUD hint.
- `features.act_lines` (default on) gates unprompted cue and reaction lines. Off keeps normal
  dialogue and the HUD cue.

## Pony climax

- At 100 readiness she climaxes. `MAX_PONY_CLIMAXES = 3`.
- The act enters `CLIMAX` for `CLIMAX_SECONDS = 5`.
- The player can keep thrusting during those 5 s. The thrust is presentation only: it does not
  update intensity, pattern or readiness.
- Each climax sends a unique world-context event and a unique generated reaction.
- When the 5 s ends:
  - fewer than 3 climaxes: return to `ACTIVE`, set readiness to `recovery`, clear pattern;
  - 3rd climax: enter `AFTERGLOW` automatically.
- The pony's `recovery` is per-mare, so a slow/low-recovery mare needs a thorough approach
  and a quick/high-recovery mare reaches the next climax faster.

## Player afterglow

Hold `Y`:

| State | Climaxes | Result |
|---|---:|---|
| `POSING_IN` | any | cancel |
| `ACTIVE` | 0 | cancel / early stop |
| `ACTIVE` | 1+ | afterglow |
| `CLIMAX` | 1+ | afterglow |
| `AFTERGLOW` | any | end afterglow |

- The player cannot enter afterglow before the first pony climax.
- One or more climaxes allows afterglow at any time.
- The 3rd climax forces afterglow after its 5 s effect.
- Pegasi and alicorns slowly fold their wings back to rest during afterglow over 6 s rather
  than holding the spread pose until the act ends.

### Standing close window

The standing afterglow always starts an 8 s close window:

- the HUD shows `Stay close · 8s · caress`;
- A/D caress time is counted while a hand is active; Z/C pause/resume the oval movement
  without releasing the palm;
- the player can hold `Y` to leave early, which cancels the reward;
- at 8 s, 2.5 s or more of caress grants the full reward; staying without caressing gets only
  the “She seems content.” cue;
- missionary afterglow is unchanged.

Normal dialogue resumes in the afterglow. The `inside` and `stay_close` generated lines are
removed; the HUD timer and active caress time own the standing close invitation. A world-context
event records that the act has ended while the two are still in the afterglow together, so a
normal reply keeps the moment present without a scripted line.

After 16 s the mare may choose to end the afterglow herself. The roll is once per second;
caressing or leaning close lowers the chance. An accepted `[stay: SECONDS]` action from normal
dialogue pauses the roll for that long. The live prompt note tells her whether Anon is
caressing her or leaning in; leaning counts as staying close/hugging.

## Memory and rewards

- **Per pony climax:** a unique world-context event and a generated reaction.
- **Once at afterglow:** `MEMORY.commit_climax`, `MEMORY.afterglow_event` and `WITNESS.commit`.
- **Standing inside event:** at afterglow only, as the player's finish. It records context but no
  longer queues a line.
- **Standing close reward:** `MEMORY.stay_close_reward` records a private memory. Staying and
  caressing adds a happy mood, a private thought and a small `romance` gain; staying alone
  records the warm beat without the extra romance.
- **Peak act:** one strongest memory per mare is kept in
  `Mods.state("unfplap").peak_memories`. It requires no disliked touch/talk and either peak
  readiness >= 90 or six both-axis thrust matches. A later higher-scoring act replaces it. The
  text is the last player exchange, or a generic warm beat if he did not speak.
- **Zero-climax Y:** the existing early-stop/cancel path; no romance commit.
- Act lines that have not started speaking are cancelled at every climax/afterglow boundary and
  at every act end. A line already speaking may finish. The intentional early-stop line is
  queued after the act-line cancel.

## HUD

- `hud_readouts` (default `true`) shows the cue, a short 0–100 bar with no ticks, and the
  separate `Wants`/`You` line.
- `act_controls` (default `true`) shows the control card. Off hides only the card; the cue,
  readiness line, bar and close prompt remain.
- Top to bottom: cue line `❤ N/3 | cue`, readiness line
  `Wants: intensity & pattern | You: intensity & pattern`, auto readout
  `Auto · wheel pace N/s · depth N%` while auto is on, readiness bar, blank separator,
  controls.
- When readouts are off, the hearts remain; the cue, readiness line and bar are hidden.
- There is no penetration/depth bar; the thrust mechanic, `thrust.orientation` and auto thrust
  still apply.
- The controls list keeps its Y row dynamic: `Hold: stop` at 0 climaxes, `Hold: afterglow`
  at 1+ and in `CLIMAX`, and `Hold: exit` in afterglow. The thrust row reads `Thrust` or
  `Max depth`, and the X row reads `Switch to auto` or `Switch to manual`. The pose rows read
  `Lean`, `Reach`, `Caress` and `Caress movement`; they do not spell out both directions.
  Only the two `Hold` rows carry the modifier column, so an icon is followed by its words with
  no reserved blank space.
- The control card fades to 20% while Anon leans in for a kiss and returns after it; the cue and
  readiness readouts stay at full opacity.
- Afterglow shows `❤ N/3 | close hint` instead of `Wants`/`You`. Missionary keeps only `Y`;
  standing keeps lean, reach, caress, caress movement, kiss and Y; thrust, auto and smack are
  hidden.
- Captions can move to the top of the screen when the game's speech setting is the explicit
  bottom caption; `captions_on_top` defaults to `true`.
- `debug_logs` gates the detailed overlay, not the HUD.

## Touch and talk classification

| Action | Event |
|---|---|
| mouse right smack | `smack` |
| held caress | `caress` |
| kiss | `kiss` |

Touch shares one 4 s scoring cooldown across smack, caress and kiss. Talk has an 8 s scoring
cooldown and uses the game's `T`/microphone turn plus the small keyword map in
`preferences.gd`; the AI still writes her reply.

## Character examples

| Character | Intensity | Pattern | Touch | Talk | Warmth | Recovery |
|---|---|---|---|---|---|---|
| Twilight | firm | steady | kiss | curious, praise | normal | 20 |
| Fluttershy | firm | steady | caress | reassurance | slow | 12 |
| Rarity | soft | steady | caress | praise | normal | 18 |
| Pinkie | firm | quick | smack | playful | quick | 35 |
| Applejack | firm | steady | caress, smack | praise, reassurance | normal | 24 |
| Rainbow | rough | quick | smack | praise, playful | quick | 30 |
| Derpy | rough | quick | smack | playful | quick | 35 |
| Lyra | firm | steady | caress, kiss | curious, playful | normal | 22 |
| Octavia | soft | steady | caress | praise | slow | 15 |
| Vinyl | rough | quick | smack, kiss | playful | quick | 32 |
| Berry | rough | quick | smack | playful, dirty | quick | 30 |
| Cheerilee | firm | steady | caress | praise, reassurance | normal | 20 |
| Maud | soft | steady | caress | none (quiet) | slow | 10 |
| Trixie | firm | steady | kiss | praise, playful | quick | 28 |
| Zecora | firm | steady | caress | curious, reassurance | slow | 18 |
| Spitfire | rough | quick | smack | praise, playful | normal | 26 |
| Default | firm | steady | none | none | normal | 20 |

Dislikes are shown in the settings editor and stay in the `taste` block. The current
templates use `smack` and/or `dirty` as dislikes for Rarity, Octavia, Maud and Zecora.

The `notes` field carries the private attitude; the AI prompt receives the mood, the taste
summary and the last concrete input, never a speed or depth dump.
