# Architecture

This is the conceptual contract for how `unfplap` is put together. It defines what a service is,
what it may depend on, where state lives, how lifecycle is owned and how the rules are checked.

It does not document individual services. The service index is `docs/README.md`; the technical
contract for each service is `docs/<service>.md`. A service doc is the single source of truth for
that service's responsibility and boundary, its decisions, invariants, ordering constraints, traps
and extension points.

## What the mod is made of

| Part | Role |
|---|---|
| Entry | `main.gd`: the mod's primitives, the one ordered service list, the `Mods` hooks, the frame order and the one teardown. |
| Per-pony host | `runtime.gd`: one per non-player pony, idle and in an act. Lifetime, parenting, the two engine-frame forwards, the reparent across a body swap and the world-close release; its own `act/` modules own the state, timers and clock, the ledgers, the schedule, the collaborator set, the view and the idle schedule. |
| Service | An isolated unit that owns one authority over mutable state and exposes it through one facade. |
| Service base | `shared/service.gd`: the four lifecycle hooks as no-ops. Every world-list service extends it, so the entry calls the hooks directly; the HUD is the one `CanvasLayer` that carries them itself. |
| Service internals | Private modules under `<service>/`. Nothing outside the service imports them. |
| Shared pure module | Deterministic data or math in `shared/`. No scene, no lifecycle, no service dependency. |
| Shared store | Persisted shared data in `shared/`. No scene, no lifecycle; may read `settings`, never a domain service. |
| Scene read facade | `world/api.gd`: the live world root, Anon's body and the reads derived from them, bound by the entry. Answers where and what, never whether. |
| Base-game accessors | `world/game.gd`: every base-game and presentation member the mod reads or writes, one static typed function per member with the handle as an argument. Read like the scene by services, shared modules and the settings layer. |
| Read model | A scene-free mutable value object refreshed by its owner, for example the act view. |
| Port | A service-owned abstract `RefCounted` contract the runtime implements once per pony, for example `shared/start_port.gd`; it replaces a `Callable` bag without a service cycle. |
| Cross-mod API | `api.gd` and `docs/api.md`: the only stable contract another mod may call. |
| Host | A scene or orchestrator object a service receives values and callbacks from. A host is not a service. |

`main.gd` and `runtime.gd` are not services. They compose services and own order. They may hold
per-world or per-pony orchestration state, but they do not implement another service's rules.

The entry has four jobs and nothing else:

1. the primitives: the settings load, the two debug switch binds and the loader lookup;
2. the one ordered service list (`_build_services()`), a line or two per service;
3. the broadcasts and the frame loop, in a visible order;
4. the one teardown (`_release()` then `_shutdown()`).

A world-list service extends `shared/service.gd`, which supplies `on_world(host)`,
`on_world_closed()`, `on_player(body)` and `shutdown()` as no-ops; a service overrides the ones it
needs. The list order is the call order. The entry validates the four names once at boot, so a
service that skips the base fails loudly instead of being skipped. The entry is not a service
locator: nothing outside `main.gd` (and `tests/`) names `main`, so a consumer preloads the facade it
needs, reads `WORLD` for the scene, or takes a host parameter.

## Layers and allowed imports

```text
main.gd / runtime.gd          entry and orchestration
api.gd                        cross-mod facade
world/api.gd                  scene read facade
world/game.gd                 base-game accessors
<service>/api.gd              service facades (preferred)
<service>/service.gd          legacy service facade
<service>/**                  private service implementation
shared/**                     pure modules, shared stores, read models
res://world/..., res://player/...   game and engine
```

| Layer | May import |
|---|---|
| Entry / orchestrator | anything |
| Cross-mod API | service facades, shared modules |
| Scene read facade | `res://world/`, `res://player/`, shared modules and its own accessor module |
| Base-game accessors | `res://world/`, `res://player/` only |
| Infrastructure service (`settings`) | shared pure modules |
| Domain service | `settings`, shared modules, other service facades |
| Shared store | `settings`, shared pure |
| Read model | shared pure |
| Shared pure | shared pure only |

