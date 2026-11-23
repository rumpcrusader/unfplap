# Ponies

The one registry of per-pony runtimes. `ponies/service.gd` (RefCounted, world scope, static state)
owns the attach and prepare hooks a new body passes through, the adoption of the act owner's
pending swap and the prompt note the game reads. It is the only owner of "which body has which
runtime", so no consumer reads the entry for it.

## Scope

This contract covers:

- the pony-to-runtime registry and the `runtime_for(pony)` lookup;
- the attach and prepare hooks, including the late prepare a mod calls once its node exists;
- the adoption of the act owner's pending body swap and the duplicate-runtime guard;
- the prompt note the game's `pony_prompt_notes` group reads;
- the live and installed character lists the Characters selector shows;
- the per-runtime live-settings pass and the teardown.

It does not cover the act itself (`docs/runtime.md`), the attach-time anatomy and tail work
(`docs/anatomy.md`), the eligibility rule (`docs/eligibility.md`), the body-change sources
(`docs/body_change.md`) or the hint and start the idle scan leads to (`docs/offer.md`).

## Ownership

| Member | What it owns |
|---|---|
| `attach(pony)` | the one spawn hook: the player-body refusal, the prepare pass, the pending-swap adoption, then one runtime built by the entry's factory |
| `prepare_late(pony)` | the prepare pass again for a body a mod completed after its first spawn; never creates a runtime |
| `runtime_for(pony)` | the registry entry, or the runtime node the body carries |
| `live_ponies()` | the bodies that hold a runtime, for the debug block; a body the act owner's swap is taking away is not listed |
| `adopt_pending_body(pony)` | the prepare and adoption the act handover asks for after the adoption grace |
| `apply_live_settings()` | the live settings pass over every runtime, not only the act's |
| `prompt_note(id)` | the live act/afterglow note and the cycle line for one stable id |
| `live_character_ids()` / `installed_character_ids()` | the off-roster mares the Characters tab lists |
| `cone_target(eye)` | the nearest standing mare in the rear fan, from the game's live mare array |
| `act_target(pony)` / `relationship_ok(pony)` | the eligibility capability and the act gate's Base clearance relationship row |
| `close_world()` | the process exit: the act owner's live act ends through its one exit |
| `shutdown()` | process exit: close the act, stop and free every runtime, drop the bindings |

The service preloads no runtime: the entry owns that file and hands over `factory`, a `(Node pony)
-> Node` callable that builds the runtime with its body and host set. Every call into a runtime is
dynamic on a `Node`, so the registry only needs the methods the act contract publishes.

## Attach order

`attach(pony)` runs in one order, and the order is the contract:

1. the player's own AnonPony and any node with a `rig` are refused, because they are Anon's body,
   not a mare's;
2. the prepare pass: `body_change.notify_body_ready()` (the provider's form is fitted and mirrored
   before anything binds), then `anatomy.present()` once with the provider's stored form, then
   `estrus.track()`, the stock smack layer's `pony_ready()`, `eligibility.warm()` (the identity
   record, read once since the era moved) and `act_gate.warm()` (the clearance relationship row,
   read once at attach so the first offer does not pay it). Anatomy owns the identity gate inside
   `present`, so the roster makes no separate capability or tail decision. Every hook is
   idempotent, which is what makes `prepare_late()` safe;
3. the pending swap is offered the body, which is the only way a suspended act keeps its runtime;
4. an already registered body is left alone; otherwise the factory builds the runtime, the runtime
   enters the body's tree, the registry maps the body and one `runtime attached <name> id=<id>`
   line is logged;
5. the body's `tree_exiting` drops the registry entry, so a freed body never leaves a stale map.

A body with no factory, no runtime or no services attached is a quiet no-op: a suite can bind any
subset.

## The body swap

The act handover records the pending swap on the act owner (`docs/act_owner.md`) before the
runtime leaves the old body, so the new body's spawn finds the record instead of creating a second
act owner. The registry still maps the old body; `live_ponies()` and the character list skip it
while the record names it as the old one.

