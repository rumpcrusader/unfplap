# Mod integrations

Optional bridges to other installed mods. The service presents another mod's reactions through the
act without changing that mod, and lists every supported integration in its own settings tab
whether or not the other mod is installed.

## Scope

- `integrations/service.gd` is the per-act facade and the only per-act scene adapter.
- `integrations/pantyhose.gd` is the world-side adapter for the Pantyhose & Panties 0.1.1 pack:
  it lifts a worn piece over the anatomy and takes the lower garment off at an act start. The pack
  is never edited; the compatibility shaders are a pinned copy under `integrations/shaders/`.
- `shared/integrations.gd` is the provider catalog: mod identity, verified version, feature names
  and binding paths.
- `integrations/provider.gd`, `context.gd`, `action.gd` and `kissing.gd` are pure service
  internals.
- Two integrations are supported: the Kissing 1.2.9 reaction layer and the Pantyhose & Panties
  0.1.1 world garment adapter. Kissing's own kiss driver, guard, rear, reach, approach, step-back
  and memory recorder stay out of this service.
- The Integrations settings tab always lists a supported mod, even when that mod is absent. The
  version is the one this adapter was verified with, not a semver compatibility promise; a later
  release may still work, and the tab does not report the installed version or a mismatch.

## Ownership

The facade owns the per-act provider state, the binding resolution, the save/restore table and the
lifecycle. Providers own only policy: whether they apply, and which properties they want set. A
provider never reads a node, a tree, the clock, the filesystem, the settings file or the runtime's
private fields.

The world adapter owns its scan (the debug Update frequency, 2 Hz by default), the per-node
material overrides, its cached feature/debug values and the act-start undress. It reads the anatomy
through `main.anatomy` and the game through `main.game`; it never preloads either host and never
edits the pack.

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

Pantyhose & Panties 0.1.1 is a world integration: its `bindings` dictionary is empty, so the
per-act facade never creates a provider for it. Its two features drive the world adapter below.

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

`integrations/context.gd` carries the state, pose family, satisfaction, mood, seconds since the last
real stroke, act seconds, afterglow flag, Affection kind, the provider's reaction cap, whether the
provider's external mod is active this launch, the runtime feature snapshot and binding presence.
The external-mod flag comes from the runtime's `shared/act_facts.gd` `mod_active(id)` callback; a
provider that does not need it ignores the field. `integrations/action.gd` carries a `set` (required binding),
`bind` (optional binding) or `restore` action with one property and value. The facade saves each
original value before its first write and restores the saved values in reverse order on stop,
feature-off, missing required binding, failed start, act end or `reset()`. A `restore` puts one
saved original back without dropping the record, so a later write keeps the act-start value for the
final reset.

Providers must stay scene-free. `tests/test_source_hygiene.gd` rejects `extends Node`, `get_tree(`,
`Time.`, `FileAccess`, `SETTINGS` and runtime/main/world preloads in the pure files.

## Kissing provider

`integrations/kissing.gd` runs when `features.kissing_reactions` is on and the required bindings
exist. It exists to keep Kissing's build-up, which is driven by `Feelings.level`, under act control
while suppressing the game's own burst excitement. The act owns the level instead of giving Kissing
a permanent cause:

- Start: clear `excitement._until`, take the shared excitement Beat hold, and suppress the optional
  `KissingFidgets` weight shift and hoof taps (`_root = -1`, `_tap_next = 1e9`).
- Tick: below the close band (`mood != "close"`) the target level is 0. Once she is close and a
  real stroke landed within `ACTIVE_GRACE_S = 1.2 s`, the target ramps from 0 to her bond cap with
  readiness (`CLOSE_AT = 65` to 100), and the provider eases `feelings.level` toward it. The cap is
  read from Kissing's `Feelings._peak()` at provider start and carried as `context.reaction_cap`, so
  the ramp never exceeds the stage's ambient ceiling. When the player stops stroking, the target
  falls to 0 and the level fades.
- The cause (`excitement._until = 0.5`) stays set only while the level is above the resting
  threshold, which keeps Kissing's hold topped up; afterglow clears it and lets Kissing's own 1.5 s
  hold + 4 s fade run.
- Climax: `state == CLIMAX` pins the target to `reaction_cap` at the climax rate, so the reaction is
  fully active for her bond even if the player keeps thrusting through it.
- An Affection kiss keeps its own cause and build-up; the provider resumes act control after it.
- Optional `KissingFidgets`: the weight-shift root and the hoof-tap clock stay suppressed through
  the act, because they move the skeleton root or lift a planted hoof. Her climax restores them for
  its duration, then suppresses them again when the climax ends or afterglow starts.

