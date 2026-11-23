extends "res://mods/unfplap/tests/support/suite.gd"
## The settings API contract, tested once.
##
## The declarations are compile-time: a wrong accessor, a mistyped name or a missing setting fails
## to parse. What stays here is what the compiler cannot see: registry integrity, defaults, the
## file round-trip, coercion and bounds, section state, the panel layout, and the per-mare merge.
##
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_settings.gd

const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const ROWS := preload("res://mods/unfplap/settings/rows.gd")
const CHANGE := preload("res://mods/unfplap/shared/settings_change.gd")
const SETTINGS_UI := preload("res://mods/unfplap/settings/ui.gd")
const GAME := preload("res://mods/unfplap/settings/game.gd")
const CHARACTERS_UI := preload("res://mods/unfplap/settings/characters_ui.gd")
const DEBUG_UI := preload("res://mods/unfplap/debug/ui.gd")
const DEBUG_ACTIONS := preload("res://mods/unfplap/debug/service.gd")
const CONSENT := preload("res://mods/unfplap/shared/consent.gd")
const INTEGRATIONS := preload("res://mods/unfplap/shared/integrations.gd")

var original := {}


## A settings subscriber that counts its calls.
class ChangeSpy extends RefCounted:
	var calls := 0

	func changed() -> void:
		calls += 1


## A settings page stand-in: the three private calls the settings tab makes and its redraw count.
class FakeSettingsPage extends Node:
	var redraws := 0
	var last_callback := Callable()

	func _button(parent: Node, text: String, callback: Callable) -> Button:
		last_callback = callback
		var button := Button.new()
		button.text = text
		if parent != null:
			parent.add_child(button)
		return button

	func _icon_texture(_kind: String) -> Texture2D:
		var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		return ImageTexture.create_from_image(image)

	func _redraw() -> void:
		redraws += 1


## A menu icon stand-in with the one field the settings tab writes.
class FakeIcon extends Control:
	var kind := ""


## A mods host stand-in with the one folder call the settings file path makes.
class FakeMods extends Node:
	func data_folder(id: String) -> String:
		return "user://mods/data/%s" % id


## A settings autoload stand-in with the values the accessors read.
class FakeSettings extends Node:
	func get_value(key: String) -> Variant:
		match key:
			"ponies/size":
				return "mounting"
			"access/speech_text":
				return "caption"
		return null

	func anon_height_scale() -> float:
		return 1.3

	func tts_enabled() -> bool:
		return true

func run() -> void:
	_check_load()
	_check_registry()
	_check_shipped_defaults()
	_check_characters()
	_check_player_document()
	_check_act_key()
	_check_snapshot()
	_check_placement()
	_check_tail_seat()
	_check_write_round_trip()
	_check_read_view()
	_check_typed_rows()
	_check_coercion()
	_check_sections()
	_check_groups()
	_check_general_tail()
	_check_panels()
	_check_pose_tab_visibility()
	_check_anatomy_gate()
	_check_integrations_panel()
	_check_section_folding()
	_check_migration()
	_check_migration_diff()
	_check_placement_migration()
	_check_api_names()
	_check_change_notification()
	_check_profiles()
	_check_profile_identity()
	_check_characters_form()
	_check_provider_precedence()
	_check_character_overrides()
	_check_base_game_access()
	_check_participation()
	_check_player_file_recovery()
	_check_player_split()
	_check_player_recovery()
	if failures == 0:
		print("SETTINGS_PASS")
	finish()


## Every declaration is well formed and reachable.
func _check_registry() -> void:
	var all: Array = SETTINGS.all_settings()
	var names := {}
	var paths := {}
	var tabs := {}
	var complete := true
	for setting: Variant in all:
		if names.has(setting.name) or paths.has(setting.path):
			complete = false
		names[setting.name] = true
		paths[setting.path] = true
		# An empty group is legal: the setting then has no section heading. An empty hint is
		# legal too: the label alone can say what the row does.
		if str(setting.label).is_empty():
			complete = false
		if str(setting.tab) not in [SETTINGS.GENERAL, SETTINGS.ANATOMY, SETTINGS.POSES,
				SETTINGS.WORLD, SETTINGS.INTEGRATIONS]:
			complete = false
		tabs[setting.tab] = int(tabs.get(setting.tab, 0)) + 1
	check(complete, "every setting has a unique name and path, a label and tab")
	for tab: String in [SETTINGS.GENERAL, SETTINGS.ANATOMY, SETTINGS.POSES, SETTINGS.WORLD,
			SETTINGS.INTEGRATIONS]:
		check(int(tabs.get(tab, 0)) > 0, "%s tab has settings" % tab)
	# Poses holds every pose row: the two player switches at the top and the debug tuning blocks.
	# A feature flag that belongs to a pose section follows that section into Poses.
	var not_in_poses: Array = []
	var not_debug: Array = []
	var misrouted: Array = []
	for setting: Variant in all:
		var path := str(setting.path)
		var pose_row := path.begins_with("presentation.missionary.") \
			or path.begins_with("presentation.standing.")
		if pose_row:
			if str(setting.tab) != SETTINGS.POSES:
				not_in_poses.append(path)
			if not bool(setting.debug):
				not_debug.append(path)
		elif path.begins_with("features.") and (str(setting.group) == "Missionary"
				or str(setting.group).begins_with("Standing")):
			if str(setting.tab) != SETTINGS.POSES:
				misrouted.append(path)
	check(not_in_poses.is_empty(), "every pose row is in Poses: %s" % str(not_in_poses))
	check(not_debug.is_empty(), "every pose row is debug-only in Poses: %s" % str(not_debug))
	check(misrouted.is_empty(), "every pose feature follows its section to Poses: %s" % str(misrouted))
	# Auto Thrust is a player section, not part of the Debug block.
	var misplaced_thrust: Array = []
	for name: String in ["min_depth", "max_depth", "pace", "curve"]:
		var row: Variant = SETTINGS.by_name(name)
		if row == null or str(row.tab) != SETTINGS.GENERAL \
				or str(row.group) != "Auto Thrust" or bool(row.debug):
			misplaced_thrust.append(name)
	check(misplaced_thrust.is_empty(),
		"Auto Thrust stays a player section in General: %s" % str(misplaced_thrust))
	var climax: Variant = SETTINGS.by_path("presentation.act.climax_mode")
	check(climax != null and str(climax.tab) == SETTINGS.GENERAL,
		"the climax face stays in General")
	var overlay: Variant = SETTINGS.by_path("anatomy.skeleton_overlay")
	check(overlay != null and bool(overlay.debug), "the skeleton overlay is a debug flag")
	check(SETTINGS.by_name("hud_readouts") != null, "a setting is reachable by name")
	check(SETTINGS.by_path("features.hud_readouts") != null, "a setting is reachable by path")


## The act key is a hidden physical-key setting; the General row captures any key.
func _check_act_key() -> void:
	var before := int(SETTINGS.act_key.get_num())
	check(bool(SETTINGS.act_key.hidden), "the act key is drawn by the hand-built capture row")
	SETTINGS.act_key.set_num(float(KEY_F))
	check(int(SETTINGS.act_key.get_num()) == KEY_F, "a captured key is stored")
	SETTINGS.reload_file()
	check(int(SETTINGS.act_key.get_num()) == KEY_F, "a captured key survives a reload")
	var list := VBoxContainer.new()
	SETTINGS_UI.build(list, SETTINGS.GENERAL, 16, null, Callable())
	root.add_child(list)
	var capture := _find_capture(list)
	check(capture != null, "the General tab has the Act Key capture")
	if capture != null:
		capture.call("start_capture")
		var event := InputEventKey.new()
		event.physical_keycode = KEY_G
		event.pressed = true
		capture.call("_input", event)
		check(int(SETTINGS.act_key.get_num()) == KEY_G, "the capture stores any key")
		check(capture.text == "G", "the capture label follows the key")
	list.queue_free()
	SETTINGS.act_key.set_num(float(before))
	check(int(SETTINGS.act_key.get_num()) == before, "the original act key is restored")


func _find_capture(node: Node) -> Button:
	for child: Node in node.find_children("*", "Button", true, false):
		if child is SETTINGS_UI.KeyCaptureButton:
			return child as Button
	return null


## The shipped settings document is the schema contract: exactly one value per declared setting,
## of the declared kind, inside the declared bounds. The test never names a value, so changing a
## shipped default does not touch this file.
func _check_shipped_defaults() -> void:
	var text := FileAccess.get_file_as_string(SETTINGS.DEFAULTS_FILE)
	check(not text.is_empty(), "the shipped settings document exists")
	var parsed: Variant = JSON.parse_string(text)
	check(parsed is Dictionary, "the shipped settings document is a JSON object")
	var document: Dictionary = parsed if parsed is Dictionary else {}
	check(not document.has("default"),
		"the shipped settings document holds no profile block")
	check(not document.has("characters"),
		"the shipped settings document holds no character block")
	var leaves := _flatten_paths(document)
	var declared := {}
	for setting: Variant in SETTINGS.all_settings():
		declared[str(setting.path)] = setting
	var missing: Array = []
	var dead: Array = []
	for path: String in declared:
		if not leaves.has(path):
			missing.append(path)
	for path: String in leaves:
		if not declared.has(path):
			dead.append(path)
	check(missing.is_empty(), "every declared setting has a shipped default: %s" % str(missing))
	check(dead.is_empty(), "the shipped settings hold no undeclared path: %s" % str(dead))
	for path: String in declared:
		if not leaves.has(path):
			continue
		var setting: Variant = declared[path]
		var value: Variant = leaves[path]
		if setting is SETTINGS.FlagSetting:
			check(value is bool, "%s is a flag" % path)
		elif setting is SETTINGS.NumSetting:
			check(value is int or value is float, "%s is a number" % path)
			if (value is int or value is float) and not bool(setting.debug):
				var n := setting as SETTINGS.NumSetting
				check(float(value) >= n.low and float(value) <= n.high,
					"%s is inside its declared bounds" % path)
		elif setting is SETTINGS.ChoiceSetting:
			check(value is String, "%s is a choice string" % path)
			if value is String:
				check((setting as SETTINGS.ChoiceSetting).options.has(value),
					"%s is one of its declared options" % path)
		elif setting is SETTINGS.ListSetting:
			check(value is Array, "%s is a list" % path)
			if value is Array:
				for item: Variant in value:
					check(item is String and (setting as SETTINGS.ListSetting).options.has(item),
						"%s holds only its declared options" % path)
		elif setting is SETTINGS.ColorSetting:
			check(value is String and _is_hex_color(str(value)), "%s is a hex colour" % path)
		else:
			fail("%s has a known setting kind" % path)
	check(_flatten_paths(SETTINGS._shipped()) == leaves,
		"the settings loader reads the shipped settings document")
	var copy := SETTINGS.defaults().raw()
	check(not copy.is_empty(), "defaults() returns the shipped document")
	if copy is Dictionary:
		copy["debug_mode"] = not bool(copy.get("debug_mode", false))
		check(bool(SETTINGS.defaults().raw().get("debug_mode", false))
			!= bool(copy.get("debug_mode", false)),
			"defaults() is detached from the shipped document")


