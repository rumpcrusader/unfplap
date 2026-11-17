# Debug tooling

The mod's debug surface: the console gate, the Debug block actions, the action wheel, the skeleton
overlay and the log switches. The lab scripts are in `WORKFLOW.md`; the settings framework is
`docs/settings.md`; the perf probe is `docs/perf.md`.

## Scope

`debug/service.gd` owns the action registry and the wheel page order. `debug/ui.gd` draws the
Debug block buttons. `debug/wheel.gd` is the hold-middle wheel. `debug/perf_view.gd` draws the
perf panel. `debug/bed.gd` is the stock bed cuddle helper behind the wheel's Bed cuddle
action and Show data's BED section. `debug/pony.gd` is the debug pony-preparation helper shared by
the bed cuddle and the wheel's Sex ready action. `debug/idle_stretch.gd` is the Idle Life
deep-stretch bridge behind the wheel's Force deep stretch action. `debug/skeleton.gd` draws the
skeleton overlay. `settings/ui.gd` injects the Unfplap tab and calls `debug/ui.gd` for each Debug
block. `main.gd` owns the console gate, the wheel gate, the perf panel and the skeleton-flag sync.

## Console

- The backtick command console is gated by `DEV.enabled()`. Source/editor runs have it; a player
  build unlocks it with **Settings → Updates** pressed five times.
- Acts own `controls_locked`, so the console is not available while an act is running.
- The lab's backtick toggle releases the control lock temporarily so it also opens while Anon is
  lying down.

## Debug actions

Debug actions live in `debug/service.gd` and render as buttons in the **Debug** block of the tab
their `tab` names (`general` by default, `anatomy`, `world` or `integrations`); the Poses tab
carries none. Adding an action is one entry plus one method. An action on a wheel page sets
`panel: false`, so the settings blocks draw only the settings-only actions and the wheel is the
only trigger for the rest; those wheel-backed actions are desktop-only.

The registry declares no global hotkeys: the game's own dev keys (`F4` render breakdown, `F9`
trace, `F10` FPS overlay, `F11` free camera) must stay usable while the mod is loaded, so a Debug
block button or the action wheel is the only trigger. `input/service.gd` still routes a declared
`"hotkey"` for a future action that genuinely must fire while the world is unpaused.

| Action | Settings block | Wheel page |
|---|---|---|
| Reload posed base | General | — |
| Pose: test variant | General | — |
| Pose: face-sit | General | — |
| Trigger bed offer | — | Mare |
| Trigger standing offer | — | Mare |
| Show data | — | Mare and Act |
| Bed cuddle | — | Mare |
| Make sex-ready | — | Mare |
| Force deep stretch | — | Mare and Act |
| Give footstool | General | — |
| Reset act prompts | General | — |
| Pantyhose: rebuild hull | Integrations | — |
| Force/Clear heat | — | Mare |
| Force/Clear diestrus | — | Mare |
| Resume automatic cycle | World | — |
| Reset act history | World | — |
| Clear offer cooldown | World | — |
| Force neglect warning | — | Act |
| Force neglect stop | — | Act |
| Force act face | — | Act |
| Placement up/down/forward/back/pitch/bigger/smaller | Anatomy | — |
| Tail placement up/down/forward/back, tilt left/right | Anatomy | — |
| Dock placement up/down/bigger/smaller | Anatomy | — |
| Save placement, Reset placement, Show placement | Anatomy | — |

- **Placement** actions edit the selected target (global default or pointed mare). The Anatomy
  Actions block starts with the **Placement target** pill. See `docs/anatomy.md`.
- **Trigger bed/standing offer** forces a proactive ask for the aimed test mare. It bypasses the
  quiet, cooldown and AI-usage checks but keeps the eligibility gate, pose and free-bed gates.
- **Show data** replaces the old Show act history, Show stool state, Show act face, Show prompt
  context and Show pose state actions, and the lab's per-mare report. See below.
