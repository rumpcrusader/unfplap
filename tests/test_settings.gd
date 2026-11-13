extends SceneTree
## The settings API contract, tested once.
##
## The declarations are compile-time: a wrong accessor, a mistyped name or a missing setting fails
## to parse. What stays here is what the compiler cannot see: registry integrity, defaults, the
## file round-trip, coercion and bounds, section state, the panel layout, and the per-mare merge.
##
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_settings.gd

const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const SETTINGS_UI := preload("res://mods/unfplap/settings/ui.gd")
const DEBUG_UI := preload("res://mods/unfplap/debug/ui.gd")
const DEBUG_ACTIONS := preload("res://mods/unfplap/debug/service.gd")
const CONSENT := preload("res://mods/unfplap/shared/consent.gd")
const INTEGRATIONS := preload("res://mods/unfplap/shared/integrations.gd")


class PhaseMain extends Node:
	var phase := "heat"

	func debug_cycle_phase() -> String:
		return phase

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
	_check_snapshot()
	_check_placement()
	_check_tail_seat()
	_check_write_round_trip()
	_check_read_view()
	_check_coercion()
	_check_sections()
	_check_groups()
	_check_panels()
	_check_anatomy_gate()
	_check_debug_actions()
	_check_integrations_panel()
	_check_section_folding()
	_check_migration()
	_check_placement_migration()
	_check_api_names()
	_check_profiles()
	_check_character_overrides()
	_check_participation()
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
		# An empty group is legal: the setting then has no section heading. An empty hint is
		# legal too: the label alone can say what the row does.
		if str(setting.label).is_empty():
			complete = false
		if str(setting.tab) not in [SETTINGS.GENERAL, SETTINGS.ANATOMY, SETTINGS.WORLD,
				SETTINGS.INTEGRATIONS]:
			complete = false
		tabs[setting.tab] = int(tabs.get(setting.tab, 0)) + 1
	check(complete, "every setting has a unique name and path, a label and tab")
	for tab: String in [SETTINGS.GENERAL, SETTINGS.ANATOMY, SETTINGS.WORLD,
			SETTINGS.INTEGRATIONS]:
		check(int(tabs.get(tab, 0)) > 0, "%s tab has settings" % tab)
	check(SETTINGS.by_name("hud_readouts") != null, "a setting is reachable by name")
	check(SETTINGS.by_path("features.hud_readouts") != null, "a setting is reachable by path")
	check(SETTINGS.by_path("features.act_faces") == null, "act faces are not a setting")
	for name: String in ["act_lines", "act_line_angles", "caress_areas",
			"allow_act_during_cuddle", "contact_gap_m", "standing_plant_feet",
			"plant_spread_m", "anatomy_vr", "show_dock", "dock_color"]:
		check(SETTINGS.by_name(name) == null, "%s is retired" % name)


## The declared defaults are the values a fresh file would give.
func _check_defaults() -> void:
	check(bool(SETTINGS.hud_readouts.default), "hud readouts default on")
	check(near(float(SETTINGS.pace.default), 1.0), "auto pace default")
	check(str(SETTINGS.orientation.default) == "up", "thrust orientation default")
	check(not bool(SETTINGS.debug_mode.default), "debug mode is off by default")
	check(bool(SETTINGS.reseat_tails.default), "re-seat tails defaults on")
	check(near(float(SETTINGS.tail_y.default), 0.0) and bool(SETTINGS.tail_y.debug),
		"the default tail Y is a debug number at zero")
	check(near(float(SETTINGS.dock_scale.default), 1.2) and bool(SETTINGS.dock_scale.debug),
		"the default dock scale is a debug number at 1.2")
	check(near(float(SETTINGS.tail_tilt_deg.default), 0.0) and bool(SETTINGS.tail_tilt_deg.debug),
		"the default tail tilt is a debug number at zero")
	check(bool(SETTINGS.radius.debug), "the jiggle radius is a debug setting")
	check(not bool(SETTINGS.skeleton_overlay.get_bool()), "the skeleton overlay is off by default")
	check(bool(SETTINGS.skeleton_overlay.debug), "the skeleton overlay is a debug setting")
	check(not bool(SETTINGS.kissing_reactions.default),
		"the Kissing reaction bridge defaults off")
	check(not bool(SETTINGS.idle_life_stretch.default),
		"the Idle Life stretch pose defaults off")
	check(not bool(SETTINGS.kissing_full_fidgets.default)
		and bool(SETTINGS.kissing_full_fidgets.debug),
		"full Kissing fidgets are an off-by-default debug feature")
	check(str(SETTINGS.dock_style.default) == "genitals", "dock style defaults to genitals")
	check(near(float(SETTINGS.back_out_m.default), 0.0) and bool(SETTINGS.back_out_m.debug),
		"back-out gap is a debug number at zero")
	check(near(float(SETTINGS.back_out_m.low), -5.0)
		and near(float(SETTINGS.back_out_m.high), 5.0),
		"back-out gap keeps its signed range")
	check(near(float(SETTINGS.pace.low), 1.0) and near(float(SETTINGS.pace.high), 3.75),
		"auto pace keeps its contract bounds")


