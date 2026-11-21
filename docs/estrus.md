# Estrus cycle

The optional 30-day mare cycle. `estrus/service.gd` owns the per-pony wink schedule and the idle
rest push to anatomy; the phase it reads comes from `shared/cycle_state.gd`, the one derivation the
act gate also uses. It is off when `features.estrus_cycle` is off; the session-only debug override
is honoured either way.

## Scope

The act gate keeps the act's cycle row and asks the same shared derivation; estrus keeps the clock,
the schedule and the idle animation. Anatomy keeps the wink animation settings and the shapes;
estrus owns when to call `anatomy.wink()` and `anatomy.rest()`. The relationship bond day is the
clock.

## Lifecycle

- Scope: world
- Constructed by: the entry's service list
- Begin: `on_world(host)`
- End: `on_world_closed()`/`shutdown()`
- Idempotent: yes

## Public API

```gdscript
phase(pony) -> String
debug_set_phase(pony, phase) -> String
track(pony), untrack(pony)
bind(anatomy: API)
```

`phase()` returns `heat`, `diestrus` or `normal` from `shared/cycle_state.gd`: the debug override
first, then the feature switch and her relationship bond day. `debug_set_phase()` writes the
session override through `shared/cycle.gd`. `track()` starts one pony's schedule; the roster calls it on a prepare
and on body exit.

## Settings

The service is the only reader of `features.estrus_cycle`, `anatomy.wink_min_s`,
`anatomy.wink_max_s` and `anatomy.heat_rest_open`. It snapshots them on world enter and on a
settings change.

## Dependencies

### Uses

| Kind | Target | Entry point | Purpose |
|---|---|---|---|
| service | anatomy | `anatomy/api.gd` | anatomy and tail seat |
| service | settings | `settings/service.gd` | settings declarations and live values |
| shared | cycle | `shared/cycle.gd` | estrus cycle |
| shared | cycle_state | `shared/cycle_state.gd` | shared data |
| shared | log | `shared/log.gd` | log sink |
| shared | perf | `shared/perf.gd` | one profiler |
| shared | pony_id | `shared/pony_id.gd` | shared data |
| shared | settings_change | `shared/settings_change.gd` | settings change notification |

## Tests

`tests/estrus/test_estrus.gd` pins the phase order, the override, the schedule suppression and the
one `estrus_tick` row.
