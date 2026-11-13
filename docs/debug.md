# Debug tooling

The mod's debug surface: the console gate, the action buttons, the skeleton overlay and the log
switches. The lab scripts are in `WORKFLOW.md`; the settings framework is `docs/settings.md`; the
perf probe is `docs/perf.md`.

## Scope

`debug/service.gd` owns the Debug block's action buttons, and `debug/ui.gd`
draws the buttons. `debug/skeleton.gd` owns the skeleton overlay. `settings/ui.gd` injects the
Unfplap settings tab and passes `debug/ui.gd`'s builder into each Debug block. `main.gd` owns the
console gate. The lab scripts are `lab.sh`, `lab-stress.sh` and `lab-vr.sh`; their keys are in
`WORKFLOW.md`.

## Console

- The backtick command console is gated by `DEV.enabled()`. Source/editor runs have it; a player
  build unlocks it with **Settings → Updates** pressed five times.
- Acts own `controls_locked`, so the console is not available while an act is running.
- The lab's backtick toggle releases the control lock temporarily so it also opens while Anon is
  lying down.

## Actions

Debug actions live in `debug/service.gd` and render as buttons in the **Debug** block of the tab
their `tab` names (`general` by default, `anatomy` or `world`). Adding an action is one entry plus
one method. The registry declares no global hotkeys: the game's own dev keys (`F4` render
breakdown, `F9` trace, `F10` FPS overlay, `F11` free camera) must stay usable while the mod is
loaded, so a Debug block button is the only trigger. `input/service.gd` still routes a declared
`"hotkey"` for a future action that genuinely must fire while the world is unpaused.

| Action | Tab | Hotkey |
|---|---|---|
| Reload posed base | General | — |
| Trigger bed offer | General | — |
| Trigger standing offer | General | — |
| Reset act history | World | — |
| Show act history | World | — |
| Show prompt context | World | — |
| Force heat | World | — |
| Force diestrus | World | — |
| Clear forced cycle | World | — |
| Force neglect warning | World | — |
| Force neglect stop | World | — |
| Give footstool | General | — |
| Show stool state | General | — |
| Reset act prompts | General | — |
| Show pose state | General | — |
| Force act face | General | — |
| Show act face | General | — |
| Skeleton overlay | General | — |
| Placement up/down/forward/back/pitch/bigger/smaller | Anatomy | — |
| Tail placement up/down/forward/back, tilt left/right | Anatomy | — |
| Dock placement up/down/bigger/smaller | Anatomy | — |
| Save placement, Reset placement | Anatomy | — |

- **Placement** actions edit the selected target (global default or pointed mare). The Anatomy
  Actions block starts with the **Placement target** pill. See `docs/anatomy.md`.
- **Trigger bed/standing offer** forces a proactive ask for the aimed (or nearest) test mare. It
  bypasses the quiet, cooldown and AI-usage checks but keeps the eligibility gate, pose and
  free-bed gates. Because the settings page pauses the tree, an offer advances after it closes.
- **Reset/Show act history** and **Show prompt context** read the history and prompt state; see
  `docs/summary.md` and `docs/lines.md`.
- **Force heat/diestrus/Clear forced cycle** set the session-only estrus override; see the cycle
  section of `docs/eligibility.md`.
- **Force neglect warning/stop** act on the live act; they are consumed on the next unpaused frame.
- **Force act face/Show act face** cycle the base-game faces and print the live act face; see
  `docs/face.md`.
- **Reset act prompts** clears the per-mare prompt overrides; see `docs/settings.md`.

## Skeleton overlay

**Skeleton overlay** in General's Debug block toggles the skeleton overlay for nearby ponies and
reports `Skeleton overlay ON`/`OFF` in the block's status line. Lines are thin
(`LINE_HALF_WIDTH = 0.0015`) and joint circles remain visible; hover a joint to turn it red, then
left-click to print its bone name, parent, world/local origin, rotation, scale and rest. Colors:
body green, face amber, hair/tail pink. It updates at 30 Hz and covers 15 m.

## Logging

- Logging follows **Enable debug** (General's last row); there is no separate log switch and no
  hotkey. It controls logging only, not the HUD.
- **Print perf logs** is a separate debug toggle, OFF by default. With **Enable debug** and
  **Print perf logs** on, an act prints one `perf` block a second. See `docs/perf.md`.
- `features.face_debug` prints one line per act face change, the climax score parts and the
  mood-face start/end.
- The debug log prints one `summary grade=... quality=... checks=... reasons=... tier=... hurt=...
  comfort=...` line per act while **Enable debug** is on.
- Neglect events log their warning/stop, tier, distress and dislike.
- Multi-line diagnostics are one entry: identification line first, then tab-indented rows.

## Lab keys

- `Shift+[` / `Shift+]` cycles every adult mare the population catalogue can spawn. The eight
  starters stay live; a non-starter is spawned through the population streamer on demand and the
  previous extra is despawned.
- `-`/`=` romance tier; `9`/`0` anger mood; Mouse4 bed invite; Mouse5 sex-ready.
- Reload the posed base and toggle the skeleton overlay from General's Debug block.
- Backtick toggles the debug console with a temporary control-lock release.
- `./lab.sh` uses the isolated `unfplap-test` world and writes `last-run.log`.
  `./lab-stress.sh` uses `unfplap-stress` and writes `last-run-stress.log`.
  `./lab-vr.sh` runs room-scale VR under Monado and writes `last-run-vr.log`.

## Dependencies

### Uses

| Kind | Target | Entry point | Purpose |
|---|---|---|---|
| service | settings | `settings/service.gd` | action-button rows and the placement target pill |

## Lifecycle

- Scope: process
- Constructed by: static initialization
- Begin: none
- End: none
- Idempotent: yes


## Tests

The debug actions and overlay are manual. Their settings and action declarations are covered by
`tests/test_source_hygiene.gd` and `tests/test_settings.gd`.

## Related docs

- `docs/settings.md` — the Debug block and the declaration rules.
- `docs/perf.md` — the act perf probe.
- `docs/anatomy.md` — the placement actions.
- `docs/summary.md`, `docs/face.md`, `docs/eligibility.md` — the per-service debug actions.
- `WORKFLOW.md` — the lab commands.
