# Cross-mod API

This is the contract between unfplap and other Home: Equestria mods.

`api.gd` is the **only** unfplap script another mod should ever call. Every other script, service
facade, runtime node or signal should be treated as private: unfplap gives no guarantees about the
stability of any other surface except `api.gd`. The facade is main-thread only.

## Discovery

The facade is a Node in two groups. `Mods.on_node` finds it whether it already exists or appears
later, so load order does not matter. Unfplap's switch-off removes every layer it holds; when it
returns, `Mods.on_node` fires again, so register there.

| Group | Meaning |
|---|---|
| `unfplap_api` | The current API major. |
| `unfplap_api_v1` | Pinned major 1. Long-lived mods should use this. |

```gdscript
extends Node

func _ready() -> void:
	Mods.on_node("group:unfplap_api_v1", _on_unfplap)

func _on_unfplap(api: Node) -> void:
	if not api.supports("registry.mare"):
		push_warning("this version of unfplap doesn't support 'registry.mare'")
		return
	api.register_mare(self, {
		"id": "milky_way",
		"source": "milky_way_mod",
		"name": "Milky Way",
	})
```

## Contract

`api.contract()` returns the version surface: the provider, the API and mod versions, the schemas,
the capabilities and the deprecations. It is plain data and may be cached for the process lifetime.
`api.supports(capability, min_version := 1)` returns true when this build has the capability at
least at that version; an unknown capability is false. A capability's version rises when the
surface it covers grows: `supports("registry.mare", 2)` asks whether the descriptor accepts a newer
schema. `deprecations` lists any method a consumer should replace; it is empty in 1.4.

`schemas.mare` is the descriptor shape. A descriptor's `schema` must not exceed it; a schema this
build does not understand is rejected. `schemas.act_progress` and `schemas.act_result` are the two
signal payloads; each payload's `schema` is its version.

| Capability | Covers |
|---|---|
| `registry.mare` | `register_mare`, `unregister_mare` |
| `mare.read` | `describe_mare` |
| `profile.mare` | the `eligible` and `profile` descriptor keys and the matching `describe_mare` fields |
| `act.progress` | the `act_progress` signal and its payload |
| `act.result` | the `act_result` signal and its payload |

```gdscript
{
	"provider": "unfplap",
	"api_version": "1.4",
	"api_major": 1,
	"api_minor": 4,
	"mod_version": "<unfplap version>",
	"game_version": "<game version>",
	"schemas": {
		"mare": 1,
		"act_progress": 1,
		"act_result": 1,
	},
	"capabilities": {
		"registry.mare": 1,
		"mare.read": 1,
		"profile.mare": 1,
		"act.progress": 1,
		"act.result": 1,
	},
	"deprecations": [],
}
```

## Compatibility

Within major 1, the methods, return shapes, capability names, descriptor keys and signal payloads
are stable; additions are allowed.

A change that breaks a method, a return shape, a capability name, a descriptor key or a signal
payload ships as a new major facade (`unfplap_api_v2`), while `unfplap_api_v1` keeps working. The
previous major is supported indefinitely. A major two or more behind the current major may be
removed without notice.

## Methods

### register_mare

Registers or replaces one owner's template. `owner` must be a Node inside the scene tree, normally
the caller's entry Node; the registration lives while that Node is in the tree. Re-registering the
same owner and id replaces that layer in place, so it can refresh its data without changing
precedence. A registration made during an act updates `describe_mare` and the live anatomy at once
and reaches her next act; the running act keeps the preferences, cue gap, aftercare threshold and
smack radius it started with.

`act_prompts` and `event_prompts` are not descriptor keys; either one registers with an
`unknown key` warning and changes no resolved value.

Descriptor:

| Key | Meaning |
|---|---|
| `schema` | Descriptor shape; must not exceed `schemas.mare`. |
| `id` | Required. Stable identity/relationship id; `default` and `anon` are reserved. |
| `source` | Required. Provider mod id, for logs and `sources`. |
| `name` | Settings label and `describe_mare().name` for an off-roster mare; a base-game name always wins. |
| `preferences` | How she likes the act: her intensity and pattern, the touch and talk she likes or dislikes, how fast she warms, how much neglect she tolerates, her notes and her teat size. Values and enum lists are in `shared/preferences.gd`. |
| `consent` | What she consents to; a missing key takes the deterministic id default. Public consent is a soft Context preference, not an offer or act gate. `docs/eligibility.md` owns the rules. |
| `eligible` | Provider-only tri-state: true or false asserts her age, absent lets the game's identity decide. Never written to the player's files. `docs/eligibility.md` owns what it changes. |
| `profile` | The participation block; a missing key means true. Subtractive: true means "does not veto", never "grants". `docs/eligibility.md` owns the rules. |
| `placement` | Where her anatomy and tail sit on her body: any subset of the placement offsets, rotations and scales. |
| `poses` | Per-pose overrides, merged over the shipped pose defaults. Only public poses are accepted. |
| `cue_gap` | Seconds between her cue lines; clamped to the cue band when read (`docs/dialogue.md`). |
| `aftercare_min` | Readiness threshold for aftercare; clamped to the satisfaction range when read (`docs/readiness.md`). |
| `smack_zone_radius` | Smack target radius in metres; clamped non-negative when read (`docs/hands.md`). |

