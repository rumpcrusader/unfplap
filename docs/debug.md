# Debug tooling

The mod's debug surface: the console gate, the Debug block actions, the action wheel, the skeleton
overlay and the log switches. The lab scripts are in `WORKFLOW.md` and the settings framework is
`docs/settings.md`; the log sink and the profiler describe themselves in their file headers.

## Scope

`debug/service.gd` is the facade: the action registry, the wheel page order, the aimed-mare rule,
the wheel's open gate and the labels. `debug/actions.gd` is the one node that runs every action,
collects Show data, gates the wheel, dispatches its slots and syncs the skeleton overlay; it is
private to this service. `debug/ui.gd` draws the Debug block buttons. `debug/wheel.gd` is the
hold-middle wheel. `debug/bed.gd`
is the stock bed cuddle helper behind the wheel's Bed cuddle action and Show data's BED section.
`debug/pony.gd` is the debug pony-state helper: the bed cuddle and wheel's Sex ready preparation,
and the scene gate's debug status line gather (the pony, world, relationship and player facts).
`debug/idle_stretch.gd` is the Idle Life deep-stretch bridge behind the wheel's Force
deep stretch action. `debug/skeleton.gd` draws the skeleton overlay. `settings/ui.gd` injects the
Unfplap tab and calls `debug/ui.gd` for each Debug block. The console gate is the game's; the log
switch is `shared/log.gd`'s and the perf panel is `shared/perf.gd`'s.

## Base-game access

`debug/game.gd` is the debug service's one base-game accessor: the three game-menu builders its
Debug block draws with. A handle is an argument, never something a consumer resolves, and
`debug/ui.gd` takes them from it, so no debug file preloads a base-game module.

## Console

- The backtick command console is gated by `DEV.enabled()`. Source/editor runs have it; a player
  build unlocks it with **Settings → Updates** pressed five times.
- Acts own `controls_locked`, so the console is not available while an act is running.
- The lab's backtick toggle releases the control lock temporarily so it also opens while Anon is
  lying down.

## Debug actions

Actions are one table in `debug/service.gd` and one method on `debug/actions.gd`. Each renders as
a button in the **Debug** block of the tab its `tab` names (`general` by default, `anatomy`,
`world` or `integrations`); the Poses tab carries none. Adding an action is one entry plus one
method. An action on a wheel page sets `panel: false`, so the settings blocks draw only the
settings-only actions and the wheel is the only trigger for the rest; those wheel-backed actions
are desktop-only. An action may declare `requires: "shape_source"`; both the settings block and
the wheel drop it unless the actions node reports that a shape-changing source is active.

The facade resolves the actions node through its `target`, which the node sets when it enters the
tree: `run_action(name)`, the labels, the availability gate and the wheel/skeleton forwards all
reach it without a caller passing it in. A button or a wheel slot that has no node is a no-op.

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
| Pantyhose: rebuild hull | Integrations | — |
| Force/Clear heat | — | Mare |
| Force/Clear diestrus | — | Mare |
| Resume automatic cycle | World | — |
| Reset act history | World | — |
| Clear offer cooldown | World | — |
| Force neglect warning | — | Act |
| Force neglect stop | — | Act |
| Force act face | — | Act |
| Form: true form | World | Act |
| Form: next named shape | World | Act |
| Form: bring her out | World | — |
| Placement up/down/forward/back/pitch/bigger/smaller | Anatomy | — |
| Tail placement up/down/forward/back, tilt left/right | Anatomy | — |
| Dock placement up/down/bigger/smaller | Anatomy | — |
| Reset placement, Show placement | Anatomy | — |

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
  cycle** clears the override and is settings-only. The action writes the session override into
  `shared/cycle.gd`'s per-pony map through `estrus.debug_set_phase`; the runtime keeps the
  `cycle_phase()` and `cycle_override()` reads for the HUD and the debug block. See
  `docs/estrus.md`.
- **Reset act history** clears the stored row; **Force neglect warning/stop** act on the live act
  and are consumed on the next unpaused frame.
- **Clear offer cooldown** clears the aimed mare's proactive-offer cooldown, short retry and last
  scan skip, so she can be offered again immediately. It is a settings-only World action and takes
  no wheel slot. See `docs/initiation.md`.
- **Trigger Anon offer** forms an Anon offer for the aimed mare as if Anon had just asked her.
  It is on the Mare wheel page; the Anon classifier and the Mare response still run.