## The act snapshot carries the typed values the runtime reads per stroke or per frame.
func _check_snapshot() -> void:
	var snap := SETTINGS.act_snapshot("missionary")
	check(near(snap.thrust_pixels_per_cm, SETTINGS.pixels_per_cm.get_num()),
		"the act snapshot carries sensitivity")
	check(snap.thrust_up == (SETTINGS.orientation.get_choice() == "up"),
		"the act snapshot carries the thrust direction")
	check(bool(snap.features.get("hud_readouts", false)), "the act snapshot carries features")
	check(snap.features.has("kissing_full_fidgets"),
		"the act snapshot carries the Kissing debug feature")
	check(snap.features.has("idle_life_stretch"),
		"the act snapshot carries the Idle Life stretch feature")
	check(snap.caress_quality == SETTINGS.quality.get_choice(),
		"the act snapshot carries the caress quality")
	check(snap.presentation.has("camera_mode"), "the act snapshot carries the pose presentation")
	check(snap.climax_mode == SETTINGS.climax_mode.get_choice(),
		"the act snapshot carries the climax face")
	check(near(SETTINGS.palm_scale_for("canon"), SETTINGS.canon.get_num()),
		"the palm scale resolves a size without a path read")


## Anatomy placement is one default block plus partial per-mare overrides.
func _check_placement() -> void:
	var base := SETTINGS.anatomy_placement_default("")
	check(near(float(base["offset_y"]), 0.505), "placement default Y")
	check(near(float(base["pitch_deg"]), 3.0), "placement default pitch")
	check(near(float(base["tail_y"]), 0.0) and near(float(base["tail_z"]), -0.01),
		"placement default tail")
	check(near(float(base["dock_y"]), 0.01) and near(float(base["dock_scale"]), 1.2),
		"placement default dock")
	check(near(float(base["scale"]), 0.682), "placement default scale")
	check(near(float(base["tail_tilt_deg"]), 0.0), "placement default tail tilt")

	SETTINGS.save_anatomy_placement("octavia_melody",
		{"offset_y": 0.51, "offset_z": 0.284, "scale": 0.762})
	var over := SETTINGS.anatomy_placement("octavia_melody")
	check(near(float(over["offset_y"]), 0.51), "per-mare override Y")
	check(near(float(over["offset_x"]), 0.0), "an omitted override key falls back")
	check(near(float(over["scale"]), 0.762), "per-mare override scale")
	check(SETTINGS.anatomy_placement_has_override("octavia_melody"),
		"a differing per-mare block is an override")
	SETTINGS.save_anatomy_placement("octavia_melody", base)
	check(not SETTINGS.anatomy_placement_has_override("octavia_melody"),
		"a block equal to the default is not an override")
	check(near(float(SETTINGS.anatomy_placement("rarity")["tail_y"]), -0.015)
		and near(float(SETTINGS.anatomy_placement("rarity")["tail_z"]), -0.01)
		and near(float(SETTINGS.anatomy_placement("rarity")["dock_y"]), 0.015)
		and near(float(SETTINGS.anatomy_placement("rarity")["tail_tilt_deg"]), 0.0),
		"shipped per-mare defaults resolve")

	SETTINGS.set_anatomy_placement_draft({"offset_y": 0.6, "scale": 0.9})
	check(near(float(SETTINGS.anatomy_placement_default("")["offset_y"]), 0.6),
		"the default draft previews")
	check(near(float(SETTINGS.anatomy_placement_default("", false)["offset_y"]), 0.505),
		"the persisted default stays while previewing")
	SETTINGS.clear_anatomy_placement_draft()
	check(near(float(SETTINGS.anatomy_placement_default("")["offset_y"]), 0.505),
		"clearing the draft restores the default")

	var anon := SETTINGS.anon_placement()
	check(near(float(anon["offset_y"]), 0.74), "anon placement Y")
	check(near(float(anon["scale"]), 0.2), "anon placement scale")


