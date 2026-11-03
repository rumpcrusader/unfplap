# Taste, readiness and climax contract (`unfplap` 0.0.3)

This file covers the ACTIVE-stage scoring, the pony's climaxes, and the player's afterglow
choice. Camera/pose mechanics and aftercare are outside it.

## What the player does

- Mouse vertical motion feeds raw depth. `pump.orientation` flips the direction; `"up"`
  (the default) means mouse up deepens.
- A **stroke** is continuous movement in one direction. It closes on reversal or
  `STROKE_TIMEOUT_S = 0.18 s` without movement.
- A **pump** is an inward stroke with `travel >= PUMP_MIN_TRAVEL = 0.25`.
- There is no base gain and no per-stroke multiplier. A stroke is classified, not scored.
- `strength = clamp(travel × clamp(peak_speed / 1.0, 0.35, 1.5), 0, 1)` remains the physical
  force used by jiggle and wings.
- `satisfaction` is her arousal/readiness 0–100. At 100 she climaxes; the player chooses
  afterglow separately.

## Taste profile

```gdscript
{
    "intensity": "firm",          # soft | firm | rough
    "pattern": "steady",          # steady | building | teasing | quick
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

`Settings → Unfplap → Character taste` exposes one pony selector and one form:

- intensity, pattern, warmth;
- recovery `0…80`;
- liked touch and talk;
- disliked touch and talk;
- private notes.

`Save taste` writes only `characters[id].taste`; it preserves that character's custom
`event_prompts` and pose settings. `Reset to default` removes only the taste override.
The runtime reads the merged taste at act start, so saved changes apply on the next act.

## The two continuous axes

### Intensity

From the last inward pump's strength:

```text
soft   strength < 0.33
firm   0.33 <= strength < 0.66
rough  strength >= 0.66
```

### Pattern

Classified over the last 3–4 inward pumps. Fewer than 3 pumps means “no pattern yet”; only
the intensity axis can match.

```text
teasing  mean travel < 0.38 and mean duration > 0.75 s
quick    mean duration < 0.42 s and mean travel < 0.62
building last travel > first travel × 1.25 and gain >= 0.08
steady   otherwise
```

## Readiness

`satisfaction` is readiness. It starts at 0, caps at 100, and is visible as the second HUD
bar when `readiness_hud` is on.

```text
both axes match       +2.0 /s × warmth
one axis matches      +1.0 /s × warmth
neither matches       no gain; after 3 s, -1.5 /s
liked touch / talk    +6.0 once
disliked touch/talk   -6.0 once and 1.2 s overwhelmed
```

- The pattern/intensity memory clears after 1.2 s without an inward pump.
- Cooling is recoverable. Change rhythm, touch her, or answer her.
- No hard stop from a mismatch.

## Mood and cues

```text
warming       readiness < 40
wanting       40 <= readiness < 65
close         readiness >= 65
climax        the pony is in her 5 s climax
cooling       no match for 3 s and readiness is falling
overwhelmed   a disliked touch/talk landed recently
```

- `CLOSE_AT = 65` is only the “she's close” cue.
- `PONY_CLIMAX_AT = 100` triggers the pony's climax.
- A **talk cue** is an invitation, not a gate. It can appear while `mood == wanting` for a
  mare with a non-empty `talk` taste. The HUD shows `T · Answer her`. The player's reply is
  the director's player turn; the runtime drops the cue's pending line and scores the reply.

## Pony climax

- At 100 readiness she climaxes. `MAX_PONY_CLIMAXES = 5`.
- The act enters `CLIMAX` for `CLIMAX_SECONDS = 5`.
- The player can keep pumping during those 5 s. The pump is presentation only: it does not
  update intensity, pattern or readiness.
- Each climax sends a unique world-context event and a unique generated reaction.
- When the 5 s ends:
  - fewer than 5 climaxes: return to `ACTIVE`, set readiness to `recovery`, clear pattern;
  - 5th climax: enter `AFTERGLOW` automatically.
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
- The 5th climax forces afterglow after its 5 s effect.

## Memory and rewards

- **Per pony climax:** a unique world-context event and a generated reaction.
- **Once at afterglow:** `MEMORY.commit_climax` and `WITNESS.commit`.
- **Pose-2 inside event:** at afterglow only, as the player's finish.
- **Zero-climax Y:** the existing early-stop/cancel path; no romance commit.

## HUD

- Readiness bar shows arousal; `65` is close, `100` is pony climax.
- There is no penetration/depth bar; the pump mechanic and `pump.orientation` still apply.
- `ACTIVE` Y hint: `Hold Y · Stop` at 0 climaxes; `Hold Y · Afterglow` at 1+.
- `CLIMAX` Y hint: `Hold Y · Afterglow`.
- A climax count/cue may be shown; no new meter.
- `readiness_hud` defaults to `true` and gates the readiness bar and mood cues.
- `debug_logs` gates the detailed overlay, not the readiness bar.

## Touch and talk classification

| Action | Event |
|---|---|
| mouse right smack | `smack` |
| held caress | `caress` |
| kiss | `kiss` |

Each has a 4 s scoring cooldown. Talk uses the game's `T`/microphone turn and the small
keyword map in `preferences.gd`; the AI still writes her reply.

## Character examples

| Character | Intensity | Pattern | Touch | Talk | Warmth | Recovery |
|---|---|---|---|---|---|---|
| Twilight | firm | steady | kiss | curious, praise | normal | 20 |
| Fluttershy | firm | building | caress | reassurance | slow | 12 |
| Rarity | soft | steady | caress | praise | normal | 18 |
| Pinkie | firm | quick | smack | playful | quick | 35 |
| Applejack | firm | steady | caress, smack | praise, reassurance | normal | 24 |
| Rainbow | rough | quick | smack | praise, playful | quick | 30 |
| Derpy | rough | quick | smack | playful | quick | 35 |
| Lyra | firm | steady | caress, kiss | curious, playful | normal | 22 |
| Octavia | soft | steady | caress | praise | slow | 15 |
| Vinyl | rough | quick | smack, kiss | playful | quick | 32 |
| Berry | rough | quick | smack | playful, dirty | quick | 30 |
| Cheerilee | firm | building | caress | praise, reassurance | normal | 20 |
| Maud | soft | steady | caress | none (quiet) | slow | 10 |
| Trixie | firm | building | kiss | praise, playful | quick | 28 |
| Zecora | firm | steady | caress | curious, reassurance | slow | 18 |
| Spitfire | rough | quick | smack | praise, playful | normal | 26 |
| Default | firm | steady | none | none | normal | 20 |

Dislikes are shown in the settings editor and stay in the `taste` block. The current
templates use `smack` and/or `dirty` as dislikes for Rarity, Octavia, Maud and Zecora.

The `notes` field carries the private attitude; the AI prompt receives the mood, the taste
summary and the last concrete input, never a speed or depth dump.
