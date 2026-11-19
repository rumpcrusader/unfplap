# Perf probes (`shared/perf.gd`, `shared/perf_idle.gd`, `shared/perf_tree.gd`, `shared/perf_view.gd`)

The mod's two debug performance probes. Both report timed chunks in microseconds and print one
block per one-second window, so a stall can be attributed to a modifier, a service or a single
pony without a live profiler. The act probe prints one summary per acting pony; the idle probe
aggregates every idle runtime into one block. Either block is laid out as a tree by
`shared/perf_tree.gd`, and `LOG.debug()` prefixes every printed line with `[unfplap] `. The same
window is tabled in the top-left corner; see `docs/debug.md`.

## Ownership

- `shared/perf.gd` is a pure `RefCounted` module owned by the runtime. It holds the act's window,
  chunk rows, header facts, the act parent table and summary formatting.
- `shared/perf_idle.gd` is a pure `RefCounted` module owned by `shared/log.gd`. It holds the idle
  window, aggregated rows, worst owner per chunk, counts, the idle parent table and block
  formatting.
- `shared/perf_tree.gd` is a pure static module used by both probes. It turns flat rows plus a
  parent table into the display order and the `self` residuals; it knows no chunk on its own.
- `shared/perf_view.gd` draws the panel. It owns no gate, no data and no setting: a probe hands it
  one laid-out window and its facts, and `shared/log.gd` hides it when either switch goes off.
- The runtime supplies the act probe's two gates (`enabled`, `active`), the header facts and the
  log and panel callbacks.
- `shared/log.gd` supplies the idle probe's gate (`enabled`), the header counts and the log and
  panel callbacks, and keeps the panel to the two debug switches: `perf_block()` creates the view
  on the first window. Its two scene-free unknowns, the act gate and the counts, are entry
  callables (`docs/log.md`). Idle runtimes forward their chunks through `runtime.perf_note()`.
- Timed call sites in the runtime, the anatomy controller and the skeleton modifiers report to the
  runtime; `main.gd` times its own process body and `offer/service.gd` times the scan and the hint
  through `LOG.note()`/`LOG.close()`.
- `**Print perf logs**` is a separate debug switch; it needs **Enable debug** on too. One switch
  drives both probes.

## Tree layout

Both probes hand `perf_tree.layout()` their window as `key -> [total_ms, calls]` and their parent
table, and print the returned rows in order:

- roots first, then each level depth-first, every level sorted by total milliseconds, largest
  first;
- one indentation step per level: `├─ ` for a row with a later sibling, `└─ ` for the last one,
  `│  ` while an ancestor column continues and `   ` once it closes;
- a parent's unmeasured cost prints as a `self` row among its children, with `-` in the call and
  worst-call columns. It appears only when the parent is at least 10 µs ahead of its timed
  children, so a window whose children overrun the parent simply shows no residual;
- a chunk whose parent has no row in the same window is a root, so a chunk that prints alone (a
  first caress path, a scan whose parent was not timed) still shows.

`self` is the time a parent spends outside its timed children: the loop around them, not a
measurement error.

## Panel rows

Each probe hands its window to `LOG.perf_block()` through `show` after the block is built, so the
panel and the console block can never disagree about the rows. `shared/perf_view.gd` prints the
same tree one row per line: the block's tree glyphs and chunk key, the filling space, then three
right-aligned value columns.

- average: the row's window total in `ms/s`;
- max: the row's worst single call in `ms`;
- calls: the row's call count in the window, the same number the block prints.

A permanent first row, `unfplap total`, sums the window's root totals into the average column and
takes the worst single call in the window as its max; it has no call count. The tree follows under
a separator.

The values are coloured against the debug targets: the average is green at zero and red at
`100ms/s`, the max green at zero and red at `0.5ms`, and the call count green at one call per
rendered frame and red at two. A value is amber at half its target and red at the target and
beyond. The call colour divides the count by the window's rendered frames; the
number itself stays the window's count. A `self` row prints `-` for max and calls because it has
no call of its own, and a name that no longer fits after the indentation is trimmed with an
ellipsis.

The caption repeats the probe's own header (`pony`/`pose`/`state` for an act, `runtimes`/`mares`
for idle) with `fps`, `frame`, `phys` and `tick`. From the second window on it also carries the
measured `refresh` rate in Hz: the interval between the last two panels.

## Act probe API

