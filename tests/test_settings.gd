extends SceneTree
## The settings API contract, tested once.
##
## The declarations are compile-time: a wrong accessor, a mistyped name or a missing setting fails
## to parse. What stays here is what the compiler cannot see: registry integrity, defaults, the
## file round-trip, coercion and bounds, section state, the panel layout, and the per-mare merge.
##
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_settings.gd

const SETTINGS := preload("res://mods/unfplap/settings.gd")
const SETTINGS_UI := preload("res://mods/unfplap/settings_ui.gd")

var failures := 0
var checks := 0
var original := {}


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func near(a: float, b: float, eps := 0.0001) -> bool:
	return absf(a - b) <= eps


func run() -> void:
	_check_registry()
	_check_defaults()
	_check_placement()
	_check_write_round_trip()
	_check_coercion()
	_check_sections()
	_check_groups()
	_check_panels()
	_check_section_folding()
	_check_migration()
	_check_placement_migration()
	_check_api_names()
	_check_profiles()
	print("SETTINGS_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("SETTINGS_PASS")
	quit(0 if failures == 0 else 1)


## Every declaration is well formed and reachable.
func _check_registry() -> void:
	var all: Array = SETTINGS.all_settings()
	check(all.size() > 100, "every setting is declared")
	var names := {}
	var paths := {}
	var tabs := {}
	var complete := true
	for setting: Variant in all:
		if names.has(setting.name) or paths.has(setting.path):
			complete = false
		names[setting.name] = true
		paths[setting.path] = true
		# An empty group is legal: the setting then has no section heading.
		if str(setting.label).is_empty() or str(setting.help).is_empty():
			complete = false
		if str(setting.tab) not in [SETTINGS.GENERAL, SETTINGS.ANATOMY, SETTINGS.WORLD]:
			complete = false
		tabs[setting.tab] = int(tabs.get(setting.tab, 0)) + 1
	check(complete, "every setting has a unique name and path, a label, help and tab")
	for tab: String in [SETTINGS.GENERAL, SETTINGS.ANATOMY, SETTINGS.WORLD]:
		check(int(tabs.get(tab, 0)) > 0, "%s tab has settings" % tab)
	check(SETTINGS.by_name("hud_readouts") != null, "a setting is reachable by name")
	check(SETTINGS.by_path("features.hud_readouts") != null, "a setting is reachable by path")


## The declared defaults are the values a fresh file would give.
func _check_defaults() -> void:
	check(bool(SETTINGS.hud_readouts.default), "hud readouts default on")
	check(near(float(SETTINGS.pace.default), 1.0), "auto pace default")
	check(str(SETTINGS.orientation.default) == "up", "thrust orientation default")
	check(not bool(SETTINGS.debug_mode.default), "debug mode is off by default")
	check(bool(SETTINGS.radius.debug), "the jiggle radius is a debug setting")
	check(near(float(SETTINGS.pace.low), 1.0) and near(float(SETTINGS.pace.high), 3.75),
		"auto pace keeps its contract bounds")


## Anatomy placement is one default block plus partial per-mare overrides.
func _check_placement() -> void:
	var base := SETTINGS.anatomy_placement_default("")
	check(near(float(base["offset_y"]), 0.525), "placement default Y")
	check(near(float(base["pitch_deg"]), -6.0), "placement default pitch")
	check(near(float(base["scale"]), 0.742), "placement default scale")

	SETTINGS.save_anatomy_placement("fluttershy",
		{"offset_y": 0.51, "offset_z": 0.284, "scale": 0.762})
	var over := SETTINGS.anatomy_placement("fluttershy")
	check(near(float(over["offset_y"]), 0.51), "per-mare override Y")
	check(near(float(over["offset_x"]), 0.0), "an omitted override key falls back")
	check(near(float(over["scale"]), 0.762), "per-mare override scale")
	check(SETTINGS.anatomy_placement_has_override("fluttershy"),
		"a differing per-mare block is an override")
	SETTINGS.save_anatomy_placement("fluttershy", base)
	check(not SETTINGS.anatomy_placement_has_override("fluttershy"),
		"a block equal to the default is not an override")

	SETTINGS.set_anatomy_placement_draft({"offset_y": 0.6, "scale": 0.9})
	check(near(float(SETTINGS.anatomy_placement_default("")["offset_y"]), 0.6),
		"the default draft previews")
	check(near(float(SETTINGS.anatomy_placement_default("", false)["offset_y"]), 0.525),
		"the persisted default stays while previewing")
	SETTINGS.clear_anatomy_placement_draft()
	check(near(float(SETTINGS.anatomy_placement_default("")["offset_y"]), 0.525),
		"clearing the draft restores the default")

	var anon := SETTINGS.anon_placement()
	check(near(float(anon["offset_y"]), 0.74), "anon placement Y")
	check(near(float(anon["scale"]), 0.2), "anon placement scale")


## The old placement files import into the one block and collapse rows equal to the default.
func _check_placement_migration() -> void:
	var folder := "user://mods/data/unfplap"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var mare_path := folder.path_join("anatomy_place.json")
	var anon_path := folder.path_join("anon_place.json")
	var mare := FileAccess.open(mare_path, FileAccess.WRITE)
	mare.store_string(JSON.stringify({"version": 3,
		"fluttershy": {"position": [0.0, 0.51, 0.284], "pitch": 6.0, "scale": 0.762},
		"applejack": {"position": [0.0, 0.525, 0.289], "pitch": -6.0, "scale": 0.742},
		"rainbow_dash": {"position": [0.0, 0.525, 0.289], "pitch": 6.0, "scale": 0.742},
	}, "\t"))
	mare.close()
	var anon := FileAccess.open(anon_path, FileAccess.WRITE)
	anon.store_string(JSON.stringify(
		{"position": [0.1, 0.2, 0.3], "pitch": 1.0, "scale": 0.5}, "\t"))
	anon.close()
	var data := SETTINGS._migrate({}, SETTINGS.SCHEMA_VERSION - 1)
	var placement: Dictionary = (data.get("anatomy", {}) as Dictionary).get("placement", {})
	check(placement.has("fluttershy"), "a differing mare row imports")
	check(not placement.has("applejack"), "a row equal to the default collapses")
	check(placement.has("anon"), "the anon row imports")
	check(near(float((placement["fluttershy"] as Dictionary).get("offset_y", 0.0)), 0.51),
		"the imported mare row keeps its value")
	check(near(float((placement["anon"] as Dictionary).get("scale", 0.0)), 0.5),
		"the imported anon row keeps its value")
	var dash: Dictionary = placement.get("rainbow_dash", {})
	check(dash.size() == 1 and near(float(dash.get("pitch_deg", 0.0)), 6.0),
		"a one-key legacy row stores only that key")
	SETTINGS._finish_legacy_placement_import()
	check(not FileAccess.file_exists(mare_path), "the old mare file is archived")
	check(not FileAccess.file_exists(anon_path), "the old anon file is archived")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(mare_path + ".migrated"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(anon_path + ".migrated"))
	# A current schema still imports a legacy file that appears after the bump.
	var late := FileAccess.open(mare_path, FileAccess.WRITE)
	late.store_string(JSON.stringify({"version": 3, "rarity": {
		"position": [0.0, 0.525, 0.289], "pitch": 6.0, "scale": 0.742}}, "\t"))
	late.close()
	SETTINGS.reload_file()
	SETTINGS.data()
	check(near(float(SETTINGS.anatomy_placement("rarity").get("pitch_deg", 0.0)), 6.0),
		"a current settings file still imports a late legacy placement")
	check(not FileAccess.file_exists(mare_path), "the late legacy file is archived")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(mare_path + ".migrated"))


