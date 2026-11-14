# Mare registry

The in-memory provider registry for modded and base-game mare descriptors. Another mod registers
one stable id and a character-template-shaped descriptor; this service validates it, layers it over
the built-in template, and lets the settings, eligibility, anatomy, placement and API services
resolve the same data they already resolve for a base-game mare.

Provider data is never written to `settings.json`. The player's saved block always wins, and
removing the provider leaves the player's choices intact.

## Scope

- Registration, replacement and removal of a provider descriptor.
- Validation of the descriptor schema and warnings for ignored fields.
- The provider layers over the built-in character template.
- The resolved name, preferences, consent, eligible assertion, participation, placement and pose
  overrides for one stable id.
- The owner-scoped removal used when another mod unregisters or leaves the tree.

## Ownership

`registry/service.gd` is a static process-wide store. It owns the provider layers in memory and
nothing on disk. `settings/service.gd` owns the player's persisted `characters.<id>` overrides.
`api.gd` owns the cross-mod registration surface; its contract is `docs/api.md`.

The registry is empty until a provider registers, so a run without other mods behaves exactly as
the base game.

## Internal API

`registry/service.gd` extends `RefCounted` and exposes static methods:

```gdscript
static func register(owner_id: int, descriptor: Dictionary) -> Dictionary
static func set_profile(owner_id: int, source: String, id: String, profile: Dictionary) -> Dictionary
static func unregister(owner_id: int, id: String) -> bool
static func unregister_owner(owner_id: int) -> int
static func template_for(id: String) -> Dictionary
static func placement(id: String) -> Dictionary
static func name_for(id: String) -> String
static func has(id: String) -> bool
static func ids() -> Array[String]
static func sources(id: String) -> Array[String]
static func reset() -> void
```

`revision` bumps on every layer change, so a derived cache (the resolved identity facts) can
rebuild when a provider registers, updates or leaves.

The descriptor schema and validation warnings are in `docs/api.md`. `reset()` is for tests and
world teardown.

## Data ownership

| Data | Stored where | Owner |
|---|---|---|
| Provider descriptor layers | memory only | `registry/service.gd` |
| Resolved template | derived per call | `registry/service.gd` |
| Player's character overrides | `settings.json` -> `characters.<id>` | `settings/service.gd` |
| Cross-mod registration call | memory only | `api.gd` |

No provider value is saved. Removing a provider leaves the player's saved differences in place.

## Lifecycle

- Scope: process
- Constructed by: static initialization
- Begin: none; the registry starts empty
- End: `reset()` on world close or in tests
- Idempotent: yes; `reset()` is safe to call repeatedly

## Settings

No global settings. Provider `preferences`, `consent`, `eligible`, `profile.participation`,
`placement`, `poses`, `act_prompts` and `event_prompts` are layers; the player's
`characters.<id>` block is the sparse override. The settings framework is `docs/settings.md`.

## Controls and debug

No controls. `tests/test_api.gd` exercises registration, replacement and removal through the
cross-mod API.

## Dependencies

### Uses

| Kind | Target | Entry point | Purpose |
|---|---|---|---|
| shared | anatomy_placement | `shared/anatomy_placement.gd` | placement defaults |
| shared | consent | `shared/consent.gd` | consent keys and defaults |
| shared | participation | `shared/participation.gd` | participation defaults |
| shared | pose_catalog | `shared/pose_catalog.gd` | pose ids and defaults |
| shared | preferences | `shared/preferences.gd` | profile math and defaults |

## Tests

- `tests/test_api.gd` — registration, replacement, owner removal, the stable id and the resolved
  descriptor.
- `tests/eligibility/` and `tests/anatomy/` cover the consumer layers that read the registry.

## Related docs

- `docs/api.md` — the stable cross-mod registration and read contract.
- `docs/settings.md` — the player's per-character overrides.
- `docs/eligibility.md` — the participation and consent resolution.
- `docs/anatomy.md` — placement and tail-seat resolution.
