# Eligibility

Eligibility is the permanent identity gate: may this character take part in acts, be given
anatomy, be listed as a character, and did she grant a specific action. It never answers "right
now": the dynamic answer is the act gate's, and the live scene rows are the scene gate's.

## A capability, not an identity read

Each consumer asks about its own target and receives a yes or no. It never inspects age, sex or the
provider's assertion itself, so the rules below can change without touching a caller. The three
targets are the act, the anatomy and the character list; each takes the participation flag that
belongs to it, and the character target takes none, so the Characters selector can always re-enable
a mare who opted out of acts or anatomy.

The identity predicate decides adulthood and sex once and is private to this service. The id-only
form answers for a body that is not spawned yet, using the named shape's population identity. The
witness age is the only age-shaped answer the mod gives, and it exists for witness wording alone.

## Adults

An adult is an identified character who is neither a filly nor a colt, and never the player's own
pony. A stallion counts as an adult for witness wording, but he is not a mare, so he is never an act
or anatomy target.

A provider's `eligible` assertion is a tri-state override. True or false replaces the age flag,
and an absent assertion lets the identity decide. It changes age, not sex: an asserted stallion is
still no target. It belongs to the provider layer alone, so no player value can set it, and the
same assertion answers the act gate's registration fact, which lets a provider pass that row for a
pony the base game never registered.

A young player blocks every act; the act gate reads the player's form as its own fact.

## Participation

The participation block is subtractive: true means "does not veto", never "grants", and a missing
key means the default true. Its acts flag gates the act target, and its anatomy flag gates the
anatomy target, with the tail following the same decision. The deprecated tail key is still
accepted, validated and returned for the frozen cross-mod shape, but no capability reads it.

The player's saved block is a sparse difference over the provider's layer. Reset to default clears
the player's participation and returns to the provider's default; it leaves a provider's assertion
alone, because that value was never the player's to clear.

## Consent

The profile's consent block is the stored per-mare consent, resolved from the shared defaults, a
provider layer and the player's differences. Eligibility only hands it out; the live consent
question and what each key means belong to the act gate.

## Records

Nothing here is stored or saved. A live body's identity record is built when it attaches and is
rebuilt only when its era moves: a new identity, a settings generation or a provider revision. A
capability read is therefore a lookup and a predicate, cheap enough for the discovery loops that
call it every frame. The shape identities used for a body that is not spawned belong to one world
and are cleared with it.

## Boundary

The typed profile the facade returns is this service's read side for the mod and the cross-mod
surface is `docs/api.md`. No file outside the service reads the pure identity rules; another system
asks for a capability and never duplicates one.

## Debug

The debug line reads the act gate's relationship facts rather than an eligibility answer.
Eligibility declares no debug action and prints no console line of its own.
