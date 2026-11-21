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

## Facade

`phase()` returns `heat`, `diestrus` or `normal` from `shared/cycle_state.gd`: the debug override
first, then the feature switch and her relationship bond day. `debug_set_phase()` writes the
session override through `shared/cycle.gd`. `track()` starts one pony's schedule; the roster calls it on a prepare
and on body exit.

## Settings

The service is the only reader of `features.estrus_cycle`, `anatomy.wink_min_s`,
`anatomy.wink_max_s` and `anatomy.heat_rest_open`. It snapshots them on world enter and on a
settings change.