## A write persists through the file, and the flat cache rebuilds with it.
func _check_write_round_trip() -> void:
	var before := SETTINGS.radius.get_num()
	SETTINGS.radius.set_num(0.31)
	check(near(SETTINGS.radius.get_num(), 0.31), "a write reads back")
	SETTINGS.reload_file()
	check(near(SETTINGS.radius.get_num(), 0.31), "a write survives a reload")
	SETTINGS.radius.set_num(before)
	check(near(SETTINGS.radius.get_num(), before), "the original value is restored")


## Bounds, choices and lists are enforced at the setter, and debug numbers are not clamped.
func _check_coercion() -> void:
	original["pixels"] = SETTINGS.pixels_per_cm.get_num()
	SETTINGS.pixels_per_cm.set_num(5000.0)
	check(near(SETTINGS.pixels_per_cm.get_num(), 400.0), "a player number clamps high")
	SETTINGS.pixels_per_cm.set_num(-5.0)
	check(near(SETTINGS.pixels_per_cm.get_num(), 20.0), "a player number clamps low")
	SETTINGS.pixels_per_cm.set_num(float(original["pixels"]))

	original["radius"] = SETTINGS.radius.get_num()
	SETTINGS.radius.set_num(-5.0)
	check(near(SETTINGS.radius.get_num(), -5.0), "a debug number is never clamped")
	SETTINGS.radius.set_num(float(original["radius"]))

	original["orientation"] = SETTINGS.orientation.get_choice()
	SETTINGS.orientation.set_choice("sideways")
	check(SETTINGS.orientation.get_choice() == str(original["orientation"]),
		"an unknown choice is ignored")
	SETTINGS.orientation.set_choice("down")
	check(SETTINGS.orientation.get_choice() == "down", "a known choice is stored")
	SETTINGS.orientation.set_choice(str(original["orientation"]))

	original["ignore"] = SETTINGS.ignore.get_list()
	SETTINGS.ignore.set_list(["tail", "nonsense"])
	check(SETTINGS.ignore.get_list() == ["tail"], "a list keeps only its options")
	SETTINGS.ignore.set_list(original["ignore"] as Array)

	original["travel"] = SETTINGS.travel.get_num()
	SETTINGS.travel.set_num(NAN)
	check(near(SETTINGS.travel.get_num(), float(SETTINGS.travel.default)),
		"a non-finite number falls back to the default")
	SETTINGS.travel.set_num(float(original["travel"]))


