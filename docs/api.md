# Cross-mod API

This is the contract between unfplap and other Home: Equestria mods. `api.gd` is the only
unfplap script another mod may call. Everything else is private, including `settings.gd`,
`runtime.gd`, `character_preferences.gd` and the runtime Nodes.

The API is deliberately small. It lets a mod register a character template for a custom mare or
a base-game mare, remove it, and read everything unfplap resolves for one mare. It does not start
acts, spawn ponies, change relationships, write the player's settings, or expose live act state.

## Discovery

The facade is a Node in two groups:

| Group | Meaning |
|---|---|
| `unfplap_api` | The current API major. |
| `unfplap_api_v1` | Pinned major 1. Long-lived mods should use this. |

```gdscript
extends Node

var unfplap: Node

func _ready() -> void:
	Mods.on_node("group:unfplap_api_v1", _on_unfplap)

func _on_unfplap(api: Node) -> void:
	unfplap = api
	api.tree_exiting.connect(func() -> void: unfplap = null, CONNECT_ONE_SHOT)
	if not api.supports("registry.mare"):
		push_warning("Unfplap is too old for this mod.")
		return
	api.register_mare(self, {
		"id": "starlight_glow",
		"source": "starlight_mod",
		"name": "Starlight Glow",
		"preferences": {
			"intensity": "firm",
			"pattern": "steady",
			"touch": ["caress", "kiss"],
			"talk": ["praise", "reassurance"],
			"warmth": "slow",
			"notes": "Thoughtful, self-possessed and quietly warm.",
		},
	})
```

`Mods.on_node` finds the facade whether it already exists or appears later, so load order does not
matter. If unfplap is switched off mid-game, the node leaves the tree; clear your reference and
re-register when `Mods.on_node` fires again.

## Contract

```gdscript
var contract: Dictionary = api.contract()
```

```gdscript
{
	"provider": "unfplap",
	"api_version": "1.0",
	"api_major": 1,
	"api_minor": 0,
	"mod_version": "0.4.0",
	"game_version": "0.3.0-maredev",
	"schemas": {"mare": 1, "preferences": 1, "placement": 1},
	"capabilities": {
		"registry.mare": 1,
		"mare.read": 1,
	},
	"deprecations": [],
}
```

`api.supports(capability, min_version := 1)` returns true when this build has the capability at
least at that version. `contract()` is plain data and may be cached for the process lifetime.

## Methods (API 1.0)

| Method | Returns | Purpose |
|---|---|---|
| `contract()` | `Dictionary` | Version, schemas, capabilities and deprecations. |
| `supports(capability, min_version := 1)` | `bool` | Feature detection. |
| `register_mare(owner, descriptor)` | `Dictionary` | Register or replace one owner's template. |
| `unregister_mare(owner, id)` | `Dictionary` | Remove one owner's template. |
| `describe_mare(id)` | `Dictionary` | Everything static unfplap resolves for one mare. |

There are no signals in 1.0. Signals and act events are additive later.

## Registering a mare

`register_mare(owner, descriptor)` requires `owner` to be a Node inside the scene tree — normally
the caller's entry Node. The registration lives while that Node is in the tree; switching the
provider mod off removes every layer it registered. Re-registering the same owner + id replaces
that layer in place, so it can refresh its data without changing precedence.

Registration is normally done at startup. Made during an act, it updates resolved reads,
preferences and anatomy immediately; act prompts, cue gap and aftercare are snapshotted at act
start.

```gdscript
var result: Dictionary = api.register_mare(self, {
	"schema": 1,
	"id": "starlight_glow",
	"source": "starlight_mod",
	"name": "Starlight Glow",
	"preferences": { ... },
	"consent": {"public": false, "anal": true, "oral": true},
	"placement": {"tail_tilt_deg": 4.0, "dock_scale": 0.96},
	"poses": {"missionary": {"nuzzle_scale": 0.5}},
	"act_prompts": {"cue": "Custom cue prompt..."},
	"event_prompts": {"climax": "Custom climax prompt..."},
	"cue_gap": 12.0,
	"aftercare_min": 10,
	"smack_zone_radius": 0.035,
})
```

Result:

```gdscript
{"ok": true, "id": "starlight_glow", "source": "starlight_mod",
 "replaced": false, "warnings": [], "errors": []}
```

A failed registration is atomic:

```gdscript
{"ok": false, "id": "...", "source": "...", "replaced": false,
 "warnings": [], "errors": ["preferences.intensity: expected one of soft, firm, rough"]}
```

Unknown top-level keys and unknown values inside lists are warnings. Wrong types, unknown enum
values, a reserved id, a missing `id` or `source`, and non-positive placement scales are errors.

### Descriptor fields

