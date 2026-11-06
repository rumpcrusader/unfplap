# Preference, readiness and climax contract (`unfplap` 0.2.0)

This file covers the ACTIVE-stage scoring, the pony's climaxes, and the player's afterglow
choice. Post-act scoring and the long-term history are `HISTORY.md`. Camera/pose mechanics and
aftercare are outside it.

## What the player does

- Mouse vertical motion feeds raw depth. `thrust.orientation` flips the direction; `"up"`
  (the default) means mouse up deepens. `thrust.pixels_per_full` defaults to `1000`.
- `X` toggles auto thrust in `ACTIVE`/`CLIMAX`. `auto_thrust.gd` drives a raised cosine at
  `pace` thrusts per second from 0 to `max_depth`, and the runtime feeds the same depth tracker
  the mouse feeds. It adds no separate score or heat path: intensity, pattern, readiness, audio
  and presentation are the manual ones. The wheel sets pace; mouse ↕ sets the peak depth.
  `max_depth` is the peak, so after the first stroke the tracker travel is `max_depth - 0.06`
  (`REVERSAL_HYSTERESIS`); the minimum peak is `0.20`.
- A **stroke** is continuous movement in one direction. It closes on a real reversal
  (`REVERSAL_HYSTERESIS = 0.06`) or `STROKE_TIMEOUT_S = 0.18 s` without movement.
- A **thrust** is an inward stroke with `travel >= THRUST_MIN_TRAVEL = 0.12` and
  `duration >= MIN_THRUST_DURATION = 0.04 s`. The minimum auto peak travels 0.14 and therefore
  counts as a real soft thrust. Tiny jitter, pullbacks and outward strokes are presentation only:
  they do not update the axes or score readiness.
- `strength = clamp(travel × clamp(speed / 8.0, 0.15, 1.5), 0, 1)` is the intensity value.
  The `0.15` floor lets a slow full-depth stroke read as soft. Average speed drives intensity;
  peak speed is logged and capped at `2 × average speed`, but one fast sample cannot saturate
  the score by itself.
- Visual impact is `min(1, strength × 2.0)`, so normal and fast thrusts keep the tuned wing,
  ear and blush response while slow or shallow strokes stay lighter; the foley scales from
  `strength` directly. The rump/tail wobble is separate:
  `THRUST.jiggle_amount(travel, strength)` follows travel, so a full stroke wobbles the same at
  any speed, and the soft band fades the gentlest strokes to `0.04`. The camera is on its own
  speed-driven channel, not this impact value.
- `satisfaction` is her arousal/readiness 0–100. At 100 she climaxes; the player chooses
  afterglow separately. Readiness now rises in discrete chunks from real thrusts, not on a
  passive timer.

## Preference profile

```gdscript
{
    "intensity": "firm",          # soft | firm | rough
    "pattern": "steady",          # steady | teasing | quick
    "touch": ["caress"],          # liked: smack, caress, kiss
    "dislikes": [],               # touch or talk dislike
    "talk": ["reassurance"],      # empty = talk does not score for her
    "warmth": "normal",           # quick | normal | slow
    "tolerance": "normal",        # forgiving | normal | strict
    "notes": "private attitude for the AI"
}
```

- `warmth` scales readiness gain: `quick` ×1.25, `normal` ×1.0, `slow` ×0.8.
- `tolerance` (Neglect tolerance) sets mid-act warnings and the stop threshold; see `HISTORY.md`.
- `touch`/`talk` are likes; `dislikes` cannot overlap a like.

## Settings editor

`Settings → Unfplap` is drawn from the tunable schema (`tunables_schema.gd`); every row has a
label and a help line, sits in a named section, and applies live during an act. Adding or
reading a setting goes through `tunables.gd` only — see `TUNING.md`.

**General tab**

- **Controls**: HUD readouts, control hints, captions on top, Promiscuity, Starting Sex, mute
  Ponese audio.