`world/game.gd` is not a dependency edge: a service, a shared module and the settings layer read it
like `res://world/` and `res://player/`, and it imports no mod file.

Rules:

- A service never preloads `runtime.gd`, `main.gd` or `api.gd`, and no file outside `main.gd` and
  `tests/` names the entry at all: no `main.<member>`, no `var main`, no `main.gd` preload and no
  `main` argument.
- A service never imports another service's private files.
- `world/game.gd` is the base-game boundary: one public file of static accessors with explicit
  arguments, no bound state and no mod preload. A service, a shared module and the settings layer
  read it like the scene, so a base-game member is reached through one typed function, never at the
  call site.
- A service never receives another service through a host dictionary. A host passes scene
  handles, plain values and callbacks only. Service-to-service dependencies are visible as a
  preload of the other facade.
- A shared pure module never reads `SETTINGS`, `Time`, `FileAccess` or a domain service. The
  base-game accessors in `world/game.gd` are the game boundary, so a shared module may read them
  like the scene.
- A shared store may read `settings`; that is the one infrastructure exception.
- Only `main`, `runtime` and `api` may call arbitrary service facades.
- If two services seem to need each other, the boundary is wrong or the orchestrator must mediate
  with plain values. A cycle is not an acceptable design.
- No per-frame allocation in a facade or read model. Reuse context and event objects. The
  profiler's block must not show added per-frame cost.

`settings` is infrastructure: it may import shared pure modules and the base-game accessors in
`world/game.gd`, which are the game boundary rather than a service. The one existing upward edge,
`settings -> registry/service.gd` (provider defaults and per-mare rows), is recorded in
`architecture/exceptions.json` and must shrink. Do not add a second upward edge, and do not treat
the recorded row as a pattern.

## The service contract

A service has one job and one authority. "One mod aspect" is not enough: two aspects can share
state, and one aspect can hide two state machines. The test is:

- one piece of mutable state has exactly one owner;
- one service has one reason to change;
- every other consumer reads or writes through the facade.

The service owns its setup and release: allocation, subscriptions, nodes and saved state. The
orchestrator owns **when** and **in what order** setup and release run. `act/exit.gd:run()` is the
one act exit body, entered only through the exit's own routes and the consent stop; a service
exposes idempotent begin/end or reset methods and never starts a second teardown sequence.

### Facade

`<service>/api.gd` is the preferred public entry and `<service>/service.gd` is the legacy name.
The facade is the only file another part of the mod may import. It contains the public contract,
state ownership and the scene adaptation for that service. A service that needs an internal base
class may extend it, but the public API must remain readable in the facade; prefer delegation over
inherited public methods.

A world-list service extends `shared/service.gd` for the four no-op lifecycle hooks. A per-pony or
per-act service is constructed inside the runtime and has no world broadcast, so it does not extend
the base. The cross-mod `api.gd` is frozen, is parented without joining the list, and carries no
hooks.

The facade header names the service, its contract, its scope and the import rule:

```gdscript
## Service: <id>
## Contract: docs/<id>.md
## Scope: world | per-pony | per-act | pure
## Import: <id>/api.gd only
```

### Typing

The boundary is strongly typed:

- every public parameter and return has an explicit type;
- stable data uses a typed `RefCounted` class, an inner class or an enum, not a bare dictionary;
- arrays use `Array[Type]`;
- scene handles use the narrowest engine type (`Node3D`, `Skeleton3D`, `Camera3D`, ...), not
  `Variant`;
- `Variant` is reserved for engine APIs that cannot be typed, JSON at the persistence edge and
  documented event payloads;
- `Dictionary` and `Callable` bags are migration debt, not the default. A host callback is named
  and documented, and preferably part of a typed host object.

The typing debt is tracked in `architecture/typing_debt.json`. The checker fails when the debt
grows. Removing a method from the debt is part of the change that types it.

### State and data

- A service owns its mutable state. Another service reads it through the facade, not through
  fields.
