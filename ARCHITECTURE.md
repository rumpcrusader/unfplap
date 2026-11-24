# Architecture

`unfplap` is one entry, one per-pony host and a set of services composed in two roots. This file
owns the concepts and the rules they share: what a service is, which class it belongs to, how it
reaches another, when it is created and destroyed, and what the gate guarantees. It does not
document a service. The index is `docs/README.md`; each service's contract is
`docs/<service>.md`.

## The shape of the mod

| Part | Role |
|---|---|
| Entry | `main.gd`: the primitives, the two build roots, the `Mods` hooks, the broadcasts and the one teardown. |
| Per-pony host | `runtime.gd`: one per non-player pony, idle and in an act; existence, parenting, the two engine-frame forwards, the body-swap reparent and the world-close release. |
| Service | One authority over mutable state behind one facade. |
| Service base | `shared/service.gd`: the four lifecycle hooks as no-ops. |
| Facade | `<service>/api.gd`, or `<service>/service.gd`; the only file another part of the mod imports. |
| Service internals | Private modules under `<service>/`; nothing outside imports them. |
| Shared module | Pure data or math, a store, or a read model under `shared/`; no lifecycle. |
| Scene read facade | `world/api.gd`: the live scene reads, bound by the entry. It answers where and what, never whether. |
| Game accessors | `<service>/game.gd` for the four game-layer services: every base-game read and write, one typed function each. |
| Record | A typed value object one caller fills and another reads: `WorldHandles`, `ACT_CONTEXT`. |
| Port | A service-owned abstract `RefCounted` the runtime implements once per pony, for example `shared/start_port.gd`. |
| Cross-mod API | `api.gd` and `docs/api.md`: the one stable contract another mod may call. |

There are thirty-six services: three Process (`settings`, `debug`, `registry`), twenty World and
thirteen Pony. `act/` and `vr/` are Other. The two orchestrators are not services: they compose,
and they own order rather than another service's rules.

## Classes and ownership

Every object belongs to exactly one class:

| Class | Instances | Constructed by | Reached by |
|---|---|---|---|
| **Process** | one per process | static, read by preload; the API node is parented by `_build_process()` | preload the static |
| **World** | one per process | `main.gd:_build_world()` | typed injection |
| **Pony** | one per attached body | `runtime.gd:_compose()` | typed injection |
| **Other** | per owner | its owner | passed as a value |

Class is about ownership, not feature area: a per-act handle is Other even when it belongs to a
World service's feature. `Other` is derived for everything without a facade; it is not a scope
value.

**Static state follows the class.** A Process facade may be static. A World or Pony facade is an
instance: it holds no `static var`, so it cannot become a registry a caller reaches without being
handed one. `world/api.gd` is the one static read facade. A `WORLD` alias whose value is a
`preload(...)` names that file; the settings section name is a plain string, not an alias.

Lifetime follows the class: a Process value lives as long as the process, a World service is built
once and only its state binds and resets per world, a Pony service exists with the runtime that
composed it, and an Other value lives with its owner.

Only a facade declares itself, with three fields directly under `extends`:

```gdscript
## Service: <id>
## Scope: process | world | pony
## Contract: docs/<id>.md
```

A non-facade carries no declaration; its owner and scope are derived from its path, and a module may
keep a plain purpose sentence. There is no `Import:` field: the top preload block is the dependency
manifest and the graph gate reads it.

A `world` or `pony` facade is a `Node`, `CanvasLayer` or `shared/service.gd`; a `process` facade may
be `RefCounted`. `world/api.gd` is the one World facade that is not a Node, and the gate names that
path rather than a header field.

## Layers and the game boundary

```text
main.gd / runtime.gd          entry and orchestration
api.gd                        cross-mod facade
world/api.gd                  scene read facade
<service>/game.gd             base-game accessors (game layer)
<service>/api.gd              service facades (preferred)
<service>/service.gd          service facade (the name when api.gd is absent)
<service>/**                  private service implementation
shared/**                     pure modules, stores, read models
res://world/..., res://player/...   game and engine
```

| Layer | May import |
|---|---|
| Entry / orchestrator | anything |
| Cross-mod API | service facades, shared modules |
| Scene read facade | `res://world/`, `res://player/`, shared modules and `world/game.gd` |
| Base-game accessor | base-game modules and shared value types |
| `settings` (game layer) | its own `game.gd`, shared pure modules and the `registry` store |
| Domain service | `settings`, shared modules, other service facades |
| Shared store | `settings`, shared pure |
| Read model | shared pure |
| Shared pure | shared pure only |