## The global `default` profile: three timing numbers, the preference schema and the pose schema.
## It never asserts a value.
func _check_default_profile(profile: Variant) -> void:
	check(profile is Dictionary, "the characters document has a global default profile")
	if not profile is Dictionary:
		return
	var block: Dictionary = profile
	for key: String in ["smack_zone_radius", "aftercare_min", "cue_gap"]:
		check(block.get(key) is int or block.get(key) is float,
			"default.%s is a number" % key)
	var preferences: Variant = block.get("preferences")
	check(preferences is Dictionary, "default.preferences is a block")
	if preferences is Dictionary:
		# The shipped profile carries the fields a player file inherits. A field whose neutral
		# value is the resolver's own fallback (the teat size's `auto`) may be absent; it still
		# resolves, so the schema check runs on the resolver's output.
		for key: Variant in (preferences as Dictionary).keys():
			check(str(key) in SETTINGS.PREFERENCES.KEYS,
				"default.preferences has no unknown field: %s" % str(key))
		var resolved: Dictionary = SETTINGS.PREFERENCES.resolve({})
		for key: String in SETTINGS.PREFERENCES.KEYS:
			check(resolved.has(key), "the profile resolver fills %s" % key)
		check(str(resolved.get("teat_size", "")) == "auto",
			"an unsaved profile keeps the automatic teat size")
		check(str((preferences as Dictionary).get("intensity", ""))
			in SETTINGS.PREFERENCES.INTENSITIES, "default.preferences.intensity is an option")
		check(str((preferences as Dictionary).get("pattern", ""))
			in SETTINGS.PREFERENCES.PATTERNS, "default.preferences.pattern is an option")
		check(str((preferences as Dictionary).get("warmth", ""))
			in SETTINGS.PREFERENCES.WARMTHS, "default.preferences.warmth is an option")
		check(str((preferences as Dictionary).get("tolerance", ""))
			in SETTINGS.PREFERENCES.TOLERANCES, "default.preferences.tolerance is an option")
		for key: String in ["touch", "dislikes", "talk"]:
			check((preferences as Dictionary).get(key) is Array,
				"default.preferences.%s is a list" % key)
		check((preferences as Dictionary).get("notes") is String,
			"default.preferences.notes is text")
	var poses: Variant = block.get("poses")
	check(poses is Dictionary, "default.poses is a block")
	if poses is Dictionary:
		var pose_ids: Array = (poses as Dictionary).keys()
		pose_ids.sort()
		var expected_poses: Array = SETTINGS.CATALOG.all().duplicate()
		expected_poses.sort()
		check(pose_ids == expected_poses, "default.poses has exactly the catalog poses")
		for pose_id: String in SETTINGS.CATALOG.all():
			var row: Variant = (poses as Dictionary).get(pose_id, {})
			check(row is Dictionary, "default.poses.%s is a block" % pose_id)
			if not row is Dictionary:
				continue
			var row_keys: Array = (row as Dictionary).keys()
			row_keys.sort()
			var expected_keys: Array = SETTINGS.CATALOG.POSE_KEYS[pose_id].duplicate()
			expected_keys.sort()
			check(row_keys == expected_keys, "default.poses.%s has the pose schema" % pose_id)
			for key: Variant in (row as Dictionary).keys():
				if str(key) == "gaps":
					continue
				var value: Variant = (row as Dictionary)[key]
				check(value is int or value is float,
					"default.poses.%s.%s is a number" % [pose_id, str(key)])
			if pose_id == SETTINGS.CATALOG.STANDING:
				var gaps: Variant = (row as Dictionary).get("gaps")
				check(gaps is Dictionary, "default.poses.standing.gaps is a block")
				if gaps is Dictionary:
					var gap_keys: Array = (gaps as Dictionary).keys()
					gap_keys.sort()
					var expected_gaps: Array = SETTINGS.CATALOG.GAP_KEYS.duplicate()
					expected_gaps.sort()
					check(gap_keys == expected_gaps,
						"the standing gaps hold exactly the four sizes")


## The characters document holds the global profile, the per-mare templates and the placement
## rows. It is validated here and must never appear in the settings document or the player file.
func _check_characters() -> void:
	var characters := SETTINGS.DEFAULTS.characters()
	check(not characters.is_empty(), "the shipped characters document exists")
	check(SETTINGS.DEFAULTS.characters_valid(), "the shipped characters document parses")
	check(not characters.has("act_prompts"), "the characters document has no prompt catalog")
	check(not characters.has("event_prompts"), "the characters document has no event prompts")
	check(not characters.has("character_templates"),
		"the characters document has no template catalog")
	var settings_document := SETTINGS.DEFAULTS.document()
	check(not settings_document.has("act_prompts"),
		"the settings document has no prompt catalog")
	check(not settings_document.has("characters"),
		"the settings document has no character block")
	check(not SETTINGS._settings_document(SETTINGS.data().raw()).has("characters"),
		"the player document has no character block")
	_check_default_profile(characters.get("default"))

	var templates: Variant = characters.get("characters")
	check(templates is Dictionary, "the characters document has a characters block")
	if templates is Dictionary:
		var ids: Array = (templates as Dictionary).keys()
		ids.sort()
		var expected_ids: Array = SETTINGS.CHARACTER_ORDER.duplicate()
		expected_ids.sort()
		check(ids == expected_ids, "the characters block covers the whole roster")
		var bad_blocks: Array = []
		var bad_fields: Array = []
		var bad_preferences: Array = []
		var bad_preference_fields: Array = []
		var bad_pose_blocks: Array = []
		var bad_pose_ids: Array = []
		for id: Variant in ids:
			var entry: Variant = (templates as Dictionary)[id]
			if not entry is Dictionary:
				bad_blocks.append(str(id))
				continue
			for key: Variant in (entry as Dictionary).keys():
				if not str(key) in SETTINGS.MARE_REGISTRY.TEMPLATE_KEYS:
					bad_fields.append("%s.%s" % [str(id), str(key)])
			var preferences: Variant = (entry as Dictionary).get("preferences")
			if not preferences is Dictionary:
				bad_preferences.append(str(id))
			else:
				for key: Variant in (preferences as Dictionary).keys():
					if not str(key) in SETTINGS.PREFERENCES.KEYS:
						bad_preference_fields.append("%s.preferences.%s"
							% [str(id), str(key)])
			var poses: Variant = (entry as Dictionary).get("poses", {})
			if not poses is Dictionary:
				bad_pose_blocks.append(str(id))
			else:
				for pose_id: Variant in (poses as Dictionary).keys():
					if not str(pose_id) in SETTINGS.CATALOG.all():
						bad_pose_ids.append("%s.poses.%s" % [str(id), str(pose_id)])
		check(bad_blocks.is_empty(), "every character template is a block: %s"
			% str(bad_blocks))
		check(bad_fields.is_empty(), "every template key is a template field: %s"
			% str(bad_fields))
		check(bad_preferences.is_empty(), "every template has preferences: %s"
			% str(bad_preferences))
		check(bad_preference_fields.is_empty(), "every preference key is a profile field: %s"
			% str(bad_preference_fields))
		check(bad_pose_blocks.is_empty(), "every template poses block is a block: %s"
			% str(bad_pose_blocks))
		check(bad_pose_ids.is_empty(), "every template pose is a catalog pose: %s"
			% str(bad_pose_ids))

	var anatomy: Variant = characters.get("anatomy", {})
	var placement: Variant = (anatomy as Dictionary).get("placement") \
		if anatomy is Dictionary else null
	check(placement is Dictionary, "the characters document has a placement block")
	if placement is Dictionary:
		var reserved_ids: Array = []
		var bad_blocks: Array = []
		var bad_keys: Array = []
		var bad_values: Array = []
		for id: Variant in (placement as Dictionary).keys():
			if str(id) in SETTINGS.MARE_REGISTRY.RESERVED_IDS:
				reserved_ids.append(str(id))
			var row: Variant = (placement as Dictionary)[id]
			if not row is Dictionary:
				bad_blocks.append(str(id))
				continue
			for key: Variant in (row as Dictionary).keys():
				if not str(key) in SETTINGS.PLACEMENT.KEYS:
					bad_keys.append("%s.%s" % [str(id), str(key)])
				var value: Variant = (row as Dictionary)[key]
				if not (value is int or value is float):
					bad_values.append("%s.%s" % [str(id), str(key)])
		check(reserved_ids.is_empty(), "no placement row is a reserved id: %s"
			% str(reserved_ids))
		check(bad_blocks.is_empty(), "every placement row is a block: %s" % str(bad_blocks))
		check(bad_keys.is_empty(), "every placement key is a placement key: %s"
			% str(bad_keys))
		check(bad_values.is_empty(), "every placement value is a number: %s"
			% str(bad_values))


