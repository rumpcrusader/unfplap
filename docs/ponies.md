# Ponies

The one registry of per-pony runtimes. `ponies/service.gd` (RefCounted, world scope, static state)
owns the attach and prepare hooks a new body passes through, the typed pending body swap and its
adoption, the live act pointer, the serial allocator and the prompt note the game reads. It is the
only owner of "which body has which runtime", so no consumer reads the entry for it.

## Scope

This contract covers:

- the pony-to-runtime registry and the `runtime_for(pony)` lookup;
- the attach and prepare hooks, including the late prepare a mod calls once its node exists;
- the typed pending body swap, the duplicate-runtime guard and the adoption path;
- the live act pointer, the stock smack handoff and the idle offer reset on an act start;
- the serial allocator and the `unfplap.serial` state key;
- the prompt note the game's `pony_prompt_notes` group reads;
- the live and installed character lists the Characters selector shows;
- the per-runtime live-settings pass, the idle perf header counts and the teardown.

It does not cover the act itself (`docs/runtime.md`), the attach-time anatomy and tail work
(`docs/anatomy.md`), the eligibility rule (`docs/eligibility.md`), the body-change sources
(`docs/body_change.md`) or the hint and start the idle scan leads to (`docs/offer.md`).

## Ownership

| Member | What it owns |
|---|---|
| `attach(pony)` | the one spawn hook: the player-body refusal, the prepare pass, the pending-swap adoption, then one runtime built by the entry's factory |
| `prepare_late(pony)` | the prepare pass again for a body a mod completed after its first spawn; never creates a runtime |
| `runtime_for(pony)` | the registry entry, or the runtime node the body carries |
| `live_ponies()` | the bodies that hold a runtime, for the settings tail pass and the debug block |
| `set_active(runtime)` / `clear_active(runtime)` / `active()` / `act_running()` | the one live act and its two side effects: the idle offer is dropped and the stock smack layer opens and closes its act |
| `begin_body_swap(runtime, old_pony, id, change)` | the act's one pending swap, and the old body's registry entry going with it |
| `clear_body_swap(runtime)` / `body_swap_pending()` | the swap's one end, scoped to its runtime |
| `adopt_pending_body(pony)` | the prepare and adoption the act handover asks for after the adoption grace |
| `apply_live_settings()` | the live settings pass over every runtime, not only the act's |
| `prompt_note(id)` | the live act/afterglow note and the cycle line for one stable id |
| `live_character_ids()` / `installed_character_ids()` | the off-roster mares the Characters tab lists |
| `allocate_serial()` | the `unfplap.serial` key and the last value issued in this process |
| `reset()` | a world enter: the pending swap belonged to the world that is gone |
| `close_world()` | a world close: the act ends through its one exit and the swap goes |
| `shutdown()` | process exit: close the act, stop and free every runtime, drop the bindings |

The service preloads no runtime: the entry owns that file and hands over `factory`, a `(Node pony)
-> Node` callable that builds the runtime with its body and host set. Every call into a runtime is
dynamic on a `Node`, so the registry only needs the methods the act contract publishes.

## Attach order

`attach(pony)` runs in one order, and the order is the contract:

1. the player's own AnonPony and any node with a `rig` are refused, because they are Anon's body,
   not a mare's;
2. the prepare pass: `body_change.notify_body_ready()` (the provider's form is fitted and mirrored
   before anything binds), then `anatomy.tail_ready()`, then the stock smack layer's
   `pony_ready()`. Every hook is idempotent, which is what makes `prepare_late()` safe;
3. the pending swap is offered the body, which is the only way a suspended act keeps its runtime;
4. an already registered body is left alone; otherwise the factory builds the runtime, anatomy
   binds its controller, the runtime enters the body's tree, the registry maps the body and one
   `runtime attached <name> id=<id>` line is logged;
5. the body's `tree_exiting` drops the registry entry, so a freed body never leaves a stale map.

A body with no factory, no runtime or no services attached is a quiet no-op: a suite can bind any
subset.

## The body swap

The act handover records the pending swap through `begin_body_swap()` before the runtime leaves the
old body, so the new body's spawn finds the record instead of creating a second act owner. The record is
`{runtime, old_pony, id, change}`; the old body's entry is dropped there and then.

`attach()` adopts when the change's typed source `claims_body()` the newcomer or the newcomer's
stable id (`shared/pony_id.gd`) matches the record. A body with another id is attached normally and
leaves the record alone. The adoption order is: detach a duplicate runtime's anatomy controller and
stop and free that duplicate (a race can only mean the suspended act is the owner), drop the old
body's entry, map the new body, bind anatomy to it, reparent the runtime under it, clear the record
and hand the body to `runtime.adopt_body()`. The adoption never resumes the act; the act handover
owns the one resume (`docs/runtime.md`).

`adopt_pending_body(pony)` is the same prepare-and-adopt path for a body whose spawn hook never
reached `attach()`: a provider may clear its changing state before the new body appears, so the act
handover waits out the grace and then asks here.

## The live act

