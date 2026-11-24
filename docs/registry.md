# Mare registry

The registry is the in-memory store for mare descriptors another mod provides. A provider registers
one stable id and a template-shaped descriptor; the registry validates it, layers it over the
game's built-in template, and lets every service that knows a base-game mare resolve the same data
for her. It is the authority for provider layers and their validation, not for the player's file.

## A provider layer

A layer carries the source mod id, an optional display name and the part of the template the
provider wrote. Layers for one identity merge in registration order, so a later provider wins per
key. A provider that registers the same id again replaces its own layer in place rather than
stacking a second one; another provider's layer survives.

The identity half is written separately from the template half. An update carries only the parts it
sets, so the rest of the provider's template survives a re-registration; an update with no
eligibility assertion clears the assertion rather than leaving a stale one.

## Validation

Each recognised key is checked at the edge: a wrong type and a malformed value are reported as
errors, never coerced, while an unknown key or an unknown entry in a list is a warning that changes
nothing. A value outside a closed set is an error, not a fallback. The legacy per-mare prompt fields
are unknown keys and warn like any other. A descriptor asking for a newer schema is refused rather
than half-applied, because a partial template is worse than none.

A provider is a scene node: registration needs a live owner, so leaving the tree can remove every
layer that owner wrote. Reserved names keep a descriptor from taking an identity the placement
block already uses.

## Resolution

A caller asks for a merged template, an optional placement block, a display name or the source list
for one stable id. An absent placement is distinguishable from a placement of zeroes, so a caller
never lands a mare at the origin because a provider wrote nothing. The player's saved character
block is a later layer that outranks every provider layer, and it stays in place when a provider
leaves, so removal returns the mare to her player-edited state rather than erasing it.

## Revision

A revision value moves on every layer change. A derived identity cache compares it and rebuilds
when a provider registers, updates or leaves, so no caller can change a layer without invalidating
the view built from it.

## Lifetime and ownership

The store is process-wide, in memory, and main-thread only; nothing is written to disk. It starts
empty, so a run with no provider mods behaves exactly as the base game. A test or a world teardown
may reset it. The descriptor schema and the registration result are the cross-mod contract.
