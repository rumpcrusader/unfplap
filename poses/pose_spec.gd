extends RefCounted
## The typed pose spec: one validated wrapper per `shared/pose_specs.gd` row. Private to `poses/`;
## the registry caches one per id and the pose view carries the fields. It never reads settings,
## files or the scene. Contract: `docs/poses.md`.

const SELF := preload("res://mods/unfplap/poses/pose_spec.gd")
const POSE_SPECS := preload("res://mods/unfplap/shared/pose_specs.gd")

const ID_PATTERN := "^[a-z][a-z0-9_]*$"
const FAMILIES := ["bed", "standing"]
const FRAMES := ["bed", "ground"]
const SETTINGS_GROUPS := ["missionary", "standing"]
const FORMS := ["human", "pony"]
const VIEWS := ["desktop", "vr"]

## The required keys of every profile dictionary. A new profile key is additive: add it to the
## owner's row and here together.
const REQUIRED_PROFILES := {
	"anon": ["mode", "profile"],
	"contact": ["kind", "aim", "trims"],
	"camera": ["profile", "facing", "eye"],
	"hands": ["path"],
	"controls": ["set"],
	"audio": ["impact", "speech"],
	"afterglow": ["profile", "close_window"],
	"presentation": ["profile", "hud_label", "tail", "wings", "kiss", "lean"],
	"scene": ["frame", "requires_bed", "sources", "managed_bed", "stool", "standing_free"],
	"modifiers": ["profile"],
}

var id := ""
var display_name := ""
var family := ""
var frame := ""
var base := ""
var asset := ""
var delta := ""
var driver := ""
var settings_group := ""
var game_posture := ""
var drive_policy := ""
var start_setup := ""
var anon: Dictionary = {}
var contact: Dictionary = {}
var camera: Dictionary = {}
var hands: Dictionary = {}
var controls: Dictionary = {}
var audio: Dictionary = {}
var afterglow: Dictionary = {}
var presentation: Dictionary = {}
var scene: Dictionary = {}
var modifiers: Dictionary = {}
var forms: Array[String] = []
var views: Array[String] = []
var public_pose := false
var offerable := false


## A filled wrapper, or null when `errors()` is non-empty. The registry logs the errors.
static func from_dict(spec_id: String, data: Dictionary, table: Dictionary = {}) -> Variant:
	var found := errors(spec_id, data, table)
	if not found.is_empty():
		return null
	var spec: Variant = SELF.new()
	spec._fill(spec_id, data)
	return spec


## The shared validator: the registry and the suites both call this one. `table` is the raw
## id -> row table; an empty table skips the base row, family and cycle checks.
static func errors(spec_id: String, data: Dictionary, table: Dictionary = {}) -> Array[String]:
	var out: Array[String] = []
	var pattern := RegEx.new()
	pattern.compile(ID_PATTERN)
	if pattern.search(spec_id) == null:
		out.append("id %s is not lower_snake_case" % spec_id)
	if str(data.get("id", "")) != spec_id:
		out.append("id field %s does not match %s" % [str(data.get("id", "")), spec_id])
	if str(data.get("display_name", "")).is_empty():
		out.append("display_name is empty")
	_check_choice(out, data, "family", FAMILIES)
	_check_choice(out, data, "frame", FRAMES)
	_check_choice(out, data, "settings_group", SETTINGS_GROUPS)
	for name: String in ["game_posture", "drive_policy"]:
		if str(data.get(name, "")).is_empty():
			out.append("%s is empty" % name)
	_check_base(out, spec_id, data, table)
	_check_asset(out, data)
	_check_list(out, data, "forms", FORMS)
	_check_list(out, data, "views", VIEWS)
	var is_public: Variant = data.get("public")
	var is_offerable: Variant = data.get("offerable")
	if not (is_public is bool):
		out.append("public is not a boolean")
	if not (is_offerable is bool):
		out.append("offerable is not a boolean")
	if is_public is bool and is_offerable is bool and is_offerable and not is_public:
		out.append("offerable is true without public")
	for name: String in REQUIRED_PROFILES.keys():
		var profile: Variant = data.get(name)
		if not (profile is Dictionary):
			out.append("%s is not a dictionary" % name)
			continue
		for key: String in REQUIRED_PROFILES[name]:
			if not (profile as Dictionary).has(key):
				out.append("%s.%s is missing" % [name, key])
	var afterglow: Variant = data.get("afterglow")
	if afterglow is Dictionary and (afterglow as Dictionary).has("close_window") \
			and not ((afterglow as Dictionary)["close_window"] is bool):
		out.append("afterglow.close_window is not a boolean")
	_check_scene(out, data.get("scene"))
	_check_start(out, data.get("start"))
	return out