- Derived values belong to the service that derives them. A read model is a copy for consumers,
  not a second authority.
- Save data lives under the owning service's `Mods.state("unfplap")` key or the settings file.
  One writer per key. The service doc names the storage and the owner.
- Per-character profile blocks are owned by the domain service that understands them. The
  settings service owns the file and the generic block storage, not the consent, preference,
  participation or pose semantics. In this pass the settings service still stores those blocks
  until a characters service owns them.
- A per-act service may read its typed settings handles at use, hot or cold. A bulk block uses
  `SETTINGS.act_snapshot(group)`; there are no default copies, no private settings module and no
  per-service cache. If a hot path regresses, improve the settings service.

### No reach-ins

A service never reads another service's private fields and never calls its `_` helpers. It does
not do this through `get("_...")`, `call("_...")`, a host dictionary, a raw scene node or a
preloaded private file. The same applies to `runtime.gd` and `main.gd` from a service. A service
also never reaches another through a static `instance` handle: the entry passes the facade or the
caller takes it as a host parameter.

## Service layout

```text
<service>/
  api.gd           # public contract (preferred)
  service.gd       # legacy public contract
  internal.gd      # private implementation
  ui.gd            # private scene adapter, if the service owns a panel
  data.json        # private data
```

```text
shared/
  preferences.gd   # pure profile math and schema
  act_history.gd   # shared store
  act_facts.gd     # typed act read model
  pose_specs.gd    # pose capability table (pure)
  pose_view.gd     # pose read model
  ...
```

`poses/pose_state.gd` is the pure state and edge module. `poses/pose_spec.gd`,
`poses/transition_spec.gd` and `poses/registry.gd` are private to the pose service; the capability
table is `shared/pose_specs.gd`, the read model the session refreshes is `shared/pose_view.gd`, and
the authored edges are the data documents under `poses/transitions/*.json`. The session owns the
live pose state and the `act_body`; the runtime owns the tick/fan-out order and the one teardown. A
pose change retargets through `pose_changed(view)` and never calls a pose-scope or act-exit step.

Every service has exactly one facade. A second entry point is either merged into the facade or
moved to `shared/` with its own contract. There are no root-level forwarding shims: a shim would
give the mod two entry points and hide the real dependency.

## Lifetimes

| Scope | Constructed by | Begun / ended by | Examples |
|---|---|---|---|
| World | the entry's service list, at boot | the list order on world enter, close and exit | eligibility, memory, negotiation, hud, offer, input, initiation, anatomy, body_change, the world adapters, stool, stock smack, debug actions; the cross-mod `api.gd` is parented but takes no broadcast |
| Per-pony | `ponies` through the entry's one factory | pony despawn or world close | the runtime itself |
| Per-pony handle | the runtime, once per pony | the runtime ledger or the negotiation hold | pose, camera, hands, kiss, face, history, afterglow, scene hold, rest |
| Pure / read model | its owner | no teardown | preferences math, act view, the log sink and the profiler |

A service doc declares its scope, constructor, begin/end and idempotency. A service that outlives
one act must reset every act-owned value in its begin/reset path; a service that is created per
act must release every node and subscription it created.

The pose service is the worked example of the scope split: the session owns the pose-scope
teardown steps (`leave_pose_start()`, `leave_pose_body()` and the final `release_pose()`), while
`act/exit.gd:run()` owns the act exit and calls them through `free_pose()` between the
cross-system resets, then restores the pony bones through `context.pose.restore_bones()`. A pose
transition calls none of the
pose-scope steps or the act exit; it retargets through `pose_changed(view)` and leaves the
teardown to `free_pose()`. The order is `docs/poses.md`.

## Composition

### `main.gd`

`main.gd` is the mod entry and composition root. It owns four things:

- **the primitives**: the settings load, the two debug switch binds and the loader lookup;
- **the ordered service list**: `_build_services()` constructs every long-running service in one
  literal list, one construction line and one `bind()` per service. The list order is the
  construction order and the broadcast order, so a consumer is built after the services it reads.
  The entry assigns only the registry's composition handles and the cross-mod factory; a service
  owns its own fields and rules;
