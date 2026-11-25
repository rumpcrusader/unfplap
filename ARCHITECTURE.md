# Architecture

`unfplap` is one entry, one per-pony host and a set of services composed in two roots. This file
owns the concepts and the principles they share: what a service is, how it reaches another, when it
is created and destroyed, and what the gate guarantees. It does not document a service: a service's
doc is `docs/<id>.md`, named after its directory.

## Design principles

- **One job, one authority.** A service has one responsibility and owns the mutable state behind it.
  "One mod aspect" is not enough: two aspects can share state, and one aspect can hide two state
  machines. A derived value belongs to the service that derives it; a read model is a copy for
  consumers, not a second authority.
- **One facade.** Every service has exactly one entry point, `<id>/api.gd`. A second entry point is
  merged into it or moved to `shared/` with its own contract; a forwarding shim is refused, because
  it would give the mod two entry points and hide the real dependency.
- **The contract is typed.** Every public parameter and return has an explicit type. Stable data
  uses a typed `RefCounted`, an inner class or an enum, not a bare dictionary; arrays use
  `Array[Type]`; scene handles use the narrowest engine type. `Variant` is reserved for engine APIs
  that cannot be typed, JSON at the persistence edge and documented event payloads.
- **No reach-ins.** A service never reads another service's private fields, calls its `_` helpers or
  reaches it through a raw node, a preloaded private file, `get("_...")`, `call("_...")` or a static
  handle. The same applies to `runtime.gd` and `main.gd` from a service.
- **One game boundary.** A base-game import lives only in a game-layer service's `game.gd`; only
  that service's own files import it. Every other file reads the game through a facade, and the
  `/root/Settings` and `/root/Mods` literals obey the same rule.
- **Static state follows ownership.** A Process facade may be static. A World or Pony facade is an
  instance: it holds no `static var`, so it cannot become a registry a caller reaches without being
  handed one. `world/api.gd` is the one static read facade.
- **The preload block is the dependency manifest.** Every script dependency is a top-level
  `const … := preload(...)` directly below the doc header, and a file uses only the preload consts
  it declares. A late or nested preload and a `load()` of a script are defects.
- **Reuse, don't allocate per frame.** No per-frame allocation in a facade or a read model; context
  and event objects are reused.

## The parts

- **Entry** — `main.gd`: the primitives, the two build roots, the `Mods` hooks, the broadcasts and
  the one teardown.
- **Orchestrator** — a file that composes and owns order, never another service's rules.
- **Per-pony host** — `runtime.gd`: one per non-player pony, idle and in an act.
- **Service** — one authority over mutable state behind one facade.
- **Service base** — `shared/service.gd`: the four lifecycle hooks as no-ops.
- **Facade** — `<id>/api.gd`: the only file another part of the mod imports.
- **Service internals** — private modules under `<id>/`; nothing outside imports them.
- **Shared module** — pure data or math, a store, or a read model under `shared/`; no lifecycle.
- **Scene read facade** — `world/api.gd`: the live scene reads, bound by the entry. It answers where
  and what, never whether.
- **Game layer** — `<id>/game.gd` for a game-layer service: every base-game read and write, one
  typed function each.
- **Record** — a typed value object one caller fills and another reads.
- **Port** — a service-owned abstract `RefCounted` the runtime implements once per pony.
- **Cross-mod surface** — `api.gd` and `docs/api.md`: the one stable contract another mod may call.

## Naming

The directory is the name. A service's directory `<id>/` is its id, its facade is always
`<id>/api.gd`, and its doc is `docs/<id>.md`. There is no index, no path router and no reference
table; `docs/api.md` is the frozen cross-mod contract, and the project docs (`tests`, `quality`,
`vr`) are named after their subject. A new service ships its doc with its directory.

## Declarations

Only a facade declares itself, with one field directly under `extends`:

```gdscript
## Scope: process | world | pony
```

A non-facade carries no declaration (the two frozen headers excepted); its owner and scope are
derived from its path, and a module may keep a plain purpose sentence. There is no `Import:` field: the top preload block is the dependency
manifest and the graph gate reads it. A `world` or `pony` facade is a `Node`, `CanvasLayer` or
`shared/service.gd`; a `process` facade may be `RefCounted`. `world/api.gd` is the one World facade
that is not a Node, and the gate names that path rather than a header field.

## The service contract

The facade contains the public contract, the state ownership and the scene adaptation. A service
that needs an internal base class may extend it, but the public API stays readable in the facade;
prefer delegation over inherited public methods.