```gdscript
var result: Dictionary = api.register_mare(self, {
	"id": "milky_way",
	"source": "milky_way_mod",
	"name": "Milky Way",
	"preferences": {
		"intensity": "firm",
		"touch": ["caress", "kiss"],
	},
	"consent": {
		"public": false,
		"anal": true,
		"oral": true,
	},
	"eligible": true,
	"profile": {
		"participation": {
			"acts": true,
		},
	},
	"placement": {
		"tail_tilt_deg": 4.0,
	},
	"poses": {
		"missionary": {
			"nuzzle_scale": 0.5,
		},
	},
	"cue_gap": 12.0,
})
```

Result:

| Key | Meaning |
|---|---|
| `ok` | Whether the layer was written. |
| `id` | The trimmed id the call used. |
| `source` | The trimmed provider id. |
| `replaced` | True when this owner already had a layer for the id. |
| `warnings` | Unknown keys and unknown list values; they still register. |
| `errors` | Every fault. |

```gdscript
{
	"ok": true,
	"id": "milky_way",
	"source": "milky_way_mod",
	"replaced": false,
	"warnings": [],
	"errors": [],
}
```

A failure carries the same keys with `ok: false` and the reason in `errors`, such as
`preferences.intensity: expected one of soft, firm, rough`. Unknown keys at any level and unknown
list values are warnings. Wrong types, unknown enum values, an unsupported `schema`, a missing or
reserved `id`, a missing `source`, a non-finite number, and a non-positive placement scale are
errors. A registration with errors writes nothing; warnings still register. `docs/registry.md` owns
the layer and validation rules.

Registration is metadata only: it does not spawn a pony, grant a relationship or start an act. A
provider's `eligible` assertion changes unfplap's own view of her age, not the base game's identity;
the base game's own gates still apply. A custom mare still needs the game's pony locomotion and
hybrid rig, a stable id, `pony_hips`, `MareBody`, and a hair skeleton plus `OpenPonyDock` for tail
seating.

A provider pack may register a base-game id to update defaults for everyone:

```gdscript
api.register_mare(self, {
	"id": "fluttershy",
	"source": "softer_fluttershy",
	"preferences": {
		"intensity": "soft",
		"notes": "Quieter and more hesitant.",
	},
})
```

The built-in display name still wins; the provider supplies defaults, not a rename. **Reset to
default** restores her preferences and participation to the shipped profile plus the provider
layer, and leaves consent, poses and timing alone (`docs/settings.md`).

Provider layers stack in registration order, and a later provider wins per field. Removing a layer
reveals the one beneath it; unregistering the last restores the shipped and global values. The
player's saved data outranks every provider layer and stays when a provider leaves, so a removal
returns her to her player-edited state. `eligible` is provider-only and never a player value, and a
built-in display name beats a provider's, which beats a humanized id (`docs/registry.md`,
`docs/eligibility.md`).

### unregister_mare

Removes one layer this owner registered.

| Key | Meaning |
|---|---|
| `ok` | False only for an invalid owner. |
| `id` | The trimmed id the call used. |
| `removed` | False when this owner had no layer for the id. |
| `errors` | Present on an invalid owner. |

```gdscript
var result: Dictionary = api.unregister_mare(self, "milky_way")
```

### describe_mare

Returns the full resolved static description for one id, always complete, including for an unknown
id. It resolves the profile chain and the pose settings, so it is for on-demand reads rather than
every frame. `poses` is only the public/offerable poses; internal poses never appear. Live state
stays out: satisfaction, act history, relationship, estrus phase, the current act and anatomy
attachment. Every returned dictionary and array is a deep copy; mutating it cannot change unfplap's
state.

| Key | Meaning |
|---|---|
| `schema` | Description shape. |
| `id` | The trimmed id the call used. |
| `name` | The resolved display name. |
| `known` | Built-in or registered. |
| `registered` | At least one provider layer. |
| `sources` | Provider mod ids, in resolution order, one per source. |
| `preferences` | Resolved, with the player's override applied. |
| `consent` | Resolved, with the deterministic id defaults where no layer. |
| `eligible` | The provider's tri-state assertion; null lets the identity decide. |
| `profile` | The resolved participation block. |
| `placement` | Every placement value, with the player's override applied. |
| `poses` | The public poses and their resolved values. |
| `cue_gap` | The effective cue gap, clamped. |
| `aftercare_min` | The effective aftercare threshold, clamped. |
| `smack_zone_radius` | The effective radius, non-negative. |

