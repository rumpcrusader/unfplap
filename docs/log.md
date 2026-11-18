# Log and perf entry (`shared/log.gd`)

The mod's one log sink and perf entry: the two debug switches, the `[unfplap] ` prefix on every
printed line, the idle perf probe and the corner perf panel. Static like `settings/service.gd`, so
any module prints a line through a preload instead of a reference to the entry.

## Ownership

`shared/log.gd` owns the switches, the line format, the block format, the idle window and the panel
node. It owns no rule and no scene read, so the entry installs the three live facts it cannot know:
both switches, the act gate and the header counts.

- A module never carries `main` to log a line: it preloads `LOG` and calls `LOG.debug()`. The three
  hosts that take a sink callable (`hud`, `stock_smack` and the negotiation host) are handed
  `Callable(LOG, "debug")`.
- The switches are the entry's `settings` read and nothing else reads `settings` for them:
  `main._ready()` sets them once and `apply_settings_changed()` again.
- The act gate and the counts are entry callables, because the active runtime and the runtime
  registry belong to the entry.
- `debug_logs` gates every line; `debug_perf` only gates the perf window and the panel, and it
  needs `debug_logs` on too.
- The idle probe's own text, rows, tree and one-second window are `shared/perf_idle.gd`'s; this
  module supplies its gate, counts, log and panel sinks. See `docs/perf.md`.

## API

| Member | Contract |
|---|---|
| `debug_logs`, `debug_perf` | the two game settings, set by the entry |
| `act_running: Callable` | true while an act owns the frame; the idle window stays off |
| `counts: Callable` | `{runtimes, mares}` for the idle header, read once per window |
| `sink: Callable` | empty in game, where lines go to the console; a suite binds one to read the text it asserts |
| `attach(entry)` | the node that parents the lazy panel |
| `detach()` | the entry left the tree: drops the panel reference and clears the window |
| `debug(text)` | one line, or one entry with one prefix per line; silent with the switch off |
| `block(title, rows)` | the title, then one tab-indented row each, empty rows dropped |
| `note(key, usec, owner)` | one idle chunk with its microseconds |
| `close(key, started)` | one idle chunk whose stamp the caller took |
| `idle_on()` | the cheap idle gate |
| `tick(delta)` | print at the window boundary, then report the gate for the frame |
| `reset()` | clear the idle window |
| `perf_block(entries, info)` | hand one window to the panel, creating it on the first |
| `clear_panel()` | hide the panel and drop its window |

## Host boundary

| Host call | Purpose |
|---|---|
| `main._ready()` | `attach()`, the two switches, `act_running` and `counts` |
| `main._perf_act_running()` | the act gate: a live `active_runtime` |
| `main._perf_counts()` | the header counts: the live runtimes and `WORLD.mares()` |
| `main._apply_settings_changed()` | re-reads the switches and clears the panel when one goes off |
| `main._on_world()` | `reset()` |
| `main._on_world_closed()` | `reset()` and `clear_panel()` |
| `main._process(delta)` | `tick(delta)` first, and `close("entry_process", started)` after the body |
| `main._exit_tree()` | `detach()` |

## Frame order

`tick()` runs first in `_process`, so a window prints at the frame boundary. The entry closes its
own `entry_process` chunk after the body, which is what that row measures, so the block's ordering
and format are unchanged. A chunk noted during a frame lands in the window that frame opened.

## Debug

**Enable debug** is General's last row; **Print perf logs** sits in the same Debug block. With both
on, the panel (`shared/perf_view.gd`) is created under the entry on the first printed window and
listed in `docs/debug.md`. A suite sets `sink` to read the block text instead of the console.

## Tests

- `tests/perf/test_log.gd` — the switch gate, the host callable, the block text, one idle window a
  second, the act gate and the panel created lazily under `attach()`.
- `tests/perf/test_perf_idle.gd` — the aggregator behind the idle window: gate, boundary, per-owner
  aggregation, worst owner, tree block text and reset-on-disable.
- `tests/test_perf_panel.gd` — the panel's row height, colour targets, caption and clear.

## Related docs

- `docs/perf.md` — both probes, their chunks and the window format.
- `docs/debug.md` — the Debug block, the console gate and the panel as a player sees it.
- `docs/settings.md` — the two debug switches and how a value reaches a module.