| Key | Required | Meaning |
|---|---|---|
| `schema` | no, default `1` | Descriptor shape. A newer schema is rejected by an older build. |
| `id` | yes | Stable identity/relationship id. Not `default` or `anon`; at most 64 characters; no `.` or `:`. |
| `source` | yes | Provider mod id, for logs and `sources`. |
| `name` | no | Settings label and `describe_mare().name` for an off-roster mare. A base-game name always wins. |
| `preferences` | no | `preferences.gd` profile fields: `intensity`, `pattern`, `touch`, `dislikes`, `talk`, `warmth`, `tolerance`, `notes`. |
| `consent` | no | `public`, `anal`, `oral` booleans. Missing keys use the existing deterministic id defaults. |
| `placement` | no | Any subset of `offset_x`, `offset_y`, `offset_z`, `pitch_deg`, `scale`, `tail_y`, `tail_z`, `dock_y`, `dock_scale`, `tail_tilt_deg`. |
| `poses` | no | Partial per-pose blocks, merged over `poses/catalog.gd` defaults. |
| `act_prompts` | no | `cue` and `utterance` prompt overrides. |
| `event_prompts` | no | `climax` and `end_early` prompt overrides. |
| `cue_gap` | no | Seconds; the existing 8–30 s clamp applies when read. |
| `aftercare_min` | no | Readiness threshold; the existing 0–100 clamp applies when read. |
| `smack_zone_radius` | no | Smack target radius in metres. |

Provider data is never written to `settings.json`. It is an in-memory layer. The player's saved
character block and placement override always win.

Registration is metadata only. It does not make a pony adult, spawn her, grant a relationship or
start an act; the game's identity and relationship runtime still decide all of that. A custom
mare still needs the game's pony locomotion and hybrid rig, a stable id, `pony_hips`,
`MareBody`, and a hair skeleton plus `OpenPonyDock` for tail seating.

## Base-game mares

A provider pack may register a base-game id to update defaults for everyone:

```gdscript
api.register_mare(self, {
	"id": "fluttershy",
	"source": "softer_fluttershy",
	"preferences": {"intensity": "soft", "notes": "Quieter and more hesitant."},
})
```

The built-in display name still wins, and the provider supplies defaults, not a rename. A player
who edits her profile in the Characters tab keeps their edit; pressing **Reset to default** returns
to the built-in template plus the provider layer.

This works because saved character blocks hold only real differences from the shipped template.
An older settings file that contains a full copy of a built-in template is reduced to differences
on load. A field that differs from the current built-in is kept as a player pin: it may be a
genuine edit or an old template, and preserving it is safer.

## Precedence

| Data | Resolution order |
|---|---|
| Preferences, consent, poses, prompts, timing | player differences → provider layers (registration order) → built-in template → global default |
| Placement | player `anatomy.placement.<id>` → provider placement → shipped `MARE_DEFAULTS` → global default |
| Display name | built-in name → provider name → humanized id |

Provider layers stack in registration order: a later provider wins per field. Removing a layer
reveals the one beneath it. Unregistering the last layer restores the built-in/global values.

## `describe_mare`

`describe_mare(id)` returns the full resolved static description. It always returns a complete
dictionary, including for an unknown id.

```gdscript
{
	"schema": 1,
	"id": "fluttershy",
	"name": "Fluttershy",
	"known": true,          # built-in or registered
	"registered": false,    # at least one provider registered her
	"sources": [],          # provider mod ids, in resolution order

	"preferences": { ... }, # resolved, player override applied
	"consent": {"public": false, "anal": true, "oral": true},
	"placement": { ... },   # all ten keys, player override applied
	"poses": {"missionary": { ... }, "standing": { ... }},
	"act_prompts": { ... }, # resolved built-ins plus overrides
	"event_prompts": { ... },
	"cue_gap": 12.0,        # effective value, existing clamp applied
	"aftercare_min": 10,    # effective value
	"smack_zone_radius": 0.035,
}
```

It excludes live state: satisfaction, act history, relationship, estrus phase, lover bond, the
current act and anatomy attachment. Use it on demand, not every frame; it resolves prompts and
pose settings.

Every returned dictionary and array is a deep copy. Mutating it cannot change unfplap's state.

## Player overrides

Provider layers are defaults. The player's saved data remains authoritative:

- `characters.<id>` stores only the preference and consent keys that differ from the resolved
  default;
- `anatomy.placement.<id>` stores only placement keys that differ from the resolved default;
- **Reset to default** in the Characters form returns to the built-in template plus the provider
  layer;
- removing the provider leaves the player's saved differences in place and simply drops the
  provider layer from resolution.

## Stability and deprecation

- Within API major 1, public methods, return shapes, capability names and descriptor fields are
  never removed or given a new meaning. Additions are allowed.
- A breaking change ships as a new major facade in `unfplap_api_v2`, while `unfplap_api_v1` keeps
  working. The old major stays supported for at least two minor releases of the new major or 180
  days, whichever is longer.
- A deprecated method still works for the life of its major. It warns once and is listed in
  `contract().deprecations` as `{name, since, replacement, remove_in}`.
- A descriptor key is accepted and remapped for the life of the major; it is removed only in the
  next major.
- `docs/api.md` and `tests/test_api.gd` are updated in the same change as any public surface change.
  The test compares the reflected method list against an explicit manifest.

## Version history

| API | Unfplap | Changes |
|---|---|---|
| 1.0 | 0.4.0 (next) | `contract`, `supports`, `register_mare`, `unregister_mare`, `describe_mare`; custom and base-game provider templates. |
