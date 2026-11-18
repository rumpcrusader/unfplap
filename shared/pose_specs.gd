extends RefCounted
## The static pose capability table: one row per pose the act can run. Pure data: no service, no
## settings read, no FileAccess and no scene. `poses/registry.gd` validates it and the pose view
## carries the row the session is in. Contract: `docs/poses.md`.
##
## The profile vocabulary is fixed. Add keys, never rename one; `poses/pose_spec.gd` owns the
## required-key list a new profile key must extend.

const ACT_COMMANDS := preload("res://mods/unfplap/shared/act_commands.gd")

const MISSIONARY := "missionary"
const STANDING := "standing"
## An internal debug pose: it inherits `standing`'s geometry, driver and profiles, and is not a
## public pose, an offer or a settings template. `CATALOG.every()` alone carries it.
const STANDING_TEST := "standing_test"
## The standing oral pose: an internal procedural delta on `standing`. It is reached only by the
## authored oral edges, is not an offer and has no settings template of its own.
const STANDING_ORAL := "standing_oral"
## The internal bed face-sit: its own authored bed asset, reached only by the debug pair edge. It
## shares the missionary settings block and has no row of its own.
const BED_FACESIT := "bed_facesit"

## The closed act-start vocabulary. `mode` says whether the act key is required; `setup` names the
## runtime placement adapter. The start sequence dispatches on `setup`, never on a pose id.
const START_MODES := ["key", "auto"]
const START_SETUPS := ["bed_stand_up", "bed_keep_lying", "standing_place"]

