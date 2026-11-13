# Architecture

This is the conceptual contract for how `unfplap` is put together. It defines what a service is,
what it may depend on, where state lives, how lifecycle is owned and how the rules are checked.

It does not document individual services. The service index is `docs/README.md`; the technical
contract for each service is `docs/<service>.md`. A service doc is the single source of truth for
that service's purpose, API, state, settings, controls, debug actions, dependencies and tests.

## What the mod is made of

| Part | Role |
|---|---|
| Entry | `main.gd`: the `Mods` hooks, world/player lifecycle, service construction, settings-tab injection and the top-level services. |
| Orchestrator | `runtime.gd`: one per pony. The act state machine, tick order, start sequence, the single teardown ledger and the composition of act services. |
| Service | An isolated unit that owns one authority over mutable state and exposes it through one facade. |
| Service internals | Private modules under `<service>/`. Nothing outside the service imports them. |
| Shared pure module | Deterministic data or math in `shared/`. No scene, no lifecycle, no service dependency. |
| Shared store | Persisted shared data in `shared/`. No scene, no lifecycle; may read `settings`, never a domain service. |
| Read model | A scene-free mutable value object refreshed by its owner, for example the act view. |
| Cross-mod API | `api.gd` and `docs/api.md`: the only stable contract another mod may call. |
| Host | A scene or orchestrator object a service receives values and callbacks from. A host is not a service. |

`main.gd` and `runtime.gd` are not services. They compose services and own order. They may hold
per-world or per-pony orchestration state, but they do not implement another service's rules.

## Layers and allowed imports

```text
main.gd / runtime.gd          entry and orchestration
api.gd                        cross-mod facade
<service>/service.gd          service facades
<service>/**                  private service implementation
shared/**                     pure modules, shared stores, read models
res://world/..., res://player/...   game and engine
```

| Layer | May import |
|---|---|
| Entry / orchestrator | anything |
| Cross-mod API | service facades, shared modules |
| Infrastructure service (`settings`) | shared pure modules |
| Domain service | `settings`, shared modules, other service facades |
| Shared store | `settings`, shared pure |
| Read model | shared pure |
| Shared pure | shared pure only |

Rules:

- A service never preloads `runtime.gd`, `main.gd` or `api.gd`.
- A service never imports another service's private files.
- A service never receives another service through a host dictionary. A host passes scene
  handles, plain values and callbacks only. Service-to-service dependencies are visible as a
  preload of the other facade.
- A shared pure module never reads `SETTINGS`, `Time`, `FileAccess` or a service.
- A shared store may read `settings`; that is the one infrastructure exception.
- Only `main`, `runtime` and `api` may call arbitrary service facades.
- If two services seem to need each other, the boundary is wrong or the orchestrator must mediate
  with plain values. A cycle is not an acceptable design.
- No per-frame allocation in a facade or read model. Reuse context and event objects. The perf
  probe must not show added per-frame cost.

## The service contract

A service has one job and one authority. "One mod aspect" is not enough: two aspects can share
state, and one aspect can hide two state machines. The test is:

- one piece of mutable state has exactly one owner;
- one service has one reason to change;
- every other consumer reads or writes through the facade.

The service owns its setup and release: allocation, subscriptions, nodes and saved state. The
orchestrator owns **when** and **in what order** setup and release run. `runtime._end_session` is
the only act exit path; a service exposes idempotent begin/end or reset methods and never starts a
second teardown sequence.

### Facade

`<service>/service.gd` is the only file another part of the mod may import. It contains the public
contract, state ownership and the scene adaptation for that service. A service that needs an
internal base class may extend it, but the public API must remain readable in `service.gd`; prefer
delegation over inherited public methods.

The facade header names the service, its contract, its scope and the import rule:

```gdscript
## Service: <id>
## Contract: docs/<id>.md
## Scope: world | per-pony | per-act | pure
## Import: <id>/service.gd only
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
  participation or pose semantics.
- A per-act service receives its settings values once per act and receives them again on
  `apply_live_settings()`. New code does not read `Settings` every frame.

### No reach-ins

A service never reads another service's private fields and never calls its `_` helpers. It does
not do this through `get("_...")`, `call("_...")`, a host dictionary, a raw scene node or a
preloaded private file. The same applies to `runtime.gd` and `main.gd` from a service.

## Service layout

```text
<service>/
  service.gd       # public contract
  internal.gd      # private implementation
  settings.gd      # private declarations owned by this service
  ui.gd            # private scene adapter, if the service owns a panel
  data.json        # private data
```

```text
shared/
  preferences.gd   # pure profile math and schema
  act_history.gd   # shared store
  act_view.gd      # read model
  ...