- A service owns its mutable state; another service reads it through the facade, not its fields.
- Save data lives under the owning service's `Mods.state("unfplap")` key or the settings file, with
  one writer per key.
- Per-character blocks are owned by the domain service that understands them. The settings service
  owns the file and the generic block storage, not the consent, preference, participation or pose
  semantics.
- A per-act service reads its typed settings handles at use, hot or cold. There is no bulk
  act snapshot and no per-act cache: feature flags, presentation values and act values are
  read where they are used. The act's reaction, camera and dialogue configs are built once at
  the act start from the same typed handles because those services hold state. There are no
  default copies, no private settings module and no per-service cache. If a hot path
  regresses, improve the settings service.

**No sentinel defaults.** A value the caller must supply has no initialiser: an empty id or a
placeholder time that can reach storage or a comparison is a defect in the type, not a case in the
reader. A default exists only where the default is the truth — `false`, an empty set, a zero count.
GDScript zero-fills an uninitialised field, so "required" means a constructor parameter, and
everything else is supplied by the type's one construction site.

**A constructor exists to make an invalid object unrepresentable** — an identity that must exist, an
enum that must be one of its values, a pair that is meaningless apart. A constructor that mirrors
every field is not documentation: the fields carry their own names, a wide record is completed at
its single construction site, and a test that sets every source value to a distinct one is the
check.

## How services reach each other

A service reaches another through typed injection or a preload of its facade; a host never hands it
a service. Each facade declares at most one `wire()`, called once by its scope's root, with explicit
typed parameters: no tree access, no scene read, no `WORLD` or `SETTINGS` read inside it. A required
peer is asserted; an optional peer is declared `= null` and not asserted, because suites pass it as
null on purpose. `wire()` sets and `shutdown()` clears; no other member writes a field `wire()` fills,
so a service can never be half-rewired and the root never nulls a service's field. A rebind on a body
or state change is a separately named member that takes a host, a body or a value, never a peer.

Two records carry the values that are not peers:

- **`WorldHandles`** is the Pony→World record: typed fields for the World services a Pony service
  reads, built once after the last World service exists and before wiring, and held by the entry,
  the runtime and the act context. It is not a locator: a field is read, never looked up, and a Pony
  service that needs a World peer takes it as a `wire` parameter instead of reading the record.
- **The act context** is the act modules' typed collaborator record, filled once by the runtime's
  composition. The act modules read it instead of the runtime node.

`WORLD` is the static read facade, `world/api.gd`. It answers typed zeroes between worlds, so a late
reader is safe rather than absent; it is for the scene, never for a service lookup.

Groups are assertions, not discovery: `unfplap_api`/`unfplap_api_v1` for the API, `unfplap_pony`
for the runtimes, and `unfplap_world`/`unfplap_pony_service` for the two scope checks. A service
never reaches another by group or node name.

## Composition and lifecycle

Each instance scope has one root: the entry's world build for the World services and the runtime's
composition for the Pony ones. The entry parents the cross-mod API; the Process services are static
and are read by preload, never constructed.

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

**Creation.** Process values exist at boot by preload. World services are built at entry `_ready` or
on the mid-game enable path. A pony body arrives through `Mods.on_node`, is prepared, and gets a
runtime that composes its services and act modules in `_init` and binds body, face and anatomy in
`_ready`.

**Binding.** The world-ready broadcast calls every World service's `on_world(host)` in list order;
the player-ready broadcast calls every `on_player(body)`; the world-close broadcast calls every
`on_world_closed()` and unbinds `WORLD` last, because reset code still reads the scene. A body swap
records the suspended act, reparents the live runtime, adopts the new body and rebinds it; the
runtime and its Pony services survive.

**Destruction.** A body exit drops it from the roster, the runtime leaves the tree and releases its
children. An act ends only through `act/exit.gd:run()`, entered through the exit's own routes and
the consent stop; no second exit sequence exists. A world close resets state only, never frees a
World service. Mod switch-off or quit stops the roster first, then calls every World `shutdown()` in
reverse list order.

## The orchestrators

`main.gd` has four jobs and nothing else: the primitives (the settings load, the two debug switch
binds and the loader lookup); the two build roots; the broadcasts and the frame loop in a visible
order; the one teardown. It also keeps the `Mods` hooks, the group join, the prompt-note forward, the
settings-page injection and the one runtime factory. It owns no domain rule, no debug action
implementation and no service's private state. The gate refuses string dispatch in the entry.