## `asset` is the row's authored pose document under `poses/`; a base chain supplies it to an
## internal row. `driver` is the procedural recipe, `base` an inherited pose id and `delta` an
## authored delta asset. `start` is the act-start contract: every row declares its `mode` and
## `setup`, and the runtime matches that closed vocabulary. `forms` are the game's `human`/`pony`
## identifiers and `views` the `desktop`/`vr` configurations the pose is authored for; A0/A1
## declare them and the scene gate enforces them in Phase B1.
const SPECS := {
	MISSIONARY: {
		"id": MISSIONARY,
		"display_name": "Missionary",
		"family": "bed",
		"frame": "bed",
		"base": "",
		"asset": "poses/missionary_pose.json",
		"delta": "",
		"driver": "poses/missionary_recipe.gd",
		"start": {"mode": "key", "setup": "bed_stand_up"},
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
			"frame": "bed", "requires_bed": true,
			"sources": ["bed_side", "already_lying", "cradle"],
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
		"asset": "poses/standing_pose.json",
		"delta": "",
		"driver": "poses/standing_recipe.gd",
		"start": {"mode": "key", "setup": "standing_place"},
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
	STANDING_TEST: {
		"id": STANDING_TEST,
		"display_name": "Standing test",
		"family": "standing",
		"frame": "ground",
		"base": STANDING,
		"asset": "",
		"delta": "",
		"driver": "",
		"start": {"mode": "key", "setup": "standing_place"},
		"settings_group": "standing",
		"game_posture": "stand",
		"drive_policy": "standing",
		"anon": {"mode": "player_body", "profile": "standing"},
		"contact": {"kind": "opening", "aim": "part", "trims": "standing"},
		"camera": {"profile": "standing_procedural", "facing": "standing", "eye": "player"},
		"hands": {"path": "standing"},
		"controls": {"set": "standing_test"},
		"audio": {"impact": "standing", "speech": "act"},
		"afterglow": {"profile": "standing", "close_window": true},
		"presentation": {
			"profile": "standing_test", "hud_label": "Test", "tail": "pose",
			"wings": "hold", "kiss": "standing", "lean": "standing",
		},
		"scene": {
			"frame": "ground", "requires_bed": false, "sources": [],
			"managed_bed": false, "stool": true, "standing_free": true,
		},
		"modifiers": {"profile": "standing"},
		"forms": ["human", "pony"],
		"views": ["desktop", "vr"],
		"public": false,
		"offerable": false,
	},
	STANDING_ORAL: {
		"id": STANDING_ORAL,
		"display_name": "Standing oral",
		"family": "standing",
		"frame": "ground",
		"base": STANDING,
		"asset": "",
		"delta": "poses/standing_oral_recipe.gd",
		"driver": "",
		"start": {"mode": "key", "setup": "standing_place"},
		"settings_group": "standing",
		"game_posture": "stand",
		"drive_policy": "standing",
		"anon": {"mode": "player_body", "profile": "standing"},
		"contact": {"kind": "mouth", "aim": "part", "trims": "standing"},
		"camera": {"profile": "standing_procedural", "facing": "standing", "eye": "player"},
		"hands": {"path": "oral"},
		"controls": {"set": "standing_oral"},
		"audio": {"impact": "standing", "speech": "oral"},
		"afterglow": {"profile": "passive", "close_window": false},
		"presentation": {
			"profile": "standing_oral", "hud_label": "Oral", "tail": "pose",
			"wings": "hold", "kiss": "standing", "lean": "standing",
		},
		"scene": {
			"frame": "ground", "requires_bed": false, "sources": [],
			"managed_bed": false, "stool": true, "standing_free": true,
		},
		"modifiers": {"profile": "standing"},
		"forms": ["human", "pony"],
		"views": ["desktop", "vr"],
		"public": false,
		"offerable": false,
	},
	BED_FACESIT: {
		"id": BED_FACESIT,
		"display_name": "Face-sit",
		"family": "bed",
		"frame": "bed",
		"base": "",
		"asset": "poses/bed_facesit_pose.json",
		"delta": "",
		"driver": "poses/missionary_recipe.gd",
		"start": {"mode": "key", "setup": "bed_stand_up"},
		"settings_group": "missionary",
		"game_posture": "stand",
		"drive_policy": "missionary",
		"anon": {"mode": "act_body", "profile": "facesit"},
		"contact": {"kind": "face", "aim": "part", "trims": "missionary"},
		"camera": {"profile": "missionary_shots", "facing": "anon_eye", "eye": "anon"},
		"hands": {"path": "missionary"},
		"controls": {"set": "facesit"},
		"audio": {"impact": "missionary", "speech": "act"},
		"afterglow": {"profile": "passive", "close_window": false},
		"presentation": {
			"profile": "missionary", "hud_label": "Face-sit", "tail": "lay",
			"wings": "stock", "kiss": "missionary", "lean": "missionary",
		},
		"scene": {
			"frame": "bed", "requires_bed": true, "sources": [],
			"managed_bed": true, "stool": false, "standing_free": false,
		},
		"modifiers": {"profile": "missionary"},
		"forms": ["human"],
		"views": ["desktop"],
		"public": false,
		"offerable": false,
	},
}


## The modifier owners each authored profile installs. The session keeps the shared owners on a
## pose change, installs the target-only ones and removes the source-only ones. The act-exit
## `leave_pose_body()` still removes every extra modifier.
const MODIFIER_PROFILES := {
	"missionary": ["prone_sway", "tail_lay"],
	"standing": ["body_sway", "ear_twitch", "tail"],
}


## The commands each pose's `controls.set` profile allows. `end` is reserved and always allowed,
## and `request_command()` also allows it before the profile lookup, so an edge lock cannot deny
## it. `pose_back`/`pose_forward` are reserved for pose navigation and no key emits them.
const CONTROL_SETS := {
	MISSIONARY: [
		ACT_COMMANDS.THRUST, ACT_COMMANDS.LEAN, ACT_COMMANDS.CARESS, ACT_COMMANDS.KISS,
		ACT_COMMANDS.HOLE, ACT_COMMANDS.END,
	],
	STANDING: [
		ACT_COMMANDS.THRUST, ACT_COMMANDS.LEAN, ACT_COMMANDS.CARESS, ACT_COMMANDS.KISS,
		ACT_COMMANDS.ORAL, ACT_COMMANDS.HOLE, ACT_COMMANDS.POSE_BACK,
		ACT_COMMANDS.POSE_FORWARD, ACT_COMMANDS.END,
	],
	STANDING_TEST: [ACT_COMMANDS.END],
	STANDING_ORAL: [ACT_COMMANDS.ORAL, ACT_COMMANDS.POSE_BACK, ACT_COMMANDS.END],
	"facesit": [ACT_COMMANDS.THRUST, ACT_COMMANDS.LEAN, ACT_COMMANDS.CARESS,
		ACT_COMMANDS.END],
}


## The scene block a missing or malformed row reads as. The scene gate fails closed by reading
## `frame` empty and every capability false.
const NO_SCENE := {
	"frame": "", "requires_bed": false, "sources": [], "managed_bed": false,
	"stool": false, "standing_free": false,
}


## The start block a missing or malformed row reads as. An empty setup fails the runtime dispatcher
## closed; `mode` claims the act key but never reaches an adapter.
const NO_START := {"mode": "key", "setup": ""}


## The shipped spec ids, in table order.
static func ids() -> Array[String]:
	return [MISSIONARY, STANDING, STANDING_TEST, STANDING_ORAL, BED_FACESIT]


## The raw spec dictionary for `id`, or `{}` when the table has no row.
static func spec(id: String) -> Dictionary:
	return SPECS.get(id, {})


## The scene block for `id`, or the fail-closed default. The returned dictionary is the table's own
## row (or `NO_SCENE`); callers read it and never write it.
static func scene(id: String) -> Dictionary:
	var row: Variant = SPECS.get(id)
	if not row is Dictionary:
		return NO_SCENE
	var block: Variant = (row as Dictionary).get("scene")
	return block if block is Dictionary else NO_SCENE


## The start block for `id`, or the fail-closed default. Callers read it and never write it.
static func start(pose: String) -> Dictionary:
	var row: Variant = SPECS.get(pose)
	if not row is Dictionary:
		return NO_START
	var block: Variant = (row as Dictionary).get("start")
	return block if block is Dictionary else NO_START


## The act-start mode: `key` waits for the act key, `auto` lets a trigger call the start path.
static func start_mode(pose: String) -> String:
	return str(start(pose).get("mode", "key"))


## The runtime setup adapter name. An unknown row returns "" and `start()` aborts.
static func start_setup(pose: String) -> String:
	return str(start(pose).get("setup", ""))


## Whether `id` is a public pose. An internal pose is reachable only through its authored edge.
static func is_public(id: String) -> bool:
	var row: Variant = SPECS.get(id)
	return row is Dictionary and bool((row as Dictionary).get("public", false))


## Whether `id` may be offered by the request service. An offerable pose is always public.
static func is_offerable(id: String) -> bool:
	var row: Variant = SPECS.get(id)
	return row is Dictionary and bool((row as Dictionary).get("offerable", false))


## Whether the pose is authored for the player form (`human`/`pony`) and the live view
## (`desktop`/`vr`). A missing row supports nothing.
static func supports(id: String, form: String, view: String) -> bool:
	var row: Variant = SPECS.get(id)
	if not row is Dictionary:
		return false
	var forms_value: Variant = (row as Dictionary).get("forms")
	var views_value: Variant = (row as Dictionary).get("views")
	return forms_value is Array and form in (forms_value as Array) \
		and views_value is Array and view in (views_value as Array)