```

Every service has exactly one facade. A second entry point is either merged into the facade or
moved to `shared/` with its own contract. There are no root-level forwarding shims: a shim would
give the mod two entry points and hide the real dependency.

## Lifetimes

| Scope | Constructed by | Begun / ended by | Examples |
|---|---|---|---|
| World | `main` on ready or world entry | `main` on world close | settings, registry, anatomy, stool, initiation, input, debug |
| Per-pony | `main` when a runtime attaches | pony despawn or world close | the runtime itself |
| Per-act handle | the runtime, usually once per pony and reset per act | the runtime start/teardown ledger | pose, camera, hands, kiss, face, history, afterglow, scene hold, rest |
| Pure / read model | its owner | no teardown | preferences math, act view, perf probe |

A service doc declares its scope, constructor, begin/end and idempotency. A service that outlives
one act must reset every act-owned value in its begin/reset path; a service that is created per
act must release every node and subscription it created.

## Composition

### `main.gd`

`main.gd` is the mod entry and composition root:

- receives the `Mods` hooks and the world/player lifecycle;
- constructs world services and exposes them to the game and the API;
- creates per-pony runtimes and attaches them to ponies;
- injects the settings page and the Characters form through the owning service;
- ticks world services and the active runtime;
- does not own domain rules, debug action implementations or a service's private state.

### `runtime.gd`

`runtime.gd` is the per-pony act orchestrator:

- owns the state machine (`IDLE`, `POSING_IN`, `ACTIVE`, `CLIMAX`, `AFTERGLOW`, `RESTORE`);
- owns the start sequence, the tick order and the one teardown ledger;
- creates or binds the act services and passes them typed contexts;
- forwards input commands and publishes a typed act view;
- does not own scoring math, pose math, settings declarations, debug actions or a service's
  mutable state.

The state flow, start order and teardown order are documented in `docs/runtime.md`. The tick
order is load-bearing: `_physics_process`, `_process` (render-time pose write), the start
sequence and the impact fan-out keep their call order until a change deliberately moves one call.

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

## Host boundary

A host is the object that gives a service its scene and live values: usually `main` or `runtime`.
The relationship is not a service dependency and is not drawn as one.

A host passes:

- scene handles the service is allowed to touch;
- plain values and typed read models;
- named callbacks for writes the service cannot do itself.

A host does not pass another service facade, a service locator dictionary or a callback that
reaches into a private field. If the service needs another service, it preloads that facade. If
that creates a cycle, the orchestrator passes plain data instead.

The service doc has a `## Host boundary` table naming each callback and its type. A missing host
callback is a no-op only where the service doc says so.

## Settings and debug ownership

The settings service owns the framework:

- the declaration registry and typed `Setting` classes;
- `settings.json`, defaults, clamping, section state, migration and save;
- the declaration-drawn settings panel and the tab injection.

Each owning service provides:

- its declaration module (`<service>/settings.gd`), with keys, labels, bounds and debug flags;
- typed handles or a typed config object for its own values;
- its per-character profile block and migration hook;
- its debug action descriptors registered with the debug service;
- the settings and debug section of its contract doc.

`main` registers every service's declarations in explicit order before the file is loaded and the
panel is built. Static initialization order is not a registration mechanism. A per-act service
receives a typed config snapshot at act start; `apply_live_settings()` re-pushes it. There is one
writer to `settings.json`: the settings service.

The debug service owns the console, the panel, the skeleton overlay and the action registry. It
does not own the action behavior. A service registers an action with a typed callable bound to its
own facade; `main.gd` has no `action_*` methods.

`docs/settings.md` owns the framework and the declaration contract. Each service doc owns its
settings, feature flags and debug actions. `docs/debug.md` owns the console, panel, overlay and
lab keys.

## Documentation

| Doc | Owns |
|---|---|
| `ARCHITECTURE.md` | concepts, layers, service definition, lifecycle, dependency policy, enforcement, migration policy |
| `docs/README.md` | the service/shared/orchestrator index, the doc template and the verification matrix |
| `docs/<service>.md` | the service contract: scope, ownership, API, data, settings, controls, dependencies, tests |
| `AGENTS.md` | agent rules, the required reading table and the workflow pointers |
| `WORKFLOW.md` | commands, labs and release flow |
| `README.md` | the player-facing summary, CONTROLS and FEATURES |
| `docs/api.md` | the stable cross-mod API |
| `assets/README.md`, `AUDIO_CREDITS.md` | asset-pack and audio credits |

Rules:

- The service doc is the single source of truth for that service.
- No other doc restates its API, state, settings, controls, tests or debug actions.
- A cross-system fact is a link, not a copy.
- `AGENTS.md` does not duplicate the service index; it links to `docs/README.md`.
- Root-level docs are for players and agents. Service contracts live under `docs/`.

