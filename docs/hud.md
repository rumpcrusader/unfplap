# Act HUD contract

The act's text readouts: the cue/hearts line, the readiness/preference line, the auto readout and
the `End` tint. The card itself is `hud.gd`; the style rules are in `AGENTS.md`
(`## HUD and rewards`).

## Ownership

| File | Role |
|---|---|
| `hud_lines.gd` | pure text and tint: `cue_line`, `readiness_line`, `auto_text`, `y_pink` |
| `hud.gd` | the scene card: rows, key caps, prompt row, visibility and the act wiring |
| `docs/hud.md` | this contract |

The runtime gathers the live values (state, climax count and limit, cue, close hint, summary,
preference axes, heat, auto settings) and calls `hud_lines.gd`. The pure module has no Node,
tree, `Settings` or game access, so the formats are testable without a scene.

## Lines

`cue_line(state, pony_climaxes, max_climaxes, cue, close_text, summary_hud, show_readouts)`:

```text
❤ N/M | cue
❤ N/∞ | cue        (0 = unlimited)
❤ N/M              (readouts off; hearts stay)
❤ N/M | Close: Y   (afterglow keeps the close prompt with readouts off)
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

## Gates

- `features.hud_readouts` (default on) hides the cue and readiness segments; the hearts and the
  close prompt stay.
- `features.act_controls` (default on) hides the whole control card; the cue, readiness and close
  prompt stay.
- The afterglow summary is independent of `hud_readouts` and is always shown.

## Tests

`tests/hud/test_hud_lines.gd` covers the formats, the afterglow precedence, heat, the auto
readout and the tint. `tests/hud/test_hud.gd` covers the card rows and the style helpers.
`tests/afterglow/test_afterglow.gd` drives the runtime's HUD forwards.
