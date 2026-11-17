# Perf probes (`shared/perf.gd`, `shared/perf_idle.gd`)

The mod's two debug performance probes. Both report timed chunks in microseconds and print one
block per one-second window, so a stall can be attributed to a modifier, a service or a single
pony without a live profiler. The act probe prints one summary per acting pony; the idle probe
aggregates every idle runtime into one block.

## Ownership

- `shared/perf.gd` is a pure `RefCounted` module owned by the runtime. It holds the act's window,
  chunk rows, header facts and summary formatting.
- `shared/perf_idle.gd` is a pure `RefCounted` module owned by `main.gd`. It holds the idle window,
  aggregated rows, worst owner per chunk, counts and block formatting.
- The runtime supplies the act probe's two gates (`enabled`, `active`), the header facts and the
  log callback.
- `main.gd` supplies the idle probe's gate (`enabled`), the header counts and the log callback.
  Idle runtimes forward their chunks through `runtime.perf_note()`.
- Timed call sites in the runtime, the anatomy controller and the skeleton modifiers report to the
  runtime; `main.gd` times its own process body and the offer scan.
- `**Print perf logs**` is a separate debug switch; it needs **Enable debug** on too. One switch
  drives both probes.

## Act probe API

| Member | Contract |
|---|---|
| `enabled: Callable` | both debug switches are on |
| `active: Callable` | true while an act is running; the window clears outside it |
| `header: Callable` | returns `{pony, pose, state, lean, hands, near_mesh, tier, wings}` |
| `log: Callable` | writes one summary block |
| `note(key, usec)` | record one timed chunk; a cheap no-op when off |
| `time(key, started_usec)` | close one call site; the caller takes the start stamp |
| `reset()` | clear the window, the rows and the physics mark |
| `tick(delta)` | accumulate a frame and print at the window boundary |

The probe also reads `Engine.get_physics_frames()`, `Engine.get_frames_per_second()`, the
`Performance` process/physics monitors and the renderer's draw-call and primitive counters. Those
are engine values, not scene access.

The summary line is:

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

Rows are sorted by total milliseconds per second, largest first.

## Idle probe API

| Member | Contract |
|---|---|
| `enabled: Callable` | both debug switches are on and no act is running |
| `counts: Callable` | returns `{runtimes, mares}` for the header, read once per window |
| `log: Callable` | writes one block |
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

| Chunk | Source |
|---|---|
| `entry_process` | the whole `main._process` body |
| `offer_scan` | the 0.15 s `_refresh_offer()` call |
| `offer_cone` | the standing candidate search in `_refresh_offer()` |
| `offer_gate` | the standing hint's `runtime.hotkey_ready()` |
| `runtime_process` | one pony's idle `_process_tick` |
| `runtime_physics` | one pony's idle `_physics_process` |
| `runtime_anatomy_sync` | the two `_sync_anatomy_facts()` calls per physics tick, summed |
| `runtime_facts` | `_sync_act_facts()` in the physics tick |
| `runtime_presentation` | `_standing_presentation_controller().physics(delta)` |
| `runtime_history` | `_history_tick(delta)` |
| `anatomy_process` | the whole persistent `anatomy/controller.gd::_process`, reported outside an act |
| `anatomy_coat_follow`, `anatomy_visibility`, `teat_jiggle` | reported through `facts.perf` |

The anatomy chunks need no extra forward: `facts.perf` already calls the runtime's `perf_note`,
which is the single forwarding point. `entry_process` contains `offer_scan`, which contains
`offer_cone` and `offer_gate`. `offer_gate` reads `runtime.hotkey_ready()`: the scene rows are
rebuilt every call, while the two Base-clearance reads are cached for `0.5 s` across the 0.15 s
hint scan. A real act-key press passes `fresh` and pays the eligibility read again.

## Gate and reset

- Both probes are off unless **Enable debug** and **Print perf logs** are on.
- The act probe prints only while its runtime is not `IDLE`; its window resets outside an act.
- The idle probe prints only while no act is running (`main.active_runtime` is null). It resets
  when an act starts, when a switch goes off, on world start, on world close and on entry teardown.
- With a switch off, no clock is taken in the idle path, the runtime's forward is one bool branch
  and `note`/`tick` early-return. Rows are updated in place; nothing allocates per frame.
- The probes are debug tools, not settings: no declaration and no persisted value.

## Debug

**Enable debug** + **Print perf logs** in General's Debug block. Standing in town outside an act
prints one `perf idle` block a second. During an act the per-pony `perf` lines print instead and
no idle block prints.

The act probe's own chunks, in call order inside one physics tick: `pose_tick`, `runtime_facts`,
`pose_fanout`, `caress_tick` (inside the lean), `runtime_presentation`, `kiss_tick`, `runtime_ai`,
`anatomy_tick`, `runtime_talk`, `runtime_camera`, `runtime_face`, all inside `runtime_physics`.
`pose_tick` is the pose edge clock, the channel records, the switches/events and the oral turn;
`pose_fanout` is the modifier reconcile, the `act_body`/`anon` channel and the
camera/hands/kiss/anatomy/audio hooks. The facts sync carries the one `pose_view`; the standing
camera reads its facing each physics tick, and the mouth/contact provider reads its
`contact_kind`. The skeleton modifiers report `pose_recipe` (`UnfplapPose`) and `pose_prone`
(`UnfplapProneSway`); `runtime_process` covers the render-time pose write. Chunks nest:
`runtime_presentation` contains `wings_tick`, and `caress_tick` contains `caress_precise` →
`caress_path` (the one-time path/anchor build) and `caress_surface` → `caress_skin`/`caress_tri`/
`caress_ray`. `caress_path` only reports on a build tick; a large max there with every other chunk
steady is the first caress path, not the per-tick contact.

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
the bed family. In a standing lab, compare `runtime_process` and `pose_recipe` at
Canon and one non-canon size against the pre-C build; the ground frame sync is one transform compare
per tick and allocates nothing, and the pose write is the only new per-frame cost.

## Tests

- `tests/perf/test_perf.gd` — the act probe's on/active gates, window reset, row aggregation and
  summary formatting.
- `tests/perf/test_perf_idle.gd` — the idle probe's gate, window boundary, per-owner aggregation,
  worst owner, block text and reset-on-disable.

## Related docs

- `docs/settings.md` — the two debug switches.
- `docs/debug.md` — the Debug block and the logging bullets.
- `docs/act_facts.md` — the host callback the runtime binds.
- `docs/anatomy.md` — the tail seat performance counters.
