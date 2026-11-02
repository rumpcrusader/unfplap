# Taste and ACTIVE readiness contract (`unfplap` 0.0.2)

This file is the ACTIVE-stage scoring contract. Camera, poses, aftercare and ordinary
dialogue delivery are outside it.

## What the player does

- Mouse vertical motion feeds raw depth. `pump.orientation` flips the direction; the top of
  the depth bar is deep/orange with `"up"`.
- A **stroke** is continuous movement in one direction. It closes on reversal or
  `STROKE_TIMEOUT_S = 0.18 s` without movement.
- A **pump** is an inward stroke with `travel >= PUMP_MIN_TRAVEL = 0.25`.
- There is no base gain and no per-stroke multiplier. A stroke is classified, not scored.
- `strength = clamp(travel × clamp(peak_speed / 1.0, 0.35, 1.5), 0, 1)` remains the physical
  force used by jiggle and wings.
- `satisfaction` is readiness 0–100. It is not a stroke score and it does **not** trigger the
  climax automatically.

## Taste profile

One block per mare. Unknown or missing values fall back to the neutral default.

```gdscript
{
    "intensity": "firm",          # soft | firm | rough
    "pattern": "steady",          # steady | building | teasing | quick
    "touch": ["caress"],          # liked: smack, caress, kiss
    "dislikes": [],               # touch or talk dislike
    "talk": ["reassurance"],      # empty = talk does not score for her
    "pose": "missionary",         # missionary | horse | any
    "warmth": "normal",           # quick | normal | slow
    "notes": "private attitude for the AI"
}
```

- `touch` and `talk` are lists. A liked item cannot also be a dislike.
- `pose` is a soft preference. The current pose gives a small starting-readiness bonus and a
  more enthusiastic cue; the other pose is neutral, not a failure.
- `warmth` scales readiness gain (`quick` 1.25, `normal` 1.0, `slow` 0.8). It does not force
  a fixed act length.

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

`satisfaction` is readiness. It starts at 0 (plus a pose bonus), caps at 100 and is visible
as the second HUD bar when `readiness_hud` is on.

```text
both axes match       +2.0 /s × warmth
one axis matches      +1.0 /s × warmth
neither matches       no gain; after 3 s, -1.5 /s
liked touch / talk    +6.0 once
disliked touch/talk   -6.0 once and 1.2 s overwhelmed
```

- The pattern/intensity memory clears after 1.2 s without an inward pump. A held caress or a
  spoken line can keep the moment alive, but it does not replace the pump forever.
- Cooling is recoverable. Change rhythm, touch her, or answer her.
- No hard stop from a mismatch. Consent and the `Y` control remain separate.

## Mood and cues

```text
warming       readiness < 40
wanting       40 <= readiness < 65
close         readiness >= 65
cooling       no match for 3 s and readiness is falling
overwhelmed   a disliked touch/talk landed recently
```

- `READY_AT = 65`. The player can finish at or above it; below it, hold `Y` still cancels.
- The cue is a short third-person HUD line: “She wants it harder”, “She's losing focus”,
  “She's close”, “She likes that”. It is not a new dialogue line.
- A **talk cue** is an invitation, not a gate. It can appear while `mood == wanting` for a mare
  with a non-empty `talk` taste. The HUD shows `T · Answer her`. The player's reply is the
  director's player turn; the runtime drops the cue's pending line and scores the reply. A
  missed invitation expires quietly.

## Touch and talk classification

Touch comes from the existing actions:

| Action | Event |
|---|---|
| mouse right smack | `smack` |
| held caress | `caress` |
| kiss | `kiss` |

Each has a 4 s scoring cooldown. The actions themselves are not changed by this contract.

Talk comes from the game's own `T` / microphone turn. The runtime watches
`conversation_director._turn_id` and `_player_text`; the AI still writes her reply. The
classifier is a small keyword map, not an LLM call:

| Category | Examples |
|---|---|
| `praise` | good, beautiful, perfect, love you |
| `reassurance` | are you okay, safe, gentle, look at me |
| `dirty` | want, more, harder, please |
| `curious` | how, what, tell me, question mark |
| `playful` | good girl, brat, tease, beg |

An unrelated line is neutral: it can still get a normal reply, but it does not move readiness.

## Finish and HUD

- Hold `Y` at or above `READY_AT` to finish her. Below it, hold `Y` cancels.
- `readiness_hud` defaults to `true` and gates the readiness bar and mood cues. With it off,
  the depth bar and control hints remain; the player reads her.
- `debug_logs` still gates the detailed debug overlay, not the readiness bar.

## Character examples

| Character | Intensity | Pattern | Touch | Talk | Pose | Warmth |
|---|---|---|---|---|---|---|
| Fluttershy | firm | building | caress | reassurance | missionary | slow |
| Rarity | soft | steady | caress | praise | missionary | normal |
| Twilight | firm | steady | kiss | none | any | normal |
| Derpy | rough | quick | smack | playful | horse | quick |
| Default | firm | steady | none | none | any | normal |

The `notes` field carries the private attitude; the AI prompt receives the mood, the taste
summary and the last concrete input, never a speed or depth dump.