- **Thrust**: mouse-up direction, sensitivity in pixels per full thrust (`240…1200`, default
  `1000`), hip back-off (`0.25…2.0×`, default `0.5×`), climax limit (`0…20`, default `3`; `0` is
  unlimited), and auto-thrust pace (`1.0…3.75/s`, default `1.0/s`, quarter steps) and peak depth
  (`0.20…1`, default `0.5`). The auto values are act-start defaults; the wheel and mouse adjust
  them for one act.

**Characters tab**

- The hand-built per-mare preference form described below, with one pony selector (filtered by name)
  shared by every field.

**Anatomy tab**

- **Anatomy**: the master switch, teats, skin tone, only during acts and the coat depth bias.
- **Anon part**: size, pitch, yaw and roll.
- **Actions**: hole switch, oral and finish control.
- **Effects**: climax and finish fluid.
- **Experimental**: hip alignment, the Anon bed body and the VR act.

**Debug tab**

- **General**: debug logs and the separate perf-log toggle (both off by default).
- **Talk & cues**: override lifetime (default `10 s`), base/override stability, shared line gap,
  demand gap/repeat, cue/reaction max age, release hold, overwhelmed duration, and the touch/talk
  cooldowns plus receptive window.
- **History** and **Neglect tolerance**: the act summary/history scoring and threshold values.
- **Audio**: act foley, act vocals, wet climax layer.
- **Camera**: idle camera sway, plus the two `0…100%` camera-thrust amounts, defaulting to Surge
  `100%` and Bob `35%`. Surge is the forward camera travel, Bob the vertical dip; both follow the
  filtered thrust **speed**, not depth, with one smooth critically damped response.
- **Missionary**: forward, height, side, pullback, side-lean forward (`side_lean`, default
  `0.10 m`), pitch (`pitch_deg`, default `-15°`; positive looks up) and the five neck angles
  (neck 1/2, neck roll, head pitch, head roll).
- **Standing → Motion**: glance-back speed (`0.25…3.0×`), Anon torso lean.
- **Standing → Kiss**: mouth right/down/forward, camera yaw, side/forward/drop lean.
- **Standing → Caress**: palm distance (`0.02 m`), oval across/up (`1.0 cm` / `2.0 cm`), palm
  scale per body-size preset (Canon `0.75`, mounting `0.9`, same height `1.0`, Hoers `1.0`), and
  ignored body parts (tail and wing by default).
- **Standing → Smack**: max raise (`0.30 m`), hind offset (`0.10 m`), height (`-0.03 m`), palm
  arc (`0.06 m`), palm pitch (`12°`), raise speed (`2.0 m/s`) and return speed (`6.0 m/s`).

There are no Save buttons: each edit writes its value and applies to the active act immediately.
Debug numbers are never clamped; only the player-facing contract bounds listed above are
enforced. The framing, pitch and torso controls remain experimental and unbounded.

The **Characters** tab exposes one name-filtered pony selector and one form:

- intensity, pattern, warmth;
- neglect tolerance (forgiving, normal, strict);
- liked touch and talk;
- disliked touch and talk;
- public, anal and oral consent;
- private notes.

Preference edits save automatically and apply live during an act. `Reset to default` removes only the
preference override and preserves that character's custom `event_prompts` and pose settings.
Consent defaults are deterministic from her id and can be overridden per pony; `Reset to default`
does not clear those overrides.
- Public consent is opt-in and off by default for every mare. It only matters while
  `features.act_public_offer` is on; it lets her offer with others around.
- Anal consent gates `V`; oral consent gates `N`. A refusal gives a short status toast and leaves
  the act in its current state.
`hud_readouts` is a normal feature toggle in the General tab; the standing close window is always
on.

## The two continuous axes

### Intensity

From the last real inward thrust's strength:

```text
soft   strength < 0.33
firm   0.33 <= strength < 0.60
rough  strength >= 0.60
```