| Member | Contract |
|---|---|
| `enabled: Callable` | both debug switches are on |
| `active: Callable` | true while an act is running; the window clears outside it |
| `header: Callable` | returns `{pony, pose, state, lean, hands, near_mesh, tier, wings}` |
| `log: Callable` | writes one summary block |
| `show: Callable` | hands one window to the panel: the laid-out rows with each `max`, the header facts and `frames` |
| `note(key, usec)` | record one timed chunk; a cheap no-op when off |
| `time(key, started_usec)` | close one call site; the caller takes the start stamp |
| `reset()` | clear the window, the rows and the physics mark |
| `tick(delta)` | accumulate a frame and print at the window boundary |

The probe also reads `Engine.get_physics_frames()`, `Engine.get_frames_per_second()`, the
`Performance` process/physics monitors and the renderer's draw-call and primitive counters. Those
are engine values, not scene access.

The summary is a header line and one row per chunk:

```text
perf pony=<id> pose=<pose> state=<n> fps=<n> frame=<ms> phys=<ms> lean=<fwd>/<side> hands=<LR|-> tick=<n> draws=<n> prims=<n> near_mesh=<state> tier=<state> wings=<state>
<chunk> <ms/s> per-frame <ms> max <ms> calls <n>
```

- `frame` is `Performance.TIME_PROCESS`, `phys` is `Performance.TIME_PHYSICS_PROCESS`.
- `lean` is the shot's forward lean and the smoothed side lean; `hands` is the latched caress
  hands (`LR`, `L`, `R` or `-`).
- `tick` is physics frames per rendered frame. At `1.00` the physics tick runs once per frame;
  above `1.00` the engine is running two ticks per frame (`max_physics_steps_per_frame` is 2 in
  the game), which doubles every per-tick chunk.
- `draws`/`prims` are the renderer's per-frame draw-call and primitive counts, so a frame that
  costs more while those grow is a render-side change and not a tick.
- `per-frame` is the row's window total divided by the window's rendered frames.

### Act chunks

| Chunk | Parent |
|---|---|
| `runtime_physics` | root |
| `pose_tick`, `runtime_facts`, `pose_fanout`, `runtime_presentation`, `caress_tick`, `kiss_tick`, `runtime_ai`, `anatomy_tick`, `anatomy_afterglow`, `runtime_talk`, `runtime_camera`, `runtime_face` | `runtime_physics` |
| `wings_tick` | `runtime_presentation` |
| `caress_precise` | `caress_tick` |
| `caress_path`, `caress_surface` | `caress_precise` |
| `caress_ensure`, `caress_select`, `caress_skin`, `caress_closest`, `caress_ray`, `caress_blur`, `caress_tri` | `caress_surface` |
| `caress_arm` | `pose_fanout` |
| `pose_recipe`, `pose_prone`, `body_sway`, `ear_twitch`, `tail_pose` | `runtime_process` |
| `runtime_process`, `camera_motion`, `hud`, `climax_fluid` | root |

The act probe's own chunks, in call order inside one physics tick: `pose_tick`, `runtime_facts`,
`pose_fanout`, `caress_tick` (inside the lean), `runtime_presentation`, `kiss_tick`, `runtime_ai`,
`anatomy_tick`, `runtime_talk`, `runtime_camera`, `runtime_face`, all inside `runtime_physics`.
`pose_tick` is the pose edge clock, the channel records, the switches/events and the oral turn;
`pose_fanout` is the modifier reconcile, the `act_body`/`anon` channel and the
camera/hands/kiss/anatomy/audio hooks. The facts sync carries the one `pose_view`; the standing
camera reads its facing each physics tick, and the mouth/contact provider reads its
`contact_kind`. The skeleton modifiers report `pose_recipe` (`UnfplapPose`), `pose_prone`
(`UnfplapProneSway`), `body_sway`, `ear_twitch` and `tail_pose`; `runtime_process` covers the
render-time pose write and the sway replay, which is where the modifier pass reports.
`caress_tick` contains `caress_precise` → `caress_path` (the one-time path/anchor build) and
`caress_surface` → `caress_skin`/`caress_tri`/`caress_ray` and the other surface helpers.
`caress_path` only reports on a build tick; a large max there with every other chunk steady is the
first caress path, not the per-tick contact.

The body-swap watcher runs before the act chunks: one source `poll()` per `0.1 s` while an act is
live, plus a read of the same source's changing state. It allocates nothing per frame, so it stays
in the `runtime_physics` self row rather than a named chunk. A suspend/resume is one-time per change
and the watchdog covers a source that never settles. The comparison is a manual lab step: with
**Enable debug** + **Print perf logs** on, record a steady act window and an idle window and compare
`runtime_physics`, `runtime_talk` and the `self` row around the watcher. The headless perf suites pin
the probe's own behavior, not the live frame cost.

