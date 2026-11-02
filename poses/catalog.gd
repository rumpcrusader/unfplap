extends RefCounted
## Pose catalog: stable ids, legacy indexes and default per-pose settings.
## New poses add an entry here and a controller/recipe; shared runtime should not branch on
## numeric pose indexes.

const MISSIONARY := "missionary"
const HORSE := "horse"

## Legacy indexes are kept only for logs/debug output:
##   Pose 1 = missionary
##   Pose 2 = horse
const LEGACY := {
	MISSIONARY: 1,
	HORSE: 2,
}

const BY_LEGACY := {
	1: MISSIONARY,
	2: HORSE,
}

const POSE_DEFAULTS := {
	MISSIONARY: {
		"hind_spread": 0.42,
		"rump_drop_deg": 35.0,
		"head_roll": 0.0,
		"roll_tweak": 0.0,
		"camera_height": 0.45,
		"camera_forward": 0.22,
		"look_scale": 0.55,
		"nuzzle_scale": 0.45,
		"nuzzle_period": 7.0,
		"nuzzle_duration": 2.4,
		"tail_lift": 0.42,
	},
	HORSE: {
		"bow": 2.4,
		"foreleg": 2.0,
		"foreleg_spread": 0.172,
		"hind_spread": 0.32,
		"chin_up_deg": 30.0,
		"neck_down_deg": 15.0,
		"gaps": {
			"same height": 0.55,
			"mounting": 0.45,
			"canon": 0.25,
			"hoers": 0.55,
		},
		"glance_min": 5.0,
		"glance_max": 9.0,
		"glance_hold": 1.8,
		"glance_yaw": 3.0,
		"glance_back_pitch": 1.2,
		"glance_back_chance": 0.5,
		"tail_aside": 0.55,
		"tail_lift": 0.42,
	},
}


static func all() -> Array:
	return [MISSIONARY, HORSE]


static func legacy_index(id: String) -> int:
	return int(LEGACY.get(id, 0))


static func from_legacy(index: int) -> String:
	return str(BY_LEGACY.get(index, ""))


static func defaults(id: String) -> Dictionary:
	var value: Variant = POSE_DEFAULTS.get(id, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}