## A section's open state is remembered in the file, per tab.
func _check_sections() -> void:
	var before := SETTINGS.section_open(SETTINGS.GENERAL, "Controls")
	SETTINGS.set_section_open(SETTINGS.GENERAL, "Controls", false)
	check(not SETTINGS.section_open(SETTINGS.GENERAL, "Controls"), "a collapsed section stays closed")
	SETTINGS.set_section_open(SETTINGS.GENERAL, "Controls", before)
	check(SETTINGS.section_open(SETTINGS.GENERAL, "Controls") == before, "section state restores")


## A group needs at least three related settings. Fewer, and the setting belongs directly in the
## tab (or its Debug block) with no heading; a subgroup that small merges into its parent.
func _check_groups() -> void:
	for tab: String in [SETTINGS.GENERAL, SETTINGS.ANATOMY, SETTINGS.WORLD]:
		for debug: bool in [false, true]:
			var sections := {}
			var subs := {}
			for setting: Variant in SETTINGS.tab_settings(tab):
				if bool(setting.hidden) or bool(setting.debug) != debug:
					continue
				var group := str(setting.group)
				if group.is_empty():
					continue
				var parts := group.split("›", true, 1)
				var top := parts[0].strip_edges()
				sections[top] = int(sections.get(top, 0)) + 1
				if parts.size() > 1:
					subs[group] = int(subs.get(group, 0)) + 1
			for name: String in sections:
				check(int(sections[name]) >= 3,
					"%s %s section %s has at least 3 settings (%d)" % [
						tab, "debug" if debug else "player", name, int(sections[name])])
			for name: String in subs:
				check(int(subs[name]) >= 3,
					"%s %s subgroup %s has at least 3 settings (%d)" % [
						tab, "debug" if debug else "player", name, int(subs[name])])


## The panel draws every declaration in its tab, and the Debug block follows debug mode.
func _check_panels() -> void:
	var debug_before := SETTINGS.debug_mode.get_bool()
	SETTINGS.debug_mode.set_bool(false)
	for tab: String in [SETTINGS.GENERAL, SETTINGS.ANATOMY, SETTINGS.WORLD]:
		_check_panel_tab(tab, false)
	SETTINGS.debug_mode.set_bool(true)
	for tab: String in [SETTINGS.GENERAL, SETTINGS.ANATOMY, SETTINGS.WORLD]:
		_check_panel_tab(tab, true)
	SETTINGS.debug_mode.set_bool(debug_before)


