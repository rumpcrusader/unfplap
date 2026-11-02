# Pump preferences contract (`unfplap` 0.0.2)

Brittle scoring rules for the mouse pump, camera bob, preferences and reactions. Update with
`preferences.gd`/`pump.gd` whenever the math changes.

## Input and depth

- Mouse vertical relative motion feeds raw depth. Free camera mode ignores the rest of the motion;
  legacy camera mode keeps the old mouse look.
- `pump.orientation`:
  - `"up"` (default): mouse up deepens; top = deep/orange, bottom = shallow/blue.
  - `"down"`: mouse down deepens; top = shallow/blue, bottom = deep/orange.
- `pump.pixels_per_full` is pixels for a `0→1` sweep (default `600`), independent of look
  sensitivity.
- Raw depth is clamped `0…1`; overshoot is discarded. The HUD reads raw depth directly.
- Legacy mode mouse look is `ACT_LOOK_YAW_SCALE = 0.10` laterally and
  `ACT_LOOK_PITCH_SCALE = 0.10` vertically, with motion consumed. Free mode uses no mouse look.

## Strokes and scoring

- A stroke is continuous movement between direction reversals.
- It closes on reversal or `STROKE_TIMEOUT_S = 0.18 s` without movement.
- A pump is an inward stroke with `travel >= PUMP_MIN_TRAVEL = 0.25`.
- Base gain is `Σ |Δd| × depth_weight(d)`.
- A full `0→1→0` at `steady` is exactly `2.0`.
- Outward strokes score base gain only; speed/shape multipliers apply to inward strokes.
- Final multiplier is `clamp(speed_multiplier × shape_multiplier, 0.40, 1.80)`.

## Physical pump strength

- Separate from preference scoring.
  `strength = clamp(travel × clamp(peak_speed / 1.0, 0.35, 1.5), 0, 1)`.
- Drives jiggle and wing flick. It is the intended selector input for future mod-owned plap
  clips; the current plap sound is unchanged.
- The pose-2 Anon hip follows raw `depth` directly and is **not** driven by strength:
  `THRUST_MAX_M = 0.045 m` forward at full depth, with no spring or return animation.

## Camera bob

- **Disabled by default.** `pump.bobs` is `false`; both pump and climax camera bobs are skipped.
  Set `"bobs": true` in the top-level `pump` block to enable the springs below.
- When enabled, each pump adds `BOB_PUMP_IMPULSE = 2.30 / 6` (≈`0.383`) to vertical velocity and
  `BOB_FORWARD_IMPULSE = 1.80 / 6` (`0.30`) to forward velocity.
- Vertical spring: stiffness `105`, damping `13`, limit `±0.40`.
- Forward spring: stiffness `100`, damping `12`, limit `±0.32`.
- Pose 1 scales vertical bob by `POSE1_BOB_SCALE = 0.35`; pose 2 uses the full value.
- Climax uses `BOB_CLIMAX_AMPLITUDE = 0.025 / 6` (≈`0.0042`) vertically and
  `BOB_CLIMAX_FORWARD = 0.12 / 6` (`0.02`).
- **Pump-speed response.** At or above `BOB_SPEED_REFERENCE = 0.80` depth/s the bob uses the
  full-speed spring. Below it, the response scale is `speed / 0.80`, clamped to
  `BOB_SPEED_SCALE_MIN = 0.35`. Stiffness scales by `s²`, damping and impulse by `s`, so slow
  strokes take longer while keeping roughly the same peak; fast strokes are unchanged.

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
