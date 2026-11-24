# World

The world service is the one place a service reads the live scene. The entry binds it when the
world and the player arrive and clears it when the world closes. It answers where and what —
the world root, Anon's body, the reads derived from them and the typed views of the base-game
objects around them — and never whether: every gate, offer and act rule stays with its caller.

## The bound pair

The service's ready answer means both the world root and Anon's body are bound, and the world-only
half serves a caller that must parent or hand off the scene root. This is the mod's one "is there
a world" read; a service never names the entry to ask it. The entry is the only writer: it binds the
world, binds the player body and unbinds on close. An unbound service answers its absent values,
which means "no world yet", not a rule.

## What it answers

It owns the reads a rule is built on: a copy of the world's live mare list; the place directory's
region for a point and the house interior that owns a node; the bed under a downward probe, the
real bed behind a mattress hit, the bed a cradle looks at, occupancy and Anon's seat beside a bed;
a house's bed through its own builder; the shop's item scene and the population's shape catalogue;
the menu and panel gates and the headset test; her cached bond level with a found flag that keeps a
missing row distinct from a real one. A handful of scene writes belong here because a service
cannot do them itself: the merged LOD rebuild after a shape change, opening the chat past the act's
controls lock, and a body's velocity. It never answers an offer, a pose, an act start or a gate
verdict, and it preloads no other service and no runtime.

## The pony record

The pony record is built once after the world services exist and handed to every runtime. Its
fields are fixed and typed, so it cannot answer a lookup, and a null field is the same absent peer a
bare suite runtime sees. The act modules read the live runtime through its one act-frame field, and
the roster is a field of its own. It is a value the entry fills, not a locator.

## Views

A view is a base-game object with its receiver already bound. The factory caches one handle per
bound node and clears the cache on every bind and unbind, so a swapped body never answers through
the old one. A view built on null still answers with typed empty values, so one held past her
removal cannot crash the caller. A view holds no service and no act state, writes nothing on
construction, and is the surface every consumer outside the world service uses.

An Anon view is bound to the player handle by the service, so its player members take no node; the
presentation and the hand or torso driver it acts on are still passed because a caller may hold a
different one. A pony view binds her body, or the act body that answers for her, and resolves her
identity, skeleton, head, mouth, hair, dock and gaze; a member that acts on another object takes
that object first. A wings view is split by what owns the call, with the wing node and her Beat
answering different members.

## The rest family and the navigator

A bed view binds whichever rest-family node holds the row a member reads: the bed itself for the
bedding and the stock rest, the couch or rest it belongs to for the seats and guest entries, one of
its seats for the exit floor, and the seating system for a pony's seating phase. Each call passes
the other nodes it needs — the seat it asks about, the pony, the body stepping off — because they
are not the receiver.

A navigator view binds her navigator child, or the navigator itself when a caller recorded it, so
the ledger that took a lease at claim time keeps its reads and writes even after the pony read is
lost. The lease remains the property of whoever claimed it, and only that caller's operations pass
through here, with no claim, reassignment or release of its own.

## The other views

The director view is the one view bound to two nodes: the director itself and the bound world's
context, which answers the impressions and the journal. The inventory view binds the inventory node,
while the store a slot row reads and the bar a visibility call asks about are passed. The menu view
binds the world root for the named panels. The relationship view binds the relationship runtime,
while the store-keyed members take the store because the pony or the store is not the receiver. The
mods view binds the game's registry. The affection view binds the scene's stock kisser, and passes
the affection, pose, Beat, cuddle and reach objects its other members write. The registry's save
call is forwarded, but the caller that decides to save owns that call.

## Base-game access and failure

The accessor layer is stateless: every read takes the scene handle it needs, and a member that is
gone or was renamed yields a typed zero instead of an error — a handle reads null, a flag false, a
measurement `NAN`, a point zero or infinite, a list empty; a clamp hands back its input. A freed or
mismatched argument takes the same quiet answer. The game-private quirk members are mirrored here,
so a game version change is a change in this layer and never in a caller. A typed copy or a typed
view is the only allocating answer; the per-frame accessors copy nothing, and the few calls that
rebuild or sense go through the game's own allocation.

## Data and boundary

The service stores no saved data. It holds the bound handles and the view caches, all cleared on
every bind and on close, and it writes nothing to the settings file or the mod state. It declares
no setting, no control and no debug action. The debug tooling reads the scene through it like any
other consumer, and it never calls back into the entry.