Rules:

- No service preloads `runtime.gd`, `main.gd` or `api.gd`. Nothing outside `main.gd` and `tests/`
  names the entry at all: no `main.<member>`, no `var main`, no `main.gd` preload, no `main`
  argument.
- No service imports another service's private files.
- A service receives another service as a typed `wire` parameter or a preload of its facade, never
  through a host dictionary, a locator or a static handle. A host passes scene handles, plain
  values, read models and named callbacks only.
- A shared pure module never reads `SETTINGS`, `Time`, `FileAccess`, a domain service or a game
  accessor; its values are arguments. A shared store may read `settings`; that is the one service
  read a shared module makes.
- Only `main`, `runtime` and `api` may call a facade they do not specifically depend on; every
  other file preloads the facade it uses.
- A mutual pair is legal only through two-phase wiring. `initiation ↔ negotiation` is the one
  documented pair and a future merge candidate; a new pair is a boundary defect.
- No per-frame allocation in a facade or a read model: reuse context and event objects.

The game layer is the set of services allowed to touch the base game: `world`, `settings`, `debug`
and `hud`. Each owns exactly one `game.gd`, its only base-game boundary and, besides `main.gd`, the
only place the `/root/Settings` and `/root/Mods` autoload paths may appear. Only that service's own
files import it; `shared/` never does. A member reads the game for its own job only: `settings` owns
every setting, file and settings-page read; `world` owns the scene, rig, bed, relationship and
mod-registry reads; `debug` owns the debug panel's menu chrome; `hud` owns the caption node's
fields. `settings` and `world` are peers and do not import each other.

## The service contract

A service has one job and one authority. "One mod aspect" is not enough: two aspects can share
state, and one aspect can hide two state machines. One piece of mutable state has exactly one
owner; every consumer reads or writes through the facade; the service owns its setup and release,
while the orchestrator owns when and in what order those run.

Every service has exactly one facade. A second entry point is merged into it or moved to `shared/`
with its own contract; a forwarding shim is refused, because it would give the mod two entry points
and hide the real dependency.

The facade contains the public contract, the state ownership and the scene adaptation. A service
that needs an internal base class may extend it, but the public API stays readable in the facade;
prefer delegation over inherited public methods.

The boundary is strongly typed:

- every public parameter and return has an explicit type;
- stable data uses a typed `RefCounted`, an inner class or an enum, not a bare dictionary;
- arrays use `Array[Type]`, and scene handles use the narrowest engine type;
- `Variant` is reserved for engine APIs that cannot be typed, JSON at the persistence edge and
  documented event payloads;
- `Dictionary` and `Callable` bags are migration debt, not the default; a host callback is named,
  documented and preferably part of a typed host object.

The typing debt is tracked in `architecture/typing_debt.json`; the gate fails when it grows, and
typing a member removes its row in the same change.

State rules:

- A service owns its mutable state; another service reads it through the facade, not its fields.
- A derived value belongs to the service that derives it. A read model is a copy for consumers, not
  a second authority.
- Save data lives under the owning service's `Mods.state("unfplap")` key or the settings file, with
  one writer per key. The service doc names the storage and the owner.
- Per-character blocks are owned by the domain service that understands them. The settings service
  owns the file and the generic block storage, not the consent, preference, participation or pose
  semantics.
- A per-act service reads its typed settings handles at use, hot or cold. A bulk block uses
  `SETTINGS.act_snapshot(group)`; there are no default copies, no private settings module and no
  per-service cache. If a hot path regresses, improve the settings service.

No reach-ins: a service never reads another service's private fields, calls its `_` helpers or
reaches it through a raw node, a preloaded private file, `get("_...")`, `call("_...")` or a static
handle. The same applies to `runtime.gd` and `main.gd` from a service.

## How services reach each other

A service reaches another through typed injection or a preload of its facade; a host never hands it
a service. Each facade declares at most one `wire()`,
called once by its scope's root, with explicit typed parameters: no tree access, no scene read, no
`WORLD` or `SETTINGS` read inside it. A required peer is asserted; an optional peer is declared
`= null` and not asserted, because suites pass it as null on purpose. `wire()` sets and `shutdown()`
clears; no other member writes a field `wire()` fills, so a service can never be half-rewired and
the root never nulls a service's field. A rebind on a body or state change is a separately named
member that takes a host, a body or a value, never a peer.