Kissing's horn aura/hum, wing shiver and earth-pony tail/ear fidgets are the three reaction families
in scope. The act's own wing controller creates the open-wing node the shiver needs.

## Pantyhose & Panties

`integrations/pantyhose.gd` is the world adapter, created by `main` as `main.pantyhose`. It runs
outside acts: at the debug Update frequency (2 Hz by default, `0` stops the automatic scan) it
finds each mare's `Wear_panties-*` and `Wear_pantyhose-*` nodes and, while the anatomy mesh is
shown and the bulge flag is on, gives every surface of the shared piece an override of the copied
compatibility shader. The original material stays on the shared mesh; the override is per node, and
every instance value is per node, so two mares never share a transform. The compatibility material
is cached per source material and variant, so each fabric keeps its own look parameters while every
mare shares it. The previous override is saved and restored on a hidden anatomy, feature-off,
pack-off, node replacement and world close.

The lift samples `anatomy/garment_hull.gd`'s rear-facing outer depth field, built from the refined
anatomy mesh and shared by every mare. The field is the **rest appearance**: the base mesh with
`closed` at 1 and `ponut_scale` at the rest `anal_scale - 1`; `wink`, the anal keys and `stretch`
are at 0. The inner canal is excluded by the rear-facing normal test. The garment is removed at act
start, so the field does not need the opened/stretched act shapes.
The shader maps the garment vertex into anatomy-local space with the per-mare transform, reads the
field, and pushes the cloth out along the anatomy's +Z by the surface difference plus the margin.
The margin is stored in anatomy-local units and converted back by the basis' Z scale, so the
slider stays in world millimetres. The debug controls choose the field resolution, smoothing,
margin and update frequency. The hull rows are unbounded debug values; a high resolution or many
smoothing passes costs a one-time rebuild. A precision edit clears the cache and rebuilds after
0.3 s, and the Rebuild action rebuilds immediately. Both are off the frame path. **Show hull**
draws the heatmap as a continuous corner-grid surface from a top-level world mesh that copies the
anatomy mesh's transform, so the field can be inspected even when the anatomy is hidden (far mesh
or `act` mode outside an act); the overlay state and the reason it is hidden are logged once per
change with debug logs on.

On `anatomy.act_started` the adapter calls the wardrobe's `set_worn(id, "panties", false)` and
`set_worn(id, "pantyhose", false)` and then `dress(pony, id, season)` immediately, so the nodes are
gone before the first rendered act frame. `set_worn` writes the game's own `pony_off` state; the
adapter does not restore anything at act end, so she stays undressed until she is asked or given a
new piece. A missing wardrobe, pony id or season is a quiet no-op (the season falls back to
`spring`).

The compatibility shaders are `integrations/shaders/pantyhose_common.gdshaderinc`,
`pantyhose_cut.gdshader` and `pantyhose_sheer.gdshader`: a self-contained copy of 0.1.1's look
with the hull block added. The catalog's `verified_version` pins the copy. A renamed or changed
pack shader is left alone and logged once; the adapter never edits the pack.

## Settings

One declaration per supported integration, in `settings/service.gd`:

| Setting | Behavior |
|---|---|
| `features.kissing_reactions` | run the Kissing reaction bridge during the act |
| `features.pantyhose_undress` | take her panties and pantyhose off when an act starts; she stays undressed |
| `features.pantyhose_bulge` | lift the worn panties and pantyhose over the anatomy |

Each supported mod gets its own collapsible section, named `$mod_name by $author` and open by
default, under one blue **Experimental** notice at the top of the tab. The section body carries the hint `Verified with version: $verified_version`, then that
provider's player-facing feature flags; its open state is stored under `integrations/Mods/<mod id>`.
The tab's one Debug block (behind **Enable debug**) carries the Pantyhose hull precision rows
(`debug.pantyhose_hull_*`), the **Update frequency** row (`debug.pantyhose_update_hz`) and the
**Pantyhose: rebuild hull** action; Kissing has no debug rows.
There is no installed/mismatch status and no other buttons. A flag edit during an act starts or
stops the Kissing provider live through `apply_live_settings()`; the Pantyhose flags are cached by
the world adapter on the same settings edit.

## Lifecycle

- Scope: per-act service + world adapter
- Constructed by: `runtime._integrations_controller()` for the per-act facade;
  `main._ready()` for the world adapter
- Begin: `begin()` at `State.POSING_IN`; `on_world(host)` on world entry
- End: `reset()` in `_free_pose()`; `on_world_closed()` on world close and `shutdown()` in
  `main._exit_tree()`