## The player files split by kind: declared settings in `settings.json`, the profile differences
## and the per-mare rows in `characters.json`. An untouched profile writes no character file.
func _check_player_document() -> void:
	var shipped: Dictionary = SETTINGS.defaults().raw()
	var untouched := SETTINGS._settings_document(shipped)
	check(not untouched.has("default"), "an untouched profile stores no default block")
	check(int(untouched.get("version", 0)) == SETTINGS.SCHEMA_VERSION,
		"the settings document carries the current schema")
	check(untouched.has("debug_mode"), "declared settings stay materialised")
	check(not untouched.has("characters"), "the settings document has no character block")
	check(SETTINGS._characters_document(shipped).is_empty(),
		"an untouched profile writes no character document")

	var changed := shipped.duplicate(true)
	var profile: Dictionary = changed["default"]
	(profile["preferences"] as Dictionary)["intensity"] = "rough"
	(profile["poses"]["standing"] as Dictionary)["bow"] = 3.5
	var settings_doc := SETTINGS._settings_document(changed)
	check(not settings_doc.has("default"), "a changed profile stays out of the settings document")
	var characters := SETTINGS._characters_document(changed)
	check(int(characters.get("version", 0)) == SETTINGS.SCHEMA_VERSION,
		"the character document carries the current schema")
	var diff: Dictionary = characters.get("default", {})
	var preference: Dictionary = diff.get("preferences", {})
	check(str(preference.get("intensity", "")) == "rough",
		"a changed preference is stored in the character document")
	check(not preference.has("notes"), "an untouched preference key is not pinned")
	var standing: Dictionary = (diff.get("poses", {}) as Dictionary).get("standing", {})
	check(near(float(standing.get("bow", 0.0)), 3.5), "a changed pose value is stored")
	check(not standing.has("foreleg"), "an untouched pose key is not pinned")

	var merged := SETTINGS._merge(shipped, SETTINGS._attach_characters(settings_doc, characters))
	check(near(float((merged["default"]["poses"]["standing"] as Dictionary)["bow"]), 3.5),
		"the sparse default merges back to the resolved value")
	check(str((merged["default"]["preferences"] as Dictionary).get("notes", ""))
		== str((shipped["default"]["preferences"] as Dictionary).get("notes", "")),
		"the sparse default keeps the shipped preference it did not change")

	var placed := changed.duplicate(true)
	var anatomy: Dictionary = placed["anatomy"]
	var rows: Dictionary = anatomy["placement"]
	rows["fluttershy"] = {"tail_y": 0.021}
	var split_settings := SETTINGS._settings_document(placed)
	var kept: Dictionary = (split_settings.get("anatomy", {}) as Dictionary).get("placement", {})
	check(kept.has("default") and kept.has("anon"),
		"the declared placement rows stay in the settings document")
	check(not kept.has("fluttershy"), "a per-mare placement row leaves the settings document")
	var split_characters := SETTINGS._characters_document(placed)
	var moved: Dictionary = (split_characters.get("anatomy", {}) as Dictionary).get("placement", {})
	check(moved.has("fluttershy") and not moved.has("default") and not moved.has("anon"),
		"the character document holds only the per-mare placement rows")


## Every leaf path of a nested settings document.
func _flatten_paths(value: Variant, prefix := "") -> Dictionary:
	var out: Dictionary = {}
	if value is Dictionary:
		for key: Variant in (value as Dictionary).keys():
			var name := str(key)
			var path := name if prefix.is_empty() else prefix + "." + name
			out.merge(_flatten_paths((value as Dictionary)[key], path))
	else:
		out[prefix] = value
	return out


func _is_hex_color(value: String) -> bool:
	var re := RegEx.new()
	re.compile("^[0-9a-f]{6}([0-9a-f]{2})?$")
	return re.search(value) != null


## The act snapshot carries the typed values the runtime reads per stroke or per frame.
func _check_snapshot() -> void:
	var snap := SETTINGS.act_snapshot("missionary")
	check(near(snap.thrust_pixels_per_cm, SETTINGS.pixels_per_cm.get_num()),
		"the act snapshot carries sensitivity")
	check(snap.thrust_up == (SETTINGS.orientation.get_choice() == "up"),
		"the act snapshot carries the thrust direction")
	check(snap.features is Dictionary and not snap.features.is_empty(),
		"the act snapshot carries the feature flags")
	check(snap.presentation.has("free_look"), "the act snapshot carries the pose presentation")
	var standing := SETTINGS.act_snapshot("standing")
	check(standing.presentation.has("chin_up_deg") and standing.presentation.has("neck_down_deg"),
		"the standing group carries its presentation block")
	check(SETTINGS.pose("", "standing_oral").raw().is_empty(),
		"the internal oral pose has no settings block of its own")
	check(SETTINGS.pose("", "bed_facesit").raw().is_empty(),
		"the internal face-sit pose has no settings block of its own")
	check(snap.climax_mode == SETTINGS.climax_mode.get_choice(),
		"the act snapshot carries the climax face")
	check(near(SETTINGS.palm_scale_for("canon"), SETTINGS.canon.get_num()),
		"the palm scale resolves a size without a path read")


## Anatomy placement is one default block plus partial per-mare overrides.
func _check_placement() -> void:
	var base := SETTINGS.anatomy_placement_default("").raw()
	for key: String in SETTINGS.PLACEMENT.KEYS:
		check(base.has(key), "the placement default carries %s" % key)
	var nudged := base.duplicate(true)
	nudged["offset_y"] = float(base["offset_y"]) + 0.1
	nudged["scale"] = float(base["scale"]) + 0.1
	SETTINGS.save_anatomy_placement_default(ROWS.Rows.of(nudged))
	var applied := SETTINGS.anatomy_placement_default("").raw()
	check(near(float(applied["offset_y"]), float(nudged["offset_y"])),
		"a placement action applies the default immediately")
	check(near(float(applied["scale"]), float(nudged["scale"])),
		"a placement action applies the whole default block")
	SETTINGS.reset_anatomy_placement_default()
	var restored := SETTINGS.anatomy_placement_default("").raw()
	check(near(float(restored["offset_y"]), float(base["offset_y"]))
		and near(float(restored["scale"]), float(base["scale"])),
		"reset restores the shipped default placement")

	var anon := SETTINGS.anon_placement().raw()
	for key: String in ["offset_x", "offset_y", "offset_z", "pitch_deg", "scale"]:
		check(anon.has(key), "the anon placement carries %s" % key)
	check(near(float(anon["offset_x"]), 0.0) and near(float(anon["pitch_deg"]), 0.0),
		"the anon placement has no X or pitch offset")
	check(float(anon["scale"]) > 0.0, "the anon placement keeps a positive scale")


## Tail and dock placement share the anatomy block and disappear at the default.
func _check_tail_seat() -> void:
	var default := SETTINGS.anatomy_placement_default("octavia_melody").raw()
	for key: String in SETTINGS.PLACEMENT.KEYS:
		check(default.has(key), "a mare with no override resolves %s" % key)
	var maud_before := SETTINGS.anatomy_placement("maud_pie").raw()
	var values := default.duplicate(true)
	values["tail_y"] = float(default["tail_y"]) + 0.012
	values["tail_z"] = float(default["tail_z"]) + 0.007
	values["dock_y"] = float(default["dock_y"]) - 0.008
	values["dock_scale"] = float(default["dock_scale"]) + 0.06
	values["tail_tilt_deg"] = float(default["tail_tilt_deg"]) + 7.0
	SETTINGS.save_anatomy_placement("octavia_melody", ROWS.Rows.of(values))
	var placed := SETTINGS.anatomy_placement("octavia_melody").raw()
	check(near(float(placed["tail_y"]), float(values["tail_y"]))
		and near(float(placed["tail_z"]), float(values["tail_z"])),
		"a tail placement override reads back")
	check(near(float(placed["dock_y"]), float(values["dock_y"]))
		and near(float(placed["dock_scale"]), float(values["dock_scale"])),
		"a dock placement override reads back")
	check(near(float(placed["tail_tilt_deg"]), float(values["tail_tilt_deg"])),
		"a tail tilt override reads back")
	check(SETTINGS.anatomy_placement_has_override("octavia_melody"),
		"a non-default tail/dock placement is an override")
	check(near(float(SETTINGS.anatomy_placement("maud_pie").raw()["tail_y"]),
		float(maud_before["tail_y"])), "tail placement overrides are per mare")
	SETTINGS.save_anatomy_placement("octavia_melody",
		SETTINGS.anatomy_placement_default("octavia_melody"))
	check(not SETTINGS.anatomy_placement_has_override("octavia_melody"),
		"returning to the default removes the override")
	var data := SETTINGS.data().raw()
	var anatomy: Variant = data.get("anatomy", {})
	var placement: Variant = (anatomy as Dictionary).get("placement", {}) \
		if anatomy is Dictionary else {}
	check(not placement is Dictionary or not (placement as Dictionary).has("octavia_melody"),
		"a default placement removes the mare row")

## The old placement files import into the one block and collapse rows equal to the default.
func _check_placement_migration() -> void:
	var folder := "user://mods/data/unfplap"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var mare_path := folder.path_join("anatomy_place.json")
	var anon_path := folder.path_join("anon_place.json")
	var fluttershy := SETTINGS.anatomy_placement_default("fluttershy").raw()
	fluttershy["offset_y"] = float(fluttershy["offset_y"]) + 0.005
	var applejack := SETTINGS.anatomy_placement_default("applejack").raw()
	var dash := SETTINGS.anatomy_placement_default("rainbow_dash").raw()
	dash["pitch_deg"] = float(dash["pitch_deg"]) + 3.0
	var mare := FileAccess.open(mare_path, FileAccess.WRITE)
	mare.store_string(JSON.stringify({"version": SETTINGS.PLACEMENT.LEGACY_VERSION,
		"fluttershy": _legacy_row(fluttershy),
		"applejack": _legacy_row(applejack),
		"rainbow_dash": _legacy_row(dash),
	}, "\t"))
	mare.close()
	var anon_default := SETTINGS.anon_placement().raw()
	anon_default["scale"] = float(anon_default["scale"]) + 0.1
	var anon := FileAccess.open(anon_path, FileAccess.WRITE)
	anon.store_string(JSON.stringify(_legacy_row(anon_default), "\t"))
	anon.close()
	var data := SETTINGS._normalize_anatomy_placement({})
	var placement: Dictionary = (data.get("anatomy", {}) as Dictionary).get("placement", {})
	check(placement.has("fluttershy"), "a differing mare row imports")
	check(not placement.has("applejack"), "a row equal to the default collapses")
	check(placement.has("anon"), "the anon row imports")
	check(near(float((placement["fluttershy"] as Dictionary).get("offset_y", 0.0)),
		float(fluttershy["offset_y"])), "the imported mare row keeps its value")
	check(near(float((placement["anon"] as Dictionary).get("scale", 0.0)),
		float(anon_default["scale"])), "the imported anon row keeps its value")
	var dash_row: Dictionary = placement.get("rainbow_dash", {})
	check(dash_row.size() == 1 and near(float(dash_row.get("pitch_deg", 0.0)),
		float(dash["pitch_deg"])), "a one-key legacy row stores only that key")
	SETTINGS._finish_legacy_placement_import()
	check(not FileAccess.file_exists(mare_path), "the old mare file is archived")
	check(not FileAccess.file_exists(anon_path), "the old anon file is archived")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(mare_path + ".migrated"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(anon_path + ".migrated"))
	# A current schema still imports a legacy file that appears after the bump.
	var late_values := SETTINGS.anatomy_placement_default("rarity").raw()
	late_values["pitch_deg"] = float(late_values["pitch_deg"]) + 3.0
	var late := FileAccess.open(mare_path, FileAccess.WRITE)
	late.store_string(JSON.stringify({"version": SETTINGS.PLACEMENT.LEGACY_VERSION,
		"rarity": _legacy_row(late_values)}, "\t"))
	late.close()
	SETTINGS.reload_file()
	SETTINGS.data()
	check(near(float(SETTINGS.anatomy_placement("rarity").raw().get("pitch_deg", 0.0)),
		float(late_values["pitch_deg"])),
		"a current settings file still imports a late legacy placement")
	check(not FileAccess.file_exists(mare_path), "the late legacy file is archived")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(mare_path + ".migrated"))