- **the broadcasts and the frame order**: `_on_world`, `_on_player` and the release walk the list;
  `_process` keeps the frame order visible;
- **the one teardown**: `_exit_tree` runs the same `_release()` a world close runs, then
  `_shutdown()`, which stops the registry and calls every service's `shutdown()` in reverse list
  order. `WORLD` is bound before the first service and unbound after the last.

It also keeps the `Mods` hooks, the group join, the three-line `prompt_note` forward, the settings
page injection and the one runtime factory. It does not own domain rules, debug action
implementations, a service's private state or a second exit path. `scripts/architecture.py --check`
refuses string dispatch in the entry: no `.call(`, `.get("` or `.set("`, and no `action_*` handler.

### `runtime.gd`

`runtime.gd` is the per-pony Node host. One Node exists for every non-player pony, idle and in an
act, and it:

- owns existence, parenting, the reparent across a body swap, the two engine-frame forwards and the
  world-close release. `_init()` builds the bundle once; `_ready()` binds the pony, the face and the
  anatomy; `_physics_process` is one `act.tick()`, `_process` one `act.render()`, and `_exit_tree()`
  releases the kiss forelegs, the stool, the tail tuck, the aftercare, the anatomy act and the face;
- exposes exactly `act` (the `ActSession`), `scene` (the `SceneGate`), `start` and `presentation`
  (the two ports), `pony`, `live_id()`, `attach_to_body()`, `adopt_body()` and the engine
  callbacks. `NODE_SURFACE` and `NODE_PROPERTIES`
  in `scripts/architecture.py` compare both directions, so a new public member and a stale row both
  fail;
- hands all composition to `act/build.gd`, a plain struct builder with typed fields and
  `bind_pony()`. It constructs the session, the modules, the typed hosts, the context and every
  callback once per pony. `runtime.gd` stores the `Bundle`; it keeps no per-system field alias and
  no private host callback;
- keeps the act state in `act/session.gd`: the one `state` writer `_set_state()`, the timers, the
  clock, the act values and the two frame forwards. `act/settings.gd` owns the act's settings
  snapshot and its live apply; `act/view.gd` composes the values the owners read; the ledgers
  (`act/start.gd`, `act/exit.gd`) own the ordered start and the one teardown; the modules own the
  schedule, the presentation, the input protocol, the consent meter and the swap seams.

Every host callback names its owner rather than a runtime method: act state and act values are
session accessors, a system value is that service's method, node and scene operations are
`act/host.gd`, logging is `shared/log.gd`, and anatomy reads are `anatomy/act_bridge.gd`.

It implements no system's rules and owns no system's mutable state: no scoring, pose math, camera
shots, hand/kiss/wing behaviour, body-change detection or provider policy, raw input decoding,
audio creation, aftercare nodes, HUD strings, eligibility or gate rules, debug formatting,
settings declarations or per-frame settings reads. `scripts/architecture.py --check` enforces the
shape: one `state` writer in `act/session.gd`, the fixed Node surface, no raw input, no settings
read in `runtime.gd`, no child node, plus the one exit, the start recipe's order, the pose ledger's
three callers, the fan-out order and the one resume. File size is reported as a smell, never a
cap. `owner_of()` treats every `act/**` file as the runtime's own module: it may preload a service,
and a service that preloads it fails as a host import.

The state flow, start, suspend/resume, tick and exit orders are documented in `docs/runtime.md`.
The tick order is load-bearing: `act/tick.gd:tick` (physics), its `render` (the render-time pose
write), the start sequence and the impact fan-out keep their call order until a change deliberately
moves one call.

### `api.gd`

`api.gd` is the only stable contract another mod may call. It returns plain data, never a runtime,
service handle or scene node. Service facades are internal APIs and may change freely. The
cross-mod shape is `docs/api.md`.

## Shared layer

`shared/` has three kinds, and a module says which one it is:

| Kind | Contract |
|---|---|
| Pure | Deterministic data or math. No Node, Time, FileAccess, `SETTINGS` or service. |
| Store | Persisted shared data. No scene and no lifecycle. May read `settings`; never a domain service. |
| Read model | Scene-free mutable values refreshed by its owner. Not a service and not a second source of truth. |

A module that needs a service, a Node or a lifecycle is not shared: it belongs to a service. A
module that needs settings rules but is otherwise pure receives those rules as arguments; it does
not become a shared store just to read `SETTINGS`.

`shared/act_history.gd` is the current shared store: eligibility, initiation, history and memory read the
same stored rows, and making it history-private would create
`eligibility -> history -> memory -> eligibility`. A shared store is the deliberate cycle break.
It owns its `Mods.state` key and its pure policy; it does not own scene behavior.

`shared/prompt_text.gd` is the one prompt implementation: it builds and validates the part/slot
graph and renders every prompt from `settings/prompts.json` (`docs/prompts.md`). A service that
sends a prompt names a shipped node and passes the slot values; a second placeholder parser or
prompt formatter is a review failure.

## Host boundary

A host is the object that gives a service its live values: a runtime for its act services, and the
entry only for the callbacks it wires at construction. The relationship is not a service
dependency and is not drawn as one.

The entry is not a locator. Nothing outside `main.gd` and `tests/` names it, so a consumer that
needs another service preloads that facade, a consumer that needs the live scene reads `WORLD`
(`world/api.gd`), the one scene read facade the entry binds, a consumer that needs a base-game
member reads `GAME` (`world/game.gd`), and a consumer that needs a write takes a named callback. A
host passes:

- scene handles the service is allowed to touch;
- plain values and typed read models;
- named callbacks for writes the service cannot do itself.

A host does not pass another service facade, a service locator dictionary or a callback that
reaches into a private field. If the service needs another service, it preloads that facade. If
that creates a cycle, the orchestrator passes plain data instead.

The service doc has a `## Host boundary` table naming each callback and its type. A missing host
callback is a no-op only where the service doc says so.

## Settings and debug ownership

The settings service owns the catalog and the framework:

- every declaration and its typed `Setting` handle in `settings/service.gd`;
- the three shipped documents — `settings/settings.json` (the declared settings),
  `settings/characters.json` (the global `default` profile, the per-mare profiles and the
  placement rows) and `settings/prompts.json` (the prompt text) — the two player files
  (`settings.json` and `characters.json`), the merge, clamping, section state, migration and save;
- the declaration-drawn settings panel and the tab injection in `settings/ui.gd`.

The default value of every declared setting lives in `settings/settings.json`; the declaration
supplies the kind, path, label, help, bounds and options. The `default` profile, the per-mare
profiles and the per-mare placement rows live in `settings/characters.json`; they resolve at read
time, so the player files store only the differences the player made. The shipped documents are
read-only content: a cross-mod provider layer applies above the shipped profile and placement and
below the player's differences (`docs/api.md`), and `scripts/settings_sync.py` is the only path
that copies a local value back into the shipped data.

The catalog is the settings service's **internal public API**. A service that needs a setting:

- contributes it with a literal declaration in `settings/service.gd`, in the owner/tab/group block
  where the row belongs;
- documents the setting's behavior in its own contract;
- depends on `settings/service.gd` and reads or writes the typed handle.

There is no per-service `settings.gd` module and no registration manifest. A consumer may read
another service's contributed handle because the catalog is public inside the mod. It is not part
of the cross-mod API: other mods still only see `api.gd`.

Panel order is declaration order. A per-act service may read its typed handles at use; a bulk
block uses `SETTINGS.act_snapshot(group)` and receives it again on `apply_live_settings()`. There is one writer to the player files: the
settings service. The per-mare profiles live in the player's `characters.json`, split out of the
settings document by that writer, until a characters service owns them.