`attach()` adopts when the change's typed source `claims_body()` the newcomer or the newcomer's
stable id (`shared/pony_id.gd`) matches the record. A body with another id is attached normally and
leaves the record alone. The adoption order is: detach a duplicate runtime's anatomy controller and
stop and free that duplicate (a race can only mean the suspended act is the owner), drop the old
body's entry, map the new body, bind anatomy to it, reparent the runtime under it, clear the
owner's record and hand the body to `runtime.adopt_body()`. The adoption never resumes the act; the
act handover owns the one resume (`docs/runtime.md`).

`adopt_pending_body(pony)` is the same prepare-and-adopt path for a body whose spawn hook never
reached `attach()`: a provider may clear its changing state before the new body appears, so the act
handover waits out the grace and then asks here.

## The act frame

The live act, its side effects and the serial belong to the act owner (`docs/act_owner.md`). The
registry reads that owner for the pending swap, for the departing body the swap names, and for the
live runtime at a settings edit and at the process exit. A static `act_owner` field on the registry
is the entry's composition handle until the roster becomes a World service. The stable id and
display name are `shared/pony_identity.gd`'s, read by the act directly.

## The standing cone

`cone_target(eye)` answers the idle hint's standing target. It walks the game's own `mares` array
without copying it, rejects by squared ground distance to the approximate rump anchor, then checks
her standing posture and the rear fan (`shared/rump_cone.gd`), collecting the passing candidates in
distance order. It asks `act_target()` down that order and returns the first one that passes; a
nearer non-target is skipped, not the answer. The act key still runs its own gate.
`relationship_ok(pony)` is the mirrored facade for the act gate's Base clearance relationship row;
the offer fan reads it through this service, so no consumer preloads the gate.

## Characters

`live_character_ids()` lists the adult mares that hold a runtime and pass
`eligible(pony, Target.CHARACTER)`, drops the base roster from them, appends the mares an active
installed-profile source lists even while she is away, and sorts by display name. The base roster
stays the base roster; a provider owns its own installation gate.

## Prompt note

The game asks the mod for one dialogue note per mare through the `pony_prompt_notes` group, whose
members must be Nodes. The entry keeps the group join and forwards three lines; the note itself is
built here: the runtime whose stable id matches the query answers with its `prompt_note()`, and its
`cycle_note()` is appended when the cycle has one. A runtime that has not read its id yet is
matched through its body's identity (`shared/pony_id.gd:of()`).

## Host boundary

The entry's `bind(anatomy_service, body_change_service, stock_smack_service, eligibility_service,
gate_service, estrus_service, api_service)` sets these once, before the first hook, from its
`_build_world()` root:

| Bound by the entry's service list | Purpose |
|---|---|
| `factory` | `(Node pony) -> Node`, the entry's one runtime construction |
| `anatomy` | `present(pony, form)` for the prepare and `withdraw(pony)` for a leaving body |
| `body_change` | `notify_body_ready(pony)` and `installed_character_ids()` |
| `stock_smack` | `pony_ready(pony)` for the prepare |
| `eligibility` | `eligible(pony, Target.CHARACTER)` for the Characters tab, `Target.ACT` behind `act_target()`, and `warm(pony)` |
| `act_gate` | `relationship_ok(pony)` behind `relationship_ok()` and `warm(pony)` |
| `estrus` | `track(pony)` and `untrack(pony)` for the idle cycle schedule |
| `api` | the cross-mod facade an integration registers its mare through |

`bind_settings()` joins the settings change notification and `shutdown()` leaves it: a settings edit
re-runs `apply_live_settings()` over every runtime and the act a pending body swap has taken out of
the registry. `act_target(pony)` is the act-target rule the offer and the debug block read through
the preloaded `PONIES` facade. The `act_owner` field is the entry's composition handle, set beside
the others rather than through `bind()`.

A missing service reads as "no prepare", "no character list" and "no side effect", so a suite
binds only what it tests.

The service binds no state of its own: the registry, the record and the act owner are rebound by
the entry and cleared by `shutdown()`.

## Settings

None. The service reads no setting; the live pass hands each runtime its own snapshot.

## Controls

None. The act key belongs to `docs/input.md` and the idle scan to `docs/offer.md`.

## Debug

The Debug block builds its own `Host` from the `PONIES` facade and the act owner in
`debug/actions.gd` and reads `active()`, `runtime_for()` and `live_ponies()` through them; the
entry binds none of them. See `docs/debug.md`.