- **Bed cuddle** is the stock bed invite migrated from the lab's Mouse4 key. It sits on the wheel
  only; `debug/bed.gd` finds the player's bed, reclines Anon, moves a far mare to the bed approach
  and calls the stock `accept()` path. The detailed result goes to the debug log.
- **Make sex-ready** is the lab's Mouse5 qualification migrated to the Mare page. It clears the
  aimed adult mare's busy state, writes the game's own bond record (dating only when she is below
  it; engaged and married stay), clears her pending plan/offer and the boundary and dating
  cooldowns, and commits a neutral mood. Her romance tier is untouched. A missing relationship
  runtime or bond save path refuses before anything changes. The record is written through the
  game's `player_bonds._save`, so the action is a debug cheat like Reset act history; the detailed
  rows go to the debug log and the toast names the mare.
- **Force deep stretch** plays Idle Life 1.4.2's `stretch_deep` idle on the live act's pony, or on
  the aimed mare outside an act. It interrupts an idle already running through Idle Life's
  `_finish()` and calls its forced `play()`, so the stretch is not cut short by her posture, a
  conversation or a live act. Idle Life is optional: without it the action reports "Idle Life
  isn't running." This is a debug preview, not an integration; `debug/idle_stretch.gd` is the one
  file that names the other mod's entry.
- **Force/Clear heat** and **Force/Clear diestrus** are one slot each. The label follows the
  aimed mare's current phase; Clear sets the session phase to **normal**. **Resume automatic
  cycle** clears the override and is settings-only. See the cycle section of
  `docs/eligibility.md`.
- **Reset act history** clears the stored row; **Force neglect warning/stop** act on the live act
  and are consumed on the next unpaused frame.
- **Clear offer cooldown** clears the aimed mare's proactive-offer cooldown, short retry and last
  scan skip, so she can be offered again immediately. It is a settings-only World action and takes
  no wheel slot. See `docs/initiation.md`.
- **Trigger Anon offer** forms an Anon offer for the aimed mare as if Anon had just asked her.
  It is on the Mare wheel page; the Anon classifier and the Mare response still run.
- **Force act face** cycles the base-game faces; see `docs/face.md`.
- **Reload posed base** re-reads the active pose's authored JSON in place; a running act picks it
  up on its next frame. With no live act it re-reads the default missionary asset. See
  `docs/poses.md`.
- **Pose: test variant** is a Debug-block button with no hotkey: it toggles the internal
  `standing_test` pose in a live standing act, runs the authored `standing ↔ standing_test` edge
  and logs the request code and the status event. It never ends the act, releases the pose or
  restores bones; in a missionary act it refuses with "Only in a standing act." See `docs/poses.md`.
  The real oral edge has no debug action: `N` is its only trigger, and the forward/reverse status
  and switch lines are in the same log.
- **Pose: face-sit** is a Debug-block button with no hotkey: in a live missionary or face-sit act
  it requests the other id of the internal `missionary ↔ bed_facesit` pair and logs the request
  code. It refuses with a reason when no act is active, the view is not missionary or face-sit, the
  act is not `ACTIVE`, the pose is changing, a kiss is running or the anatomy act body is
  unavailable. It never ends the act. See `docs/poses.md`.
- **Reset act prompts** clears the per-mare prompt overrides; see `docs/settings.md`.
- **Pantyhose: rebuild hull** clears the shared garment depth field and rebuilds it from the
  anatomy mesh after a precision edit; the build time is logged with debug logs on. It is inert
  when the pack is absent. See `docs/integrations.md` (`## Pantyhose & Panties`).

## Action wheel

**Hold the middle mouse button** in captured desktop play to open the wheel; release it on a slot
to run that action. Releasing in the centre just closes. It is debug-only, does not pause the
tree, does not dim the frame and claims no hotkey or setting. The ring is compact and the whole
wheel is drawn at 75% opacity.

| Page | Slots, clockwise from the top |
|---|---|
| **Mare** | Show data · Bed offer · Bed cuddle · Standing offer · Anon offer · Force/Clear heat · Force/Clear diestrus · Sex ready · Deep stretch |
| **Act** | Show data · Neglect warning · Neglect stop · Next face · Deep stretch |

