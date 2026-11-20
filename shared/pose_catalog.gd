extends RefCounted
## Pose catalog: stable ids and the per-pose settings schema.
## New poses add an entry here and a controller/recipe; shared runtime should not branch on
## numeric pose indexes. `POSE_KEYS` only describes the schema; the default values ship in the
## defaults document.

const DEFAULTS_DATA := preload("res://mods/unfplap/shared/defaults_data.gd")

const MISSIONARY := "missionary"
const STANDING := "standing"
## An internal debug pose: known to the registry and to `every()`, never public.
const STANDING_TEST := "standing_test"
## The internal standing oral pose: a procedural delta on `standing`, reached only by its edge.
const STANDING_ORAL := "standing_oral"
## The internal bed face-sit: its own authored bed asset, reached only by the debug pair edge.
const BED_FACESIT := "bed_facesit"

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
	return [MISSIONARY, STANDING, STANDING_TEST, STANDING_ORAL, BED_FACESIT]


## The shipped defaults for one pose, or `{}` when the pose has none.
static func defaults(id: String) -> Dictionary:
	return DEFAULTS_DATA.block("default.poses." + id)