## One row of the old placement file, from a resolved placement block.
func _legacy_row(placement: Dictionary) -> Dictionary:
	return {
		"position": [float(placement["offset_x"]), float(placement["offset_y"]),
			float(placement["offset_z"])],
		"pitch": float(placement["pitch_deg"]),
		"scale": float(placement["scale"]),
	}


## A write persists through the file, and the flat cache rebuilds with it.
func _check_write_round_trip() -> void:
	var before := SETTINGS.radius.get_num()
	SETTINGS.radius.set_num(0.31)
	check(near(SETTINGS.radius.get_num(), 0.31), "a write reads back")
	SETTINGS.reload_file()
	check(near(SETTINGS.radius.get_num(), 0.31), "a write survives a reload")
	SETTINGS.radius.set_num(before)
	check(near(SETTINGS.radius.get_num(), before), "the original value is restored")


## Reads share the live cached view. `data()` hands the tools and suites a detached copy, so a
## caller cannot edit the live tree through it.
func _check_read_view() -> void:
	var live_flag := bool(SETTINGS._read().get("debug_mode", false))
	var view := SETTINGS.data().raw()
	view["debug_mode"] = not live_flag
	check(bool(SETTINGS._read().get("debug_mode", false)) == live_flag,
		"the merged view is detached from the live cache")
	var block: Variant = view.get("default")
	var before := SETTINGS.aftercare_min("fluttershy")
	if block is Dictionary:
		(block as Dictionary)["aftercare_min"] = before + 999
	check(SETTINGS.aftercare_min("fluttershy") == before,
		"nested blocks in the merged view are detached")


## The typed wrapper is the JSON edge: a round trip keeps the values and the nested block.
func _check_typed_rows() -> void:
	var document := {"intensity": "soft", "count": 2, "ratio": 0.5, "on": true,
		"nested": {"acts": false, "label": "x"}, "list": [1, 2]}
	var parsed: Variant = JSON.parse_string(JSON.stringify(document))
	check(parsed is Dictionary, "the settings document round-trips through JSON")
	var data: Dictionary = parsed if parsed is Dictionary else {}
	var rows := ROWS.Rows.of(data)
	check(rows.str_value("intensity") == "soft", "the wrapper reads a string")
	check(rows.num("count") == 2.0 and near(rows.num("ratio"), 0.5),
		"the wrapper reads a number")
	check(rows.bool_value("on") and not rows.bool_value("missing"),
		"the wrapper reads a bool")
	check(rows.str_value("missing", "fallback") == "fallback",
		"a missing value takes the fallback")
	check(rows.has("nested") and not rows.has("absent"), "the wrapper answers presence")
	check(not rows.rows("nested").bool_value("acts", true),
		"the wrapper reads a nested document")
	check(rows.rows("absent").raw().is_empty(), "an absent nested document reads as empty")
	var keys := rows.keys()
	check(keys.size() == document.size() and "nested" in keys,
		"the wrapper lists the document keys")
	check(rows.raw() == parsed, "the wrapper hands back the same document")


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

	original["tail_y"] = SETTINGS.tail_y.get_num()
	SETTINGS.tail_y.set_num(500.0)
	check(near(SETTINGS.tail_y.get_num(), 500.0), "the default tail Y is never clamped")
	SETTINGS.tail_y.set_num(-500.0)
	check(near(SETTINGS.tail_y.get_num(), -500.0), "a negative default tail Y is kept")
	SETTINGS.tail_y.set_num(float(original["tail_y"]))

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
## tab (or its Debug block) with no heading; a subgroup that small merges into its parent. A pose
## feature flag moved to Poses keeps its pose section; see docs/settings.md.
func _check_groups() -> void:
	for tab: String in [SETTINGS.GENERAL, SETTINGS.ANATOMY, SETTINGS.POSES, SETTINGS.WORLD]:
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
	var path_id := SETTINGS.by_name("path_id")
	check(path_id != null and str(path_id.group) == "Missionary",
		"the missionary caress path folds into the Missionary section")


## Enable debug is the last player row of General: it governs the Debug block every section ends
## with, so it is drawn under the sections rather than at the top of the tab.
func _check_general_tail() -> void:
	var list := VBoxContainer.new()
	root.add_child(list)
	SETTINGS_UI.build(list, SETTINGS.GENERAL, 16, null, Callable())
	var labels: Array = []
	_collect_labels(list, labels)
	var thrust := labels.find("Auto Thrust")
	var largest := labels.find("Auto max depth")
	var debug := labels.find("Enable debug")
	check(thrust >= 0 and largest >= 0, "General draws the Auto Thrust section")
	check(debug > thrust and debug > largest,
		"Enable debug is drawn after the Auto Thrust section")
	list.free()


## The panel draws every declaration in its tab, and the Debug block follows debug mode.
func _check_panels() -> void:
	var debug_before := SETTINGS.debug_mode.get_bool()
	SETTINGS.debug_mode.set_bool(false)
	for tab: String in [SETTINGS.GENERAL, SETTINGS.ANATOMY, SETTINGS.POSES, SETTINGS.WORLD]:
		_check_panel_tab(tab, false)
	SETTINGS.debug_mode.set_bool(true)
	for tab: String in [SETTINGS.GENERAL, SETTINGS.ANATOMY, SETTINGS.POSES, SETTINGS.WORLD]:
		_check_panel_tab(tab, true)
	SETTINGS.debug_mode.set_bool(debug_before)


## Anatomy Never keeps the pill active while greying out and disabling everything it governs.
func _check_anatomy_gate() -> void:
	var before := SETTINGS.anatomy_mode.get_choice()
	SETTINGS.anatomy_mode.set_choice("never")
	var list := VBoxContainer.new()
	SETTINGS_UI.build(list, SETTINGS.ANATOMY, 16, null, Callable())
	SETTINGS_UI.refresh_debug_visibility()
	var gate: Variant = _find_named(list, "AnatomyGateContent")
	check(gate is VBoxContainer, "the Anatomy tab has a gated content container")
	if gate is VBoxContainer:
		var content := gate as VBoxContainer
		check(is_equal_approx(content.modulate.a, 0.75), "Never dims the Anatomy content to 75%")
		var pill := _find_button_text(list, "Never")
		check(pill != null and not pill.disabled,
			"the Anatomy pill stays active while Never")
		var mare := _find_button_text(content, "Mare")
		check(mare != null and mare.disabled, "Never disables the Mare section")
		check(content.visible, "the gated content stays visible")
		SETTINGS.anatomy_mode.set_choice("always")
		SETTINGS_UI.refresh_debug_visibility()
		check(is_equal_approx(content.modulate.a, 1.0),
			"Act or Always restores the Anatomy content")
		check(mare != null and not mare.disabled,
			"Act or Always re-enables the Mare section")
	SETTINGS.anatomy_mode.set_choice(before)
	SETTINGS_UI.refresh_debug_visibility()
	list.free()


## The Poses tab is always in the bar, injected after Anatomy. Only its Debug block follows debug
## mode; the two pose switches must stay reachable with debug off.
func _check_pose_tab_visibility() -> void:
	var before := SETTINGS.debug_mode.get_bool()
	var tabs := TabContainer.new()
	root.add_child(tabs)
	SETTINGS_UI._settings_tab_list("General", tabs)
	SETTINGS_UI._settings_tab_list("Anatomy", tabs)
	var poses_list := SETTINGS_UI._settings_tab_list("Poses", tabs)
	SETTINGS_UI.build(poses_list, SETTINGS.POSES, 16, null, Callable())
	SETTINGS_UI._settings_tab_list("World", tabs)
	var poses := poses_list.get_parent().get_parent() as ScrollContainer
	check(poses != null, "the Poses tab has its scroll page")
	if poses != null:
		var index := poses.get_index()
		check(index == 2, "the Poses tab sits after Anatomy")
		SETTINGS.debug_mode.set_bool(false)
		SETTINGS_UI.refresh_debug_visibility()
		check(not tabs.is_tab_hidden(index), "the Poses title stays with debug off")
		check(tabs.current_tab == 0, "the bar starts on General")
		tabs.current_tab = index
		check(tabs.current_tab == index, "the Poses tab can be selected with debug off")
		check(tabs.get_current_tab_control() == poses,
			"the Poses page is the selected page with debug off")
		var labels: Array = []
		_collect_labels(poses_list, labels)
		check(labels.has("Enable Oral") and labels.has("Enable Anal"),
			"the pose switches draw without debug mode")
		SETTINGS.debug_mode.set_bool(before)
		SETTINGS_UI.refresh_debug_visibility()
	tabs.free()


## A section heading is drawn once, even when its declarations interleave another group.
func _check_section_folding() -> void:
	var list := VBoxContainer.new()
	var fold: Array = [
		SETTINGS.by_path("presentation.missionary.size.canon.gaze_offset_mm"),
		SETTINGS.by_path("presentation.missionary.anon_size_match"),
	]
	SETTINGS_UI._build_sections(list, SETTINGS.POSES, "", fold, 16, null, Callable())
	var labels: Array = []
	_collect_labels(list, labels)
	check(labels.count("Missionary") == 1, "an interleaved section draws one heading")
	check(labels.has("Gaze height") and labels.has("Anon size match"),
		"an interleaved section keeps every row")
	check(labels.has("Size"), "the per-size section draws its dropdown")
	check(not labels.has("Bob"), "the Poses sections draw no General camera row")
	list.free()
	var general := VBoxContainer.new()
	SETTINGS_UI._build_sections(general, SETTINGS.GENERAL, "",
		[SETTINGS.by_path("camera_thrust.bob")], 16, null, Callable())
	var general_labels: Array = []
	_collect_labels(general, general_labels)
	check(general_labels.has("Bob"), "the General camera row stays in General")
	check(not general_labels.has("Missionary"), "the General camera row draws no pose heading")
	general.free()