```gdscript
{
	"schema": 1,
	"id": "fluttershy",
	"name": "Fluttershy",
	"known": true,
	"registered": false,
	"sources": [],
	"preferences": { ... },
	"consent": { ... },
	"eligible": null,
	"profile": {
		"participation": {
			"acts": true,
			"anatomy": true,
			"tail": true,  # deprecated; accepted for the frozen shape, gates nothing
		},
	},
	"placement": { ... },
	"poses": {
		"missionary": { ... },
		"standing": { ... },
	},
	"cue_gap": 12.0,
	"aftercare_min": 10,
	"smack_zone_radius": 0.035,
}
```

## Signals

The two act signals are the whole act surface: no call starts, reads or replays an act. Subscribe
after `Mods.on_node`.

Both signals deliver at the end of the frame and carry their own deep copy, so a consumer callback
never re-enters the act's tick, pose write or exit and cannot change unfplap's state. Unfplap
stores no result for replay, so a subscriber that arrives mid-act sees only the changes that
follow.

The payload is mechanical: ids, pose, counters, duration and outcome. It never carries her
thought, wants, line text, cues or satisfaction; resolve a name from `pony_id` or `form_id` through
the registry or `describe_mare`.

### act_progress

One live snapshot per change, at most once per physics frame. The same `act_id` identifies one act
from its first progress update to its one result; there is no other correlation key. An update is
emitted only when `state`, `mood`, `climaxes.current`, `heat`, `pose` or `form_id` differs from the
last emission; `duration_s` is a snapshot, not a reason to emit.
`POSING_IN` reports the start pose building; `ACTIVE`, `CLIMAX` and `AFTERGLOW` follow the act;
`RESTORE` is the teardown and one `IDLE` closes it. Nothing is emitted for a fixed climax limit,
while a body swap suspends the act, during the after-act satisfaction decay, or after the runtime
leaves the world.

| Key | Meaning |
|---|---|
| `schema` | Payload version. |
| `act_id` | The act serial. |
| `state` | `POSING_IN`, `ACTIVE`, `CLIMAX`, `AFTERGLOW`, `RESTORE` or `IDLE`. |
| `pony_id` | Her stable identity. |
| `form_id` | The presented form: her own reads as `pony_id`, a borrowed one as the provider's id. |
| `pose` | The running pose id; empty on the final `IDLE`. |
| `duration_s` | Elapsed seconds at emission. |
| `mood` | Her readiness mood: `warming`, `wanting`, `close`, `climax` or `overwhelmed`. |
| `climaxes` | The climax count and cap; zero means no cap. |
| `heat` | Whether the estrus cycle has her in heat. |

```json
{
	"schema": 1,
	"act_id": 12,
	"state": "ACTIVE",
	"pony_id": "chrysalis",
	"form_id": "fluttershy",
	"pose": "missionary",
	"duration_s": 63.4,
	"mood": "close",
	"climaxes": {
		"current": 1,
		"limit": 2
	},
	"heat": false
}
```

### act_result

One result is emitted per act where the summary is committed: the normal afterglow end, an early
end, or a partner stop. A forced stop, a failed start, a world close, and an early end the summary
skips emit nothing. `forms` is the literal sequence of presented forms, repeats included:
an ordinary mare is `["fluttershy"]`, own → Fluttershy → own → Rarity is
`["chrysalis", "fluttershy", "chrysalis", "rarity"]`, and a disguised start that reveals is
`["fluttershy", "chrysalis"]`. `form_id` is the current form at the commit, so it repeats the last
entry, and a new act starts a new sequence. `outcome.romance` is what the summary writes;
`outcome.mood` is her lasting impression. There is no separate `early`, `stopped` or `severe` key:
infer `early` from `ended_early` in `stop_reasons`, `stopped` from `stopped_by_her`, and `severe`
from a `bad` grade with an `annoyed` or `angry` mood. `docs/summary.md` owns the grade and the
reasons.

| Key | Meaning |
|---|---|
| `schema` | Payload version. |
| `act_id` | The act serial, shared with its progress updates. |
| `pony_id` | Her stable identity. |
| `form_id` | The presented form at the commit. |
| `forms` | The forms she presented, in order, from the form at act start to the commit; her own reads as `pony_id`. |
| `pose` | The pose the act ran. |
| `duration_s` | Elapsed seconds at the commit. |
| `thrusts` | Her real inward strokes. |
| `climaxes` | The climax count and cap at the commit. |
| `grade` | `great`, `good`, `neutral` or `bad`. |
| `stop_reasons` | The summary's reason codes; empty on a clean act. |
| `outcome` | The romance written and her lasting mood: `happy`, `relaxed`, `sad`, `annoyed` or `angry`. |

```json
{
	"schema": 1,
	"act_id": 12,
	"pony_id": "chrysalis",
	"form_id": "chrysalis",
	"forms": ["chrysalis", "fluttershy", "chrysalis"],
	"pose": "missionary",
	"duration_s": 186.4,
	"thrusts": 143,
	"climaxes": {
		"current": 2,
		"limit": 0
	},
	"grade": "great",
	"stop_reasons": [],
	"outcome": {
		"romance": 2,
		"mood": "happy"
	}
}
```
