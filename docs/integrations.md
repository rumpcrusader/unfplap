# Mod integrations

Optional bridges to other installed mods. The service presents another mod's reactions or pose
style through the act without changing that mod, and lists every supported integration in its own
settings tab whether or not the other mod is installed.

## Scope

- `integrations/service.gd` is the facade and the only scene adapter.
- `shared/integrations.gd` is the provider catalog: mod identity, verified version, feature names
  and binding paths.
- `integrations/provider.gd`, `context.gd`, `action.gd`, `kissing.gd` and `idle_life.gd` are
  pure service internals.
- Two integrations are supported: the Kissing 1.2.9 reaction layer and the Idle Life 1.4.2
  stretch pose. Kissing's own kiss driver, guard, rear, reach, approach, step-back and memory
  recorder stay out of this service.
- The Idle Life provider only switches the act pose node's `stretch` flag. The external pose
  script is loaded and held by `poses/idle_stretch.gd`; its owner is `docs/poses.md`.
- The Integrations settings tab always lists a supported mod, even when that mod is absent. The
  version is the one this adapter was verified with, not a semver compatibility promise; a later
  release may still work, and the tab does not report the installed version or a mismatch.

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

Idle Life 1.4.2 binds:

| Binding | Path | Required |
|---|---|---|
| `pose` | pony property `skeleton`, child `UnfplapPose` | yes |

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

`integrations/context.gd` carries the state, pose id, satisfaction, mood, seconds since the last
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
- Optional `KissingFidgets`: the two suppressed fields stay off through the act. The debug feature
  `features.kissing_full_fidgets` restores them for the climax only, then suppresses them again when
  the climax ends or afterglow starts.

Kissing's horn aura/hum, wing shiver and earth-pony tail/ear fidgets are the three reaction families
in scope. The act's own wing controller creates the open-wing node the shiver needs.

## Idle Life provider

`integrations/idle_life.gd` runs when `features.idle_life_stretch` is on, the pose id is
`standing`, the `pose` binding resolves and Idle Life is active this launch. It appends one start
action, `set_value("pose", "stretch", true)`, and has no tick, afterglow, reaction-cap or
excitement-hold behavior. The facade saves the pre-act `stretch` value and restores it on stop,
feature-off, missing binding, act end or `reset()`, so the normal standing recipe returns.

The stretch switch is debug-only and default off, and the feature is currently broken: entering
the act with it on makes Anon undergo a transformation. It stays dormant unless **Enable debug** is
on; `act_snapshot()` forces the feature false and the standing presentation's `_stretch_enabled()`
also requires debug mode. Do not recommend turning it on until the transformation is fixed.

The provider never reads or writes Idle Life's files. The external script, the episode choice and
the modifier order belong to `poses/idle_stretch.gd` (`docs/poses.md`).

## Settings

One declaration per supported integration, in `settings/service.gd`:

| Setting | Default | Behavior |
|---|---|---|
| `features.kissing_reactions` | `false` | run the Kissing reaction bridge during the act |
| `features.kissing_full_fidgets` | `false` | debug-only: restore Kissing's weight shift and hoof taps during the climax; the switch is in General's Debug block |
| `features.idle_life_stretch` | `false` | debug-only: switch the accepted standing presentation and act to Idle Life's stretch pose while Idle Life is active; dormant unless Enable debug is on, currently broken, and the ask stays normal |

Each supported mod gets its own collapsible section, named `$mod_name by $author` and open by
default, under one blue **Experimental** notice at the top of the tab. The section body carries the hint `Verified with version: $verified_version`, then that
provider's player-facing feature flags; its open state is stored under `integrations/Mods/<mod id>`.
The tab's **Debug** block, shown only when **Enable debug** is on, holds its debug-only switches.
There is no installed/mismatch status and no buttons. A flag edit during an act starts or
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
- `tests/integrations/test_kissing.gd` — Kissing availability, the warming/close/climax ramp, the
  bond cap, the pause fade, afterglow, an Affection kiss and the full-fidget restore/suppress.
- `tests/integrations/test_idle_life.gd` — the stretch provider's feature, pose, external-mod and
  binding gates, and its one reused pose write.
- `tests/integrations/test_service.gd` — binding resolution, save/restore, optional bindings,
  the reaction cap, live feature edits, shared Beat ownership, full fidgets and idempotent reset.
- `tests/integrations/test_hold.gd` — the runtime's named excitement Beat hold and last-release restore.
- `tests/test_settings.gd` — the Integrations tab draws every provider header and flag.
- `tests/test_source_hygiene.gd` — pure providers, facade-only imports and docs links.

## Verification / lab

- Start a standing act with Kissing 1.2.9 installed: no horn/wing/fidget reaction before the close
  band, a bond-capped ramp through it, the reactions fading when thrusting stops, and the full cap
  through the five-second climax.
- Start a missionary act: the same readiness-driven level drives the reactions.
- Toggle `Use Kissing reactions` off and on during an act, including during a base kiss: the
  provider stops and restores (including `level`), then starts again, and the Beat hold follows the
  last owner.
- Enable `Play full Kissing fidgets` in General's Debug block: the root sway and hoof taps return
  only during the climax and are suppressed again when it ends or afterglow begins.
- End the act and force-stop one: `_until`, `level`, the fidget fields and the shared Beat hold are
  restored.
- Remove Kissing: the tab still shows `Kissing by modChad` and `Verified with version: 1.2.9`; the
  flag has no effect.
- With Idle Life 1.4.2 installed and `Use the Idle Life stretch pose` on: a private standing offer
  asks in the normal pose while she faces Anon; once the line finishes and Anon accepts, the
  presentation and act hold the same light/deep variant and side; a public ask stays normal; a
  cancelled offer drops the choice.
- Toggle the Idle Life flag off and on during the presentation and the act: the normal standing
  pose returns and the stretch is reinstalled with no stale modifier.
- Remove or disable Idle Life: the tab still shows `Idle Life by modChad`,
  `Verified with version: 1.4.2` and the switch; the flag has no effect and no script errors
  appear.
- Run both integrations together: Kissing's readiness ramp and the stretch act coexist.

## Related docs

- `docs/settings.md` — the declaration model and the Integrations tab.
- `docs/runtime.md` — the act lifecycle and tick order.
- `docs/act_facts.md` — the typed view the host passes.