The debug service owns the console, the panel, the action registry (`debug/service.gd`), the
action behavior (`debug/actions.gd`, the one node the entry adds), the action wheel
(`debug/wheel.gd`), the stock bed cuddle helper (`debug/bed.gd`), the pony-preparation helper
(`debug/pony.gd`), the Idle Life deep-stretch bridge (`debug/idle_stretch.gd`), the skeleton
overlay and the action-button builder (`debug/ui.gd`). The settings panel passes the debug action
builder into its Debug block. The entry only adds the actions node and binds its named reads of the
live act; the wheel gate and the persisted skeleton flag's sync run in that node. The registry
resolves the node through its `target` and its public functions are typed.

`docs/settings.md` owns the framework and the declaration contract. Each service doc owns its
settings, feature flags and debug actions. `docs/debug.md` owns the console, panel, overlay and
lab keys.

## Documentation

| Doc | Owns |
|---|---|
| `ARCHITECTURE.md` | concepts, layers, service definition, lifecycle, dependency policy, enforcement, migration policy |
| `docs/README.md` | the service/shared/orchestrator index, the doc template and the verification matrix |
| `docs/<service>.md` | the service contract: responsibility and boundary, decisions, invariants, ordering constraints, traps and extension points |
| `AGENTS.md` | agent rules, the path router and the workflow pointers |
| `WORKFLOW.md` | commands, labs and release flow |
| `README.md` | the player-facing summary; human-owned, do not edit |
| `docs/api.md` | the stable cross-mod API |
| `docs/prompts.md` | the prompt document, its graph and the one renderer |
| `assets/README.md`, `CREDITS.md` | asset-pack and external credits |

Rules:

- The service doc is the single source of truth for its responsibility and boundary.
- No other doc restates its decisions, invariants or extension points.
- A cross-system fact is a link, not a copy.
- `AGENTS.md` does not duplicate the service index; it links to `docs/README.md`.
- Root-level docs are for players and agents. Service contracts live under `docs/`.

### Service doc shape

```markdown
# <Service>

## Scope
## Ownership
## Data ownership
## <behaviour sections>
## Settings
## Verification / lab
```

A service may use `## Ownership` in place of `## Scope`. `## Data ownership` is the save-schema and
single-writer map; `## Settings` names settings and behaviour without copying defaults or bounds.
Every other section is a behaviour section named after its responsibility. The preload graph is the
dependency record; do not mirror it in a table. `## Host boundary` has a callback table where the
service has a host.

## Enforcement

The architecture gate is `scripts/architecture.py --check`, run from `scripts/test_all.sh`:

- discovers services from `*/service.gd` and `*/api.gd` outside `shared/`, preferring `api.gd`,
  and treats the rest of the directory as private;
- checks that every service the entry adds extends `shared/service.gd`; the HUD is the allowed
  `CanvasLayer` and must define all four hooks;
- rejects a static `instance` in a shipped service; world facades are injected or taken as host
  parameters;
- scans `preload`, `extends "res://..."` and `load()` for mod paths and base-game paths;
- requires every script dependency in every `.gd` to be a top-level `const … := preload(...)` in the
  contiguous block directly below the doc header; a preload after another declaration or inside a
  class or function fails, and so does a `load()` of a script path or a const that resolves to one,
  while a runtime `load(path)` for an asset stays allowed;
- rejects a base-game import outside `world/game.gd`; every other module reads the game through
  `GAME`;
- rejects a cross-module preload-const reach-through; enums, nested classes and plain constants
  stay reachable, and `GAME.X` is the one allowed re-export;
- rejects a private import, a service -> `runtime`/`main`/`api` import, a shared -> service import
  and a service cycle;
- rejects any shipped file outside `main.gd` that names the entry (`main.<member>`, `var main`, a
  `main.gd` preload or `main` as an argument); `tests/` is exempt;
- checks that every service has a facade, doc, test directory and index row;
- checks that every service doc has an ownership heading and names its facade, and that every
  facade's public type carries a `##` note;
