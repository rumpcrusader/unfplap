# Cross-mod API

This is the contract between unfplap and other Home: Equestria mods. `api.gd` is the only unfplap
script another mod may call; every other script, service facade and runtime node is private. The
surface is deliberately small: register a character template for a custom or base-game mare, remove
it, and read the static data unfplap resolves for one mare. It does not start acts, spawn ponies,
change relationships, write the player's files, or expose live act state. The facade is
main-thread only.

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
	"api_version": "1.3",
	"api_major": 1,
	"api_minor": 3,
	"mod_version": "<unfplap version>",
	"game_version": "<game version>",
	"schemas": {"mare": 1},
	"capabilities": {
		"registry.mare": 1,
		"mare.read": 1,
		"profile.mare": 1,
	},
	"deprecations": [],
}
```

`contract()` is plain data and may be cached for the process lifetime.
`api.supports(capability, min_version := 1)` returns true when this build has the capability at
least at that version; an unknown capability is false. The script's constants are implementation
details; `contract()` is the version surface.

| Capability | Covers |
|---|---|
| `registry.mare` | `register_mare`, `unregister_mare` |
| `mare.read` | `describe_mare` |
| `profile.mare` | the `eligible` and `profile` descriptor keys and the matching `describe_mare` fields |

`schemas.mare` is the descriptor shape. A descriptor's `schema` must not exceed it; a schema this
build does not understand is rejected.

## Methods

| Method | Returns | Purpose |
|---|---|---|
| `contract()` | `Dictionary` | Version, schemas, capabilities and deprecations. |
| `supports(capability, min_version := 1)` | `bool` | Feature detection. |
| `register_mare(owner, descriptor)` | `Dictionary` | Register or replace one owner's template. |
| `unregister_mare(owner, id)` | `Dictionary` | Remove one owner's template. |
| `describe_mare(id)` | `Dictionary` | Everything static unfplap resolves for one mare. |

## Registering a mare

`register_mare(owner, descriptor)` requires `owner` to be a Node inside the scene tree — normally
the caller's entry Node. The registration lives while that Node is in the tree; switching the
provider mod off removes every layer it registered. Re-registering the same owner + id replaces
that layer in place, so it can refresh its data without changing precedence.

Registration is normally done at startup. A registration made during an act updates
`describe_mare`, her preferences and the live anatomy at once; the act keeps the cue gap, aftercare
threshold and smack radius it started with.

```gdscript
var result: Dictionary = api.register_mare(self, {
	"schema": 1,
	"id": "starlight_glow",
	"source": "starlight_mod",
	"name": "Starlight Glow",
	"preferences": { ... },
	"consent": {"public": false, "anal": true, "oral": true},
	"eligible": true,
	"profile": {"participation": {"acts": true, "anatomy": true, "tail": true}},
	"placement": {"tail_tilt_deg": 4.0, "dock_scale": 0.96},
	"poses": {"missionary": {"nuzzle_scale": 0.5}},
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

`replaced` is true when this owner already had a layer for the id. A failed registration writes
nothing:

```gdscript
{"ok": false, "id": "...", "source": "...", "replaced": false,
 "warnings": [], "errors": ["preferences.intensity: expected one of soft, firm, rough"]}
```

`unregister_mare(owner, id)` returns `{ok, id, removed}`. `removed` is false when this owner had no
layer for the id; an invalid owner returns `ok: false`, `removed: false` and `errors`.

Unknown keys at any level and unknown list values are warnings. Wrong types, unknown enum values,
an unsupported `schema`, a missing or malformed `id`/`source`, a non-finite number, and a
non-positive placement scale are errors. A registration with errors writes nothing; warnings still
register.

### Descriptor fields

| Key | Required | Meaning |
|---|---|---|
| `schema` | no, default `1` | Descriptor shape. A schema this build does not understand is rejected. |
| `id` | yes | Stable identity/relationship id. Not `default` or `anon`; at most 64 characters; no `.` or `:`. |
| `source` | yes | Provider mod id, for logs and `sources`. |
| `name` | no | Settings label and `describe_mare().name` for an off-roster mare. A base-game name always wins. |
| `preferences` | no | Accepted keys: `intensity`, `pattern`, `warmth`, `tolerance`, `teat_size`, `touch`, `talk`, `dislikes`, `notes`. Values and enum lists are in `docs/preferences.md`. |
| `consent` | no | `public`, `anal`, `oral` booleans. Missing keys use the deterministic id defaults. `public` is a soft Context preference; it is not an offer or act gate. `docs/eligibility.md` owns the rules. |
| `eligible` | no | Provider-only tri-state: `true` or `false` asserts the pony's age; absent lets the game's identity decide. It is never written to the player's files. `docs/eligibility.md` owns what it changes. |
| `profile` | no | `participation` with `acts`, `anatomy` and `tail` booleans. Missing keys default to `true`. It is subtractive: `true` means "does not veto", never "grants". `docs/eligibility.md` owns the rules. |
| `placement` | no | Any subset of `offset_x`, `offset_y`, `offset_z`, `pitch_deg`, `scale`, `tail_y`, `tail_z`, `dock_y`, `dock_scale`, `tail_tilt_deg`. |
| `poses` | no | Partial per-pose blocks, merged over `shared/pose_catalog.gd` defaults. Only public poses are accepted. |
| `cue_gap` | no | Seconds; clamped to the cue band when read (`docs/dialogue.md`). |
| `aftercare_min` | no | Readiness threshold; clamped to the satisfaction range when read (`docs/readiness.md`). |
| `smack_zone_radius` | no | Smack target radius in metres; clamped non-negative when read (`docs/hands.md`). |

`act_prompts` and `event_prompts` are not descriptor keys: prompt text is one shipped document with
no per-mare or provider layer (`docs/prompts.md`). A descriptor that sends either key registers
with `ok: true` and one `unknown key` warning per key; the value is never copied into the layer and
changes no resolved value. `describe_mare()` does not return them.

Provider data is an in-memory layer; it is never written to the player's files, and the player's
saved values win (`docs/settings.md`).

Registration is metadata only: it does not spawn a pony, grant a relationship or start an act. A
provider's `eligible` assertion changes unfplap's own view of the pony's age, not the base game's
identity; the base game's own gates still apply. `docs/eligibility.md` owns the full rule. A custom
mare still needs the game's pony locomotion and hybrid rig, a stable id, `pony_hips`, `MareBody`,
and a hair skeleton plus `OpenPonyDock` for tail seating.

## Base-game ids

A provider pack may register a base-game id to update defaults for everyone:

```gdscript
api.register_mare(self, {
	"id": "fluttershy",
	"source": "softer_fluttershy",
	"preferences": {"intensity": "soft", "notes": "Quieter and more hesitant."},
})
```

The built-in display name still wins; the provider supplies defaults, not a rename. A player's
saved edit wins. **Reset to default** restores her preferences and participation to the shipped
profile plus the provider layer; it leaves consent, poses and timing alone. `docs/preferences.md`
owns the Characters form, and `docs/settings.md` owns how the player's differences are stored.

## Resolution

Provider layers apply in this order, highest priority first:

| Data | Resolution order |
|---|---|
| Preferences, poses, timing | player differences → provider layers (registration order) → shipped profile → global default |
| Consent | player differences → provider layers (registration order) → deterministic id defaults |
| `eligible` | provider layers only (never a player value) |
| `profile.participation` | player differences → provider layers (registration order) → shipped default |
| Placement | player `anatomy.placement.<id>` → provider placement → `settings/characters.json` `anatomy.placement.<id>` → global default |
| Display name | built-in name → provider name → humanized id |

Provider layers stack in registration order: a later provider wins per field. Removing a layer
reveals the one beneath it; unregistering the last restores the shipped/global values. The shipped
profile and placement rows live in `settings/characters.json`; `docs/settings.md` owns the
shipped/player split and `docs/preferences.md` owns the profile chain.

Provider layers are defaults; the player's saved data wins. `eligible` is provider-only. Removing
a provider leaves the player's saved differences. `docs/settings.md` owns the player files and the
sparse-difference rule; `docs/preferences.md` owns the Characters form and Reset.

## `describe_mare`

`describe_mare(id)` returns the full resolved static description. It always returns a complete
dictionary, including for an unknown id.

```gdscript
{
	"schema": 1,
	"id": "fluttershy",
	"name": "Fluttershy",
	"known": true,          # built-in or registered
	"registered": false,    # at least one provider layer
	"sources": [],          # provider mod ids, in resolution order, one per source

	"preferences": { ... }, # resolved, player override applied, includes teat_size
	"consent": { ... },     # resolved, deterministic id defaults where no layer
	"eligible": null,       # provider's tri-state assertion; null = the identity decides
	"profile": {"participation": {"acts": true, "anatomy": true, "tail": true}},
	"placement": { ... },   # every placement key, player override applied
	"poses": {"missionary": { ... }, "standing": { ... }},
	"cue_gap": 12.0,        # effective value, clamped
	"aftercare_min": 10,    # effective value, clamped
	"smack_zone_radius": 0.035, # effective value, non-negative
}
```

`poses` is only the public/offerable poses; internal poses never appear. `describe_mare()` excludes
live state: satisfaction, act history, relationship, estrus phase, the current act and anatomy
attachment. It is for on-demand reads, not every frame; it resolves the profile chain and pose
settings. Every returned dictionary and array is a deep copy; mutating it cannot change unfplap's
state. Main thread only.

## Compatibility

Within major 1, the methods, return shapes, capability names and descriptor keys are stable;
additions are allowed. A breaking change ships as a new major facade (`unfplap_api_v2`), while
`unfplap_api_v1` keeps working.

The previous major is supported indefinitely. A major two or more behind the current major may be
removed without notice.

`contract().deprecations` lists any method a consumer should replace; it is empty in 1.3.