- **Force act face** cycles the base-game faces; see `docs/face.md`.
- **Form: true form**, **Form: next named shape** and **Form: bring her out** are the generic
  body-change actions. They are drawn only while `shape_source_active()` is true, so a launch
  without an installed provider has no dead buttons. In a live act the first two go through
  `runtime.act.request_form_change()` and the body handover continues the act; outside an act they ask
  `body_change`, which forwards to the provider and runs the idle change path. The named action
  cycles the shipped adult mares in `FORM_DEBUG_SHAPES` and
  names the next one in its result. Bring-out only asks the provider to put an away actor in the
  world and is not a change. The wheel's Act page carries the two act actions; there is no hotkey.
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
| **Act** | Show data · True form · Named shape · Neglect warning · Neglect stop · Next face · Deep stretch |

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
  field and the left mouse button released. That decision is the facade's one `wheel_gate()` over
  the frame's facts, so a headless display, a paused tree, a free mouse or a focused text field
  each close it on their own. With debug off the middle press is not consumed.
  While open, mouse motion, mouse buttons and keys are consumed; the act does not thrust or
  free-look.
- An action closes the wheel, writes its one-line result to the HUD toast and its name/result to
  the debug log. Show data's multi-line block stays in the log.
- The wheel closes on release (running the hovered slot first), debug-off, pause, focus loss, a
  menu or headset, a mouse-mode change, a world close or an act-context change.

## Show data

`debug/actions.gd`'s `debug_data(target)` returns the stable sections `TARGET`, `CYCLE`, `GATE`, `REQUEST`,
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
  prefix; `LOG.debug()` (`shared/log.gd`) adds it per line, and every module prints through it.
- **Print perf logs** is a separate debug toggle. With **Enable debug** and
  **Print perf logs** on, `shared/perf.gd` prints one `perf` block a second, in an act and out of
  one alike. Either switch off stops it.
- `features.face_debug` prints one line per act face change, the climax score parts and the
  mood-face start/end.
- The debug log prints one `summary grade=... quality=... checks=... reasons=... tier=... hurt=...
  comfort=...` line per act while **Enable debug** is on.
- Neglect events log their warning/stop, tier, distress and dislike.
- The Act Negotiation logs `anon_watch armed|disarmed`, `anon_line received|skip|-> negotiation`,
  `classifier start|result` and `negotiation state|outcome|offer|hold|privacy|hotkey` lines. The
  classifier lines carry the kind, scope, parsed answer, option index, failure and the trimmed
  raw reply/error.
- The idle offer logs its `OFFER ...` and `OFFER blocked ...` lines and the act start's
  `hotkey exact match|interrupt|immediate|start` and `agreement auto-start|start` lines; the
  entry logs `agreement formed` when the Agreement reaches it. `docs/offer.md` lists them.
- The Proactive Mare reasoning logs `request reasoning start` and `request reasoning result` with
  the parsed offer/index and the trimmed raw reply/error; `request outcome` carries the terminal
  reason and cooldown.
- Multi-line diagnostics are one entry: identification line first, then tab-indented rows.

## Perf panel

With **Enable debug** and **Print perf logs** on, the top-left corner carries the perf panel: the
same tree the block prints, one row per chunk, with its average, worst call and call count in
right-aligned columns. It is a `CanvasLayer` at layer 20 that ignores the mouse, so it never blocks
the act view or the wheel, and it stays hidden until the first window arrives. Either switch off
clears and hides it, and the next window redraws the same node.
`shared/perf.gd` creates it under the entry on the first printed window.

The tree glyphs and indentation are the block's own. Each value runs green → amber → red against
its target — `100ms/s` for the average, `0.5ms` for the worst call and two calls per rendered frame
for the count — so a red cell is the row to look at first. A permanent first row, `unfplap total`,
sums the window's roots and takes the worst single call, so the mod's own cost is one line; it has
no call count. A `self` row prints `-` for max and calls. The caption names the engine frame numbers and,
from the second window, the measured refresh rate in Hz. The rows themselves are a chunk's own
total over the window, its calls and its worst call.

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

## Host boundary

The entry adds the actions node and hands it the services it acts through with `bind(body_change,
initiation, negotiation, anatomy, pantyhose, hud)` and the settings page's Debug block builder
(`build_settings_block()`). The wheel's one-line result goes to the bound `hud.toast()`, not
through a static sink. The live act state is these named reads, built by the node itself in `_ready()` from the
facades, so the entry binds none of them:

| Callback | Type | Purpose |
|---|---|---|
| `host.act` | `Callable() -> Node` | the live act's runtime, or null |
| `host.runtime_for` | `Callable(Node) -> Node` | the runtime of one pony |
| `host.runtimes` | `Callable() -> Array` | every live runtime node |
| `host.act_target` | `Callable(Variant) -> bool` | the act-target capability |
| `host.reload_posed_base` | `Callable() -> String` | re-read the authored pose file when no act is live |

All five are facade reads: the `ponies` registry for the first four (`act_target` asks its
eligibility rule) and `poses/service.gd`'s `reload_authored_base()` for the last. `apply_settings()`
is the node's settings change listener: it closes the wheel when debug mode goes off and re-syncs
the skeleton overlay; `_ready()` joins that list and `_exit_tree()` leaves it.