## Idle probe API

| Member | Contract |
|---|---|
| `enabled: Callable` | both debug switches are on and no act is running |
| `counts: Callable` | returns `{runtimes, mares}` for the header, read once per window |
| `log: Callable` | writes one block |
| `show: Callable` | hands one window to the panel: the laid-out rows with each `max`, the header counts and `frames` |
| `on()` | the cheap gate |
| `note(key, usec, owner)` | aggregate one chunk; the worst call keeps its owner id |
| `reset()` | clear the window, the rows and the physics mark |
| `tick(delta)` | accumulate a frame and print at the window boundary |

The block is:

```text
perf idle runtimes=<n> mares=<n> fps=<n> frame=<ms> phys=<ms> tick=<n>
<chunk> <ms/s> <us/call> calls <n> max <ms> <owner>
```

`ms/s` is the window total (same convention as the act probe), `us/call` the average call and
`max` the worst single call with the pony id that made it (`-` for a chunk without an owner). At
`tick=2.00` every per-physics-tick chunk is paid twice per rendered frame. Rows are sorted by
total, largest first, so the first row is the chunk to fix.

### Idle chunks

| Chunk | Source | Parent |
|---|---|---|
| `entry_process` | the whole `main._process` body, closed after it | root |
| `entry_initiation` | `initiation.tick(delta)` | `entry_process` |
| `entry_negotiation` | `negotiation.tick(delta)` | `entry_process` |
| `entry_watch` | `_tick_negotiation_watch()` | `entry_process` |
| `entry_hint` | the offer hint build and its prompt-row sync, in `offer.tick()` | `entry_process` |
| `offer_scan` | the `OFFER_SCAN_S` `offer.scan()` call | `entry_process` |
| `offer_cone` | the standing candidate search in `offer.scan()` | `offer_scan` |
| `offer_gate` | the standing gate, `offer._standing_ready()` | `offer_scan` |
| `offer_rows` | `scene_only_verdict()`, every scene row | `offer_gate` |
| `offer_policy` | `eligible()` and `relationship_ok()` after the rows pass | `offer_gate` |
| `runtime_physics` | one pony's idle `_physics_process` | root |
| `runtime_anatomy_sync` | the two `_sync_anatomy_facts()` calls per physics tick, summed | `runtime_physics` |
| `runtime_facts` | `_sync_act_facts()` in the physics tick | `runtime_physics` |
| `runtime_presentation` | `_standing_presentation_controller().physics(delta)` | `runtime_physics` |
| `runtime_history` | `_history_tick(delta)` | `runtime_physics` |
| `runtime_process` | one pony's idle `_process_tick` | root |
| `anatomy_process` | the whole persistent `anatomy/controller.gd::_process`, reported outside an act | root |
| `anatomy_coat_line`, `anatomy_visibility` | reported through `facts.perf` | `anatomy_process` |
| `teat_jiggle`, `climax_fluid` | reported through `facts.perf` | root |

The anatomy chunks need no extra forward: `facts.perf` already calls the runtime's `perf_note`,
which is the single forwarding point. `entry_process` contains the four entry chunks and
`offer_scan`; `offer_scan` contains `offer_cone` and `offer_gate`, and `offer_gate` contains
`offer_rows` and `offer_policy`. The entry chunks split the per-frame body at its calls, so a row
that stays large is one call site and the `entry_process` `self` row is the body around them.
`offer_scan` and `entry_hint` are reported by `offer.tick()` and stay under `entry_process` because
the entry calls it in its own body. The Agreement auto-start clock rides in the same `offer.tick()`
and has no chunk of its own: it is one arithmetic step in the common frame. The caption move has
no idle chunk: the entry only reports the live act state, the HUD moves nothing outside
`POSING_IN`/`ACTIVE`/`CLIMAX`, and the idle probe is off during an act.

`offer_cone` is the standing candidate search: geometry first, and Base clearance only for the
candidates that beat the nearest eligible one already found, in one pass with no per-candidate
allocation. `offer_rows` is the whole scene-row verdict and `offer_policy` the clearance and
relationship reads behind it, so a gate dominated by `offer_rows` is a scene question and one
dominated by `offer_policy` is a relationship question; `relationship_ok()` reads only the
clearance facts rather than the full snapshot, and the relationship ladder behind it is the single
largest item in one gate.

