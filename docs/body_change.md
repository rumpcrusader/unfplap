# Body change

The body-change mechanism gives a presented body its typed form, moves a pony between bodies when a
provider supplies another shape, and refreshes every body-bound system through one fan-out. It owns
the form store, the apply path and the index of live changes; a provider owns its pack, its forms
and its own timing. The act, the pose and the camera keep their own state.

## One identity, one form

A pony has one identity that outlives the body on screen. Memory, dialogue, preferences,
eligibility, act history and the summary follow that identity, so a nickname, a relationship or an
act never depends on which shape stands there. The presented body carries the form: the identity it
belongs to, an optional borrowed form id, a display name, the fit row the anatomy and the tail seat
use, and the rig that positions a winking body.

The own form carries no form id. Its name, fit and rig fall back through the identity's own data,
and the body's live scale rides with it. A body with no stored form reads its own form, built once
and kept; an invalid body has none.

## The apply path

One write applies a form to a body, and everything that must follow a form change hangs off it. An
impossible or non-finite scale is clamped to what the body can carry before any binding sees it. The
form is stored with a revision and only what actually changed is touched: a body taking its first
form binds, the same body with a new revision or changed values refreshes, and the same form applied
again does nothing.

A provider can learn a detail after the body is up: a prepared form may gain its tail root a few
frames later, the next prepare bumps the revision, and the refresh path re-seats the tail without a
new body. The first apply also arms one release on the body's own exit, so a body leaving the tree
gives its bindings back even when nobody asks it to; releasing drops that body's stored form, its
revision and its place in the live-change index.

## Providers

A provider is the typed source of forms. It registers with the service, claims the bodies it
handles, supplies the form for a new body, runs one change at a time and reports when its own
observed state moves. Registration refuses anything outside the contract, so the source list can be
trusted.

The base mechanism is push-only and never polls. A provider watches its own pack on its own timer or
signal and pushes what it sees; one that has no form for a body yet leaves the own form in place. A
pack an install does not have, or a feature a player switched off, registers no provider and the
mechanism stays inert for those bodies.

A future provider supplies a feature gate, its body claims, its change state, the typed form per
body and its observation. The offer policy, the installed character list and the tail hooks are
optional. The base mod never names a provider's characters, pack ids or mesh markers.

## The live change

A change is indexed by its provider and by both presented bodies, so the act's read of the old body
and of the new one never depends on a scan. A provider runs one change at a time, and a second
provider cannot overwrite a change another one already holds for the same body: an idle change never
replaces an act's change.

A terminal change clears its provider's entry and both body entries. A body that leaves the tree
releases only the key that names it: the departing predecessor's entry disappears while its
successor keeps the change readable, and a successor that exits before it settles clears the change.
The provider keeps the finished change as a record the act may still read, and the in-progress
question stays separate from that record.

The act's handover reads the change on its own cadence and returns one action the runtime applies;
it never reads the provider. A body that never arrives is given up on after the watchdog, leaving
the old body and form in place. A change that lands while the act is already returning finishes the
return instead of resuming a half-restored act.

## The shape offer and the reveal

A provider decides whether and when to offer, what the offer says and what a reveal does. The base
runtime keeps the once-per-act gates and executes the generic effects, so a provider that wants none
of it simply answers nothing.

The offer question is asked on live act time until the offer is made or the chance is spent, and a
no before the provider's own trigger spends nothing. A provider without a policy, or with an empty
offer line, never offers. The written offer becomes the act's one shape reaction.

A player line that names a form starts a player's change; a line that asks for her own body starts a
reveal. A completed player change applies the provider's offer-accepted effects; a completed
own-form ask applies the reveal effects once and gives the act its exceptional face beat. Heat and a
cue land only while the act itself is live; the memory kind and the peak become the reveal
impression and the peak. An AI-started change is neutral: it uses no player effects and leaves the
player's pending offer exactly where it was, so her own initiative neither spends nor restores it.

An unanswered offer ends with the act. A player-named change that fails before a new body arrives
puts the offer back, so the player can ask again in the same act.

## Bindings

Every body-bound system joins the fan-out in registration order. The built-in chain covers the
anatomy and the tail seat, the runtime living under the body, the level-of-detail caches, worn
garments and the stock smack layer. A system that is absent or driven by a switched-off pack
registers nothing, and the rest of the chain still runs.

Each binding is scene-free: it reads the handle it was built from and adds no line to the entry. A
binding added later joins the end of the same fan-out, and a body without a runtime is inert rather
than broken.

## Failure and restore

The form store answers null for an invalid body, and a provider that prepares no form leaves the own
form where it was, so a failed swap is an unchanged body rather than a half-applied one. The
mechanism never ends an act: no force-stop, no exit and no resume of a suspended act belongs here,
and the old body and the offer behave as they did before the change failed.

## Diagnostics

With the debug switch on, one line records each apply with the body, the identity, the form, the fit
and the rig, the scale and revision, the previous form, what the apply did and which bindings ran.
The act's own swap lines carry the suspension, adoption, resume and failure phases, and the form
never becomes a HUD row: the reveal stays the player's discovery.