- The page is chosen by the live act: **Act** while an act runs, **Mare** otherwise. There are no
  subpages, so every action is at most one click from the open wheel.
- The centre names the target (the act's mare on the Act page, else the aimed mare) and says
  whether she was aimed or the live act. There is no help text in the centre.
- The aimed mare is the one closest to the camera's forward ray: in front, within `8 m`, and
  within `1.5 m` of the ray. There is no nearest-pony fallback.
- A virtual reticle follows mouse motion. Moving onto a slot plays the base game's
  `prop_ui_confirm` UI click once; the centre, opening and closing are silent. **Releasing the
  middle button** runs the highlighted slot and closes the wheel; a release in the centre just
  closes. **Left click** over a slot also runs it. **Right click** and **Escape** close. The
  game's `F4`/`F9`/`F10`/`F11` dev keys close the wheel and pass through.
- Opening needs **Enable debug**, captured desktop play, a focused window, no pause/menu/text
  field and the left mouse button released. With debug off the middle press is not consumed.
  While open, mouse motion, mouse buttons and keys are consumed; the act does not thrust or
  free-look.
- An action closes the wheel, writes its one-line result to the HUD toast and its name/result to
  the debug log. Show data's multi-line block stays in the log.
- The wheel closes on release (running the hovered slot first), debug-off, pause, focus loss, a
  menu or headset, a mouse-mode change, a world close or an act-context change.

## Show data

`main.debug_data(target)` returns the stable sections `TARGET`, `CYCLE`, `GATE`, `REQUEST`,
`NEGOTIATION`, `ACT`,
`STOOL`, `HISTORY`, `PROMPT` and `BED`; `ACT` is present only while this target owns the live act.
The Show data action prints them as one tab-indented log entry. `BED` is the same row builder the
Bed cuddle action uses. The old Show actions are gone; a future always-on overlay can render the
same dictionary.

## Skeleton overlay

**Show skeleton overlay** is a persisted Anatomy → Debug flag (`anatomy.skeleton_overlay`), not an
action or a wheel slot. It draws only while **Enable debug** is on. Left-click a joint to print
its bone name, parent, world/local origin, rotation, scale and rest. Lines are thin
(`LINE_HALF_WIDTH = 0.0015`) and joint circles remain visible; hover a joint to turn it red.
Colors: body green, face amber, hair/tail pink. It updates at 30 Hz and covers 15 m.

## Logging

- Logging follows **Enable debug** (General's last row); there is no separate log switch and no
  hotkey. It controls logging only, not the HUD.
- Every logged line, continuation rows of a multi-line block included, carries the `[unfplap] `
  prefix; `main.debug()` adds it per line.
- **Print perf logs** is a separate debug toggle. With **Enable debug** and
  **Print perf logs** on, an act prints one `perf` block a second and, outside an act, one
  aggregated `perf idle` block a second. Either switch off stops both. See `docs/perf.md`.
- `features.face_debug` prints one line per act face change, the climax score parts and the
  mood-face start/end.
- The debug log prints one `summary grade=... quality=... checks=... reasons=... tier=... hurt=...
  comfort=...` line per act while **Enable debug** is on.
- Neglect events log their warning/stop, tier, distress and dislike.
- The Act Negotiation logs `anon_watch armed|disarmed`, `anon_line received|skip|-> negotiation`,
  `classifier start|result`, `negotiation state|outcome|offer|hold|privacy|hotkey`,
  `agreement formed|auto-start|start`, and `hotkey exact match|interrupt|immediate|start` lines.
  The classifier lines carry the kind, scope, parsed answer, option index, failure and the trimmed
  raw reply/error.
- The Proactive Mare reasoning logs `request reasoning start` and `request reasoning result` with
  the parsed offer/index and the trimmed raw reply/error; `request outcome` carries the terminal
  reason and cooldown.
- Multi-line diagnostics are one entry: identification line first, then tab-indented rows.

## Perf panel

With **Enable debug** and **Print perf logs** on, the top-left corner carries the perf panel: the
same tree the probes print, one row per chunk, with its average, worst call and call count in
right-aligned columns. It is a `CanvasLayer` at layer 20 that ignores the mouse, so it never blocks
the act view or the wheel, and it stays hidden until the first window arrives. Either switch off
clears and hides it; a world close clears it, and the next window redraws the same node.

The tree glyphs and indentation are the block's own. Each value runs green → amber → red against
its target — `100ms/s` for the average, `0.5ms` for the worst call and two calls per rendered frame
for the count — so a red cell is the row to look at first. A `self` row prints `-` for max and
calls. The caption names the probe's own header and the engine frame numbers. The rows themselves
are `docs/perf.md`'s.

## Lab keys

- `Shift+[` / `Shift+]` cycles every adult mare the population catalogue can spawn. The eight
  starters stay live; a non-starter is spawned through the population streamer on demand and the
  previous extra is despawned.
- `-`/`=` romance tier; `9`/`0` anger mood.
- Hold middle to open the action wheel; use **Sex ready** to qualify the aimed adult mare and
  **Bed cuddle** for the treebrary bed.
- Reload the posed base from General's Debug block; the skeleton overlay is the Anatomy Debug
  flag.
- Pose test variant: in a live standing act, press **Pose: test variant** and read the
  `pose request standing -> standing_test (debug): ok` and `pose status standing_test: test` log
  lines; press again to return to `standing`. The act, the pose node and the bones stay alive, so
  the body does not move.
- Backtick toggles the debug console with a temporary control-lock release.
- `./lab.sh` uses the isolated `unfplap-test` world and writes `last-run.log`.
  `./lab-stress.sh` uses `unfplap-stress` and writes `last-run-stress.log`.
  `./lab-vr.sh` runs room-scale VR under Monado and writes `last-run-vr.log`.

## Dependencies

### Uses

| Kind | Target | Entry point | Purpose |
|---|---|---|---|
| service | settings | `settings/service.gd` | action-button rows, the skeleton flag and the placement target pill |
| shared | pony_id | `shared/pony_id.gd` | stable pony id in Show data's BED rows |
| game | interaction_sounds | `res://world/audio/interaction_sounds.gd` | the hover `prop_ui_confirm` cue |

## Lifecycle

- Scope: process (registry), world (wheel node), pure static (bed and pony helpers)
- Constructed by: static initialization; `main` creates the wheel lazily and the skeleton on the
  first enabled sync
- Begin: none for the registry; Node `_ready()` for the wheel
- End: `main` closes the wheel on world close, debug-off and teardown
- Idempotent: yes

## Tests

`tests/test_debug_wheel.gd` pins the wheel page order, the nine-slot cap, the settings-only split
(wheel actions are `panel: false`, settings-only actions stay on the panel), the retired action
ids, the dynamic cycle labels and the hold-middle input contract (middle press opens, release over
a slot runs it, release in the centre only closes). `tests/test_deep_stretch.gd` pins the Idle Life
bridge: its entry path and idle id, the missing-entry and missing-pony refusals, the forced play
call, interrupting a running idle and a refused play. `tests/test_debug_pony.gd` pins the shared
preparation helper: upright and idle, busy clearing, the raise-only sex-ready record, its floors
and cleared fields, the refusal paths and the log/toast text. `tests/test_settings.gd` covers the
skeleton flag, the Debug block labels that remain and the absence of every wheel action from the
blocks. The overlay, the hover cue and the lab pass are manual. `tests/test_perf_panel.gd` pins the
perf panel's row height, colour targets, caption and clear.

## Related docs

- `docs/settings.md` — the Debug block and the declaration rules.
- `docs/perf.md` — the act perf probe.
- `docs/anatomy.md` — the placement actions and the skeleton flag.
- `docs/summary.md`, `docs/face.md`, `docs/eligibility.md` — the per-service debug actions.
- `WORKFLOW.md` — the lab commands.