The cone scan runs every `OFFER_SCAN_S`, but the gate behind it is reused while the same mare stays
the cone target and refreshed every `GATE_REFRESH_S`. A reused window prints `offer_gate` as the
cache read alone, so its per-call average mixes the two. The act key runs the gate again on every
press, so a reused verdict can only hold the hint back, never start or block an act. The two
offerable pose assets are parsed at world ready, so their load is not inside a first scan.

## Gate and reset

- Both probes are off unless **Enable debug** and **Print perf logs** are on.
- The act probe prints only while its runtime is not `IDLE`; its window resets outside an act.
- The idle probe prints only while no act is running (`LOG.act_running` reads false). It resets
  when an act starts, when a switch goes off, on world start, on world close and on entry teardown
  (`LOG.reset()`/`LOG.detach()`). `LOG.tick(delta)` runs first in `_process`, so a window prints at
  the frame boundary and the entry closes `entry_process` after its body.
- With a switch off, no clock is taken in the idle path, the runtime's forward is one bool branch
  and `note`/`tick` early-return. Rows are updated in place; nothing allocates per frame. The tree
  layout runs once per window, not per note.
- The probes are debug tools, not settings: no declaration and no persisted value.

## Debug

**Enable debug** + **Print perf logs** in General's Debug block. Standing in town outside an act
prints one `perf idle` block a second. During an act the per-pony `perf` lines print instead and
no idle block prints. Either block also redraws the corner perf panel (`docs/debug.md`). Every
printed line, continuation rows included, carries the `[unfplap] ` prefix from `LOG.debug()`, so
a block stays attributable after the game's own output interleaves with it.

### Pose edge comparison

With **Enable debug** + **Print perf logs** on, record three `perf` windows in a standing act: one
steady window, one while the Debug **Pose: test variant** edge runs (`standing ↔ standing_test`),
and one after it returns. Then repeat in a standing act with the oral edge: one steady standing
window, one forward edge window, one settled oral window with its soft-kiss timer, and one reverse
edge window. Compare `pose_tick` and `pose_fanout` with the steady window and the act's
`runtime_physics` total; both chunks stay in the noise, the oral turn allocates nothing per frame,
and an edge window costs no settings or file read. One idle window with the probe on must show
neither chunk: the `IDLE` path returns before both.

The runtime also prints one-shot `tail perf attach`/`tail perf refresh` lines and a
once-per-second `tail perf seats=… skinned=… builds=…/s` line when the probe is on.

The bed face-sit edge adds the same two-asset base/Anon blend as the oral pair and a face driver
that reads one anchor and eases a frame-space vector per tick; it allocates nothing in the steady
tick. A face-sit perf pass compares a steady missionary window, a steady face-sit window and one
window that loops the forward/reverse edge; the edge is bounded by its 1.6 s / 1.2 s durations.
The face-sit perf window is not yet measured; the D closeout recorded it unavailable. Run the
steady missionary, steady face-sit and looping-edge windows when the live lab is available; do not
claim numbers before then.

The standing family now pays the render-time pose write as well: `render_write()` runs
`sync_ground_frame()` and `apply_render()` after every physics and process writer, the same order as
the bed family. In a standing lab, compare `runtime_process` and `pose_recipe` at Canon and one
non-canon size against the pre-C build; the ground frame sync is one transform compare per tick
and allocates nothing, and the pose write is the only new per-frame cost.

## Tests

- `tests/perf/test_perf.gd` — the act probe's on/active gates, window reset, row aggregation,
  parent and child rows, per-level order, the self residual and summary formatting.
- `tests/perf/test_log.gd` — the module around both probes: the switch gate, the block text, one
  idle window a second and the panel created lazily under `attach()`.
- `tests/perf/test_perf_idle.gd` — the idle probe's gate, window boundary, per-owner aggregation,
  worst owner, tree block text and reset-on-disable.
- `tests/perf/test_perf_tree.gd` — the shared layout: roots, nesting, glyph prefixes, per-level
  order, the self residual and its floor.
- `tests/test_perf_panel.gd` — the panel: the row height, the colour targets for average, max and
  calls per frame, and the view's caption and clear.

## Related docs

- `docs/log.md` — the switches, the line format and the panel's owner.
- `docs/settings.md` — the two debug switches.
- `docs/debug.md` — the Debug block and the logging bullets.
- `docs/act_facts.md` — the host callback the runtime binds.
- `docs/anatomy.md` — the tail seat performance counters.
