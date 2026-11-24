# Act owner

The one World service that owns the act frame: which runtime is acting, the serial floor under the
act ids and the one suspended body swap. It is the only place an act start, an act end and a
body-change adoption agree on who owns the act.

`act_owner/api.gd` is the facade. Every caller injects it: the entry builds and wires it, the
World record carries it to the runtimes and the act modules read it from there, and the World
services that gate on a live act take it as a `wire` peer.

## Scope

This contract covers:

- the live act's runtime and the two side effects of taking and freeing the frame;
- the per-process serial allocator and its store key;
- the one pending body-swap record: what it holds, who may clear it and what clears it at a world
  boundary.

It does not cover the act itself (`docs/runtime.md`), the pose and camera (`docs/poses.md`,
`docs/camera.md`), the roster that builds and adopts runtimes (`docs/ponies.md`) or the body-change
sources (`docs/body_change.md`).

## Ownership

| Member | What it owns |
|---|---|
| `wire(offer, stock_smack)` | the frame's two side-effect peers, set once by the composition root |
| `set_active(runtime)` | the live act, the idle offer's current record and the stock smack layer's act start |
| `clear_active(runtime)` / `active()` / `act_running()` | the frame's release, scoped to its runtime, and the two typed reads every starter gates on |
| `allocate_serial()` | the `unfplap.serial` key and the last value issued this process |
| `begin_body_swap(runtime, old_pony, id, change)` | the act's one suspended record |
| `clear_body_swap(runtime)` / `body_swap_pending()` / `pending_swap()` | the record's one end, scoped to its runtime, and the roster's typed read of it |

The service preloads no runtime: the runtime is a `Node` and the record read is the one property
it publishes. It takes the offer and the stock smack layer as two peers rather than the World
record: they are the only services the frame calls, and the record already carries this service.

## The frame

An act start takes the frame before the runtime emits its act-started signal: the idle offer drops
whatever it had scanned and the stock smack layer hands the acting body's outside-act player over
to the act. An act end frees the frame only when the runtime that asks is the one that holds it, so
a stale exit from another body cannot end the live act; the same call returns the smack layer to
the body. `active()` answers null for a freed runtime, and `act_running()` is the plain bool the
idle probe, the act key, the offer, the fan sensor, the stool supply and the Anon-offer watch gate
on.

A null owner is a bare runtime or a suite without the World record: taking the frame does nothing,
reading it answers null and false, and allocating a serial answers zero. No caller crashes on a
missing owner.

## The swap record

The act handover records one suspended act before the runtime leaves the old body, so the new
body's spawn finds it instead of creating a second act owner. The record is one `Swap` value —
runtime, old body, id and change; `pending_swap()` is the roster's typed read of it, and the roster
does not list the departing body while the record names it as the old one.

The record is scoped to its runtime: a clear from another runtime is a no-op, and a clear with no
runtime is too. The roster's adoption reads the record, maps the new body, and clears it through
`clear_body_swap()`; the handover's own finish, abort and failure paths clear it as well. A null
change records nothing.

## World close

A world enter drops the swap of the world that is gone. A world close drops the swap too, but it
never force-stops a live act: the runtime leaves with its body, so the frame is dropped by the
runtime's own teardown and `active()` answers null afterwards. The process exit is the one place a
live act is stopped through its exit, and the roster owns that path.

## The serial

`allocate_serial()` returns the stored `unfplap.serial` value plus one and writes the key back.
The last value this process issued is a floor under the stored one, so a store that cannot keep the
write never hands the same serial out twice. The floor is World state and the teardown drops it; a
store that did keep the write still outranks the fresh floor. The serial is the act's identity, not
the entry's.

## Settings

None. The service reads no setting.

## Controls

None. The act key belongs to `docs/input.md` and the idle scan to `docs/offer.md`.