## A section heading is drawn once, even when its declarations interleave another group.
func _check_section_folding() -> void:
	var list := VBoxContainer.new()
	SETTINGS_UI._build_sections(list, SETTINGS.GENERAL, "", [
		"presentation.missionary.size.canon.gaze_offset_mm", "camera_thrust.bob",
		"presentation.missionary.camera_mode"], 16, null, Callable())
	var labels: Array = []
	_collect_labels(list, labels)
	check(labels.count("Missionary") == 1, "an interleaved section draws one heading")
	check(labels.has("Gaze height") and labels.has("Camera"),
		"an interleaved section keeps every row")
	check(labels.has("Size"), "the per-size section draws its dropdown")
	check(labels.has("Bob"), "the interleaved section still draws the other group")
	list.free()


func _check_panel_tab(tab: String, debug_on: bool) -> void:
	var list := VBoxContainer.new()
	var owner := Node.new()
	var debug_section: Control = SETTINGS_UI.build(list, tab, 16, null, Callable(), owner)
	var labels: Array = []
	_collect_labels(list, labels)
	var missing: Array = []
	var sections: Array = []
	for setting: Variant in SETTINGS.tab_settings(tab):
		if bool(setting.hidden):
			continue
		if not labels.has(str(setting.label)):
			missing.append(setting.path)
		var heading := str(setting.group).split("›", true, 1)[0].strip_edges()
		if not heading.is_empty() and not sections.has(heading):
			sections.append(heading)
	check(missing.is_empty(), "%s tab draws every setting (%s)" % [tab, str(missing)])
	for heading: String in sections:
		check(labels.has(heading), "%s tab heading for %s" % [tab, heading])
		check(labels.count(heading) == 1, "%s draws the %s heading once" % [tab, heading])
	if debug_section == null:
		check(SETTINGS.tab_settings(tab).is_empty(), "%s has no Debug block without debug settings" % tab)
	else:
		check(debug_section.visible == debug_on, "%s Debug block follows debug mode" % tab)
		if debug_on:
			check(labels.has("ACTIONS"), "%s Debug block lists the actions" % tab)
			var expected: Array = []
			match tab:
				SETTINGS.GENERAL:
					expected = ["Trigger bed offer", "Reset act prompts"]
				SETTINGS.ANATOMY:
					expected = ["Pitch +", "Up", "Pointed mare"]
				SETTINGS.WORLD:
					expected = ["Heat", "Warning"]
			for action: String in expected:
				check(labels.has(action), "%s Debug block has the %s action" % [tab, action])
	# An action lives in exactly one tab's block. "Heat" is also the Anatomy section heading, so
	# the World guard uses its row caption "Cycle" instead of the action's short label.
	if tab != SETTINGS.ANATOMY:
		check(not labels.has("Pitch +"), "%s does not carry the anatomy actions" % tab)
	if tab != SETTINGS.WORLD:
		check(not labels.has("Cycle"), "%s does not carry the world actions" % tab)
	list.free()
	if is_instance_valid(owner):
		owner.free()


