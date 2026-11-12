# Perf probe (`perf.gd`)

The act's debug performance probe. Timed chunks report microseconds and one summary prints per
one-second window, so a pony-specific stall can be attributed to a modifier or a service without a
live profiler.

## Ownership

- `perf.gd` is a pure `RefCounted` module owned by the runtime. It holds the window, the chunk
  rows and the summary formatting.
- The runtime supplies the two gates (`enabled`, `active`), the header facts and the log callback.
- Timed call sites in the runtime and the skeleton modifiers call `perf_note(key, usec)`.
- `**Print perf logs**` is a separate debug switch; it needs **Enable debug** on too.

## API

| Member | Contract |
|---|---|
| `enabled: Callable` | both debug switches are on |
| `active: Callable` | true while an act is running; the window clears outside it |
| `header: Callable` | returns `{pony, pose, state, near_mesh, tier, wings}` |
| `log: Callable` | writes one summary block |
| `note(key, usec)` | record one timed chunk; a cheap no-op when off |
| `time(key, started_usec)` | close one call site; the caller takes the start stamp |
| `reset()` | clear the window and rows |
| `tick(delta)` | accumulate a frame and print at the window boundary |

The summary line is:

```text
perf pony=<id> pose=<pose> state=<n> fps=<n> frame=<ms> near_mesh=<state> tier=<state> wings=<state>
    <chunk> <ms/s> per-frame <ms> max <ms> calls <n>
```

Rows are sorted by total milliseconds per second, largest first.

## Rules

- No scene access. The module reads no Node and no global Settings.
- Off is allocation-free apart from the empty dictionary and the window counters.
- The window resets whenever the runtime is `IDLE`, so nothing prints outside an act.
- The probe is a debug tool, not a setting: no declaration and no persisted value.

## Debug

**Enable debug** + **Print perf logs** in General's Debug block. The runtime also prints one-shot
`tail perf attach`/`tail perf refresh` lines and a once-per-second
`tail perf seats=… skinned=… builds=…/s` line when the probe is on.

## Tests

- `tests/perf/test_perf.gd` — the on/active gates, window reset, row aggregation and summary
  formatting.

## Related docs

- `docs/settings.md` — the two debug switches.
- `docs/act_facts.md` — the host callback the runtime binds.
- `docs/anatomy.md` — the tail seat performance counters.
