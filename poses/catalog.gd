extends RefCounted
## Pose catalog: stable ids and default per-pose settings.
## New poses add an entry here and a controller/recipe; shared runtime should not branch on
## numeric pose indexes.

const MISSIONARY := "missionary"
const STANDING := "standing"

const POSE_DEFAULTS := {
	MISSIONARY: {
		"nuzzle_scale": 0.45,
		"nuzzle_period": 7.0,
		"nuzzle_duration": 2.4,
	},
	STANDING: {
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
	},
}


static func all() -> Array:
	return [MISSIONARY, STANDING]


static func defaults(id: String) -> Dictionary:
	var value: Variant = POSE_DEFAULTS.get(id, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}