## The catalog-driven tab lists every supported mod, even one that is not installed, with the
## version this adapter was verified with and every declared flag. Debug-only switches sit in the
## tab's Debug block.
func _check_integrations_panel() -> void:
	var debug_before := SETTINGS.debug_mode.get_bool()
	SETTINGS.debug_mode.set_bool(false)
	var list := VBoxContainer.new()
	var debug_section: Control = SETTINGS_UI.build_integrations(list, 16, null, Callable())
	var labels: Array = []
	_collect_labels(list, labels)
	var notice := _find_named(list, "IntegrationsExperimental")
	check(notice is PanelContainer, "the Integrations tab opens with the Experimental notice")
	check(labels.size() > 0 and str(labels[0]) == "Experimental",
		"the Experimental notice is the first text in the tab")
	var providers: Array[Dictionary] = INTEGRATIONS.all()
	check(not providers.is_empty(), "the Integrations tab has a provider")
	for provider: Dictionary in providers:
		var title := "%s by %s" % [str(provider.get("mod_name", "")),
			str(provider.get("author", ""))]
		check(labels.has(title), "the Integrations tab names %s" % title)
		var version := "Verified with version: %s" % str(provider.get("verified_version", ""))
		check(labels.has(version), "the Integrations tab shows %s" % version)
	for setting: SETTINGS.Setting in SETTINGS.tab_settings(SETTINGS.INTEGRATIONS):
		check(labels.has(setting.label),
			"the Integrations tab draws %s" % setting.name)
	check(debug_section is Control,
		"the Integrations tab builds its Debug block when it has debug settings")
	check(not (debug_section as Control).visible,
		"the Integrations Debug block is hidden without Enable debug")
	check(labels.has("Debug"), "the Integrations tab has one Debug heading")
	list.free()
	SETTINGS.debug_mode.set_bool(true)
	var debug_list := VBoxContainer.new()
	var shown: Control = SETTINGS_UI.build_integrations(debug_list, 16, null, Callable())
	check(shown is Control and (shown as Control).visible,
		"Enable debug shows the Integrations Debug block")
	var debug_labels: Array = []
	_collect_labels(debug_list, debug_labels)
	check(debug_labels.has("Hull width"), "the Debug block draws the hull width row")
	check(debug_labels.has("Hull height"), "the Debug block draws the hull height row")
	check(debug_labels.has("Min hull margin"), "the Debug block draws the min hull margin row")
	check(debug_labels.has("Show hull"), "the Debug block draws the Show hull row")
	debug_list.free()
	SETTINGS.debug_mode.set_bool(debug_before)


func _check_panel_tab(tab: String, debug_on: bool) -> void:
	var list := VBoxContainer.new()
	var owner := Node.new()
	var builder := func(body: VBoxContainer, size: int, tab_name: String) -> void:
		DEBUG_UI.build_actions(body, size, owner, tab_name)
	var debug_section: Control = SETTINGS_UI.build(list, tab, 16, null, Callable(), builder)
	var labels: Array = []
	_collect_labels(list, labels)
	var missing: Array = []
	var player_headings := {}
	var debug_headings := {}
	for setting: Variant in SETTINGS.tab_settings(tab):
		if bool(setting.hidden):
			continue
		if not labels.has(str(setting.label)):
			missing.append(setting.path)
		var heading := str(setting.group).split("›", true, 1)[0].strip_edges()
		if heading.is_empty():
			continue
		if bool(setting.debug):
			debug_headings[heading] = true
		else:
			player_headings[heading] = true
	check(missing.is_empty(), "%s tab draws every setting (%s)" % [tab, str(missing)])
	var missing_player: Array = []
	for heading: String in player_headings:
		if not labels.has(heading):
			missing_player.append(heading)
	check(missing_player.is_empty(), "%s player headings (%s)" % [tab, str(missing_player)])
	var missing_debug: Array = []
	for heading: String in debug_headings:
		if not labels.has(heading):
			missing_debug.append(heading)
	check(missing_debug.is_empty(), "%s Debug headings (%s)" % [tab, str(missing_debug)])
	if debug_section == null:
		check(SETTINGS.tab_settings(tab).is_empty(), "%s has no Debug block without debug settings" % tab)
	else:
		check(debug_section.visible == debug_on, "%s Debug block follows debug mode" % tab)
		if debug_on:
			check(labels.has("ACTIONS"), "%s Debug block lists the actions" % tab)
			var expected: Array = []
			match tab:
				SETTINGS.GENERAL:
					expected = ["Reload posed base", "Give footstool"]
				SETTINGS.ANATOMY:
					expected = ["Pitch +", "Up", "Pointed mare", "Show skeleton overlay"]
				SETTINGS.WORLD:
					expected = ["Resume auto", "Reset", "Clear cooldown"]
			var missing_actions: Array = []
			for action: String in expected:
				if not labels.has(action):
					missing_actions.append(action)
			check(missing_actions.is_empty(), "%s Debug actions (%s)"
				% [tab, str(missing_actions)])
			for page: String in ["mare", "act"]:
				var unexpected: Array = []
				for name: String in DEBUG_ACTIONS.wheel_actions(page):
					var action_label := DEBUG_ACTIONS.action_label(name, null)
					var short_label := DEBUG_ACTIONS.action_short(name, null)
					if labels.has(action_label):
						unexpected.append(action_label)
					if labels.has(short_label):
						unexpected.append(short_label)
				check(unexpected.is_empty(), "%s Debug block leaves the %s wheel actions off (%s)"
					% [tab, page, str(unexpected)])
	# An action lives in exactly one tab's block. "Heat" is also the Anatomy section heading, so
	# the World guard uses its row caption "Cycle" instead of the action's short label.
	if tab != SETTINGS.ANATOMY:
		check(not labels.has("Pitch +"), "%s does not carry the anatomy actions" % tab)
	if tab != SETTINGS.WORLD:
		check(not labels.has("Cycle"), "%s does not carry the world actions" % tab)
	list.free()
	if is_instance_valid(owner):
		owner.free()


## The player file loads eagerly and reports the shipped document's health.
func _check_load() -> void:
	check(SETTINGS.load_settings(), "the shipped defaults document loads")
	check(not SETTINGS.data().raw().is_empty(), "the player file is merged at load")


## Retired keys and deprecations run on every file; the only version step is the schema-11 split.
func _check_migration() -> void:
	var current: Dictionary = SETTINGS._migrate({
		"version": SETTINGS.SCHEMA_VERSION,
		"pose1_forward": 0.3,
		"relationship": {"ignore_gates": true, "promiscuity": "any"},
		"features": {"act_chat": true, "hud_readouts": true},
		"anatomy": {"genital_yaw_deg": 1.0, "skin_tone": 0.4},
	}, SETTINGS.SCHEMA_VERSION)
	check(current.has("pose1_forward"), "a current file skips a dropped pre-0.7 rename")
	var relationship: Dictionary = current.get("relationship", {})
	check(not relationship.has("ignore_gates"), "a retired setting is erased on a current file")
	check(str(relationship.get("promiscuity", "")) == "any",
		"a retired setting leaves its neighbour alone")
	var features: Dictionary = current.get("features", {})
	check(not features.has("act_chat"), "a retired key is erased on a current file")
	check(bool(features.get("hud_readouts", false)), "a live key survives the retired-key pass")
	check(near(float((current.get("anatomy", {}) as Dictionary).get("skin_tone", 0.0)), 0.4),
		"a stored skin tone is kept as a number")

	# The schema-11 step drops the prompt overrides a pre-0.7 file still carries.
	var older: Dictionary = SETTINGS._migrate({
		"version": SETTINGS.SCHEMA_VERSION - 1,
		"default": {"act_prompts": {"cue": ["old"]}, "event_prompts": {"climax": "old"}},
		"characters": {"fluttershy": {"act_prompts": {"cue": ["old"]},
			"event_prompts": {"climax": "old"}}},
	}, SETTINGS.SCHEMA_VERSION - 1)
	var prompt_paths: Array = []
	for path: String in _flatten_paths(older):
		if path.ends_with("act_prompts") or path.ends_with("event_prompts"):
			prompt_paths.append(path)
	check(prompt_paths.is_empty(),
		"no prompt override survives the schema-11 step: %s" % str(prompt_paths))
	var unchanged: Dictionary = {"version": SETTINGS.SCHEMA_VERSION, "default": {"cue_gap": 15.0},
		"characters": {"fluttershy": {"cue_gap": 16.0}}}
	check(SETTINGS._migrate(unchanged.duplicate(true), SETTINGS.SCHEMA_VERSION) == unchanged,
		"a current file has no structural step")


## The migration log is a leaf-path diff: changed, added and removed paths, with `version` ignored.
func _check_migration_diff() -> void:
	var before := {"version": 3, "controls": {"act_key": "o"}, "thrust": {"travel": 0.5},
		"old": {"radius": 0.4}}
	var after := {"version": 9, "controls": {"act_key": 54.0}, "thrust": {"travel": 0.5},
		"jiggle": {"radius": 0.4}}
	var diff := SETTINGS._migration_diff(before, after)
	check(diff["changed"] == ["controls.act_key"], "the diff names a changed leaf")
	check(diff["added"] == ["jiggle.radius"], "the diff names an added leaf")
	check(diff["removed"] == ["old.radius"], "the diff names a removed leaf")
	check(not (diff["changed"] as Array).has("version") and not (diff["added"] as Array).has("version"),
		"the schema version is not a migration change")
	var empty := SETTINGS._migration_diff({}, {})
	check((empty["changed"] as Array).is_empty() and (empty["added"] as Array).is_empty()
		and (empty["removed"] as Array).is_empty(), "an unchanged document has no changes")


