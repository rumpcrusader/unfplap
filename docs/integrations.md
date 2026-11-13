# Mod integrations

Optional act-time bridges to other installed mods. The service presents another mod's reactions
through the act without changing that mod, and lists every supported integration in its own settings
tab whether or not the other mod is installed.

## Scope

- `integrations/service.gd` is the facade and the only scene adapter.
- `shared/integrations.gd` is the provider catalog: mod identity, verified version, feature names
  and binding paths.
- `integrations/provider.gd`, `context.gd`, `action.gd` and `kissing.gd` are pure service internals.
- Only the Kissing 1.2.9 reaction layer is supported in this change. Its own kiss driver, guard,
  rear, reach, approach, step-back and memory recorder stay out of this service.
- The Integrations settings tab always lists a supported mod, even when that mod is absent. The
  version is the one this adapter was verified with, not a semver compatibility promise; a later
  Kissing release may still work, and the tab does not report the installed version or a mismatch.

## Ownership

The facade owns the per-act provider state, the binding resolution, the save/restore table and the
lifecycle. Providers own only policy: whether they apply, and which properties they want set. A
provider never reads a node, a tree, the clock, the filesystem, the settings file or the runtime's
private fields.

The runtime constructs one service per act through `_integrations_controller()` and passes its typed
`shared/act_facts.gd` view. The runtime calls `begin()`, `tick()`, `afterglow()`,
`apply_live_settings()` and `reset()` at the ordered lifecycle points; `_end_session()` remains the
only act teardown.

## Catalog

`shared/integrations.gd` is the single source for the tab and the adapter. A provider entry has
`mod_id`, `mod_name`, `author`, `verified_version`, `features` and `bindings`.

A binding is a path from the act pony: each step is `{"property": "..."}` or `{"child": "..."}`.
A step marked `"optional": true` makes the whole binding optional. The facade resolves every
binding at act start, re-checks required bindings each tick, and keeps optional bindings pending
until their node appears. The catalog order is the tab order.

Kissing 1.2.9 binds:

| Binding | Path | Required |
|---|---|---|
| `feelings` | pony child `KissingFeelings` | yes |
| `excitement` | pony property `excitement` | yes |
| `beat` | `excitement` child `Beat` | yes |
| `skeleton` | pony property `skeleton` | yes |
| `fidgets` | `skeleton` child `KissingFidgets` | no |

## Provider contract

`integrations/provider.gd` is the pure base. A provider implements:

```gdscript
func available(context: RefCounted) -> bool
func holds_excitement() -> bool
func start_actions(context: RefCounted, out: Array) -> void
func tick_actions(context: RefCounted, delta: float, out: Array) -> void
func afterglow_actions(context: RefCounted, out: Array) -> void
```

`holds_excitement()` asks the facade to acquire the runtime's shared excitement Beat hold while the
provider runs. The runtime refcounts named owners, so the kiss service and a provider can hold the
Beat at the same time; only the last release restores the original pause state. A provider never
writes `Beat.paused` itself.

`integrations/context.gd` carries the state, pose id, satisfaction, act seconds, afterglow flag,
Affection kind, the runtime feature snapshot and binding presence. `integrations/action.gd` carries
a `set` (required binding) or `bind` (optional binding) action with one property and value. The
facade saves each original value before its first write and restores the saved values in reverse
order on stop, feature-off, missing required binding, failed start, act end or `reset()`.

Providers must stay scene-free. `tests/test_source_hygiene.gd` rejects `extends Node`, `get_tree(`,
`Time.`, `FileAccess`, `SETTINGS` and runtime/main/world preloads in the pure files.

## Kissing provider

`integrations/kissing.gd` runs when `features.kissing_reactions` is on and the required bindings
exist. It exists to keep Kissing's build-up, which is driven by `Feelings.level`, while the act
supplies the cause and suppresses the game's own burst excitement:

- Start: clear `excitement._until`; the facade acquires the shared excitement Beat hold.
- Tick: unless an Affection kiss is active, set `excitement._until` above zero, so
  `Feelings._cause()` returns `"other"` and the build-up continues. Afterglow stops that write.
