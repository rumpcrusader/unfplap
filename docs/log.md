# Log and perf entry (`shared/log.gd`)

The mod's one log sink and perf entry: the two debug switches, the `[unfplap] ` prefix on every
printed line, the idle perf probe and the corner perf panel. Static like `settings/service.gd`, so
any module prints a line through a preload instead of a reference to the entry.

## Lifecycle

- Scope: process (the two switches, the idle window and the panel)
- Constructed by: static initialization
- Begin: `attach(entry)` in `main._ready()`, which also sets the switches from `settings`
- End: `detach()` on entry teardown
- Idempotent: yes; a missing parent or a missing switch only makes the module quiet

## Dependencies

### Uses

| Kind | Target | Entry point | Purpose |
|---|---|---|---|
| shared | perf_idle | `shared/perf_idle.gd` | idle perf aggregator |
| shared | perf_view | `shared/perf_view.gd` | the corner perf panel |

## Tests

- `tests/perf/test_log.gd` — the switch gate, the block text, one idle window a second and the
  lazily created panel.
- `tests/perf/test_perf_idle.gd` — the aggregator behind the idle window.
- `tests/test_perf_panel.gd` — the panel's rows, colours and caption.