## A script constant resolves a built-in before a same-named static function, so an API name that
## exists on Script/GDScript would silently call the built-in instead of ours.
func _check_api_names() -> void:
	var names := ["all_settings", "by_name", "by_path", "tab_settings", "groups", "act_snapshot",
		"get_value_at", "set_value_at", "default_at", "apply_live",
		"on_changed", "off_changed", "notify", "listener_count",
		"section_open", "set_section_open", "flag", "num", "choice", "list", "data", "defaults",
		"load_settings", "reload_file",
		"preferences", "pose", "template_for", "get_bool", "set_bool",
		"get_num", "set_num", "get_choice", "set_choice", "get_list", "set_list", "build",
		"build_actions", "build_integrations"]
	var clashes: Array = []
	for name: String in names:
		if ClassDB.class_has_method("GDScript", name):
			clashes.append(name)
	check(clashes.is_empty(), "no settings API name shadows a Script built-in: %s" % str(clashes))


## The change notification is the one path a settings edit takes to the services: `apply_live()`
## reaches every subscriber once, `off_changed()` releases it, and a freed subscriber is dropped
## instead of called. The order itself is `tests/test_settings_change.gd`.
func _check_change_notification() -> void:
	var base := CHANGE.listener_count()
	var first := ChangeSpy.new()
	var second := ChangeSpy.new()
	var first_call := Callable(first, "changed")
	CHANGE.on_changed(first_call)
	CHANGE.on_changed(first_call)
	CHANGE.on_changed(Callable(second, "changed"))
	check(CHANGE.listener_count() == base + 2, "a settings listener keeps one place")
	SETTINGS.apply_live()
	check(first.calls == 1 and second.calls == 1, "apply_live() notifies every subscriber once")
	CHANGE.off_changed(first_call)
	CHANGE.off_changed(Callable(second, "changed"))
	check(CHANGE.listener_count() == base, "off_changed() releases the place")
	var released := ChangeSpy.new()
	var released_call := Callable(released, "changed")
	released = null
	CHANGE.on_changed(released_call)
	check(CHANGE.listener_count() == base, "a freed callable is never registered")
	SETTINGS.apply_live()
	check(CHANGE.listener_count() == base, "a settings pass leaves the list as it found it")


## The Characters form draws the teat-size row in its approved place: after Neglect tolerance,
## before the touch rows, with Auto first and the four named sizes.
func _check_characters_form() -> void:
	var list := VBoxContainer.new()
	CHARACTERS_UI.build(list, 16, Callable(), Callable(), Callable())
	var labels: Array = []
	_collect_labels(list, labels)
	check(labels.has("Teat size"), "the Characters form has a Teat size row")
	for option: String in ["Auto", "Small", "Medium", "Large", "Huge"]:
		check(labels.has(option), "the Teat size row offers %s" % option)
	var tolerance_index := labels.find("Neglect tolerance")
	var teat_index := labels.find("Teat size")
	var touch_index := labels.find("Smack")
	check(tolerance_index >= 0 and teat_index > tolerance_index,
		"Teat size follows Neglect tolerance")
	check(touch_index >= 0 and teat_index < touch_index,
		"Teat size comes before the touch rows")
	list.free()


## Per-mare profiles share the file and the merge; a few representative checks.
func _check_profiles() -> void:
	var base := ROWS.Rows.of(SETTINGS._filled_default())
	check(SETTINGS.CHARACTER_ORDER.size() == SETTINGS.CHARACTER_NAMES.size(),
		"every pony has a display name")
	check(SETTINGS.CHARACTER_ORDER.size() == SETTINGS.CHARACTER_TEMPLATES.size(),
		"every editable pony has a preference template")
	var modded: Dictionary = SETTINGS._profile_merge(base.raw(), {}, "a_modded_mare")
	check((modded["preferences"] as Dictionary)
		== SETTINGS.default_preferences_for(base, "a_modded_mare").raw(),
		"an off-roster mare uses the global preference profile")
	check(not (modded.get("poses", {}) as Dictionary).is_empty(),
		"an off-roster mare gets the pose defaults")
	var modded_override := SETTINGS.profile_for(base,
		ROWS.Rows.of({"a_modded_mare": {"preferences": {"intensity": "soft"}}}),
		"a_modded_mare")
	check(modded_override.preferences.str_value("intensity", "") == "soft",
		"an off-roster mare keeps a saved preference override")
	check(modded_override.participation.bool_value("acts", true),
		"the typed profile carries her participation")
	check(modded_override.consent.has("public"),
		"the typed profile carries her consent")
	check(not modded_override.identity.has("eligible"),
		"an off-roster mare has no provider assertion")
	check(SETTINGS.anatomy_placement_default("a_modded_mare").raw()
		== SETTINGS.anatomy_placement_default("").raw(),
		"an off-roster mare uses the global anatomy placement")
	var override: Dictionary = SETTINGS._profile_merge(base.raw(),
		{"fluttershy": {"cue_gap": 15.0}}, "fluttershy")
	check(near(float(override.get("cue_gap", 0.0)), 15.0), "a character override wins")
	check(not SETTINGS.template_for("fluttershy").raw().is_empty(), "live template")


## The identity document is tri-state: a provider assertion is present, absence leaves the game the
## decision, and the typed profile shares the same participation block.
func _check_profile_identity() -> void:
	var id := "typed_identity_mare"
	SETTINGS.MARE_REGISTRY.reset()
	check(not SETTINGS.profile_has_assertion(id), "without a provider the identity has no assertion")
	var identity := SETTINGS.profile_identity(id)
	check(identity.rows("participation").bool_value("acts", false),
		"the identity carries participation")
	check(not identity.has("eligible"), "an absent assertion is not stored")
	var base := ROWS.Rows.of(SETTINGS._filled_default())
	var profile := SETTINGS.profile_for(base, ROWS.Rows.of({}), id)
	check(profile.identity.rows("participation").raw() == profile.participation.raw(),
		"the profile facets share the participation block")
	check(profile.consent.keys().size() == CONSENT.KEYS.size(),
		"the profile carries the consent keys")
	SETTINGS.MARE_REGISTRY.register(1, SETTINGS.MARE_REGISTRY.Descriptor.from_dict({
		"id": id,
		"source": "identity_test",
		"eligible": true,
		"profile": {"participation": {"acts": false}},
	}))
	check(SETTINGS.profile_has_assertion(id) and SETTINGS.profile_eligible(id),
		"a provider assertion is readable")
	var asserted := SETTINGS.profile_for(base, ROWS.Rows.of({}), id)
	check(asserted.identity.bool_value("eligible", false),
		"the typed identity carries the assertion")
	check(not asserted.participation.bool_value("acts", true),
		"the provider participation reaches the typed profile")
	SETTINGS.MARE_REGISTRY.reset()
	check(not SETTINGS.profile_has_assertion(id),
		"the assertion clears when the provider leaves")


## A cross-mod provider layer wins over the catalog and the global default, and the player's sparse
## override wins per field. Unregistering restores the catalog/global values.
func _check_provider_precedence() -> void:
	var id := "provider_precedence_mare"
	SETTINGS.MARE_REGISTRY.reset()
	var base := ROWS.Rows.of(SETTINGS._filled_default())
	var registered := SETTINGS.MARE_REGISTRY.register(1,
		SETTINGS.MARE_REGISTRY.Descriptor.from_dict({
			"id": id,
			"source": "precedence_test",
			"preferences": {"intensity": "rough", "notes": "Provider note."},
			"poses": {"standing": {"bow": 9.0}},
			"placement": {"tail_y": 0.09},
		}))
	check(registered.ok, "the precedence provider registers")

	var profile := SETTINGS.profile_for(base, ROWS.Rows.of({}), id)
	check(profile.preferences.str_value("intensity", "") == "rough",
		"the provider preference beats the global default")
	var standing: Dictionary = SETTINGS.template_for(id).rows("poses").raw().get("standing", {})
	check(near(float(standing.get("bow", 0.0)), 9.0),
		"the provider pose beats the catalog pose")
	check(near(float(SETTINGS.anatomy_placement(id).raw().get("tail_y", 0.0)), 0.09),
		"the provider placement beats the global default")

	# The player's edit wins for the field it changed, and only that field.
	SETTINGS.save_preferences(id, ROWS.Rows.of({"intensity": "soft", "warmth": "slow"}))
	var live_characters: Dictionary = SETTINGS.data().raw().get("characters", {})
	var characters := ROWS.Rows.of(live_characters)
	var player := SETTINGS.profile_for(base, characters, id)
	check(player.preferences.str_value("intensity", "") == "soft",
		"a player preference beats the provider")
	check(player.preferences.str_value("notes", "") == "Provider note.",
		"the provider preference survives the player's edit")

	var placed := SETTINGS.anatomy_placement(id).raw()
	placed["tail_y"] = 0.11
	SETTINGS.save_anatomy_placement(id, ROWS.Rows.of(placed))
	check(near(float(SETTINGS.anatomy_placement(id).raw().get("tail_y", 0.0)), 0.11),
		"a player placement beats the provider")

	SETTINGS.MARE_REGISTRY.unregister(1, id)
	check(near(float(SETTINGS.anatomy_placement(id).raw().get("tail_y", 0.0)), 0.11),
		"the player placement survives the provider leaving")
	SETTINGS.save_anatomy_placement(id, SETTINGS.anatomy_placement_default(id))
	check(not SETTINGS.anatomy_placement_has_override(id),
		"removing the player placement returns to the global default")
	var restored := SETTINGS.profile_for(base, characters, id)
	check(restored.preferences.str_value("intensity", "") == "soft",
		"the player preference survives the provider leaving")
	check(restored.preferences.str_value("notes", "")
		== base.rows("preferences").str_value("notes", ""),
		"the provider note falls back to the global default")
	var restored_standing: Dictionary = SETTINGS.template_for(id).rows("poses").raw().get(
		"standing", {})
	var base_standing: Dictionary = base.rows("poses").raw().get("standing", {})
	check(near(float(restored_standing.get("bow", 0.0)), float(base_standing.get("bow", 0.0))),
		"the provider pose falls back to the catalog")

	SETTINGS.reset_preferences(id)
	SETTINGS.MARE_REGISTRY.reset()