## A save from an older build migrates once; a retired key maps or is erased.
func _check_migration() -> void:
	var old: Dictionary = SETTINGS._migrate({"version": 0, "anatomy": {
		"genital_yaw_deg": 1.0, "skin_tone": "dark"}}, 0)
	var anatomy: Dictionary = old.get("anatomy", {})
	check(not anatomy.has("genital_yaw_deg"), "a removed anatomy key is erased")
	check(near(float(anatomy.get("skin_tone", -1.0)), 1.0), "a legacy skin tone maps to its anchor")
	var current: Dictionary = SETTINGS._migrate({"version": SETTINGS.SCHEMA_VERSION,
		"pose1_forward": 0.3}, SETTINGS.SCHEMA_VERSION)
	check(current.has("pose1_forward"), "a current file skips the structural chain")
	SETTINGS._deprecated.append(SETTINGS.deprecated("old.radius",
		func(value: Variant) -> Dictionary: return {"jiggle.radius": value}))
	var moved: Dictionary = SETTINGS._migrate({"version": SETTINGS.SCHEMA_VERSION,
		"old": {"radius": 0.4}}, SETTINGS.SCHEMA_VERSION)
	SETTINGS._deprecated.pop_back()
	check(near(float((moved.get("jiggle", {}) as Dictionary).get("radius", 0.0)), 0.4),
		"a deprecated key maps to its replacement")
	check(not (moved.get("old", {}) as Dictionary).has("radius"),
		"the deprecated key is erased")

	# The per-size split seeds Canon from the old flat value.
	var sized: Dictionary = SETTINGS._migrate({"version": SETTINGS.SCHEMA_VERSION,
		"presentation": {"missionary": {"vulva_shift_mm": 42.0}}}, SETTINGS.SCHEMA_VERSION)
	var sized_missionary: Dictionary = (sized.get("presentation", {}) as Dictionary).get(
		"missionary", {})
	check(not sized_missionary.has("vulva_shift_mm"), "the old flat vulva shift is erased")
	var sized_size: Dictionary = sized_missionary.get("size", {})
	var sized_canon: Dictionary = sized_size.get("canon", {})
	check(near(float(sized_canon.get("vulva_shift_mm", 0.0)), 42.0),
		"the old flat vulva shift seeds Canon")

	# A file that already has the nested block is left alone.
	var nested: Dictionary = SETTINGS._migrate({"version": SETTINGS.SCHEMA_VERSION,
		"presentation": {"missionary": {"size": {"canon": {"vulva_shift_mm": 55.0}}}}},
		SETTINGS.SCHEMA_VERSION)
	var nested_missionary: Dictionary = (nested.get("presentation", {}) as Dictionary).get(
		"missionary", {})
	var nested_canon: Dictionary = (nested_missionary.get("size", {}) as Dictionary).get(
		"canon", {})
	check(near(float(nested_canon.get("vulva_shift_mm", 0.0)), 55.0),
		"the nested size block survives migration")

	# The anatomy master switch and the act-only switch fold into one pill.
	var off: Dictionary = SETTINGS._normalize_anatomy_visibility({
		"features": {"anatomy": false}, "anatomy": {"act_only": true}})
	check(str(off["anatomy"].get("anatomy_mode", "")) == "never", "anatomy off maps to never")
	check(not (off["features"] as Dictionary).has("anatomy"), "the old master switch is erased")
	check(not (off["anatomy"] as Dictionary).has("act_only"), "the old act-only switch is erased")
	var during: Dictionary = SETTINGS._normalize_anatomy_visibility({
		"features": {"anatomy": true}, "anatomy": {"act_only": true}})
	check(str(during["anatomy"].get("anatomy_mode", "")) == "act", "act-only maps to act")
	var always: Dictionary = SETTINGS._normalize_anatomy_visibility({
		"features": {"anatomy": true}, "anatomy": {"act_only": false}})
	check(str(always["anatomy"].get("anatomy_mode", "")) == "always", "on maps to always")
	# The dock switch is inverted by the deprecation mapper.
	var dock: Dictionary = SETTINGS._migrate({"version": SETTINGS.SCHEMA_VERSION,
		"anatomy": {"hide_dock": true}}, SETTINGS.SCHEMA_VERSION)
	check(not bool(dock["anatomy"].get("show_dock", true)), "hide_dock true maps to show_dock false")

	# Retired paths are erased while live neighbours survive, and an emptied sub-block is dropped.
	var dead: Dictionary = SETTINGS._migrate({"version": 3,
		"features": {"act_chat": true, "hud_readouts": true},
		"anatomy": {"anal_ring": false, "strip_width": 1.0},
		"presentation": {"missionary": {}, "standing": {
			"kiss": {"forelegs": "planted"}, "smack": {"sound": "pack"}}},
		"thrust": {"camera_bob": true, "contact_gap_m": 0.0},
		"auto_thrust": {"pace_step": 0.25}}, 3)
	var dead_features: Dictionary = dead.get("features", {})
	check(not dead_features.has("act_chat"), "a retired feature is erased")
	check(bool(dead_features.get("hud_readouts", false)), "a live feature is kept")
	check(not (dead.get("anatomy", {}) as Dictionary).has("anal_ring"),
		"a retired anatomy key is erased")
	check(not (dead.get("thrust", {}) as Dictionary).has("camera_bob"),
		"a retired thrust key is erased")
	var dead_standing: Dictionary = (dead.get("presentation", {}) as Dictionary).get("standing", {})
	check(not dead_standing.has("kiss"), "an emptied retired sub-block is dropped")
	check(not dead_standing.has("smack"), "an emptied retired smack block is dropped")
	check((dead.get("thrust", {}) as Dictionary).has("contact_gap_m"),
		"a live neighbour of a retired key is kept")