`runtime.gd` is the per-pony host: one for each non-player pony, idle or in an act. It lives under
the body and moves with it across a swap; both engine frames pass through it; it releases what
outlives an act on world close; and it holds no system's mutable state. It exposes the typed act,
scene, start, presentation and pony handles, the live id, and the attach and adopt hooks. Its act
modules live in `act/` and its VR act handle in `vr/`; they may preload services, and a service that
preloads them is a host import, not an edge.

`api.gd` is the only stable contract another mod may call. It returns plain data, never a runtime, a
service handle or a scene node; its shape is `docs/api.md`.

## The act view

Presentation modules read the typed act view instead of the runtime node. It is the value handoff
from the orchestrator to the scene adapters.

## Shared layer

`shared/` has three kinds, and a module's kind is a classification, not a header field:

- **Pure** — deterministic data or math. No Node, `Time`, `FileAccess`, `SETTINGS` or service.
- **Store** — persisted shared data. No scene and no lifecycle. May read `settings`; never a domain
  service.
- **Read model** — scene-free mutable values refreshed by its owner. Not a service and not a second
  source of truth.

A module that needs a service, a Node or a lifecycle belongs to a service. A module that needs
settings rules but is otherwise pure receives them as arguments.

`shared/act_history.gd` is the shared store: eligibility, initiation, history and memory read the
same rows, and making it history-private would create `eligibility -> history -> memory ->
eligibility`. A shared store is the deliberate cycle break; it owns its `Mods.state` key and its
pure policy, not scene behaviour.

`shared/prompt_text.gd` is the one prompt implementation: it builds and validates the part/slot
graph and renders every prompt from `settings/prompts.json`. A service names a shipped node and
passes the slot values; a second placeholder parser or prompt formatter is a review failure.

## Enforcement

The static gate is `scripts/check.sh --static`, run from `scripts/test.sh`. It discovers the
services and enforces the ownership model, the two composition roots, the game boundary, the
preload manifest, single-place wiring, the fixed runtime shape and the act's load-bearing orders;
every rule has both fixture directions in the gate's self-test. The checker is the rule roster;
`docs/quality.md` owns the parse, lint and comment gates, the documentation gate, the shell rules
and the pack report.

One rule is architecture's own: `shared/log.gd`, `shared/perf.gd`, `api.gd`, `docs/api.md` and
`tests/test_api.gd` change only with the user's explicit approval.

## Documentation

- The path is the name: `<id>/` is the service id and its doc is `docs/<id>.md`. There is no index
  and no path router; a new service adds its doc, nothing else.
- A doc owns its responsibility, its functional meaning (policy, behaviour and outcomes) and a
  high-level map of its internals as roles. It never carries a file or member inventory, a formula
  or step-by-step how, a setting row list, a test list, a count or a signature dump. Concept names,
  setting names and control names stay where behaviour needs them.
- The service doc is the single source of truth for its responsibility and boundary. No other doc
  restates its decisions, invariants or extension points; a cross-system fact is a link, not a copy.
- A doc states the current state. An obsolete claim is removed, never kept as history.
- `docs/api.md` is the only cross-mod API contract. `README.md` is human-owned; `WORKFLOW.md` owns
  the commands, the labs and the release flow.

## Adding a service

1. Pick a stable snake_case id and one responsibility.
2. Create the facade `<id>/api.gd` with the `## Scope:` field, a narrow typed API and the state
   ownership.
3. Keep every helper under `<id>/`; move a genuinely shared pure module to `shared/`. A game-layer
   member also owns `<id>/game.gd`, whose typed accessors are its only base-game reads.
4. Add `docs/<id>.md`; nothing else.
5. Add its suites under `tests/`, keeping pure-core tests separate from facade tests.
6. Contribute the service's settings as declarations in `settings/api.gd` and its debug actions
   to `debug/api.gd`; document the behaviour in the service doc.
7. A World service extends `shared/service.gd` (or the body-change source base for a provider),
   overrides the lifecycle hooks it needs and adds one line to the entry's world build; a Pony
   service extends `Node` and is attached by the runtime's composition.
8. Run `scripts/check.sh` and `scripts/test.sh`.
9. Add an exception only if the boundary cannot be fixed in the same change. An exception needs an
   owner, a reason and an expiry; a stale exception fails.

## Change discipline

- `architecture/exceptions.json` may only shrink; a new violation and a stale exception both fail.
- `architecture/typing_debt.json` may only shrink between deliberate updates.
- A boundary change lands with its tests and the doc sentences it makes false, in one commit.
- No root shim and no second entry point: the old path is deleted.
- New files are tracked before a build; the pack manifest reads `git ls-files`.
