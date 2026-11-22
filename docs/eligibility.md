# Eligibility

The permanent identity gate: may this character take part in acts, be assigned anatomy, be listed
as a character, and did she grant a specific action. It never answers "right now"; the dynamic
question is `docs/act_gate.md` and the live scene rows are `docs/scene_gate.md`.

The internal API is `eligibility/service.gd`. The typed surface is `eligible`, `eligible_id`,
`get_profile`, `set_profile`, `witness_age` and `warm`. Cross-mod exposure stays `docs/api.md`,
which this contract does not change.

## Scope

This contract covers:

- the one adult predicate and the per-target capability answers;
- the provider's tri-state `eligible` assertion and the resolved participation block;
- the stored profile document the cross-mod API returns (assertion, participation, consent);
- the witness age category.

It does not cover the relationship, romance, Promiscuity floor, willingness, cycle, history or the
consent question: they belong to `act_gate`. It does not cover poses, acts, readiness or camera.

## Architecture

| File | Role |
|---|---|
| `eligibility/service.gd` | public API: the cached identity record, the capability answers and the profile layer |
| `eligibility/identity_record.gd` | the typed per-pony identity record: scalars as fields and the one participation document, reused until its era moves |
| `eligibility/policy.gd` | pure identity predicates and the age category over plain values |
| `eligibility/facts.gd` | pure identity fact schema; the one adulthood predicate stays private here |
| `eligibility/scene.gd` | the world boundary: a live body lookup and the population shape cache |
| `docs/eligibility.md` | this contract |

The purity boundary is deliberate:

- `policy.gd` and `facts.gd` have no `Node`, `Time`, `SceneTree`, `FileAccess`, `SETTINGS` preload
  or scene preload. They receive plain data and return plain data.
- `eligibility/service.gd` is read-only. It never saves settings, history or consent.
- Only `eligibility/scene.gd` reads `world/api.gd`; only `eligibility/service.gd` reads
  `bonds`-free identity values, `SETTINGS.profile_identity` and `SETTINGS.consent`.
- The service is a leaf: it preloads its own files, shared data, the settings and registry facades
  and the scene boundary. It preloads no other service. `scripts/architecture.py --check` enforces
  the leaf rule, including the shape cache's one world read.
- No file outside `eligibility/` preloads the pure core. Another system calls the facade, which
  answers `eligible(pony, target)` or `witness_age(pony)`; it never inspects age, sex or the
  provider assertion itself.

## Data ownership

Eligibility stores no eligibility state. The only caches are the typed identity record of a live
pony and a named shape's scene identity for `eligible_id()`. A pony's record is rebuilt only when
its era moves: the `relationship_id` metadata, the identity resource, the settings generation or
the provider revision. The record carries the stable id, the identity flags, the provider assertion
and the participation block, so a per-frame capability read is a dictionary lookup and a predicate.

| Data | Stored where | Owner |
|---|---|---|
| Per-mare participation (`acts`, `anatomy`) | `characters.json` -> `characters.<id>.profile.participation` (differences only) | `settings/service.gd` plus the `shared/participation.gd` resolver |
| Per-mare consent (public, anal, oral) | `characters.json` -> `characters.<id>.consent` (differences only) | `settings/service.gd` plus the `shared/consent.gd` resolver |
| Provider assertion, participation and consent | the registry's provider layers | `registry/service.gd` |
| Eligibility facts | nowhere | `eligibility/service.gd` per call |

Rules:

- No `characters.<id>.eligibility`, no eligibility block in `settings.json`, no eligibility block
  in `Mods.state("unfplap")`.
- `eligibility/service.gd` never calls `SETTINGS.save_*` or `Mods.save_changed`.
- `shared/participation.gd:KEYS` and `shared/consent.gd:KEYS` are the capability and consent key
  tables. `PARTICIPATION.all_keys()` adds the deprecated `tail` key, which is still accepted,
  validated and returned but ignored by every capability.
- `shared/pony_id.gd:from()` is the only stable-id rule: `relationship_id` metadata first, then the
  identity id. Runtime, eligibility, placement, memory and the anatomy internals call it.
- The cross-mod read stays static (`docs/api.md`); it is not extended with live eligibility.

## Facade

`eligibility/service.gd` extends `shared/service.gd`, the world-service base. The entry creates one
instance per world and binds it as `PONIES.eligibility`; `anatomy`, `act_gate`, `initiation`,
`negotiation`, `debug`, `memory`, `api` and the standing presentation read it. The types are
declared in the facade, so a consumer names them `ELIGIBILITY.Target`, `ELIGIBILITY.Profile`, and
so on.

