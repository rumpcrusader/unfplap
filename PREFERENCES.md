# Pump preferences contract (`unfplap` 0.0.2)

Brittle scoring rules for the mouse pump, travel, preferences and reactions. Update with
`preferences.gd`/`pump.gd` whenever the math changes.

## Input, depth and travel

- Mouse vertical relative motion feeds raw depth; horizontal motion is camera look.
- `pump.orientation`:
  - `"up"` (default): mouse up deepens; top = deep/orange, bottom = shallow/blue.
  - `"down"`: mouse down deepens; top = shallow/blue, bottom = deep/orange.
- `pump.pixels_per_full` is pixels for a `0→1` sweep (default `800`), independent of look
  sensitivity.
- Raw depth is clamped `0…1`; overshoot is discarded.
- `view_depth` is a critically damped spring toward raw depth:
  `PUMP_TRAVEL_OMEGA = 30`, damping `60`. The HUD knob and camera use it; scoring/strokes use raw
  depth. It brakes sharply before changing direction.
- During `ACTIVE`, mouse look is `ACT_LOOK_YAW_SCALE = 0.10` laterally and
  `ACT_LOOK_PITCH_SCALE = 0.20` vertically, with motion consumed.

## Strokes and scoring

- A stroke is continuous movement between direction reversals.
- It closes on reversal or `STROKE_TIMEOUT_S = 0.18 s` without movement.
- A pump is an inward stroke with `travel >= PUMP_MIN_TRAVEL = 0.25`.
- Base gain is `Σ |Δd| × depth_weight(d)`.
- A full `0→1→0` at `steady` is exactly `2.0`.
- Outward strokes score base gain only; speed/shape multipliers apply to inward strokes.
- Final multiplier is `clamp(speed_multiplier × shape_multiplier, 0.40, 1.80)`.
- Camera travel is `(view_depth − 0.10) × 0.09`: 10% behind at 0, 90% forward at 1.

## Depth profiles

Normalized so `∫₀¹ weight(d) dd = 1.0`:

| Profile | Meaning |
|---|---|
| `steady` | flat |
| `deep` | more weight near `1.0` |
| `shallow` | more weight near `0.0` |
| `peak` | more weight around `0.7` |

Comfort bands:

```text
deep    0.60–1.00
shallow 0.00–0.40
peak    0.50–0.85
steady  none
```

## Speed and boredom

Measured on the inward stroke in depth units per second.

```text
slow:    speed < min
perfect: abs(speed - perfect) <= epsilon
fast:    speed > max
ok:      otherwise
```

Default speed is **enabled**:

```text
min 0.001, perfect 0.80, max 1.60, epsilon 0.15
slow_gain 0.70, fast_gain 0.70, perfect_gain 1.30
```

Twilight and all unspecified mares follow these defaults. `min = 0` disables slow/bored
detection for special mares.

Boredom:

- 1.5 s rolling effective speed (travel / time; 0 when still).
- If `min > 0`, below `min × 0.9` for 10 s queues `bored`.
- Leaves boredom above `min × 1.2`.
- Timer pauses while the director is speaking or the player is talking.
- `speed_slow` remains the immediate 3-stroke complaint.

## Shapes

Classified on the inward stroke only. Requires travel ≥ `0.30`, duration ≥ `0.12 s`, at least 4
samples, and best-fit RMSE under `0.18`; otherwise `mixed`.

| Shape | `d(t)` |
|---|---|
| `steady` | `t` |
| `ease_in` | `t²` |
| `ease_out` | `1 − (1−t)²` |
| `ease_in_out` | `3t² − 2t³` |

Liked `1.20`, disliked `0.75`, neutral/mixed `1.0`.

## Satisfaction phases

`preferences.pump.phases` is an optional array. `progress = satisfaction / climax_at`; a phase
applies when `min_satisfaction ≤ progress < max_satisfaction`. The last matching phase is merged
over the base preferences; the active phase drives scoring, depth bands and prompt notes.

Fluttershy has a `0.75–1.0` phase:

```text
depth deep
speed 0.60 / 1.60 / 2.60 / 0.28
likes ease_out, dislikes ease_in_out
```

## Character examples

| Character | Depth | Speed min/perfect/max/ε | Likes | Dislikes | Lines |
|---|---|---|---|---|---|
| Fluttershy | `deep` | `0.40 / 1.20 / 2.00 / 0.22` | `ease_out` | `ease_in_out` | `1–3` |
| Fluttershy 75%+ | `deep` | `0.60 / 1.60 / 2.60 / 0.28` | `ease_out` | `ease_in_out` | `1–3` |
| Rarity | `shallow` | `0.20 / 0.50 / 1.00 / 0.10` | `ease_in_out` | `ease_out` | `4–7` |
| Twilight | `steady` | default | — | — | `2–5` |
| Default | `steady` | `0.001 / 0.80 / 1.60 / 0.15` | — | — | `2–5` |

## Prompt values

`{state}` example:

```text
pose=missionary, satisfaction=42/100, depth=0.78 (deep), speed=0.90/s (perfect), stroke=ease_in,
18s in
```

`{preferences}` contains the mechanical summary plus `preferences.pump.notes`, marked as private
feelings, never lines to say. `{recent}` is the last two lines the director actually spoke.