- Afterglow: clear `excitement._until` so Kissing's own hold and fade run.
- Optional `KissingFidgets`: bind `_root = -1` and `_tap_next = 1e9` when the node appears, which
  keeps the tail swish and ear flicks and suppresses the weight shift and hoof taps.

Kissing's horn aura/hum, wing shiver and earth-pony tail/ear fidgets are the three reaction families
in scope. The act's own wing controller creates the open-wing node the shiver needs; the standing
base kiss supplies an `Affection` cause, and the missionary pose supplies the `_until` cause.

## Settings

One declaration per supported integration, in `settings/service.gd`:

| Setting | Default | Behavior |
|---|---|---|
| `features.kissing_reactions` | `false` | run the Kissing reaction bridge during the act |

Each supported mod gets its own collapsible section, named `$mod_name by $author` and open by
default. The section body carries the hint `Verified with version: $verified_version`, then that
provider's feature flags; its open state is stored under `integrations/Mods/<mod id>`. The tab has
no Debug block, no installed/mismatch status and no buttons. A flag edit during an act starts or
stops the provider live through `apply_live_settings()`.

## Lifecycle

- Scope: per-act
- Constructed by: `runtime._integrations_controller()`
- Begin: `begin()` at `State.POSING_IN`
- End: `reset()` in `_free_pose()`
- Idempotent: yes

## Host boundary

| Host call | Purpose |
|---|---|
| `runtime._integrations_controller()` | one service per runtime, lazily created like the kiss and hands controllers |
| `begin()` | resolve bindings and start available providers after the act reaches `POSING_IN` |
| `tick(delta)` | update context, watch optional bindings and apply provider tick actions |
| `afterglow()` | apply the one afterglow action before Kissing's hold/fade |
| `apply_live_settings()` | restart or stop providers after a settings edit |
| `reset()` | restore every saved value after the base kiss reset in `_free_pose()` |
| `shared/act_facts.gd` | typed read model passed to the constructor; no per-frame settings read |
| `hold_beat(owner)` / `release_beat(owner)` | acquire or release the runtime's shared excitement Beat hold |

## Dependencies

### Uses

| Kind | Target | Entry point | Purpose |
|---|---|---|---|
| shared | integrations | `shared/integrations.gd` | verified mod catalog |

### Used by

| Kind | Target | Entry point | Purpose |
|---|---|---|---|
| host | runtime | `_integrations_controller()` | act lifecycle and typed facts |
| service | settings | `settings/ui.gd` | Integrations tab catalog |

## Tests

- `tests/integrations/test_catalog.gd` — metadata completeness and feature/declaration agreement.
- `tests/integrations/test_kissing.gd` — Kissing availability, actions, afterglow and the reduced
  earth fidgets.
- `tests/integrations/test_service.gd` — binding resolution, save/restore, optional bindings,
  live feature edits, shared Beat ownership and idempotent reset.
- `tests/integrations/test_hold.gd` — the runtime's named excitement Beat hold and last-release restore.
- `tests/test_settings.gd` — the Integrations tab draws every provider header and flag.
- `tests/test_source_hygiene.gd` — pure providers, facade-only imports and docs links.

## Verification / lab

- Start a standing act with Kissing 1.2.9 installed: horn/wing build-up and earth tail/ear fidgets;
  no skeleton-root sway and no hoof tap.
- Start a missionary act: the `_until` cause drives the same reactions.
- Toggle `Use Kissing reactions` off and on during an act, including during a base kiss: the
  provider stops and restores, then starts again, and the Beat hold follows the last owner.
- End the act and force-stop one: `_until`, the fidget fields and the shared Beat hold are restored.
- Remove Kissing: the tab still shows `Kissing by modChad` and `Verified with version: 1.2.9`; the
  flag has no effect.

## Related docs

- `docs/settings.md` — the declaration model and the Integrations tab.
- `docs/runtime.md` — the act lifecycle and tick order.
- `docs/act_facts.md` — the typed view the host passes.