## Tail and dock placement share the anatomy block and disappear at the default.
func _check_tail_seat() -> void:
	var default := SETTINGS.anatomy_placement_default("octavia_melody")
	check(near(float(default["tail_y"]), 0.0) and near(float(default["tail_z"]), -0.01),
		"a mare with no override uses the default tail")
	check(near(float(default["dock_y"]), 0.01) and near(float(default["dock_scale"]), 1.2),
		"a mare with no override uses the default dock")
	var values := default.duplicate(true)
	values["tail_y"] = 0.012
	values["tail_z"] = -0.003
	values["dock_y"] = -0.008
	values["dock_scale"] = 1.06
	values["tail_tilt_deg"] = 7.0
	SETTINGS.save_anatomy_placement("octavia_melody", values)
	var placed := SETTINGS.anatomy_placement("octavia_melody")
	check(near(float(placed["tail_y"]), 0.012) and near(float(placed["tail_z"]), -0.003),
		"a tail placement override reads back")
	check(near(float(placed["dock_y"]), -0.008) and near(float(placed["dock_scale"]), 1.06),
		"a dock placement override reads back")
	check(near(float(placed["tail_tilt_deg"]), 7.0), "a tail tilt override reads back")
	check(SETTINGS.anatomy_placement_has_override("octavia_melody"),
		"a non-default tail/dock placement is an override")
	check(near(float(SETTINGS.anatomy_placement("maud_pie")["tail_y"]), 0.0),
		"tail placement overrides are per mare")
	SETTINGS.save_anatomy_placement("octavia_melody",
		SETTINGS.anatomy_placement_default("octavia_melody", false))
	check(not SETTINGS.anatomy_placement_has_override("octavia_melody"),
		"returning to the default removes the override")
	var data := SETTINGS.data()
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
	var mare := FileAccess.open(mare_path, FileAccess.WRITE)
	mare.store_string(JSON.stringify({"version": 3,
		"fluttershy": {"position": [0.0, 0.51, 0.284], "pitch": 6.0, "scale": 0.762},
		"applejack": {"position": [0.0, 0.505, 0.284], "pitch": 3.0, "scale": 0.682},
		"rainbow_dash": {"position": [0.0, 0.505, 0.284], "pitch": 6.0, "scale": 0.682},
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


## Reads share the live cached view. `data()` hands the tools and suites a detached copy, so a
## caller cannot edit the live tree through it.
func _check_read_view() -> void:
	var live_flag := bool(SETTINGS._read().get("debug_mode", false))
	var view := SETTINGS.data()
	view["debug_mode"] = not live_flag
	check(bool(SETTINGS._read().get("debug_mode", false)) == live_flag,
		"the merged view is detached from the live cache")
	var block: Variant = view.get("default")
	var before := int(SETTINGS.template_for("fluttershy").get("aftercare_min", 0))
	if block is Dictionary:
		(block as Dictionary)["aftercare_min"] = before + 999
	check(int(SETTINGS.template_for("fluttershy").get("aftercare_min", 0)) == before,
		"nested blocks in the merged view are detached")


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


## A section heading is drawn once, even when its declarations interleave another group.
func _check_section_folding() -> void:
	var list := VBoxContainer.new()
	var fold: Array = [
		SETTINGS.by_path("presentation.missionary.size.canon.gaze_offset_mm"),
		SETTINGS.by_path("camera_thrust.bob"),
		SETTINGS.by_path("presentation.missionary.camera_mode"),
	]
	SETTINGS_UI._build_sections(list, SETTINGS.GENERAL, "", fold, 16, null, Callable())
	var labels: Array = []
	_collect_labels(list, labels)
	check(labels.count("Missionary") == 1, "an interleaved section draws one heading")
	check(labels.has("Gaze height") and labels.has("Camera"),
		"an interleaved section keeps every row")
	check(labels.has("Size"), "the per-size section draws its dropdown")
	check(labels.has("Bob"), "the interleaved section still draws the other group")
	list.free()


## The catalog-driven tab lists every supported mod, even one that is not installed, with the
## version this adapter was verified with and every declared flag.
func _check_integrations_panel() -> void:
	var list := VBoxContainer.new()
	SETTINGS_UI.build_integrations(list, 16, null, Callable())
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
	check(not labels.has("Debug"), "the Integrations tab has no Debug section")
	list.free()


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
	for heading: String in player_headings:
		check(labels.has(heading), "%s tab heading for %s" % [tab, heading])
		var expected := 2 if debug_headings.has(heading) else 1
		check(_count_text(list, heading) == expected,
			"%s draws the %s heading once per block" % [tab, heading])
	for heading: String in debug_headings:
		check(labels.has(heading), "%s Debug heading for %s" % [tab, heading])
	if debug_section == null:
		check(SETTINGS.tab_settings(tab).is_empty(), "%s has no Debug block without debug settings" % tab)
	else:
		check(debug_section.visible == debug_on, "%s Debug block follows debug mode" % tab)
		if debug_on:
			check(labels.has("ACTIONS"), "%s Debug block lists the actions" % tab)
			var expected: Array = []
			match tab:
				SETTINGS.GENERAL:
					expected = ["Reload posed base", "Give footstool", "Reset act prompts"]
				SETTINGS.ANATOMY:
					expected = ["Pitch +", "Up", "Pointed mare", "Show skeleton overlay"]
				SETTINGS.WORLD:
					expected = ["Resume auto", "Reset"]
			for action: String in expected:
				check(labels.has(action), "%s Debug block has the %s action" % [tab, action])
			check(not labels.has("Bed cuddle"),
				"%s Debug block keeps the wheel-only bed cuddle off" % tab)
			var wheeled: Array[String] = []
			for page: String in ["mare", "act"]:
				for name: String in DEBUG_ACTIONS.wheel_actions(page):
					if not wheeled.has(name):
						wheeled.append(name)
			for name: String in wheeled:
				check(not labels.has(DEBUG_ACTIONS.action_label(name, null)),
					"%s Debug block leaves the wheel action %s off" % [tab, name])
				check(not labels.has(DEBUG_ACTIONS.action_short(name, null)),
					"%s Debug block leaves the wheel short label %s off" % [tab, name])
	# An action lives in exactly one tab's block. "Heat" is also the Anatomy section heading, so
	# the World guard uses its row caption "Cycle" instead of the action's short label.
	if tab != SETTINGS.ANATOMY:
		check(not labels.has("Pitch +"), "%s does not carry the anatomy actions" % tab)
	if tab != SETTINGS.WORLD:
		check(not labels.has("Cycle"), "%s does not carry the world actions" % tab)
	list.free()
	if is_instance_valid(owner):
		owner.free()


## The cycle actions resolve Force/Clear from the aimed target's current phase. With no target
## they keep the Force label; the wheel-only bed cuddle never joins a settings block.
func _check_debug_actions() -> void:
	var main := PhaseMain.new()
	check(DEBUG_ACTIONS.action_label("cycle_heat", null) == "Force heat",
		"cycle heat defaults to Force without a target")
	check(DEBUG_ACTIONS.action_short("cycle_diestrus", null) == "Force diestrus",
		"cycle diestrus defaults to Force without a target")
	main.phase = "heat"
	check(DEBUG_ACTIONS.action_label("cycle_heat", main) == "Clear heat",
		"cycle heat shows Clear while she is in heat")
	check(DEBUG_ACTIONS.action_short("cycle_heat", main) == "Clear heat",
		"the compact cycle heat label also shows Clear")
	check(DEBUG_ACTIONS.action_label("cycle_diestrus", main) == "Force diestrus",
		"cycle diestrus stays Force while she is in heat")
	main.phase = "diestrus"
	check(DEBUG_ACTIONS.action_label("cycle_diestrus", main) == "Clear diestrus",
		"cycle diestrus shows Clear while she is off")
	check(DEBUG_ACTIONS.action_label("cycle_heat", main) == "Force heat",
		"cycle heat returns to Force outside heat")
	check(DEBUG_ACTIONS.action_short("bed_cuddle", main) == "Bed cuddle",
		"the wheel bed cuddle has a short label")
	check(not bool(DEBUG_ACTIONS.ACTIONS["bed_cuddle"].get("panel", true)),
		"the bed cuddle stays off the settings blocks")
	var overlay: SETTINGS.Setting = SETTINGS.by_path("anatomy.skeleton_overlay")
	check(overlay != null and bool(overlay.debug) and not bool(overlay.default),
		"the skeleton overlay is a debug flag, off by default")
	main.free()


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
	# The dock visibility and colour switches fold into one style pill.
	var dock: Dictionary = SETTINGS._migrate({"version": SETTINGS.SCHEMA_VERSION,
		"anatomy": {"hide_dock": true}}, SETTINGS.SCHEMA_VERSION)
	check(str(dock["anatomy"].get("dock_style", "")) == "hide",
		"hide_dock true maps to dock style hide")
	var dock_colour: Dictionary = SETTINGS._migrate({"version": SETTINGS.SCHEMA_VERSION,
		"anatomy": {"show_dock": true, "dock_color": "coat"}}, SETTINGS.SCHEMA_VERSION)
	check(str(dock_colour["anatomy"].get("dock_style", "")) == "coat",
		"a visible dock keeps its coat colour")
	var dock_off: Dictionary = SETTINGS._migrate({"version": SETTINGS.SCHEMA_VERSION,
		"anatomy": {"show_dock": false, "dock_color": "coat"}}, SETTINGS.SCHEMA_VERSION)
	check(str(dock_off["anatomy"].get("dock_style", "")) == "hide",
		"a hidden dock wins over its colour")
	var dock_none: Dictionary = SETTINGS._migrate({"version": SETTINGS.SCHEMA_VERSION},
		SETTINGS.SCHEMA_VERSION)
	check(not (dock_none.get("anatomy", {}) as Dictionary).has("dock_style"),
		"no old dock keys leaves the genitals default")

	# The old caress shoulder default detached the arm; migrate only the shipped 12 cm value.
	var reach: Dictionary = SETTINGS._migrate({"version": SETTINGS.SCHEMA_VERSION - 1,
		"features": {"caress_reach_shoulder_m": 0.12}}, SETTINGS.SCHEMA_VERSION - 1)
	check(near(float((reach.get("features", {}) as Dictionary).get(
		"caress_reach_shoulder_m", 0.0)), 0.02), "the old caress reach default migrates")
	var reach_tuned: Dictionary = SETTINGS._migrate({"version": SETTINGS.SCHEMA_VERSION - 1,
		"features": {"caress_reach_shoulder_m": 0.05}}, SETTINGS.SCHEMA_VERSION - 1)
	check(near(float((reach_tuned.get("features", {}) as Dictionary).get(
		"caress_reach_shoulder_m", 0.0)), 0.05), "a tuned caress reach survives migration")

	var caress: Dictionary = SETTINGS._migrate({"version": SETTINGS.SCHEMA_VERSION,
		"presentation": {
			"missionary": {"caress": {"over_coat_m": 0.03, "normal_blur_m": 0.01,
				"along_m": 0.1, "oval_scale": 2.0}},
			"standing": {"caress": {"palm_distance": 0.04, "ignore": ["leg"],
				"palm_scale": {"canon": 0.8}}},
		}}, SETTINGS.SCHEMA_VERSION)
	var caress_moved: Dictionary = caress.get("caress", {})
	check(near(float(caress_moved.get("hover_m", 0.0)), 0.03),
		"the old caress hover keys map to the shared block")
	check(near(float(caress_moved.get("normal_blur_m", 0.0)), 0.01),
		"the old caress smoothing keys map to the shared block")
	check((caress_moved.get("ignore", []) as Array).has("leg"),
		"the old standing caress ignore list maps to the shared block")
	check(near(float((caress_moved.get("palm_scale", {}) as Dictionary).get("canon", 0.0)), 0.8),
		"the old palm scale maps to the shared block")
	check(not caress_moved.has("along_m") and not caress_moved.has("oval_scale"),
		"the retired caress tuning keys are erased")

	# The precise switch is retired and `balanced` folds into `precise`; a stored `fast` survives.
	var retired_caress: Dictionary = SETTINGS._migrate({"version": SETTINGS.SCHEMA_VERSION - 1,
		"features": {"caress_surface": false},
		"caress": {"quality": "balanced"}}, SETTINGS.SCHEMA_VERSION - 1)
	check(not (retired_caress.get("features", {}) as Dictionary).has("caress_surface"),
		"the retired precise caress switch is erased")
	check(str((retired_caress.get("caress", {}) as Dictionary).get("quality", "")) == "precise",
		"balanced caress quality folds into precise")
	var fast_caress: Dictionary = SETTINGS._migrate({"version": SETTINGS.SCHEMA_VERSION - 1,
		"caress": {"quality": "fast"}}, SETTINGS.SCHEMA_VERSION - 1)
	check(str((fast_caress.get("caress", {}) as Dictionary).get("quality", "")) == "fast",
		"a stored fast caress quality survives migration")

	# Retired paths are erased while live neighbours survive, and an emptied sub-block is dropped.
	var dead: Dictionary = SETTINGS._migrate({"version": 3,
		"features": {"act_chat": true, "act_vocals": true, "act_history": false,
			"act_faces": false, "hud_readouts": true, "act_lines": true,
			"act_line_angles": true, "caress_areas": true,
			"allow_act_during_cuddle": true, "standing_plant_feet": true,
			"anatomy_vr": true},
		"anatomy": {"anal_ring": false, "mare_bits": "original", "strip_width": 1.0},
		"presentation": {"missionary": {}, "standing": {
			"kiss": {"forelegs": "planted"}, "smack": {"sound": "pack"},
			"plant_spread_m": 0.4}},
		"thrust": {"camera_bob": true, "contact_gap_m": 0.0, "travel": 0.5},
		"auto_thrust": {"pace_step": 0.25}}, 3)
	var dead_features: Dictionary = dead.get("features", {})
	check(not dead_features.has("act_chat"), "a retired feature is erased")
	check(not dead_features.has("act_vocals"), "the retired audio layer is erased")
	check(not dead_features.has("act_history"), "the retired act-history switch is erased")
	check(not dead_features.has("act_faces"), "the retired act-face switch is erased")
	for name: String in ["act_lines", "act_line_angles", "caress_areas",
			"allow_act_during_cuddle", "standing_plant_feet", "anatomy_vr"]:
		check(not dead_features.has(name), "the retired feature %s is erased" % name)
	check(bool(dead_features.get("hud_readouts", false)), "a live feature is kept")
	check(not (dead.get("anatomy", {}) as Dictionary).has("anal_ring"),
		"a retired anatomy key is erased")
	check(not (dead.get("anatomy", {}) as Dictionary).has("mare_bits"),
		"the retired mesh choice is erased")
	check(not (dead.get("thrust", {}) as Dictionary).has("camera_bob"),
		"a retired thrust key is erased")
	var dead_standing: Dictionary = (dead.get("presentation", {}) as Dictionary).get("standing", {})
	check(not dead_standing.has("kiss"), "an emptied retired sub-block is dropped")
	check(not dead_standing.has("smack"), "an emptied retired smack block is dropped")
	check(not dead_standing.has("plant_spread_m"), "the retired planted stance is erased")
	check(not (dead.get("thrust", {}) as Dictionary).has("contact_gap_m"),
		"the retired contact gap is erased")
	check(near(float((dead.get("thrust", {}) as Dictionary).get("travel", 0.0)), 0.5),
		"a live neighbour of a retired key is kept")


## A script constant resolves a built-in before a same-named static function, so an API name that
## exists on Script/GDScript would silently call the built-in instead of ours.
func _check_api_names() -> void:
	var names := ["all_settings", "by_name", "by_path", "tab_settings", "groups", "act_snapshot",
		"get_value_at", "set_value_at", "default_at", "to_row",
		"section_open", "set_section_open", "flag", "num", "choice", "list", "data", "reload_file",
		"preferences", "pose", "template_for", "get_bool", "set_bool",
		"get_num", "set_num", "get_choice", "set_choice", "get_list", "set_list", "build",
		"build_actions", "build_integrations"]
	var clashes: Array = []
	for name: String in names:
		if ClassDB.class_has_method("GDScript", name):
			clashes.append(name)
	check(clashes.is_empty(), "no settings API name shadows a Script built-in: %s" % str(clashes))


## Per-mare profiles share the file and the merge; a few representative checks.
func _check_profiles() -> void:
	var base: Dictionary = SETTINGS._filled_default()
	check(SETTINGS.CHARACTER_ORDER.size() == 103, "every spawnable adult mare is editable")
	check(SETTINGS.CHARACTER_ORDER.size() == SETTINGS.CHARACTER_NAMES.size(),
		"every pony has a display name")
	check(SETTINGS.CHARACTER_ORDER.size() == SETTINGS.CHARACTER_TEMPLATES.size(),
		"every editable pony has a preference template")
	check(SETTINGS.character_name("pinkie_pie") == "Pinkie Pie", "display name lookup")
	var maud: Dictionary = SETTINGS.profile_for(base, SETTINGS.CHARACTER_TEMPLATES, "maud_pie")
	check((maud["preferences"].get("talk", []) as Array).is_empty(), "Maud is quiet")
	var modded: Dictionary = SETTINGS.profile_for(base, {}, "a_modded_mare")
	check((modded["preferences"] as Dictionary) == (base["preferences"] as Dictionary),
		"an off-roster mare uses the global preference profile")
	check(not str(modded.get("act_prompts", {}).get("cue", "")).is_empty(),
		"an off-roster mare gets the built-in prompts")
	check(not (modded.get("poses", {}) as Dictionary).is_empty(),
		"an off-roster mare gets the pose defaults")
	var modded_override: Dictionary = SETTINGS.profile_for(base,
		{"a_modded_mare": {"preferences": {"intensity": "soft"}}}, "a_modded_mare")
	check(str(modded_override["preferences"].get("intensity", "")) == "soft",
		"an off-roster mare keeps a saved preference override")
	check(SETTINGS.anatomy_placement_default("a_modded_mare")
		== SETTINGS.anatomy_placement_default(""),
		"an off-roster mare uses the global anatomy placement")
	var override: Dictionary = SETTINGS.profile_for(base, {"fluttershy": {"cue_gap": 15.0}},
		"fluttershy")
	check(near(float(override.get("cue_gap", 0.0)), 15.0), "a character override wins")
	check(near(SETTINGS.cue_gap_value(99.0), 30.0), "cue_gap clamps high")
	var live: Dictionary = SETTINGS.template_for("fluttershy")
	check(not live.is_empty(), "live template")
	check(not SETTINGS.act_prompt("fluttershy", "utterance").is_empty(), "live utterance prompt")
	check(not SETTINGS.act_prompt("fluttershy", "cue").is_empty(), "live cue prompt")
	check(str(SETTINGS.DEFAULT_ACT_PROMPTS.get("cue", "")).contains("private, not a list to say"),
		"the default cue prompt keeps preferences private")
	var legacy_data := {"default": {"act_prompts": {"cue": SETTINGS.LEGACY_ACT_PROMPTS["cue"][-1]}}}
	var normalized := SETTINGS._normalize_act_prompts(legacy_data)
	check(not (normalized["default"] as Dictionary).has("act_prompts"),
		"a saved old cue prompt is removed")
	var custom_data := {"default": {"act_prompts": {"cue": "custom"}}}
	var custom := SETTINGS._normalize_act_prompts(custom_data)
	check(str(((custom["default"] as Dictionary)["act_prompts"] as Dictionary)["cue"]) == "custom",
		"a custom cue prompt survives")


## A saved character block holds only real differences from the built-in template, so a provider
## can update the fields the player never edited.
func _check_character_overrides() -> void:
	var full: Dictionary = SETTINGS.CHARACTER_TEMPLATES["fluttershy"].duplicate(true)
	var data := {"characters": {"fluttershy": full}}
	var normalized := SETTINGS._normalize_character_overrides(data)
	check(not normalized.has("characters")
		or (normalized["characters"] as Dictionary).is_empty(),
		"a materialized built-in template normalizes away")

	var old := {"version": SETTINGS.SCHEMA_VERSION - 1, "characters": {"fluttershy": full}}
	var migrated := SETTINGS._migrate(old, SETTINGS.SCHEMA_VERSION - 1)
	check(not migrated.has("characters")
		or (migrated["characters"] as Dictionary).is_empty(),
		"an older full-template file normalizes once")
	var current := {"version": SETTINGS.SCHEMA_VERSION, "characters": {"fluttershy": full}}
	var kept := SETTINGS._migrate(current, SETTINGS.SCHEMA_VERSION)
	check((kept.get("characters", {}) as Dictionary).has("fluttershy"),
		"a current file is not normalized twice")

	var empty := {"version": SETTINGS.SCHEMA_VERSION - 1,
		"characters": {"fluttershy": {"preferences": {}}}}
	var empty_migrated := SETTINGS._migrate(empty, SETTINGS.SCHEMA_VERSION - 1)
	check(not empty_migrated.has("characters"),
		"an empty saved profile is not a player override")

	var shipped_consent := CONSENT.defaults("fluttershy")
	var consent_data := {"version": SETTINGS.SCHEMA_VERSION - 1,
		"characters": {"fluttershy": {"consent": shipped_consent}}}
	var consent_migrated := SETTINGS._migrate(consent_data, SETTINGS.SCHEMA_VERSION - 1)
	check(not consent_migrated.has("characters"),
		"unchanged consent normalizes away")
	var changed_consent := shipped_consent.duplicate(true)
	changed_consent["public"] = not bool(shipped_consent.get("public", false))
	var changed_data := {"version": SETTINGS.SCHEMA_VERSION - 1,
		"characters": {"fluttershy": {"consent": changed_consent}}}
	var changed_migrated := SETTINGS._migrate(changed_data, SETTINGS.SCHEMA_VERSION - 1)
	var stored_consent: Dictionary = ((changed_migrated.get("characters", {}) as Dictionary)
		.get("fluttershy", {}) as Dictionary).get("consent", {})
	check(stored_consent.has("public") and not stored_consent.has("anal")
		and not stored_consent.has("oral"), "only changed consent is kept")
	var custom_consent := CONSENT.defaults("a_modded_mare")
	var custom_consent_data := {"version": SETTINGS.SCHEMA_VERSION - 1,
		"characters": {"a_modded_mare": {"consent": custom_consent}}}
	var custom_consent_migrated := SETTINGS._migrate(custom_consent_data,
		SETTINGS.SCHEMA_VERSION - 1)
	check(not custom_consent_migrated.has("characters"),
		"a custom mare's unchanged consent also normalizes away")

	var edited := SETTINGS.default_preferences("fluttershy")
	edited["intensity"] = "soft"
	var edited_data := {"characters": {"fluttershy": {"preferences": edited}}}
	var edited_norm := SETTINGS._normalize_character_overrides(edited_data)
	var edited_pref: Dictionary = ((edited_norm["characters"] as Dictionary)["fluttershy"]
		as Dictionary).get("preferences", {})
	check(edited_pref.has("intensity") and not edited_pref.has("notes"),
		"a full saved profile normalizes to the edited key")
	check(not edited_pref.has("tolerance"), "the untouched defaults are not pinned")

	var custom := {"characters": {"a_modded_mare": {"preferences": {"intensity": "soft"}}}}
	var custom_norm := SETTINGS._normalize_character_overrides(custom)
	check((custom_norm["characters"] as Dictionary).has("a_modded_mare"),
		"a custom mare block is untouched")

	var base: Dictionary = SETTINGS._filled_default()
	var fluttershy: Dictionary = SETTINGS.profile_for(base, {}, "fluttershy")
	check(not (fluttershy.get("event_prompts", {}) as Dictionary).is_empty(),
		"built-in event prompts seed without a saved block")
	check(not (fluttershy.get("poses", {}) as Dictionary).is_empty(),
		"built-in poses seed without a saved block")

	SETTINGS.save_preferences("fluttershy", {"intensity": "soft"})
	var saved: Dictionary = SETTINGS.data().get("characters", {})
	var entry: Dictionary = (saved as Dictionary).get("fluttershy", {})
	var stored: Dictionary = entry.get("preferences", {})
	check(stored.has("intensity") and not stored.has("notes"),
		"a save stores only the preference difference")
	SETTINGS.reset_preferences("fluttershy")

	var consent := SETTINGS.consent("fluttershy")
	var mutated := consent.duplicate(true)
	mutated["anal"] = not bool(consent.get("anal", false))
	check(SETTINGS.consent("fluttershy") == consent,
		"a consent caller cannot mutate the memoized block")
	SETTINGS.save_consent("fluttershy", consent)
	saved = SETTINGS.data().get("characters", {})
	entry = (saved as Dictionary).get("fluttershy", {})
	check(not entry.has("consent"), "saving the resolved consent stores nothing")
	var changed := consent.duplicate(true)
	changed["public"] = not bool(consent.get("public", false))
	SETTINGS.save_consent("fluttershy", changed)
	saved = SETTINGS.data().get("characters", {})
	entry = (saved as Dictionary).get("fluttershy", {})
	var consent_diff: Dictionary = entry.get("consent", {})
	check(consent_diff.has("public") and not consent_diff.has("anal"),
		"a consent save stores only the changed key")
	check(SETTINGS.consent("fluttershy").get("public") == changed.get("public"),
		"a consent save invalidates the memoized block")
	SETTINGS.save_consent("fluttershy", consent)


## A participation block is a subtractive capability layer. A player's `adult` assertion is never
## stored, and only the player's real participation differences are saved.
func _check_participation() -> void:
	var data := {"characters": {"fluttershy": {
		"adult": true,
		"profile": {"participation": {"acts": true, "anatomy": false, "tail": true}},
	}}}
	var normalized := SETTINGS._normalize_character_overrides(data)
	var entry: Dictionary = (normalized.get("characters", {}) as Dictionary).get("fluttershy", {})
	check(not entry.has("adult"), "a player's adult assertion is dropped")
	var participation: Dictionary = (entry.get("profile", {}) as Dictionary).get("participation", {})
	check(not participation.has("acts"), "an unchanged participation is not stored")
	check(not bool(participation.get("anatomy", true)), "a changed participation is kept")
	check(not participation.has("tail"), "an unchanged participation is not stored")

	var resolved := SETTINGS.profile_participation("fluttershy")
	check(bool(resolved.get("acts", false)), "the base participation is all allowed")
	check(bool(resolved.get("anatomy", false)), "the base participation is all allowed")
	check(bool(resolved.get("tail", false)), "the base participation is all allowed")

	SETTINGS.save_participation("fluttershy", {"acts": false, "anatomy": true, "tail": true})
	var saved: Variant = SETTINGS.data().get("characters", {})
	var saved_entry: Dictionary = (saved as Dictionary).get("fluttershy", {})
	var saved_profile: Dictionary = (saved_entry.get("profile", {}) as Dictionary).get("participation", {})
	check(not bool(saved_profile.get("acts", true)), "a saved opt-out is stored")
	check(not saved_profile.has("anatomy"), "an unchanged participation is not stored")
	check(not saved_profile.has("tail"), "an unchanged participation is not stored")
	var opted_out := SETTINGS.profile_participation("fluttershy")
	check(not bool(opted_out.get("acts", true)), "the memoized profile invalidates on a save")
	SETTINGS.reset_participation("fluttershy")
	var after: Variant = SETTINGS.data().get("characters", {})
	check(not (after as Dictionary).has("fluttershy"), "reset removes the participation block")
	var restored := SETTINGS.profile_participation("fluttershy")
	check(bool(restored.get("acts", false)), "the memoized profile invalidates on a reset")


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


func _count_text(node: Node, text: String) -> int:
	var count := 0
	if node is Button and (node as Button).text.strip_edges() == text:
		count += 1
	elif node is Label and (node as Label).text.strip_edges() == text:
		count += 1
	for child: Node in node.get_children():
		count += _count_text(child, text)
	return count


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