- reads `architecture/exceptions.json` and fails on a new violation or a stale exception;
- reads `architecture/typing_debt.json` and fails when the weak-signature debt grows;
- reads `architecture/duck_typing.json` and fails when a shipped file outside the accessor
  allowlist adds a `.call("name")`, `.set("name")` or `runtime.get("name")` site. The
  `integrations/` rows are a deferred exception — that service talks to other mods, not the base
  game — and not a pattern; the `runtime.get` rows are the handle reads the typed accessors are
  replacing.

`scripts/architecture.py --graph` prints the service graph for review; it is not checked in.
`scripts/architecture.py --write-debt` is the deliberate way to update the debt after a service
is typed.

`scripts/architecture.py --check` owns the static invariants: one teardown body in
`act/exit.gd:run()` entered only through the exit's routes and the consent stop, with
`act/session.gd:force_stop()` as the one-line delegate, the start recipe's order, the pose ledger's
order and its three exact callers, the `act/tick.gd` fan-out order and the pose-before-facts write
in its physics frame, the thin-runtime shape (one `state` writer in `act/session.gd`, the fixed
`NODE_SURFACE`/`NODE_PROPERTIES`, no raw input, no settings read in `runtime.gd`, no runtime child
node), the
act-exit ban under `poses/`, the shell `errexit` prelude, the release files and the manifest, one
settings declaration
module, and the test-file rules in `docs/tests.md`. The typed act view boundary is a review rule:
presentation modules read `shared/act_facts.gd`, not the runtime node.

Suites are not services: their layout, isolation, discovery and runner are `docs/tests.md`.

The full gate remains:

```bash
scripts/architecture.py --check
scripts/check.sh --all
scripts/test_all.sh
```

Manual labs are required for behavior phases: `./lab.sh`, `./lab-stress.sh`, `./lab-vr.sh`. A
change that touches the tick, pose, camera or per-act service composition also needs one `perf`
block in an act and one outside it before and after, with **Enable debug** + **Print perf logs**.

## Adding a service

1. Pick a stable snake_case id and one responsibility.
2. Create `<id>/api.gd` with the facade header, a narrow typed API and the ownership fields.
3. Keep every helper under `<id>/`; move a genuinely shared pure module to `shared/` instead of
   making the facade a namespace.
4. Add `docs/<id>.md` with the ownership heading and the behaviour sections; the index row owns the
   contract and test router.
5. Add `tests/<id>/`; keep pure-core tests separate from facade/API tests.
6. Contribute the service's settings as declarations in `settings/service.gd` and its debug
   actions to `debug/service.gd`; document the behavior in the service contract.
7. Add the service and its facade to `docs/README.md`.
8. Extend `shared/service.gd` (or `body_change/source.gd` for a provider), override the lifecycle
   hooks it needs, and add one line to the entry's `_build_services()` list.
9. Run the architecture checker and the full gate.
10. Add an exception only if the boundary cannot be fixed in the same change. An exception needs
    an owner, a reason and an expiry; a stale exception fails.

## Migration policy

The mod is in a staged migration from flat facades to the layout above. The rules are already the
target; the exception and typing-debt files record the temporary gaps.

- Move one service per commit. Do not mix a layout move with a behavior change.
- Use `git mv`; move or remove the matching `.uid` files.
- Retarget every preload and test, and fix the doc sentence the move makes false, in the same
  commit.
- Do not add a root shim to keep an old path alive. The old path is deleted.
- New files must be tracked before a build; the pack manifest reads `git ls-files`.
- `architecture/exceptions.json` may only shrink. Removing an exception is part of the commit
  that fixes the boundary.
- `architecture/typing_debt.json` may only shrink between deliberate `--write-debt` updates.
- A behavior phase updates the service's tests and contract doc in the same commit.

## Related

- `docs/README.md` — the service index, the doc template and the verification matrix.
- `AGENTS.md` — the path router and the project-wide rules.
- `WORKFLOW.md` — commands, labs and release flow.
- `docs/runtime.md` — the act state machine, start, tick and teardown order.
- `docs/api.md` — the stable cross-mod contract.