Two records carry the values that are not peers:

- **`WorldHandles`** is the Pony→World record: typed fields for the World services a Pony service
  reads, built once after the last World service exists and before wiring, and held by the entry,
  the runtime and `ACT_CONTEXT`. It is not a locator: a field is read, never looked up, and a Pony
  service that needs a World peer takes it as a `wire` parameter instead of reading the record.
- **`ACT_CONTEXT`** is the act modules' typed collaborator record, filled once by `_compose`. The
  act modules read it instead of the runtime node.

`WORLD` is the static read facade, `world/api.gd`. It answers typed zeroes between worlds, so a late
reader is safe rather than absent; it is for the scene, never for a service lookup.

Groups are assertions, not discovery: `unfplap_api`/`unfplap_api_v1` for the API, `unfplap_pony`
for the runtimes, and `unfplap_world`/`unfplap_pony_service` for the two scope checks. A service
never reaches another by group or node name.

## Composition

Each instance scope has one root: `main.gd:_build_world()` for the World services and
`runtime.gd:_compose()` for the Pony ones. `_build_process()` parents the cross-mod API; the Process
services are static and are read by preload, never constructed.

The sequence is the spine: **construct → build the record → wire → name → attach.** Because wiring
is two-phase, construction order stops mattering; a service may read its peers as soon as it enters
the tree. A mid-game enable repeats the same calls, then binds the world and the player.

The root is pure: it may construct, `wire`, name, `add_child`, join a scope group, `connect` and
register a source, plus its own composition helpers. It reads no `WORLD`, `SETTINGS`, `LOG` or
`PERF`, runs no behaviour and reads no scene. A peer's zero-argument read passed straight into
`wire()` is composition, not behaviour; setup that looks behavioural belongs in the service's
`_ready()`.

A statically attached child can still miss its scope group, so each root cross-checks the tree once
behind `LOG.enabled`: the entry reports every direct child outside `unfplap_world` (the API node is
the named exception) and the runtime every child outside `unfplap_pony_service`. Each returns its
offender count, so a player's release run stays quiet.

## Lifecycle

**Creation.**

- Process: at boot, by preload.
- World: in `_build_world()`, at entry `_ready` or on the mid-game enable path.
- Pony: `Mods.on_node` hands the body to `ponies.attach(pony)`, which refuses the player body,
  prepares it (body change, anatomy, estrus, stock smack, eligibility and gate warm), offers a
  pending swap to `act_owner`, then creates the runtime through the entry's factory and parents it.
  The runtime composes its services and act modules in `_init` and binds body, face and anatomy in
  `_ready`.

**Binding.** `world_ready` calls every World service's `on_world(host)` in list order;
`player_ready` calls every `on_player(body)`; `world_closed` calls every `on_world_closed()` and
unbinds `WORLD` last, because reset code still reads the scene. A body swap records the suspended
act in `act_owner`, reparents the live runtime, adopts the new body and rebinds it; the runtime and
its Pony services survive.

**Destruction.**

- Body exit: the body's `tree_exiting` drops it from the roster, the runtime leaves the tree and
  `_exit_tree()` releases in the order `docs/runtime.md` owns, and the engine frees the Pony service
  children.
- Act end: `act/exit.gd:run()` is the one teardown, entered only through the exit's own routes and
  the consent stop; no second exit sequence exists.
- World close: state resets only; a World service is never freed.
- Mod switch-off or quit: `_release()` runs every `on_world_closed()` and then unbinds `WORLD`;
  `_shutdown()` stops the roster first (force-stop and free the runtimes while the World services
  they read are alive), then calls every World `shutdown()` in reverse list order.

## The orchestrators

`main.gd` has four jobs and nothing else: the primitives (the settings load, the two debug switch
binds and the loader lookup); the two build roots; the broadcasts and the frame loop in a visible
order; the one teardown, `_release()` then `_shutdown()`. It also keeps the `Mods` hooks, the group
join, the prompt-note forward, the settings-page injection and the one runtime factory. It owns no
domain rule, no debug action implementation and no service's private state. The gate refuses string
dispatch in the entry.

`runtime.gd` is the per-pony host. It owns existence, parenting, the reparent across a body swap,
the two engine-frame forwards and the world-close release; it exposes exactly the `act`, `scene`,
`start`, `presentation` and `pony` handles, `live_id()`, `attach_to_body()` and `adopt_body()`; and
it holds no system's mutable state. `docs/runtime.md` owns the state flow, the start, the
suspend/resume, the tick and the exit order.

