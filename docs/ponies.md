# Ponies

The World roster: one runtime per pony body, the attach and prepare hooks, the live-body list and
the prompt note the game reads. `ponies/service.gd` is a World Node and the only owner of "which
body has which runtime", so no consumer reads the entry for it.

## Scope

This contract covers:

- the attach and prepare hooks, including the late prepare a mod calls once its node exists;
- the runtime lookup the world services share;
- the live runtime set and the bodies it maps to;
- the adoption of the act owner's pending body swap and the duplicate-runtime guard;
- the prompt note the game's `pony_prompt_notes` group reads;
- the live and installed character lists the Characters selector shows;
- the per-runtime live-settings pass, the world hooks and the teardown.

It does not cover the act itself (`docs/runtime.md`), the attach-time anatomy and tail work
(`docs/anatomy.md`), the eligibility rule (`docs/eligibility.md`), the body-change sources
(`docs/body_change.md`) or the hint and start the idle scan leads to (`docs/offer.md`). The old
rear-fan target scan is gone: the offer's fan sensor and the eligibility and act-gate facades own
that read.

## Ownership

| Member | What it owns |
|---|---|
| `wire(anatomy, eligibility, act_gate, body_change, estrus, stock_smack, act_owner)` | the World peers one attached body passes through, set once by the composition root |
| `factory` | `(Node pony) -> Node`, the entry's one runtime construction |
| `attach(pony)` | the spawn hook: the player-body refusal, the prepare pass, the pending-swap adoption, then one runtime |
| `prepare_late(pony)` | the prepare pass again for a body a mod completed after its first spawn; never creates a runtime |
| `runtime_for(pony)` | the `UnfplapRuntime` child a body carries |
| `live_ponies()` | the bodies of the live runtimes, for the debug block; a body the act owner's swap is taking away is not listed |
| `adopt_pending_body(pony)` | the prepare and adoption the act handover asks for after the adoption grace |
| `apply_live_settings()` | the live settings pass over every runtime, not only the act's |
| `prompt_note(id)` | the live act/afterglow note and the cycle line for one stable id |
| `live_character_ids()` / `installed_character_ids()` | the off-roster mares the Characters tab lists |
| `on_world` / `on_world_closed` | no bind on the enter, because the live set is the runtime group; the close ends the live act and frees the act owner's frame |
| `shutdown()` | process exit: close the act, stop and free every runtime, drop the peers and the factory |

The roster preloads no runtime: the entry owns that file and sets `factory`. Every call into a
runtime is dynamic on a `Node`, so the roster only needs the methods the act contract publishes.

## Attach order

`attach(pony)` runs in one order, and the order is the contract:

1. the player's own AnonPony and any node with a `rig` are refused, because they are Anon's body,
   not a mare's;
2. the prepare pass: `body_change.notify_body_ready()` (the provider's form is fitted and mirrored
   before anything binds), then `anatomy.present()` once with the provider's stored form, then
   `estrus.track()`, the stock smack layer's `pony_ready()`, `eligibility.warm()` and
   `act_gate.warm()`. Anatomy owns the identity gate inside `present`, so the roster makes no
   separate capability or tail decision. Every hook is idempotent, which is what makes
   `prepare_late()` safe;
3. the pending swap is offered the body, which is the only way a suspended act keeps its runtime;
4. a body that already carries a runtime is left alone; otherwise the factory builds it, the
   runtime enters the body's tree and one `runtime attached <name> id=<id>` line is logged;
5. the body's `tree_exiting` withdraws its anatomy controller and untracks its estrus schedule.

A body with no factory, no runtime or an omitted peer is a quiet no-op: a suite can wire any subset.

## The live set

The runtime joins `unfplap_pony` when it enters the tree and the roster joins `unfplap_ponies`. The
live set is the runtimes in the group that are still inside the tree, mapped to the body each one
reports. There is no internal map: the body's `UnfplapRuntime`
child is the one lookup, and a factory must name the runtime so.

## The body swap

The act handover records the pending swap on the act owner (`docs/act_owner.md`) before the
runtime leaves the old body, so the new body's spawn finds the record instead of creating a second
act owner. The suspended runtime has left the old body but `live_ponies()` and the character list
skip the body the record names as the old one.

`attach()` adopts when the change's typed source `claims_body()` the newcomer or the newcomer's
stable id (`shared/pony_id.gd`) matches the record. A body with another id is attached normally and
leaves the record alone. The adoption order is: detach a duplicate runtime's anatomy controller and
stop and free that duplicate (a race can only mean the suspended act is the owner), bind anatomy
to the new body, reparent the runtime under it, clear the owner's record and hand the body to
`runtime.adopt_body()`. The adoption never resumes the act; the act handover owns the one resume
(`docs/runtime.md`).

`adopt_pending_body(pony)` is the same prepare-and-adopt path for a body whose spawn hook never
reached `attach()`: a provider may clear its changing state before the new body appears, so the act
handover waits out the grace and then asks here.

## Characters

`live_character_ids()` lists the adult mares whose bodies hold a runtime and pass
`eligible(pony, Target.CHARACTER)`, drops the base roster from them, appends the mares an active
installed-profile source lists even while she is away, and sorts by display name. The base roster
stays the base roster; a provider owns its own installation gate.

## Prompt note

The game asks the mod for one dialogue note per mare through the `pony_prompt_notes` group, whose
members must be Nodes. The entry keeps the group join and forwards three lines; the note itself is
built here: the runtime whose stable id matches the query answers with its `prompt_note()`, and its
`cycle_note()` is appended when the cycle has one. A runtime that has not read its id yet is
matched through its body's identity (`shared/pony_id.gd:of()`).

## Composition

`wire()` takes the World peers one attached body passes through, each read at use. `_ready()` joins
the roster group and the settings change notification; `_exit_tree()` leaves the notification.
`shutdown()` force-stops and frees every runtime in the group while the World services they read are
alive, then drops the factory and the peers.

A world close ends the act owner's frame through `act/exit.gd:run`, drops its swap and keeps the
runtimes; they leave with their bodies. The settings edit re-runs `apply_live_settings()` over
every runtime, the suspended act included.

## Settings

None. The roster reads no setting; the live pass hands each runtime its own snapshot.

## Controls

None. The act key belongs to `docs/input.md` and the idle scan to `docs/offer.md`.

## Debug

The Debug block reads the roster through its `Host` facade: `active()` from the act owner,
`runtime_for()`, `live_ponies()` and the act-target rule from the eligibility service. See
`docs/debug_actions.md`.