### Pattern

Classified over the last 3–4 real inward thrusts. Fewer than 3 means “no pattern yet”; only
the intensity axis can match. Pattern is tempo only; depth does not decide the rhythm.

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
- Cue lines are event-driven, not a timer. `utterance_scheduler.gd` owns admission, with the
  **Debug → Talk & cues** tunables as its pacing:
  - a base cue must stay unchanged for `cues.base_stable_seconds` (default `2 s`);
  - a live touch/talk override only needs `cues.override_stable_seconds` (default `0.5 s`), so
    an event cue can speak inside its `cues.override_seconds` lifetime (default `10 s`); if the
    override ends first, the queued line is dropped;
  - the per-mare `cue_gap` (default `12`, clamped `8..30`) and `cues.utterance_gap_seconds`
    (default `18 s`) must both have elapsed;
  - demand cues (`She wants it…`, `She wants a…`, `She wants to be teased…`, `She needs…`) get
    `cues.demand_gap_seconds` (default `28 s`) and `cues.demand_repeat_seconds` (default `45 s`)
    for the same text;
  - the same text as the last queued cue is not repeated, but may return after another cue;
  - a cue or reaction owns one slot at a time. Reactions bypass the cue gates but reset the shared
    gap. A queued or generating row is dropped at `cues.max_age_seconds` (default `20 s`, cue) or
    `cues.reaction_max_age_seconds` (default `30 s`, reaction); a row already speaking is never
    cut. A quiet or unchanged act may produce no cue line.
- The base fallback cue is `She wants you to keep going.` A neutral touch sets no override; a
  neutral talk sets `She listens.` The two assist-cap lines mean the touch/talk assist is already
  at `ASSIST_CAP = 60` and only real thrusting can add more.
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

- At 100 readiness she climaxes. The user-facing `thrust.max_pony_climaxes` setting (default
  `3`) sets the limit; `0` is unlimited.
- The act enters `CLIMAX` for `CLIMAX_SECONDS = 5`.
- The player can keep thrusting during those 5 s. The thrust is presentation only: it does not
  update intensity, pattern or readiness.
- Each climax sends a unique world-context event and a unique generated reaction.
- When the 5 s ends:
  - below the configured limit, or unlimited: return to `ACTIVE`, set readiness to `0`,
    clear pattern;
  - at a non-zero configured limit: enter `AFTERGLOW` automatically.

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
- A non-zero configured climax limit forces afterglow after that climax's 5 s effect.
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
- **Once at afterglow:** `_commit_summary()` scores the act, `MEMORY.commit_act()` writes the
  grade-aware romance and mood, and `MEMORY.afterglow_event` and `WITNESS.commit` follow. See
  `HISTORY.md`.
- **Standing inside event:** at afterglow only, as the player's finish. It records context but no
  longer queues a line.
- **Standing close reward:** `MEMORY.stay_close_reward` records a private memory. On a good or
  non-early neutral act, staying and caressing adds a happy mood, a private thought and a small
  `romance` gain. After a bad act, staying and caressing repairs one point of history hurt instead.
- **Peak act:** one strongest memory per mare is kept in
  `Mods.state("unfplap").peak_memories`. It requires a positive summary, no disliked touch/talk and
  either peak readiness >= 90 or six both-axis thrust matches. A later higher-scoring act replaces
  it. The text is the last player exchange, or a generic warm beat if he did not speak.
- **Zero-climax Y:** the early-stop/cancel path commits an early summary but no romance. The
  summary can add hurt through `HISTORY.md`; the early-stop reaction includes what she wanted.
- Act lines that have not started speaking are cancelled at every climax/afterglow boundary and
  at every act end. A line already speaking may finish. The intentional early-stop line is
  queued after the act-line cancel.

## HUD

- `hud_readouts` (default `true`) shows the cue and the separate `Wants`/`You` line.
- `act_controls` (default `true`) shows the control card. Off hides only the card; the cue,
  readiness line and close prompt remain.
