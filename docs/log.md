# Log and perf entry (`shared/log.gd`)

The mod's one log sink and perf entry: the two debug switches, the `[unfplap] ` prefix on every
printed line, the idle perf probe and the corner perf panel. Static like `settings/service.gd`, so
any module prints a line through a preload instead of a reference to the entry.

## Ownership

`shared/log.gd` owns the switches, the line format, the block format, the idle window and the panel
node. It owns no rule and no scene read, so the entry installs the live facts it cannot know: the
two switch reads, the act gate and the header counts.

- A module never carries the entry to log a line: it preloads `LOG` and calls `LOG.debug()`. The
  three hosts that take a sink callable (`hud`, `stock_smack` and the negotiation host) are handed
  `Callable(LOG, "debug")`.
- The switches are two `settings` reads the entry binds (`debug_read`, `perf_read`), because a
  shared module never imports a service. `attach()` reads them once and the settings change
  notification (`shared/settings_change.gd`) calls `apply_settings()` on every later edit.
- The act gate and the counts are `ponies` callables, because the active runtime and the runtime
  registry belong to that service.
- `debug_logs` gates every line; `debug_perf` only gates the perf window and the panel, and it
  needs `debug_logs` on too.
- The idle probe's own text, rows, tree and one-second window are `shared/perf_idle.gd`'s; this
  module supplies its gate, counts, log and panel sinks. See `docs/perf.md`.

## API

| Member | Contract |
|---|---|
| `debug_logs`, `debug_perf` | the two game settings, read at `attach()` and on every settings edit |
| `debug_read`, `perf_read` | the two switch reads, bound by the entry |
| `apply_settings()` | re-read the switches and close a panel that is no longer both on |
| `act_running: Callable` | true while an act owns the frame; the idle window stays off |
| `counts: Callable` | `{runtimes, mares}` for the idle header, read once per window |
| `sink: Callable` | empty in game, where lines go to the console; a suite binds one to read the text it asserts |
| `attach(entry)` | the node that parents the lazy panel; joins the settings notification and reads the switches |
| `detach()` | the entry left the tree: leaves the notification, drops the panel reference and clears the window |
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
| the entry's `_ready()` | binds `debug_read`, `perf_read`, `act_running` and `counts`, then `attach()` |
| `PONIES.act_running()` | the act gate: a live act owns the frame |
| `PONIES.runtime_count()`, `PONIES.mare_count()` | the header counts: the live runtimes and `WORLD.mares()` |
| `SETTINGS.debug_mode` / `SETTINGS.debug_perf` | the two switch reads: `Callable(setting, "get_bool")` |
| `shared/settings_change.gd` | calls `apply_settings()` on every settings edit: re-reads the switches and clears the panel when one goes off |
| the entry's `_on_world(host)` | `reset()` after the service list |
| the entry's `_release()` | `reset()` and `clear_panel()`; a world close and the process exit both run it |
| the entry's `_process(delta)` | `tick(delta)` first, and `close("entry_process", started)` after the body |
| the entry's `_exit_tree()` | `detach()` |

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