`set_active(runtime)` sets the one live act and drops the idle offer's current record, so the act
key cannot start a second act on a stale scan; `clear_active(runtime)` only clears the pointer when
that runtime owns it. Both hand the body to the stock smack layer, which owns the outside-act sound
layer (`docs/audio.md`). `active()` answers the runtime or null, `act_running()` the plain bool the
idle probe, the act key, the offer and the stool supply gate on.

## Identity

`identity_of(body)` returns the typed `Identity` (`id`, `display_name`) from the body's
`relationship_id`/character name, with the runtime's fallback read when the body has no stable id.
`act/session.gd:refresh_identity()` is the act's one consumer: it keeps the last id across a freed
body, adopts the display name and refreshes the scene gate.

## The serial

`allocate_serial()` returns `unfplap.serial + 1` and writes the key back. The last value this
process issued is a floor under the stored one, so a store that cannot keep the write (a headless
suite, a read-only `user://`) never hands the same serial out twice. The serial is the act's
identity, not the entry's, which is why it lives here.

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
matched through its body's identity (`anatomy/service.gd`'s `pony_id()`).

## Host boundary

The entry's `bind(anatomy_service, body_change_service, offer_service, stock_smack_service,
eligibility_service, api_service)` sets these once, before the first hook, from its
`_build_services()` list:

| Bound by the entry's service list | Purpose |
|---|---|
| `factory` | `(Node pony) -> Node`, the entry's one runtime construction |
| `anatomy` | `bind(pony, runtime)`, `tail_ready(pony)`, `detach_controller(pony)` |
| `body_change` | `notify_body_ready(pony)` and `installed_character_ids()` |
| `offer` | `clear_current()` on an act start |
| `stock_smack` | `pony_ready(pony)`, `act_start(pony)`, `act_end(pony)` |
| `eligibility` | `eligible(pony, Target.CHARACTER)` for the Characters tab, and `Target.ACT` behind `act_target()` |
| `api` | the cross-mod facade an integration registers its mare through |

`bind_settings()` joins the settings change notification and `shutdown()` leaves it: a settings edit
re-runs `apply_live_settings()` over every runtime and the act a pending body swap has taken out of
the registry. `act_target(pony)` is the act-target rule the offer and the debug block read through
the preloaded `PONIES` facade.

`LOG.act_running`, `LOG.runtime_count` and `LOG.mare_count` are bound to `act_running()`,
`runtime_count()` and `mare_count()`. A missing service
reads as "no prepare", "no character list" and "no side effect", so a suite binds only what it
tests.

The service binds no state of its own: the registry, the record, the pointer and the serial are
rebound by the entry and cleared by `shutdown()`.

## Settings

None. The service reads no setting; the live pass hands each runtime its own snapshot.

## Controls

None. The act key belongs to `docs/input.md` and the idle scan to `docs/offer.md`.

## Debug

The Debug block builds its own `Host` from the `PONIES` facade in `debug/actions.gd` and reads
`active()`, `runtime_for()` and `live_ponies()` through it; the entry binds none of them. The idle
perf block's header counts come from `runtime_count()` and `mare_count()`. See `docs/debug.md`.

## Lifecycle

- Scope: world
- Constructed by: static initialization
- Begin: the entry calls `PONIES.bind(...)` and sets `factory`; `attach()` per spawned body
- End: `shutdown()` on process exit, `close_world()` on a world close
- Idempotent: yes

## Dependencies

### Uses

| Kind | Target | Entry point | Purpose |
|---|---|---|---|
| service | anatomy | `anatomy/service.gd` | anatomy and tail seat |
| service | eligibility | `eligibility/service.gd` | adult and consent gate |
| service | settings | `settings/service.gd` | settings declarations and live values |
| service | world | `world/service.gd` | live scene reads |
| shared | log | `shared/log.gd` | log sink and perf entry |
| shared | body_change | `shared/body_change.gd` | typed body swap record |
| shared | body_form | `shared/body_form.gd` | the presented form's name |
| shared | pony_id | `shared/pony_id.gd` | stable pony ids |
| shared | settings_change | `shared/settings_change.gd` | the settings change notification |

The runtime itself is not a dependency: it is built by the entry's factory and called dynamically.

## Tests

- `tests/ponies/test_service.gd` — attach and detach, the live act pointer and its side effects,
  the serial, the prepare hooks, the adoption order and its duplicate guard, the world close, the
  teardown and the character lists.
- `tests/handover/test_body_swap.gd` — suspend, adopt and resume against the real service, with
  only the runtime's host handle and the body-change service faked.
- `tests/body_change/test_service.gd` — the runtime binding's lookup through the registry.
- `scripts/architecture.py --check` — the service contract, its Uses rows and the `ponies` import
  policy (never `runtime.gd`, `main.gd` or `api.gd`).

## Related docs

- `docs/runtime.md` — the act the registry builds and the body swap on the act side.
- `docs/anatomy.md` — what the attach-time bind and the tail seat do.
- `docs/body_change.md` — the providers that ask for a new body.
- `docs/eligibility.md` — the adult capability the character target asks.
- `docs/offer.md` — the idle offer the act start drops.
- `docs/log.md` — the two installed reads.