## A script constant resolves a built-in before a same-named static function, so an API name that
## exists on Script/GDScript would silently call the built-in instead of ours.
func _check_api_names() -> void:
	var names := ["all_settings", "by_name", "by_path", "tab_settings", "groups", "block",
		"default_block", "get_value_at", "set_value_at", "default_at", "entry_view",
		"section_open", "set_section_open", "flag", "num", "choice", "list", "data", "reload_file",
		"write_setting", "preferences", "pose", "template_for", "get_bool", "set_bool",
		"get_num", "set_num", "get_choice", "set_choice", "get_list", "set_list", "build",
		"build_actions"]
	var clashes: Array = []
	for name: String in names:
		if ClassDB.class_has_method("GDScript", name):
			clashes.append(name)
	check(clashes.is_empty(), "no settings API name shadows a Script built-in: %s" % str(clashes))


## Per-mare profiles share the file and the merge; a few representative checks.
func _check_profiles() -> void:
	var base: Dictionary = SETTINGS._filled_default()
	check(SETTINGS.CHARACTER_ORDER.size() == 102, "every spawnable adult mare is editable")
	check(SETTINGS.CHARACTER_ORDER.size() == SETTINGS.CHARACTER_NAMES.size(),
		"every pony has a display name")
	check(SETTINGS.CHARACTER_ORDER.size() == SETTINGS.CHARACTER_TEMPLATES.size(),
		"every editable pony has a preference template")
	check(SETTINGS.character_name("pinkie_pie") == "Pinkie Pie", "display name lookup")
	var maud: Dictionary = SETTINGS.profile_for(base, SETTINGS.CHARACTER_TEMPLATES, "maud_pie")
	check((maud["preferences"].get("talk", []) as Array).is_empty(), "Maud is quiet")
	var override: Dictionary = SETTINGS.profile_for(base, {"fluttershy": {"cue_gap": 15.0}},
		"fluttershy")
	check(near(float(override.get("cue_gap", 0.0)), 15.0), "a character override wins")
	check(near(SETTINGS.cue_gap_value(99.0), 30.0), "cue_gap clamps high")
	var live: Dictionary = SETTINGS.template_for("fluttershy")
	check(not live.is_empty(), "live template")
	check(not SETTINGS.act_prompt("fluttershy", "utterance").is_empty(), "live utterance prompt")
	check(not SETTINGS.act_prompt("fluttershy", "cue").is_empty(), "live cue prompt")
	check(SETTINGS.act_prompt("fluttershy", "cue").contains("private, not a list to say"),
		"the cue prompt keeps preferences private")
	var legacy_data := {"default": {"act_prompts": {"cue": SETTINGS.LEGACY_ACT_PROMPTS["cue"][-1]}}}
	var normalized := SETTINGS._normalize_act_prompts(legacy_data)
	check(not (normalized["default"] as Dictionary).has("act_prompts"),
		"a saved old cue prompt is removed")
	var custom_data := {"default": {"act_prompts": {"cue": "custom"}}}
	var custom := SETTINGS._normalize_act_prompts(custom_data)
	check(str(((custom["default"] as Dictionary)["act_prompts"] as Dictionary)["cue"]) == "custom",
		"a custom cue prompt survives")


func _collect_labels(node: Node, out: Array) -> void:
	var text := ""
	if node is Button:
		text = (node as Button).text.strip_edges()
	elif node is Label:
		text = (node as Label).text.strip_edges()
	if not text.is_empty() and not out.has(text):
		out.append(text)
	for child: Node in node.get_children():
		_collect_labels(child, out)
