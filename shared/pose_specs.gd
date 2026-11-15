extends RefCounted
## The static pose capability table: one row per pose the act can run. Pure data: no service, no
## settings read, no FileAccess and no scene. `poses/registry.gd` validates it and the pose view
## carries the row the session is in. Contract: `docs/poses.md`.
##
## The profile vocabulary is fixed. Add keys, never rename one; `poses/pose_spec.gd` owns the
## required-key list a new profile key must extend.

const MISSIONARY := "missionary"
const STANDING := "standing"

## A pose's own asset is `poses/<id>_pose.json` when the row has no delta; `driver` is the
## procedural recipe, `base` an inherited pose id and `delta` an authored delta asset. `forms`
## are the game's `human`/`pony` identifiers and `views` the `desktop`/`vr` configurations the
## pose is authored for; A0/A1 declare them and the scene gate enforces them in Phase B1.
const SPECS := {
	MISSIONARY: {
		"id": MISSIONARY,
		"display_name": "Missionary",
		"family": "bed",
		"frame": "bed",
		"base": "",
		"delta": "",
		"driver": "poses/missionary_recipe.gd",
		"settings_group": "missionary",
		"game_posture": "stand",
		"drive_policy": "missionary",
		"anon": {"mode": "act_body", "profile": "missionary"},
		"contact": {"kind": "opening", "aim": "part", "trims": "missionary"},
		"camera": {"profile": "missionary_shots", "facing": "anon_eye", "eye": "anon"},
		"hands": {"path": "missionary"},
		"controls": {"set": "missionary"},
		"audio": {"impact": "missionary", "speech": "act"},
		"afterglow": {"profile": "passive", "close_window": false},
		"presentation": {
			"profile": "missionary", "hud_label": "Missionary", "tail": "lay",
			"wings": "stock", "kiss": "missionary", "lean": "missionary",
		},
		"scene": {
			"frame": "bed", "requires_bed": true, "sources": ["bed_side", "already_lying"],
			"managed_bed": true, "stool": false, "standing_free": false,
		},
		"modifiers": {"profile": "missionary"},
		"forms": ["human"],
		"views": ["desktop"],
		"public": true,
		"offerable": true,
	},
	STANDING: {
		"id": STANDING,
		"display_name": "Standing",
		"family": "standing",
		"frame": "ground",
		"base": "",
		"delta": "",
		"driver": "poses/standing_recipe.gd",
		"settings_group": "standing",
		"game_posture": "stand",
		"drive_policy": "standing",
		"anon": {"mode": "player_body", "profile": "standing"},
		"contact": {"kind": "opening", "aim": "part", "trims": "standing"},
		"camera": {"profile": "standing_procedural", "facing": "standing", "eye": "player"},
		"hands": {"path": "standing"},
		"controls": {"set": "standing"},
		"audio": {"impact": "standing", "speech": "act"},
		"afterglow": {"profile": "standing", "close_window": true},
		"presentation": {
			"profile": "standing", "hud_label": "Standing", "tail": "pose",
			"wings": "hold", "kiss": "standing", "lean": "standing",
		},
		"scene": {
			"frame": "ground", "requires_bed": false, "sources": [],
			"managed_bed": false, "stool": true, "standing_free": true,
		},
		"modifiers": {"profile": "standing"},
		"forms": ["human", "pony"],
		"views": ["desktop", "vr"],
		"public": true,
		"offerable": true,
	},
}


## The shipped spec ids, in table order.
static func ids() -> Array[String]:
	return [MISSIONARY, STANDING]


## The raw spec dictionary for `id`, or `{}` when the table has no row.
static func spec(id: String) -> Dictionary:
	return SPECS.get(id, {})