## A saved character block holds only real differences from the built-in template, so a provider
## can update the fields the player never edited.
func _check_character_overrides() -> void:
	var full: Dictionary = SETTINGS.CHARACTER_TEMPLATES["fluttershy"].duplicate(true)
	var data := {"characters": {"fluttershy": full}}
	var normalized := SETTINGS._normalize_character_overrides(data)
	check(not normalized.has("characters")
		or (normalized["characters"] as Dictionary).is_empty(),
		"a materialized built-in template normalizes away")

	# The schema-11 import moves the block into the character document and normalizes it once.
	var moved: Dictionary = {}
	var imported := SETTINGS._import_player({"characters": {"fluttershy": full}}, moved, false)
	check(bool(imported["split"]), "a schema-10 character block imports")
	check(not moved.has("characters") or (moved["characters"] as Dictionary).is_empty(),
		"an imported full-template file normalizes once")
	var current: Dictionary = {"characters": {"fluttershy": full}}
	var ignored := SETTINGS._import_player({}, current, true)
	check(not bool(ignored["split"])
		and (current.get("characters", {}) as Dictionary).has("fluttershy"),
		"a current character document is not normalized twice")

	var empty := {"characters": {"fluttershy": {"preferences": {}}}}
	var empty_normalized := SETTINGS._normalize_character_overrides(empty)
	check(not empty_normalized.has("characters"),
		"an empty saved profile is not a player override")

	var shipped_consent := CONSENT.defaults("fluttershy")
	var consent_data := {"characters": {"fluttershy": {"consent": shipped_consent}}}
	var consent_normalized := SETTINGS._normalize_character_overrides(consent_data)
	check(not consent_normalized.has("characters"),
		"unchanged consent normalizes away")
	var changed_consent := shipped_consent.duplicate(true)
	changed_consent["public"] = not bool(shipped_consent.get("public", false))
	var changed_data := {"characters": {"fluttershy": {"consent": changed_consent}}}
	var changed_normalized := SETTINGS._normalize_character_overrides(changed_data)
	var stored_consent: Dictionary = ((changed_normalized.get("characters", {}) as Dictionary)
		.get("fluttershy", {}) as Dictionary).get("consent", {})
	check(stored_consent.has("public") and not stored_consent.has("anal")
		and not stored_consent.has("oral"), "only changed consent is kept")
	var custom_consent := CONSENT.defaults("a_modded_mare")
	var custom_consent_data := {"characters": {"a_modded_mare": {"consent": custom_consent}}}
	var custom_consent_normalized := SETTINGS._normalize_character_overrides(custom_consent_data)
	check(not custom_consent_normalized.has("characters"),
		"a custom mare's unchanged consent also normalizes away")

	var edited := SETTINGS.default_preferences("fluttershy").raw()
	edited["intensity"] = "soft"
	var edited_data := {"characters": {"fluttershy": {"preferences": edited}}}
	var edited_norm := SETTINGS._normalize_character_overrides(edited_data)
	var edited_pref: Dictionary = ((edited_norm["characters"] as Dictionary)["fluttershy"]
		as Dictionary).get("preferences", {})
	check(edited_pref.has("intensity") and not edited_pref.has("notes"),
		"a full saved profile normalizes to the edited key")
	check(not edited_pref.has("tolerance"), "the untouched defaults are not pinned")

	var sparse := {"characters": {"fluttershy": {"preferences": {"intensity": "soft"}}}}
	var sparse_norm := SETTINGS._normalize_character_overrides(sparse)
	var sparse_pref: Dictionary = ((sparse_norm["characters"] as Dictionary)["fluttershy"]
		as Dictionary).get("preferences", {})
	check(sparse_pref == {"intensity": "soft"},
		"a sparse profile keeps only its own key")

	var custom := {"characters": {"a_modded_mare": {"preferences": {"intensity": "soft"}}}}
	var custom_norm := SETTINGS._normalize_character_overrides(custom)
	check((custom_norm["characters"] as Dictionary).has("a_modded_mare"),
		"a custom mare block is untouched")

	var base := ROWS.Rows.of(SETTINGS._filled_default())
	var fluttershy: Dictionary = SETTINGS._profile_merge(base.raw(), {}, "fluttershy")
	check(not (fluttershy.get("poses", {}) as Dictionary).is_empty(),
		"built-in poses seed without a saved block")

	SETTINGS.save_preferences("fluttershy", ROWS.Rows.of({"intensity": "soft"}))
	var saved: Dictionary = SETTINGS.data().raw().get("characters", {})
	var entry: Dictionary = (saved as Dictionary).get("fluttershy", {})
	var stored: Dictionary = entry.get("preferences", {})
	check(stored.has("intensity") and not stored.has("notes"),
		"a save stores only the preference difference")
	SETTINGS.reset_preferences("fluttershy")

	# The teat size is a per-mare field: it saves as its own difference, merges over the template
	# and resets with the rest of the profile.
	SETTINGS.save_preferences("fluttershy", ROWS.Rows.of({"teat_size": "large"}))
	saved = SETTINGS.data().raw().get("characters", {})
	entry = (saved as Dictionary).get("fluttershy", {})
	stored = entry.get("preferences", {})
	check(str(stored.get("teat_size", "")) == "large" and not stored.has("notes"),
		"a saved teat size stores only its own difference")
	check(SETTINGS.preferences("fluttershy").str_value("teat_size", "") == "large",
		"the saved teat size merges over the template")
	check(not SETTINGS.preferences_match(SETTINGS.preferences("fluttershy"),
		SETTINGS.default_preferences("fluttershy")),
		"a changed teat size is a real preset difference")
	SETTINGS.reset_preferences("fluttershy")
	check(SETTINGS.preferences("fluttershy").str_value("teat_size", "") == "auto",
		"a reset restores the automatic teat size")

	var consent := SETTINGS.consent("fluttershy")
	var mutated := consent.raw().duplicate(true)
	mutated["anal"] = not consent.bool_value("anal", false)
	check(SETTINGS.consent("fluttershy").raw() == consent.raw(),
		"a consent caller cannot mutate the memoized block")
	SETTINGS.save_consent("fluttershy", consent)
	saved = SETTINGS.data().raw().get("characters", {})
	entry = (saved as Dictionary).get("fluttershy", {})
	check(not entry.has("consent"), "saving the resolved consent stores nothing")
	var changed := consent.raw().duplicate(true)
	changed["public"] = not consent.bool_value("public", false)
	SETTINGS.save_consent("fluttershy", ROWS.Rows.of(changed))
	saved = SETTINGS.data().raw().get("characters", {})
	entry = (saved as Dictionary).get("fluttershy", {})
	var consent_diff: Dictionary = entry.get("consent", {})
	check(consent_diff.has("public") and not consent_diff.has("anal"),
		"a consent save stores only the changed key")
	check(SETTINGS.consent("fluttershy").bool_value("public")
		== bool(changed.get("public", false)),
		"a consent save invalidates the memoized block")
	SETTINGS.save_consent("fluttershy", consent)


## A participation block is a subtractive capability layer. A player's `eligible` assertion is
## never stored, and only the player's real participation differences are saved.
func _check_participation() -> void:
	var data := {"characters": {"fluttershy": {
		"eligible": true,
		"profile": {"participation": {"acts": true, "anatomy": false, "tail": true}},
	}}}
	var normalized := SETTINGS._normalize_character_overrides(data)
	var entry: Dictionary = (normalized.get("characters", {}) as Dictionary).get("fluttershy", {})
	check(not entry.has("eligible"), "a player's eligible assertion is dropped")
	var participation: Dictionary = (entry.get("profile", {}) as Dictionary).get("participation", {})
	check(not participation.has("acts"), "an unchanged participation is not stored")
	check(not bool(participation.get("anatomy", true)), "a changed participation is kept")
	check(not participation.has("tail"), "an unchanged participation is not stored")

	var resolved := SETTINGS.profile_participation("fluttershy")
	check(resolved.bool_value("acts", false), "the base participation is all allowed")
	check(resolved.bool_value("anatomy", false), "the base participation is all allowed")
	check(resolved.bool_value("tail", false), "the base participation is all allowed")

	SETTINGS.save_participation("fluttershy",
		ROWS.Rows.of({"acts": false, "anatomy": true, "tail": true}))
	var saved: Variant = SETTINGS.data().raw().get("characters", {})
	var saved_entry: Dictionary = (saved as Dictionary).get("fluttershy", {})
	var saved_profile: Dictionary = (saved_entry.get("profile", {}) as Dictionary).get("participation", {})
	check(not bool(saved_profile.get("acts", true)), "a saved opt-out is stored")
	check(not saved_profile.has("anatomy"), "an unchanged participation is not stored")
	check(not saved_profile.has("tail"), "an unchanged participation is not stored")
	var opted_out := SETTINGS.profile_participation("fluttershy")
	check(not opted_out.bool_value("acts", true), "the memoized profile invalidates on a save")
	SETTINGS.reset_participation("fluttershy")
	var after: Variant = SETTINGS.data().raw().get("characters", {})
	check(not (after as Dictionary).has("fluttershy"), "reset removes the participation block")
	var restored := SETTINGS.profile_participation("fluttershy")
	check(restored.bool_value("acts", false), "the memoized profile invalidates on a reset")


## An unreadable, malformed or newer player file is preserved, logged and replaced by a fresh
## document built from the shipped defaults.
func _check_player_file_recovery() -> void:
	var folder := "user://mods/data/unfplap"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var path := folder.path_join("settings.json")
	var characters_path := folder.path_join("characters.json")
	_clear_settings_backups(folder)
	if FileAccess.file_exists(characters_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(characters_path))

	var broken := FileAccess.open(path, FileAccess.WRITE)
	broken.store_string("{ broken")
	broken.close()
	SETTINGS.reload_file()
	var backups := _settings_backups(folder)
	check(backups.size() == 1, "a malformed player file is preserved once")
	if backups.size() == 1:
		check(FileAccess.get_file_as_string(backups[0]).contains("broken"),
			"the malformed text is preserved")
	check(not SETTINGS.data().raw().is_empty(), "a malformed player file falls back to the defaults")
	check(_settings_version(path) == SETTINGS.SCHEMA_VERSION,
		"a malformed player file is replaced by a current document")
	_clear_settings_backups(folder)

	var newer := {"version": SETTINGS.SCHEMA_VERSION + 1, "debug_mode": true}
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(newer, "\t") + "\n")
	file.close()
	SETTINGS.reload_file()
	backups = _settings_backups(folder)
	check(backups.size() == 1, "a newer player file is preserved once")
	if backups.size() == 1:
		var backup_data: Variant = JSON.parse_string(
			FileAccess.get_file_as_string(backups[0]))
		check(backup_data is Dictionary
			and int((backup_data as Dictionary).get("version", 0)) == SETTINGS.SCHEMA_VERSION + 1,
			"the newer schema is preserved")
	check(_settings_version(path) == SETTINGS.SCHEMA_VERSION,
		"a newer player file is replaced by a current document")
	_clear_settings_backups(folder)

	# A malformed character file is preserved; the settings document still supplies its profile.
	var partial := {"version": SETTINGS.SCHEMA_VERSION, "debug_mode": true,
		"characters": {"fluttershy": {"preferences": {"intensity": "soft"}}}}
	_write_json(path, partial)
	var broken_characters := FileAccess.open(characters_path, FileAccess.WRITE)
	broken_characters.store_string("{ broken")
	broken_characters.close()
	SETTINGS.reload_file()
	var character_backups := _character_backups(folder)
	check(character_backups.size() == 1, "a malformed character file is preserved once")
	check(SETTINGS.preferences("fluttershy").str_value("intensity", "") == "soft",
		"the settings profile moves into a fresh character file")
	var rebuilt := _read_json(characters_path)
	check(((rebuilt.get("characters", {}) as Dictionary).has("fluttershy")),
		"the moved profile is written to the character file")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(characters_path))
	_clear_character_backups(folder)