static func _check_choice(out: Array[String], data: Dictionary, key: String, known: Array) -> void:
	var value: Variant = data.get(key)
	if not (value is String) or not (value in known):
		out.append("%s %s is unknown" % [key, str(value)])


## A row needs a driver unless it inherits an authored base; that base must differ from the row and,
## given a table, exist in the same family and reach the row without a cycle.
static func _check_base(out: Array[String], spec_id: String, data: Dictionary,
		table: Dictionary) -> void:
	var base := str(data.get("base", ""))
	var driver := str(data.get("driver", ""))
	if driver.is_empty() and base.is_empty():
		out.append("driver and base are both empty")
	if base.is_empty():
		return
	if base == spec_id:
		out.append("base %s is the row itself" % base)
		return
	if table.is_empty():
		return
	var family := str(data.get("family", ""))
	var seen: Dictionary = {spec_id: true}
	var cursor := base
	while not cursor.is_empty():
		if seen.has(cursor):
			out.append("base chain revisits %s" % cursor)
			return
		seen[cursor] = true
		var row: Variant = table.get(cursor)
		if not (row is Dictionary):
			out.append("base %s has no spec row" % cursor)
			return
		if str((row as Dictionary).get("family", "")) != family:
			out.append("base %s is in another family" % cursor)
			return
		cursor = str((row as Dictionary).get("base", ""))


## A pose asset is a `poses/`-relative JSON document. The shape is checked here; whether the file
## exists is the loader's job (and the scene gate's `pose_asset` row).
static func _check_asset(out: Array[String], data: Dictionary) -> void:
	var value: Variant = data.get("asset", "")
	if not (value is String):
		out.append("asset is not a string")
		return
	var path := str(value)
	if path.is_empty():
		return
	if not path.begins_with("poses/") or not path.ends_with(".json") \
			or path.contains("..") or path.contains("\\"):
		out.append("asset %s is not a poses/*.json path" % path)


static func _check_list(out: Array[String], data: Dictionary, key: String, known: Array) -> void:
	var value: Variant = data.get(key)
	if not (value is Array):
		out.append("%s is not an array" % key)
		return
	var seen: Dictionary = {}
	for item: Variant in value:
		if not (item is String) or not (item in known):
			out.append("%s has an unknown entry %s" % [key, str(item)])
			continue
		if seen.has(item):
			out.append("%s repeats %s" % [key, str(item)])
		seen[item] = true
	if (value as Array).is_empty():
		out.append("%s is empty" % key)


## The act-start block: `setup` is required and closed; extra keys are additive.
static func _check_start(out: Array[String], value: Variant) -> void:
	if not (value is Dictionary):
		out.append("start is not a dictionary")
		return
	var block: Dictionary = value
	_check_choice(out, block, "setup", POSE_SPECS.START_SETUPS)


static func _check_scene(out: Array[String], value: Variant) -> void:
	if not (value is Dictionary):
		out.append("scene is not a dictionary")
		return
	var scene: Dictionary = value
	if not (str(scene.get("frame", "")) in FRAMES):
		out.append("scene.frame %s is unknown" % str(scene.get("frame", "")))
	for key: String in ["requires_bed", "managed_bed", "stool", "standing_free"]:
		if not (scene.get(key) is bool):
			out.append("scene.%s is not a boolean" % key)
	var sources: Variant = scene.get("sources")
	if not (sources is Array):
		out.append("scene.sources is not an array")
		return
	for item: Variant in sources:
		if not (item is String):
			out.append("scene.sources has a non-string entry")
			return


func _fill(spec_id: String, data: Dictionary) -> void:
	id = spec_id
	display_name = str(data.get("display_name", ""))
	family = str(data.get("family", ""))
	frame = str(data.get("frame", ""))
	base = str(data.get("base", ""))
	asset = str(data.get("asset", ""))
	delta = str(data.get("delta", ""))
	driver = str(data.get("driver", ""))
	settings_group = str(data.get("settings_group", ""))
	game_posture = str(data.get("game_posture", ""))
	drive_policy = str(data.get("drive_policy", ""))
	var start: Dictionary = data.get("start", {})
	start_setup = str(start.get("setup", ""))
	anon = data.get("anon", {})
	contact = data.get("contact", {})
	camera = data.get("camera", {})
	hands = data.get("hands", {})
	controls = data.get("controls", {})
	audio = data.get("audio", {})
	afterglow = data.get("afterglow", {})
	presentation = data.get("presentation", {})
	scene = data.get("scene", {})
	modifiers = data.get("modifiers", {})
	forms.assign(data.get("forms", []))
	views.assign(data.get("views", []))
	public_pose = bool(data.get("public", false))
	offerable = bool(data.get("offerable", false))