`api.gd` is the only stable contract another mod may call. It returns plain data, never a runtime, a
service handle or a scene node; its shape is `docs/api.md`.

## Shared layer

`shared/` has three kinds:

| Kind | Contract |
|---|---|
| Pure | Deterministic data or math. No Node, `Time`, `FileAccess`, `SETTINGS` or service. |
| Store | Persisted shared data. No scene and no lifecycle. May read `settings`; never a domain service. |
| Read model | Scene-free mutable values refreshed by its owner. Not a service and not a second source of truth. |

A module's kind is a classification, not a header field; a module that needs a service, a Node or a
lifecycle belongs to a service. A module that needs settings rules but is otherwise pure receives
them as arguments.

`shared/act_history.gd` is the shared store: eligibility, initiation, history and memory read the
same rows, and making it history-private would create
`eligibility -> history -> memory -> eligibility`. A shared store is the deliberate cycle break; it
owns its `Mods.state` key and its pure policy, not scene behaviour.

`shared/prompt_text.gd` is the one prompt implementation: it builds and validates the part/slot
graph and renders every prompt from `settings/prompts.json`. A service names a shipped node and
passes the slot values; a second placeholder parser or prompt formatter is a review failure.

## Enforcement

The static gate is `scripts/check.sh --static`, run from `scripts/test.sh`. It discovers the
services and enforces the class model, the two composition roots, the game boundary, the preload
manifest, single-place wiring, the fixed runtime shape and the act's load-bearing orders; every rule
has both fixture directions in the gate's self-test. `docs/quality.md` owns the complete roster, the
invariants, the ledger files, the maintenance modes and the commands.

One rule is architecture's own: `shared/log.gd`, `shared/perf.gd`, `api.gd`, `docs/api.md` and
`tests/test_api.gd` change only with the user's explicit approval.

## Documentation

| Doc | Owns |
|---|---|
| `ARCHITECTURE.md` | this file: the service model, classes, layers, composition, lifecycle and the gate's guarantees |
| `docs/README.md` | the service/shared/orchestrator index, the doc template and the verification matrix |
| `docs/<service>.md` | one service's responsibility and boundary, decisions, invariants, ordering constraints, traps and extension points |
| `docs/quality.md` | the static gate roster, the lint and comment rules, the shell rules and the pack report |
| `docs/tests.md` | the suite layout, isolation, discovery and runner |
| `docs/api.md` | the stable cross-mod API |
| `AGENTS.md` | the agent rules and the path router |
| `WORKFLOW.md` | the commands, the labs and the release flow |
| `README.md` | the player-facing summary; human-owned, do not edit |

- The service doc is the single source of truth for its responsibility and boundary.
- No other doc restates its decisions, invariants or extension points; a cross-system fact is a
  link, not a copy.
- A doc states the current state. An obsolete claim is removed, never kept as history.
- `AGENTS.md` links to the index instead of duplicating it.

## Adding a service

1. Pick a stable snake_case id and one responsibility.
2. Create the facade — `<id>/api.gd`, or `<id>/service.gd` when the id already uses that name —
   with the header, a narrow typed API and the ownership fields.
3. Keep every helper under `<id>/`; move a genuinely shared pure module to `shared/`. A game-layer
   member also owns `<id>/game.gd`, whose typed accessors are its only base-game reads.
4. Add `docs/<id>.md` and its one row in `docs/README.md`; the row owns the contract and test
   router.
5. Add `tests/<id>/`, keeping pure-core tests separate from facade tests.
6. Contribute the service's settings as declarations in `settings/service.gd` and its debug actions
   to `debug/service.gd`; document the behaviour in the service contract.
7. A World service extends `shared/service.gd` (or `body_change/source.gd` for a provider),
   overrides the lifecycle hooks it needs and adds one line to `_build_world()`; a Pony service
   extends `Node` and is attached by `_compose()`.
8. Run `scripts/check.sh` and `scripts/test.sh`.
9. Add an exception only if the boundary cannot be fixed in the same change. An exception needs an
   owner, a reason and an expiry; a stale exception fails.

## Change discipline

- `architecture/exceptions.json` may only shrink; a new violation and a stale exception both fail.
- `architecture/typing_debt.json` may only shrink between deliberate updates.
- A boundary change lands with its tests and the doc sentences it makes false, in one commit.
- No root shim and no second entry point: the old path is deleted.
- New files are tracked before a build; the pack manifest reads `git ls-files`.
