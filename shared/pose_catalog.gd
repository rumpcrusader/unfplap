extends RefCounted
## Pose catalog: stable ids and the per-pose settings schema.
## New poses add an entry here and a controller/recipe; shared runtime should not branch on
## numeric pose indexes. The shipped default values live under `default.poses.<id>` in
## `settings/defaults.json`; `POSE_KEYS` is the schema, not a default.

const DEFAULTS_DATA := preload("res://mods/unfplap/shared/defaults_data.gd")

const MISSIONARY := "missionary"
const STANDING := "standing"
## An internal debug pose: known to the registry and to `every()`, never public.
const STANDING_TEST := "standing_test"
## The internal standing oral pose: a procedural delta on `standing`, reached only by its edge.
const STANDING_ORAL := "standing_oral"

const POSE_KEYS := {
	MISSIONARY: ["nuzzle_scale", "nuzzle_period", "nuzzle_duration"],
	STANDING: [
		"bow", "foreleg", "foreleg_spread", "hind_spread", "chin_up_deg", "neck_down_deg",
		"gaps", "glance_min", "glance_max", "glance_hold", "glance_yaw",
		"glance_back_pitch", "glance_back_chance",
	],
}
const GAP_KEYS := ["same height", "mounting", "canon", "hoers"]


static func all() -> Array:
	return [MISSIONARY, STANDING]


## Every pose the registry knows, public or internal. `all()` stays the public list the API,
## offers and settings use.
static func every() -> Array:
	return [MISSIONARY, STANDING, STANDING_TEST, STANDING_ORAL]


## The shipped defaults for one pose, or `{}` when the pose has none.
static func defaults(id: String) -> Dictionary:
	return DEFAULTS_DATA.block("default.poses." + id)