- Idempotent: yes. The world adapter is inert when the pack is absent.

## Host boundary

| Host call | Purpose |
|---|---|
| `runtime._integrations_controller()` | one service per runtime, lazily created like the kiss and hands controllers |
| `begin()` | resolve bindings and start available providers after the act reaches `POSING_IN` |
| `tick(delta)` | update context, watch optional bindings and apply provider tick actions |
| `afterglow()` | apply the one afterglow action before Kissing's hold/fade |
| `apply_live_settings()` | restart or stop providers after a settings edit; refresh the world adapter's cached flags |
| `reset()` | restore every saved value after the base kiss reset in `_free_pose()` |
| `shared/act_facts.gd` | typed read model passed to the constructor; no per-frame settings read |
| `hold_beat(owner)` / `release_beat(owner)` | acquire or release the runtime's shared excitement Beat hold |
| `main.anatomy` | the controller's `garment_hull()`, `garment_transform()`, `garment_visible()`, `garment_parent()`, `garment_hull_rebuild()` and the `act_started` signal |
| `main.game.mares` | the loaded mares the world adapter scans |
| `main.game.Weather` | the wardrobe season the undress passes to `dress()` |
| `pony_wardrobe` group | the wardrobe's `set_worn()` and `dress()` for the act undress |
| `main._apply_settings_changed()` | calls the world adapter's `apply_live_settings()` |

## Dependencies

### Uses

| Kind | Target | Entry point | Purpose |
|---|---|---|---|
| service | settings | `settings/service.gd` | feature flags, hull precision and the cached values |
| shared | integrations | `shared/integrations.gd` | verified mod catalog |
| shared | pony_id | `shared/pony_id.gd` | stable id for the wardrobe's `set_worn()` |

### Used by

| Kind | Target | Entry point | Purpose |
|---|---|---|---|
| host | runtime | `_integrations_controller()` | act lifecycle and typed facts |
| host | main | `main.pantyhose` | world lifecycle and the debug Rebuild button |
| service | settings | `settings/ui.gd` | Integrations tab catalog |

## Tests

- `tests/integrations/test_catalog.gd` — metadata completeness, feature/declaration agreement and
  the world-only entry (no per-act bindings).
- `tests/integrations/test_kissing.gd` — Kissing availability, the warming/close/climax ramp, the
  bond cap, the pause fade, afterglow, an Affection kiss and the full-fidget restore/suppress.
- `tests/integrations/test_pantyhose.gd` — the hull builder (fixture and real anatomy mesh), the
  transform mapping, the surface overrides and restore, the shared mesh, multi-mare independence,
  the act-start undress, the feature/pack/wardrobe/weather guards and the debug rebuild/overlay.
- `tests/integrations/test_service.gd` — binding resolution, save/restore, optional bindings,
  the reaction cap, live feature edits, shared Beat ownership, full fidgets, idempotent reset and
  the absence of a per-act provider for the world integration.
- `tests/integrations/test_hold.gd` — the runtime's named excitement Beat hold and last-release restore.
- `tests/test_settings.gd` — the Integrations tab draws every provider header, flag and the Debug
  block's hull rows.
- `tests/test_source_hygiene.gd` — pure providers, facade-only imports and docs links.

## Verification / lab

- Start a standing act with Kissing 1.2.9 installed: no horn/wing/fidget reaction before the close
  band, a bond-capped ramp through it, the reactions fading when thrusting stops, and the full cap
  through the five-second climax.
- Start a missionary act: the same readiness-driven level drives the reactions.
- Toggle `Use Kissing reactions` off and on during an act, including during a base kiss: the
  provider stops and restores (including `level`), then starts again, and the Beat hold follows the
  last owner.
- At her climax the root sway and hoof taps return, and are suppressed again when it ends or
  afterglow begins.
- End the act and force-stop one: `_until`, `level`, the fidget fields and the shared Beat hold are
  restored.
- Remove Kissing: the tab still shows `Kissing by modChad` and `Verified with version: 1.2.9`; the
  flag has no effect.
- With the pantyhose pack as `0_pantyhose.pck`, give all eight kinds and check the bulge in
  `always` and `act` anatomy modes; start an act and confirm the immediate removal; check she stays
  undressed; turn each flag off; remove the pack; check the original materials come back and two
  mares keep independent transforms. Use **Show hull** and **Rebuild** to inspect the field; the
  overlay is desktop-only and is skipped headless.

## Related docs

- `docs/settings.md` — the declaration model and the Integrations tab.
- `docs/runtime.md` — the act lifecycle and tick order.
- `docs/act_facts.md` — the typed view the host passes.