## A schema-10 player document splits once: the profile and the per-mare rows move to
## characters.json, the prompt overrides go, and the settings file keeps its declared blocks.
func _check_player_split() -> void:
	var folder := "user://mods/data/unfplap"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var path := folder.path_join("settings.json")
	var characters_path := folder.path_join("characters.json")
	_clear_settings_backups(folder)
	if FileAccess.file_exists(characters_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(characters_path))
	var old := {
		"version": SETTINGS.SCHEMA_VERSION - 1,
		"debug_mode": true,
		"default": {
			"preferences": {"intensity": "rough"},
			"act_prompts": {"cue": ["old"]},
			"event_prompts": {"climax": "old"},
		},
		"characters": {
			"fluttershy": {"preferences": {"intensity": "soft"},
				"act_prompts": {"cue": ["old"]}},
		},
		"anatomy": {"placement": {
			"default": {"offset_x": 0.01},
			"anon": {"scale": 1.1},
			"fluttershy": {"tail_y": 0.02},
		}},
	}
	_write_json(path, old)
	SETTINGS.reload_file()
	var settings_file := _read_json(path)
	check(int(settings_file.get("version", 0)) == SETTINGS.SCHEMA_VERSION,
		"the split writes a current settings document")
	check(not settings_file.has("default") and not settings_file.has("characters"),
		"the settings document holds no character blocks after the split")
	var kept: Dictionary = (settings_file.get("anatomy", {}) as Dictionary).get("placement", {})
	check(kept.has("default") and kept.has("anon"),
		"the declared placement rows stay in the settings document")
	check(not kept.has("fluttershy"), "a per-mare placement row leaves the settings document")
	var characters_file := _read_json(characters_path)
	check(int(characters_file.get("version", 0)) == SETTINGS.SCHEMA_VERSION,
		"the split writes a current character document")
	var default_block: Dictionary = characters_file.get("default", {})
	check(not default_block.has("act_prompts") and not default_block.has("event_prompts"),
		"the default prompt overrides are gone")
	check(str((default_block.get("preferences", {}) as Dictionary).get("intensity", ""))
		== "rough", "the default profile difference moves")
	var roster: Dictionary = characters_file.get("characters", {})
	check(not (roster.get("fluttershy", {}) as Dictionary).has("act_prompts"),
		"a character's prompt overrides are gone")
	var anatomy_block: Dictionary = characters_file.get("anatomy", {})
	var placement: Dictionary = anatomy_block.get("placement", {})
	check(placement.has("fluttershy"), "the per-mare placement row moves")
	check(SETTINGS.preferences("fluttershy").str_value("intensity", "") == "soft",
		"the moved profile is live")
	check(near(float(SETTINGS.anatomy_placement("fluttershy").raw()["tail_y"]), 0.02),
		"the moved placement is live")

	# A current pair reloads with no migration: the second load writes the same bytes.
	var settings_before := FileAccess.get_file_as_string(path)
	var characters_before := FileAccess.get_file_as_string(characters_path)
	SETTINGS.reload_file()
	check(FileAccess.get_file_as_string(path) == settings_before,
		"a current settings document reloads unchanged")
	check(FileAccess.get_file_as_string(characters_path) == characters_before,
		"a current character document reloads unchanged")
	var current := _read_json(path)
	check(SETTINGS._migrate(current.duplicate(true), SETTINGS.SCHEMA_VERSION) == current,
		"a current file runs no migration step")


## Both files present is a recovery: the new character document wins and the old copies in the
## settings document are erased.
func _check_player_recovery() -> void:
	var folder := "user://mods/data/unfplap"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var path := folder.path_join("settings.json")
	var characters_path := folder.path_join("characters.json")
	_write_json(path, {"version": SETTINGS.SCHEMA_VERSION, "debug_mode": false,
		"default": {"preferences": {"intensity": "rough"}},
		"characters": {"fluttershy": {"preferences": {"intensity": "rough"}}}})
	_write_json(characters_path, {"version": SETTINGS.SCHEMA_VERSION,
		"default": {"preferences": {"intensity": "soft"}},
		"characters": {"fluttershy": {"preferences": {"intensity": "soft"}}}})
	SETTINGS.reload_file()
	var settings_file := _read_json(path)
	check(not settings_file.has("default") and not settings_file.has("characters"),
		"the recovery erases the old copies from the settings document")
	check(SETTINGS.preferences("fluttershy").str_value("intensity", "") == "soft",
		"the new character document wins the recovery")
	var characters_file := _read_json(characters_path)
	var roster: Dictionary = characters_file.get("characters", {})
	var profile: Dictionary = (roster.get("fluttershy", {}) as Dictionary).get("preferences", {})
	check(str(profile.get("intensity", "")) == "soft",
		"the recovered character document is kept")


func _write_json(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "\t") + "\n")
	file.close()


func _read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _settings_backups(folder: String) -> Array:
	var out: Array = []
	for name: String in DirAccess.get_files_at(ProjectSettings.globalize_path(folder)):
		if name.begins_with("settings.json.") and name.ends_with(".invalid"):
			out.append(folder.path_join(name))
	return out


func _character_backups(folder: String) -> Array:
	var out: Array = []
	for name: String in DirAccess.get_files_at(ProjectSettings.globalize_path(folder)):
		if name.begins_with("characters.json.") and name.ends_with(".invalid"):
			out.append(folder.path_join(name))
	return out


func _clear_character_backups(folder: String) -> void:
	for path: String in _character_backups(folder):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _clear_settings_backups(folder: String) -> void:
	for name: String in DirAccess.get_files_at(ProjectSettings.globalize_path(folder)):
		if name.begins_with("settings.json.") and name.ends_with(".invalid"):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(folder.path_join(name)))


func _settings_version(path: String) -> int:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return int((parsed as Dictionary).get("version", 0))
	return -1


## The base-game accessors answer the settings page and the mods host without a raw call.
func _check_base_game_access() -> void:
	var page := FakeSettingsPage.new()
	var parent := VBoxContainer.new()
	var button := GAME.settings_page_button(page, parent, "Unfplap")
	check(button != null and button.text == "Unfplap",
		"the settings page builds its tab button")
	check(page.last_callback.is_valid(), "the page's builder gets a live handler")
	var icon := GAME.settings_page_icon(page, "heart")
	check(icon != null, "the settings page answers its icon texture")
	GAME.settings_page_redraw(page)
	check(page.redraws == 1, "the settings page redraws once")
	var menu_icon := FakeIcon.new()
	GAME.set_menu_icon_kind(menu_icon, "heart")
	check(menu_icon.kind == "heart", "the menu icon takes its kind")
	var picker := GAME.menu_picker()
	check(picker is Control, "the menu's in-page dropdown is built for a page")
	if picker is Control:
		(picker as Control).free()
	check(GAME.settings_page_button(null, parent, "Unfplap") == null,
		"an absent settings page has no button")
	check(GAME.settings_page_icon(null, "heart") == null,
		"an absent settings page has no icon")
	GAME.settings_page_redraw(null)
	var plain := Node.new()
	check(GAME.settings_page_button(plain, parent, "Unfplap") == null,
		"a page without the builder has no button")
	check(GAME.settings_page_icon(plain, "heart") == null,
		"a page without the texture op has no icon")
	GAME.settings_page_redraw(plain)
	GAME.set_menu_icon_kind(null, "heart")
	var mods := FakeMods.new()
	check(GAME.mods_data_folder(mods, "unfplap") == "user://mods/data/unfplap",
		"the mods host answers its data folder")
	check(GAME.mods_data_folder(null, "unfplap") == "",
		"an absent mods host has no folder")
	check(GAME.mods_data_folder(plain, "unfplap") == "",
		"a host without the folder op has no folder")
	var settings := FakeSettings.new()
	var saved := SETTINGS._game_settings
	SETTINGS._game_settings = settings
	check(SETTINGS.pony_size_name() == "mounting",
		"the size preset reads the game setting through the accessor")
	check(SETTINGS.caption_mode() == "caption",
		"the caption mode reads the game setting through the accessor")
	check(is_equal_approx(SETTINGS.anon_height_scale(), 1.3),
		"the Anon height scale reads the game setting through the accessor")
	check(SETTINGS.tts_enabled(), "the TTS switch reads the game setting through the accessor")
	SETTINGS._game_settings = plain
	check(is_equal_approx(SETTINGS.anon_height_scale(), 1.0),
		"a settings node without the height answers the ordinary 1.0")
	check(not SETTINGS.tts_enabled(), "a settings node without the switch answers TTS off")
	SETTINGS._game_settings = saved
	page.free()
	parent.free()
	menu_icon.free()
	plain.free()
	mods.free()
	settings.free()


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


func _find_named(node: Node, target: String) -> Node:
	if str(node.name) == target:
		return node
	for child: Node in node.get_children():
		var found := _find_named(child, target)
		if found != null:
			return found
	return null


func _find_button_text(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text.strip_edges() == text:
		return node as Button
	for child: Node in node.get_children():
		var found := _find_button_text(child, text)
		if found != null:
			return found
	return null