`eligible()` is the capability answer: the cached identity record, the provider assertion, the
stable id and the target's participation veto. It is called in per-frame discovery loops, so it
never builds a fact snapshot. `warm(pony)` is the attach-time read: it builds the identity record
and marks its era, once per era, so the first capability read is a lookup; it is called from
`PONIES._prepare()` and is a no-op on a second prepare of the same era. `eligible_id()` is the
id-only form for a body that may not be live: a live pony answers as `eligible()`, otherwise the
shape's population scene identity and the provider assertion feed the same target predicate. It is
a capability, not an age or sex read; the default character target is what a shape source asks
about a player-named body. `witness_age()` is the only age-shaped answer and only for witness
wording. `get_profile()` reads the resolved provider/player profile for one id; `set_profile()`
writes the provider layer's eligible assertion, participation and consent. The pair is the internal
typed read/write side; the cross-mod surface is `docs/api.md`. `set_profile` is test-only today.

## Capability targets

A consumer asks about its own target and never inspects identity:

| Target | Veto | Callers |
|---|---|---|
| `Target.ACT` | `participation.acts` | act discovery, the standing invitation, the fan candidates |
| `Target.ANATOMY` | `participation.anatomy` | the anatomy facade's `present`; the tail follows it |
| `Target.CHARACTER` | none | the Characters selector, so an opted-out mare stays editable |

The deprecated `tail` participation key is still returned by `get_profile()` but no target reads
it. The tail is part of the anatomy presentation; `docs/anatomy.md` owns that rule.

## Adults

- There is one adulthood predicate: `eligibility/facts.gd:adult_pony()` and `adult_mare()`. It
  takes the identity flags and the provider assertion as values and decides age and sex only. It is
  private to `eligibility/`; `eligibility/policy.gd` delegates to it.
- `Target.ACT`, `Target.ANATOMY` and `Target.CHARACTER` accept an adult mare: an identified pony
  that is not a filly/colt, not a stallion and not the player's own pony.
- `eligible()` adds the stable id and the target's participation veto to the identity predicate. An
  adult identity with no stable id is not a target, and the capability never re-derives the
  predicate.
- A provider's `eligible` assertion is a tri-state override: `true` or `false` overrides the age
  flag; `null` lets the identity decide. It changes age, not sex. It is provider-only and never
  written to the player's settings.
- The same assertion resolves the act gate's `registered_adult` fact, so a provider can pass
  unfplap's relationship row for a pony the base game has not registered as an adult.
- Adult stallions are not act or anatomy targets. They may still witness an act:
  `witness_age()` returns `Age.ADULT` for them.
- `witness_age()` returns `Age.YOUNG` for a filly/colt the provider has not asserted adult,
  `Age.ADULT` for an adult (or asserted adult), and `Age.NONE` for a pony who can be neither. The
  pure category is `eligibility/facts.gd:AgeKind`; the public `Age` enum has the same values.
- A young player blocks every act; the act gate reads the player form.

## Participation

`profile.participation` is the per-mare capability block: `acts` and `anatomy`, plus the deprecated
`tail`. It is subtractive: `true` means "does not veto", never "grants". A missing key means the
default `true`. The `acts` key is the act gate's participation row with a `block` effect; a failing
row also drops `show` and `offer`. A player who opts out of acts is a quiet boundary, not a mood
beat. The anatomy key gates `Target.ANATOMY`. `Target.CHARACTER` ignores both so the Characters
selector can always re-enable an opted-out mare.

A provider's `profile` is a layer; the player's `characters.<id>.profile` is a sparse difference
layer. The player's `Reset to default` clears the player's participation and returns to the
provider's default; it does not clear the provider's `eligible` assertion.

## Profile and consent

`profile.consent` is the stored per-mare consent block (`public`, `anal`, `oral`), resolved by
`settings.consent(id)` from the shared defaults, a provider layer and the player's differences.
Eligibility only ever reads it for `get_profile()`: the live consent question is
`act_gate.consent()`, and the act input is its only caller. `public` is a soft preference for the
negotiation reasoning, never a gate; `anal` and `oral` gate the anatomy targets' action keys.

## Debug

`debug/pony.gd` reads the act gate's `relations` for its debug line; eligibility itself has no
debug action and no console line. The Debug actions that used the old verdict now read the act
gate: `docs/act_gate.md` and `docs/debug.md`.

## Known limits

- The internal typed API is not part of `docs/api.md`, which owns the cross-mod surface.
- A provider's `eligible` assertion changes age, not sex; a stallion stays no target.
- `get_profile()` resolves the provider layer and the player's differences on every call. It is a
  cold read, not a per-frame one.
- `set_profile` is test-only today; its eventual home is the registry store or the cross-mod API.
