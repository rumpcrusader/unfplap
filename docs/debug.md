# Debug actions

The Process action table: the one registry of debug actions, the labels every surface renders and
the dispatch and gates a Debug block button or a wheel slot runs through. The node that carries the
action methods, the wheel, Show data and the skeleton overlay is `docs/debug_actions.md`; the lab
scripts are in `WORKFLOW.md`.

## Scope

`debug/api.gd` is the facade: the registry, the wheel page order, the labels, the aimed-mare
rule, the wheel's open-gate decision and the dispatch. It holds no node and runs no action itself:
the executor publishes itself to the table when it enters the tree, and every read resolves it
there, so no caller passes it in. `debug/ui.gd` renders the block's buttons and the placement-target
pill from the registry; the settings panel decides where that block sits. `debug/game.gd` is the one
base-game accessor behind their menu style.

## The registry

The registry is the table of debug actions: one entry per operation a debug surface may fire. An
entry names its label and help, the executor method that runs it, the tab and row it renders on,
whether the settings blocks draw it, its compact wheel label, and its phase pair when the label
follows the aimed mare's cycle. Entries sharing a row must stay adjacent. A debug action is a
one-off command, not a stored preference.

A wheel-only action sets the panel field off, so the settings blocks draw only the settings-only
actions and the wheel is the only trigger for the rest; those wheel-backed actions are desktop-only.
Adding an action is one entry plus one method on the executor.

The wheel's pages are the table's too: a page names its title and its actions clockwise from the
top, within the slot cap, and the live act chooses the page — the Act page while an act runs, the
Mare page otherwise. A closed runtime gate hides its action on both surfaces, the wheel included.
No provider means no form buttons: `shape_source` is the only gate today, and it keeps the form
actions off the panel and the wheel until a shape-changing source is installed.

## Labels

The full label falls back to the entry's label, and so does the compact wheel label. When an entry
names a phase and the target reports that phase, the entry's match label replaces it, so one slot
reads Force or Clear without a second entry. A supplied node that answers the phase read is
accepted, so a suite can pass its own.

## Dispatch and gates

Dispatch resolves the target — the explicit node, else the executor the table holds — then calls the
entry's method by name and returns its message, or the empty string when the action cannot run. A
button or a wheel slot with no executor is a no-op. The wheel and skeleton input forwards resolve
the same target, and a freed executor leaves none behind.

The wheel's open gate is one decision over the frame's facts: debug on, a desktop build, a live
world, no pause, the desktop view, window focus, a captured mouse, no open menu, no text focus and
the left button up. A headless display, a paused tree, a free mouse or a typing caret each close it
on their own. Read it there rather than re-deriving the rule at a call site.

The registry declares no global hotkeys. The game's own dev keys (`F4` render breakdown, `F9` trace,
`F10` fps overlay, `F11` free camera) must stay usable while the mod is loaded, so a Debug block
button or the action wheel is the only trigger. `input/api.gd` still routes a declared hotkey
for a future action that genuinely must fire while the world is unpaused. See `docs/input.md`.

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

## Logging

- Logging follows **Enable debug** (General's last row); there is no separate log switch and no
  hotkey. It controls logging only, not the HUD.
- Every logged line, continuation rows of a multi-line block included, carries the `[unfplap] `
  prefix; `LOG.debug()` (`shared/log.gd`) adds it per line, and every module prints through it.
- **Print perf logs** is a separate debug toggle. With **Enable debug** and **Print perf logs** on,
  `shared/perf.gd` prints one `perf` block a second, in an act and out of one alike. Either switch
  off stops it.
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
  **Bed cuddle** for the treebrary bed. See `docs/debug_actions.md`.
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