### Service doc shape

```markdown
# <Service>

## Scope
## Ownership
## Internal API
## Data ownership
## Lifecycle
## Settings
## Controls and debug
## Dependencies
## Tests
## Verification / lab
## Related docs
```

`## Dependencies` has a normative `### Uses` table and an optional `### Used by` table:

```markdown
### Uses

| Kind | Target | Entry point | Purpose |
|---|---|---|---|
| service | memory | `memory/service.gd` | cue facts and witness pass |
| shared | preferences | `shared/preferences.gd` | tolerance tier |
| store | act_history | `shared/act_history.gd` | stored history rows |
| read model | act_view | `shared/act_view.gd` | act state for presentation |
| host | runtime | `bind(HistoryHost)` | clock, idle state, scene callbacks |
| game | pony_director | `res://world/ai/...` | speak one line |
```

`Kind` is one of `service`, `shared`, `store`, `read model`, `host`, `game`. The checker parses
this table and compares it with the preload graph. `### Used by` is optional; the checker derives
the reverse graph and fails if a hand-written table disagrees.

`## Lifecycle` names the scope, constructor, begin/end and idempotency. `## Host boundary` has a
callback table where the service has a host.

## Enforcement

The architecture gate is `scripts/architecture.py --check`, run from `scripts/test_all.sh`:

- discovers services from `*/service.gd` and treats the rest of the directory as private;
- scans `preload`, `extends "res://..."` and `load()` for mod paths;
- compares the source graph with the `### Uses` tables in the service docs;
- rejects a private import, a service -> `runtime`/`main`/`api` import, a shared -> service import
  and a service cycle;
- checks that every service has a facade, doc, test directory and index row;
- checks that every service doc has the required sections and that no other doc names its private
  files;
- reads `architecture/exceptions.json` and fails on a new violation or a stale exception;
- reads `architecture/typing_debt.json` and fails when the weak-signature debt grows.

`scripts/architecture.py --graph` prints the service graph for review; it is not checked in.
`scripts/architecture.py --write-debt` is the deliberate way to update the debt after a service
is typed.

`tests/test_source_hygiene.gd` keeps the behavioral invariants the architecture checker cannot see:
one `_end_session`, settings widgets only in the owning UI files, no removed shims, no host
preloads, no private runtime reach-ins in presentation modules.

The full gate remains:

```bash
scripts/architecture.py --check
scripts/check.sh --all
scripts/test_all.sh
```

Manual labs are required for behavior phases: `./lab.sh`, `./lab-stress.sh`, `./lab-vr.sh`. A
change that touches the tick, pose, camera or per-act service composition also needs the perf
probe before and after, with **Enable debug** + **Print perf logs**.

## Adding a service

1. Pick a stable snake_case id and one responsibility.
2. Create `<id>/service.gd` with the facade header, a narrow typed API and the ownership fields.
3. Keep every helper under `<id>/`; move a genuinely shared pure module to `shared/` instead of
   making the facade a namespace.
4. Add `docs/<id>.md` with the standard sections, `## Lifecycle` and `## Dependencies`.
5. Add `tests/<id>/`; keep pure-core tests separate from facade/API tests.
6. Declare the service's settings and debug actions in its own directory and register them from
   `main` in explicit order.
7. Add the service and its facade to `docs/README.md`.
8. Run the architecture checker and the full gate.
9. Add an exception only if the boundary cannot be fixed in the same change. An exception needs
   an owner, a reason and an expiry; a stale exception fails.

## Migration policy

The mod is in a staged migration from flat facades to the layout above. The rules are already the
target; the exception and typing-debt files record the temporary gaps.

- Move one service per commit. Do not mix a layout move with a behavior change.
- Use `git mv`; move or remove the matching `.uid` files.
- Retarget every preload, test, doc and index row in the same commit.
- Do not add a root shim to keep an old path alive. The old path is deleted.
- New files must be tracked before a build; the pack manifest reads `git ls-files`.
- `architecture/exceptions.json` may only shrink. Removing an exception is part of the commit
  that fixes the boundary.
- `architecture/typing_debt.json` may only shrink between deliberate `--write-debt` updates.
- A behavior phase updates the owning service doc and its tests in the same commit.

## Related

- `docs/README.md` — the service index, the doc template and the verification matrix.
- `AGENTS.md` — the required reading table and the project-wide rules.
- `WORKFLOW.md` — commands, labs and release flow.
- `docs/runtime.md` — the act state machine, start, tick and teardown order.
- `docs/api.md` — the stable cross-mod contract.