- Top to bottom: cue line `❤ N/limit | cue` (or `❤ N/∞` when the climax limit is unlimited),
  readiness line `Wants: intensity & pattern | You: intensity & pattern`, auto readout
  `Auto · wheel pace N/s · depth N%` while auto is on, blank separator, controls.
- When readouts are off, the hearts remain; the cue and readiness line are hidden.
- In afterglow the summary is always shown: missionary puts it in the cue line, standing keeps its
  close prompt in the cue and puts the summary on the readiness line. Early end shows no summary.
- There is no penetration/depth bar; the thrust mechanic, `thrust.orientation` and auto thrust
  still apply.
- The controls list keeps its Y row dynamic: `End early` at 0 climaxes, then `End` in `ACTIVE`
  with 1+, `CLIMAX` and `AFTERGLOW`. `End` shades from ink toward the pink accent one step per
  climax, capped at 75%; only the earned standing afterglow caress reward makes it fully pink.
  The thrust row reads `Thrust` or `Max depth`, and the X row reads `Switch to auto` or
  `Switch to manual`. The pose rows read `Lean`, `Reach`, `Caress` and `Caress movement`; they do
  not spell out both directions. Only the two `Hold` rows carry the modifier column, so an icon
  is followed by its words with no reserved blank space.
- The control card fades to 20% while Anon leans or leans in for a kiss and returns after it;
  the cue and readiness readouts stay at full opacity.
- Afterglow shows `❤ N/limit | close hint` instead of `Wants`/`You`. Missionary keeps only `Y`;
  standing keeps lean, reach, caress, caress movement, kiss and Y; thrust, auto and smack are
  hidden.
- Captions can move to the top of the screen when the game's speech setting is the explicit
  bottom caption; `captions_on_top` defaults to `true`.
- `debug_logs` gates the detailed overlay, not the HUD. `debug_perf` separately gates the
  per-second performance block and requires `debug_logs` too.

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

Every spawnable adult mare in the base game has an explicit profile in `character_preferences.gd`:
102 mares, the original sixteen first in the selector and the rest alphabetical. This table is
the main cast sample; the catalog carries the full roster. `twist` (written as a schoolfilly) and
`fiddly_twang` (written as a stallion) are left out because their identity flags do not match
their character profiles.

| Character | Intensity | Pattern | Touch | Talk | Warmth |
|---|---|---|---|---|---|
| Twilight | firm | steady | kiss | praise | normal |
| Fluttershy | firm | steady | caress | reassurance | slow |
| Rarity | soft | steady | caress | praise | normal |
| Pinkie | firm | quick | smack | playful | quick |
| Applejack | firm | steady | caress, smack | praise, reassurance | normal |
| Rainbow | rough | quick | smack | praise, playful | quick |
| Derpy | rough | quick | smack | playful | quick |
| Lyra | firm | steady | caress, kiss | playful | normal |
| Octavia | soft | steady | caress | praise | slow |
| Vinyl | rough | quick | smack, kiss | playful | quick |
| Berry | rough | quick | smack | playful, dirty | quick |
| Cheerilee | firm | steady | caress | praise, reassurance | normal |
| Maud | soft | steady | caress | none (quiet) | slow |
| Trixie | firm | steady | kiss | praise, playful | quick |
| Zecora | firm | steady | caress | reassurance | slow |
| Spitfire | rough | quick | smack | praise, playful | normal |
| Default | firm | steady | none | none | normal |

Dislikes are shown in the settings editor and stay in the `preferences` block. They are used only where
the character's temperament supports them; the main cast uses `smack` and/or `dirty` for Rarity,
Octavia, Maud and Zecora, and the wider roster follows the same rule.

The `notes` field carries the private attitude; the AI prompt receives the mood, the preference
summary and the last concrete input, never a speed or depth dump.
