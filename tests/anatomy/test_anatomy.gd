extends SceneTree
## integration: anatomy consent, eligibility and placement checks.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/anatomy/test_anatomy.gd

const CONSENT := preload("res://mods/unfplap/shared/consent.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility/service.gd")
const ANATOMY := preload("res://mods/unfplap/anatomy/controller.gd")
const GEOMETRY := preload("res://mods/unfplap/anatomy/geometry.gd")
const PLACEMENT := preload("res://mods/unfplap/shared/anatomy_placement.gd")
const TAIL_SEAT := preload("res://mods/unfplap/anatomy/tail/seat.gd")
const CYCLE := preload("res://mods/unfplap/shared/cycle.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const MARE_REGISTRY := preload("res://mods/unfplap/registry/service.gd")
const RUNTIME := preload("res://mods/unfplap/runtime.gd")
const ANATOMY_ACT := preload("res://mods/unfplap/anatomy/act.gd")
const PLAYER_PART := preload("res://mods/unfplap/anatomy/player.gd")
const COAT_PATCH := preload("res://mods/unfplap/anatomy/body_coat_patch.gd")
const COAT := preload("res://mods/unfplap/anatomy/coat.gd")
const STILL_ZONES := preload("res://mods/unfplap/anatomy/still_zone_debug.gd")
const FACTS := preload("res://mods/unfplap/anatomy/facts.gd")

var failures := 0
var checks := 0

class FakeIdentity extends Resource:
	var id := ""
	var character_id := ""
	var filly := false
	var stallion := false

class FakePony extends Node3D:
	var identity: Resource
	var rig: Node


class FakeMain extends Node:
	var eligibility: Variant


class FakeAnatomy extends Node:
	var calls: Array[String] = []

	func _clear_part() -> void:
		calls.append("clear")

	func fluid() -> Node3D:
		return null


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func near(a: float, b: float, eps := 0.0001) -> bool:
	return absf(a - b) <= eps


func _pony(id: String, filly := false, stallion := false) -> FakePony:
	var pony := FakePony.new()
	var identity := FakeIdentity.new()
	identity.id = id
	identity.filly = filly
	identity.stallion = stallion
	pony.identity = identity
	pony.set_meta("relationship_id", id)
	return pony


func run() -> void:
	# Consent defaults are deterministic and per-id, and an override wins.
	var a := CONSENT.defaults("twilight_sparkle")
	var b := CONSENT.defaults("twilight_sparkle")
	check(a == b, "consent defaults are deterministic")
	check(a.has("public") and a.has("anal") and a.has("oral"), "consent has all three keys")
	var over := CONSENT.resolve("twilight_sparkle", {"anal": true, "oral": false})
	check(bool(over.get("anal", false)), "consent anal override wins")
	check(not bool(over.get("oral", true)), "consent oral override wins")
	check(bool(CONSENT.resolve("twilight_sparkle", {}).get("public", false))
		== bool(a.get("public", false)), "empty override keeps defaults")
	check(not bool(a.get("public", true)), "no mare is public by default")

	# Eligibility is capability-scoped: the eligibility service answers the anatomy target, and
	# the base-game roster is not an attachment whitelist.
	var host := FakeMain.new()
	root.add_child(host)
	host.eligibility = ELIGIBILITY.new()
	host.eligibility.setup(host)
	var twilight := _pony("twilight_sparkle")
	check(bool(host.eligibility.eligible(twilight, ELIGIBILITY.Target.ANATOMY)),
		"base adult is eligible")
	var off_roster := _pony("not_a_base_mare")
	check(bool(host.eligibility.eligible(off_roster, ELIGIBILITY.Target.ANATOMY)),
		"off-roster adult is eligible")
	var filly := _pony("not_a_base_mare", true)
	check(not bool(host.eligibility.eligible(filly, ELIGIBILITY.Target.ANATOMY)),
		"identity filly is excluded")
	var stallion := _pony("not_a_base_mare", false, true)
	check(not bool(host.eligibility.eligible(stallion, ELIGIBILITY.Target.ANATOMY)),
		"stallion is excluded")
	var no_id := _pony("")
	check(not bool(host.eligibility.eligible(no_id, ELIGIBILITY.Target.ANATOMY)),
		"empty id is excluded")
	var no_identity := FakePony.new()
	check(not bool(host.eligibility.eligible(no_identity, ELIGIBILITY.Target.ANATOMY)),
		"no identity is excluded")
	var player := _pony("twilight_sparkle")
	player.name = "PlayerPony"
	check(not bool(host.eligibility.eligible(player, ELIGIBILITY.Target.ANATOMY)),
		"player pony is excluded")

	# A provider's `adult` assertion overrides the identity's age flag; the participation block
	# is the anatomy target's veto, and the character target keeps her editable.
	var registered: Dictionary = MARE_REGISTRY.register(1, {
		"id": "provider_filly", "source": "test",
		"adult": true, "profile": {"participation": {"anatomy": false}},
	})
	check(bool(registered.get("ok", false)), "the provider registers")
	var provider_filly := _pony("provider_filly", true)
	check(bool(host.eligibility.eligible(provider_filly, ELIGIBILITY.Target.CHARACTER)),
		"a provider's adult assertion attaches a filly")
	check(not bool(host.eligibility.eligible(provider_filly, ELIGIBILITY.Target.ANATOMY)),
		"a participation opt-out blocks the anatomy target")
	MARE_REGISTRY.unregister(1, "provider_filly")

	# Placement and preferences use the relationship id first; the identity id is the fallback.
	var meta_first := _pony("visual_id")
	meta_first.set_meta("relationship_id", "relationship_id")
	check(ANATOMY.pony_id(meta_first) == "relationship_id", "relationship id wins")
	var placement_id := ANATOMY.new()
	placement_id.placement.set("pony", meta_first)
	check(str(placement_id.placement.call("_pony_id")) == "relationship_id",
		"anatomy placement uses the relationship id")
	placement_id.free()

	# A modded copy of a princess uses the canon body profile; an ordinary modded mare does not.
	var princess_copy := FakeIdentity.new()
	princess_copy.id = "custom_celestia"
	princess_copy.character_id = "celestia"
	check(ANATOMY.body_profile(princess_copy).size() == 3,
		"a modded Celestia copy uses the princess body profile")
	var ordinary_identity := FakeIdentity.new()
	ordinary_identity.id = "not_a_base_mare"
	check(ANATOMY.body_profile(ordinary_identity).is_empty(),
		"an ordinary modded mare uses the normal body profile")
	check(ANATOMY.body_profile(null).is_empty(), "no identity has no body profile")

	# The Characters selector lists only live off-roster mares.
	var live_ids: Array[String] = ANATOMY.off_roster_ids(
		["not_a_base_mare", "twilight_sparkle"], SETTINGS.CHARACTER_ORDER)
	check(live_ids.size() == 1 and live_ids[0] == "not_a_base_mare",
		"the Characters selector lists live off-roster mares")

	var default_place := SETTINGS.anatomy_placement_default("")
	check(near(float(default_place["offset_x"]), 0.0), "global anatomy X is on the crease")
	check(near(float(default_place["offset_y"]), 0.505), "global anatomy Y")
	check(near(float(default_place["offset_z"]), 0.284), "global anatomy Z")
	check(near(float(default_place["pitch_deg"]), 3.0), "global anatomy pitch")
	check(near(float(default_place["scale"]), 0.682), "global anatomy scale")
	var modded_place := SETTINGS.anatomy_placement_default("not_a_base_mare")
	check(modded_place == default_place, "an off-roster mare uses the global anatomy placement")
	var visibility: Variant = JSON.parse_string(FileAccess.get_file_as_string(
		TAIL_SEAT.DOCK_VISIBILITY_PATH))
	if visibility is Dictionary:
		var reference: Variant = (visibility as Dictionary).get("reference_fit")
		if reference is Dictionary:
			check(TAIL_SEAT._visibility_offset(off_roster, reference)
				== TAIL_SEAT.DOCK_VISIBILITY_FALLBACK,
				"an off-roster mare gets the fallback dock visibility")
	var place_pos := Vector3(
		float(default_place["offset_x"]),
		float(default_place["offset_y"]),
		float(default_place["offset_z"]))
	# Show tail docks is visibility only. The old placement pinned the mesh top to the dock's
	# buried base ring, which dropped a low-docked mare's anatomy by up to 9 cm.
	var place := ANATOMY.new()
	var place_mesh := MeshInstance3D.new()
	place_mesh.mesh = BoxMesh.new()
	place.add_child(place_mesh)
	place.placement.set_mesh(place_mesh, Transform3D.IDENTITY, [])
	place.placement.set("_pos", place_pos)
	place.placement.set("_pitch", float(default_place["pitch_deg"]))
	place.placement.set("_scale", float(default_place["scale"]))
	var dock_before := SETTINGS.show_dock.get_bool()
	SETTINGS.show_dock.set_bool(true)
	place.call("_apply_place")
	var dock_on: Transform3D = place_mesh.transform
	SETTINGS.show_dock.set_bool(false)
	place.call("_apply_place")
	var dock_off: Transform3D = place_mesh.transform
	check(dock_on.is_equal_approx(dock_off), "the dock switch never moves the anatomy")
	check(near(dock_on.origin.y, place_pos.y + float(place.call("_tail_lift"))),
		"placement uses the calibrated lift")
	SETTINGS.show_dock.set_bool(dock_before)
	place.free()
	# Saved placements migrate once onto the current default: v0 rows get all three shifts, v1 the
	# lateral and forward steps, v2 the forward step, and a v3 row is left alone.
	var v0 := PLACEMENT.migrate_legacy({"version": 0, "fluttershy": {
		"position": [-0.005, 0.5, 0.281], "pitch": 6.0, "scale": 0.662}})
	check(int(v0.get("version", 0)) == PLACEMENT.LEGACY_VERSION, "v0 placements migrate forward")
	var v0_pos: Array = v0["fluttershy"]["position"]
	check(near(float(v0_pos[0]), 0.0), "v0 row loses the lateral bias")
	check(near(float(v0_pos[2]), 0.289), "v0 row keeps both forward shifts")
	var v1 := PLACEMENT.migrate_legacy({"version": 1, "rarity": {
		"position": [-0.005, 0.5, 0.286], "pitch": 6.0, "scale": 0.662}})
	var v1_pos: Array = v1["rarity"]["position"]
	check(near(float(v1_pos[0]), 0.0), "v1 row loses the lateral bias")
	check(near(float(v1_pos[2]), 0.289), "v1 row gets the current forward step")
	var v2 := PLACEMENT.migrate_legacy({"version": 2, "rarity": {
		"position": [-0.004, 0.5, 0.286]}})
	var v2_pos: Array = v2["rarity"]["position"]
	check(near(float(v2_pos[0]), -0.004), "v2 row keeps its lateral offset")
	check(near(float(v2_pos[2]), 0.289), "v2 row gets the current forward step")
	var v3 := PLACEMENT.migrate_legacy({"version": 3, "rarity": {
		"position": [-0.004, 0.5, 0.289]}})
	var v3_pos: Array = v3["rarity"]["position"]
	check(near(float(v3_pos[2]), 0.289), "current rows are not touched")
	check(SETTINGS.by_path("presentation.lean_back_m") == null, "back lean setting removed")
	check(ClassDB.class_has_method("XRBodyTracker", "get_has_tracking_data"),
		"VR body tracker API")
	check(not ClassDB.class_has_method("XRBodyTracker", "get_have_tracking_data"),
		"old VR tracker API absent")
	check(not FileAccess.get_file_as_string("res://mods/unfplap/vr/service.gd").contains(
		"get_have_tracking_data"), "VR source uses the engine method")

	# A profile keeps its custom prompts and poses when consent is merged.
	var base: Dictionary = SETTINGS._filled_default()
	var characters := {"twilight_sparkle": {
		"consent": {"anal": true},
		"event_prompts": {"climax": "custom"},
		"poses": {"missionary": {"rump_drop_deg": 12.0}},
	}}
	var profile: Dictionary = SETTINGS.profile_for(base, characters, "twilight_sparkle")
	check(profile.has("consent"), "profile carries consent")
	check(str((profile.get("event_prompts", {}) as Dictionary).get("climax", "")) == "custom",
		"consent merge preserves event prompts")
	check(absf(float(((profile.get("poses", {}) as Dictionary).get("missionary", {}) as Dictionary)
		.get("rump_drop_deg", 0.0)) - 12.0) < 0.001, "consent merge preserves pose overrides")
	check(not ANATOMY.assets_exist() or ANATOMY.assets_exist(), "asset check is a bool")
	# integration: no act controller means all anatomy action gates are closed.
	var runtime: Node = RUNTIME.new()
	check(not bool(runtime.call("anatomy_hole_ready")), "hole gate closed without an act")
	check(not bool(runtime.call("anatomy_oral_ready")), "oral gate closed without an act")
	check(not bool(runtime.call("anatomy_finish_ready")), "finish gate closed without an act")
	check(not bool(runtime.call("anatomy_actions_ready")), "all anatomy gates closed without an act")
	# The refresh binds the reactions facade to her node, which is what the standing offer's rump
	# anchor reads. Without it the Y hint never appears.
	var rump_pony := Node3D.new()
	get_root().add_child(rump_pony)
	runtime.pony = rump_pony
	check(not runtime.call("rump_anchor").is_finite(),
		"no refresh leaves the rump anchor unbound")
	runtime.call("_anatomy_refresh")
	check(runtime.call("rump_anchor").is_finite(),
		"the anatomy refresh binds the reactions scene for the rump anchor")
	get_root().remove_child(rump_pony)
	rump_pony.free()
	runtime.free()

	# Idle heat: active act states suppress the display, idle allows it, and a due timer winks.
	var heat_facts := FACTS.new()
	heat_facts.cycle_phase = "heat"
	var heat_anatomy: Node = ANATOMY.new()
	var heat_pony := Node3D.new()
	var wink_mesh := MeshInstance3D.new()
	wink_mesh.mesh = BoxMesh.new()
	heat_anatomy.add_child(wink_mesh)
	get_root().add_child(heat_anatomy)
	heat_anatomy.set_process(false)
	heat_anatomy.set("pony", heat_pony)
	heat_anatomy.set("facts", heat_facts)
	heat_anatomy.attach.setup(heat_anatomy, heat_pony, heat_facts)
	heat_anatomy.attach.attached = true
	heat_anatomy.attach.mesh = wink_mesh
	heat_anatomy.shapes.set_mesh(wink_mesh, false)
	heat_anatomy.attach.apply_visibility(true)
	heat_facts.state = 2
	heat_anatomy.call("_heat_idle_tick", 0.1)
	check(heat_anatomy.heat.suppressed(), "active act suppresses idle heat")
	heat_facts.state = 0
	heat_anatomy.heat.set("_phase", CYCLE.HEAT)
	heat_anatomy.heat.set("_phase_clock", 999.0)
	heat_anatomy.heat.set("_wink_clock", 0.001)
	heat_anatomy.call("_heat_idle_tick", 0.01)
	var gap_lo := minf(SETTINGS.wink_min_s.get_num(), SETTINGS.wink_max_s.get_num())
	check(heat_anatomy.heat.wink_clock() >= gap_lo,
		"an idle heat wink resets the interval")
	check(heat_anatomy.shapes.tween_running(), "an idle heat wink builds its tween")
	heat_anatomy.set_idle_wink(0.0)
	check(is_equal_approx(float(heat_anatomy.shapes.wink_amount()), 0.0),
		"the default rest clears the wink shape")
	check(is_equal_approx(float(heat_anatomy.shapes.state().get("closed", -1.0)), 1.0),
		"the default rest is the authored closed shape")
	var rest_open := clampf(SETTINGS.heat_rest_open.get_num(), 0.0, 1.0)
	heat_anatomy.set_idle_wink(rest_open)
	check(is_equal_approx(float(heat_anatomy.shapes.wink_amount()), rest_open),
		"heat rests at the configured share of the open shape")
	check(is_equal_approx(float(heat_anatomy.shapes.state().get("closed", -1.0)),
		1.0 - rest_open), "the heat rest opens the closed lips by the same share")
	check(bool(heat_anatomy.shapes.state().get("idle_wink", false)),
		"the idle rest owns the shapes")
	heat_anatomy.drive(0.5)
	check(is_equal_approx(float(heat_anatomy.shapes.wink_amount()), 0.0),
		"acts clear the idle wink shape")
	check(not bool(heat_anatomy.shapes.state().get("idle_wink", true)),
		"an act clears the idle cut suppression")
	heat_anatomy.free()
	heat_pony.free()

	# The V2 mesh's density walk can collapse to the 4 mm floor; keep the authored band.
	check(is_equal_approx(ANATOMY.stable_lip_radius(0.004), GEOMETRY.WINKING_LIP_RADIUS),
		"a collapsed lip radius falls back to the authored band")
	check(is_equal_approx(ANATOMY.stable_lip_radius(GEOMETRY.WINKING_LIP_RADIUS),
		GEOMETRY.WINKING_LIP_RADIUS), "the authored lip radius is kept")
	check(is_equal_approx(ANATOMY.stable_lip_radius(0.030), 0.030),
		"a nearby measured lip radius is kept")

	# The refined winking mesh leaves the default closed shape alone and masks only the anal rim.
	if ANATOMY.assets_exist():
		var wink_scene: PackedScene = load(ANATOMY.WINKING_PATH)
		var wink_root: Node = wink_scene.instantiate()
		var wink_mi := wink_root as MeshInstance3D
		var source_mesh := wink_mi.mesh as ArrayMesh
		var refined_mesh := ANATOMY.refined_winking_mesh(source_mesh)
		check(refined_mesh != null, "the winking mesh rebuilds")
		if refined_mesh != null:
			check(refined_mesh.get_blend_shape_count() >= 2, "the wink keeps its shape keys")
			check(str(refined_mesh.get_blend_shape_name(0)) == "closed",
				"the closed shape keeps its name")
			check(wink_mi.find_blend_shape_by_name("wink") < 0,
				"the original mesh has no wink key; closed carries the lips")
			var src_base: PackedVector3Array = source_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var src_closed: PackedVector3Array = source_mesh.surface_get_blend_shape_arrays(0)[0][Mesh.ARRAY_VERTEX]
			var ref_base: PackedVector3Array = refined_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var ref_closed: PackedVector3Array = refined_mesh.surface_get_blend_shape_arrays(0)[0][Mesh.ARRAY_VERTEX]
			check(ref_base == src_base, "the default resting mesh is unchanged")
			var anal_index := -1
			for i in src_base.size():
				if src_base[i].y > 0.06 and (src_closed[i] - src_base[i]).length() > 0.001:
					anal_index = i
					break
			check(anal_index >= 0, "an anal rim vertex moves in the source shape")
			if anal_index >= 0:
				check((ref_closed[anal_index] - ref_base[anal_index]).length() < 0.0001,
					"the anal rim no longer winks")
		wink_root.free()

	# The V2 mesh owns the anal hole now: the cup/ring are gone.
	if ResourceLoader.exists(ANATOMY.MARE_BITS_V2_PATH):
		var v2_scene: PackedScene = load(ANATOMY.MARE_BITS_V2_PATH)
		var v2_root: Node = v2_scene.instantiate()
		var v2_mi := v2_root as MeshInstance3D
		var v2_mesh := v2_mi.mesh as ArrayMesh
		check(v2_mesh.get_blend_shape_count() >= 8, "the V2 mesh keeps its anal keys")
		check(v2_mi.find_blend_shape_by_name("wink") >= 0,
			"V2 has the clitoris wink key")
		for shape_name: String in ["anal_open", "anal_stretch", "anal_overstretch",
				"anal_extreme", "ponut_scale"]:
			check(v2_mi.find_blend_shape_by_name(shape_name) >= 0,
				"V2 has the %s key" % shape_name)
		var v2_arrays: Array = v2_mesh.surface_get_arrays(0)
		var v2_colors: Variant = v2_arrays[Mesh.ARRAY_COLOR]
		check(v2_colors != null and (v2_colors as PackedColorArray).size()
			== (v2_arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(),
			"the V2 colours cover every vertex")
		var folds := 0
		var clits := 0
		if v2_colors != null:
			for c: Color in v2_colors:
				if c.a > 0.9:
					folds += 1
				elif c.a > 0.4:
					clits += 1
		check(folds > 500, "the V2 inner folds keep their mask")
		check(clits > 200, "the V2 clitoris keeps its mask")
		get_root().add_child(v2_mi)
		v2_mi.transform = Transform3D.IDENTITY
		var v2_anatomy: Node = ANATOMY.new()
		v2_anatomy.shapes.set_mesh(v2_mi, true)
		check(v2_anatomy.shapes.v2_anal(), "the V2 shape state reports the anal mesh")
		v2_anatomy.shapes.apply_anal_local(0.030)
		var open_i := v2_mi.find_blend_shape_by_name("anal_open")
		var stretch_i := v2_mi.find_blend_shape_by_name("anal_stretch")
		var over_i := v2_mi.find_blend_shape_by_name("anal_overstretch")
		var extreme_i := v2_mi.find_blend_shape_by_name("anal_extreme")
		check(is_equal_approx(v2_mi.get_blend_shape_value(open_i), 1.0),
			"30 mm opens the V2 anus")
		check(is_equal_approx(v2_mi.get_blend_shape_value(stretch_i), 1.0),
			"30 mm reaches the normal V2 stretch")
		check(is_equal_approx(v2_mi.get_blend_shape_value(over_i), 1.0),
			"30 mm reaches the V2 overstretch")
		check(near(v2_mi.get_blend_shape_value(extreme_i), 0.0714, 0.002),
			"30 mm starts the V2 extreme")
		var mouth: Vector3 = v2_anatomy.shapes.anal_mouth()
		check(mouth.y < 0.062 and mouth.y > 0.041,
			"30 mm tracks the V2 ring down from the old cup point")
		v2_anatomy.shapes.apply_anal_local(0.056)
		mouth = v2_anatomy.shapes.anal_mouth()
		check(near(mouth.y, GEOMETRY.V2_ANAL_RING_EXTREME.y, 0.001),
			"56 mm puts the anal aim on the extreme ring")
		var aim: Vector3 = v2_anatomy.call("hole_point", 1.0)
		var aim_offset: Vector3 = v2_mi.global_transform.basis.y.normalized() \
			* (SETTINGS.anal_aim_mm.get_num() / 1000.0)
		check(aim.distance_to(v2_mi.global_transform * GEOMETRY.V2_ANAL_RING_EXTREME
			+ aim_offset) < 0.0001, "the anal act aims at the deformed V2 ring")
		v2_anatomy.shapes.apply_anal_local(0.080)
		check(v2_mi.get_blend_shape_value(extreme_i) > 1.5,
			"an oversized shaft extrapolates the V2 extreme")
		v2_anatomy.free()
		v2_root.free()

	# Climax clears the shape once and arms the wink pulses; the tick keeps driving the hug so
	# the lips stay on the shaft through the climax instead of closing on nothing.
	var anatomy_act: Node = ANATOMY_ACT.new()
	var fake_anatomy := FakeAnatomy.new()
	anatomy_act.anatomy = fake_anatomy
	anatomy_act.on_climax()
	check(fake_anatomy.calls.size() == 1 and fake_anatomy.calls[0] == "clear",
		"climax clears the shape once")
	check(absf(float(anatomy_act.get("_wink_left")) - ANATOMY_ACT.CLIMAX_WINK_S) < 0.001,
		"climax arms the wink pulses")
	anatomy_act.free()
	fake_anatomy.free()

	# The shaped length and head profile are reported from the same values the shader uses.
	var part: Node = PLAYER_PART.new()
	part.set("_part_length_scale", 1.5)
	part.set("_girth_head", 1.5)
	check(absf(float(part.call("_part_length")) - PLAYER_PART.PART_LENGTH * 1.5) < 0.0001,
		"part length scales")
	check(absf(float(part.call("_head_scale_at", 0.0)) - 1.0) < 0.0001,
		"head scale leaves the base alone")
	check(absf(float(part.call("_head_scale_at", 1.0)) - 1.5) < 0.0001,
		"head scale reaches the full glans value")
	part.set("_ready_amount", 1.0)
	part.set("_throb_gain", 1.0)
	part.set("_throb_clock", 0.099)
	part.call("_throb_tick", 0.001, 1.0)
	check(float(part.get("_throb_amount")) > 0.0, "the heartbeat produces a pulse at its peak")
	# The same beat lifts the visible shaft while it is out of her, and the rise dies at full depth.
	part.set("_throb_depth", 0.0)
	part.call("_throb_tick", 0.001, 0.0)
	check(float(part.get("_throb_lift")) > 0.0, "the heartbeat lifts the shaft while it is outside")
	part.set("_throb_depth", 1.0)
	part.call("_throb_tick", 0.001, 1.0)
	check(is_zero_approx(float(part.get("_throb_lift"))), "the upward beat fades at full thrust")
	check(not (part.call("root_now") as Vector3).is_finite(),
		"the player root is invalid before the part mesh is prepared")
	part.free()

	# Her act wink: quiet at her lips, frequent once a climax has been pulled out of her.
	check(ANATOMY_ACT.wink_mode(0.6, true, 2) == 0, "a thrusting shaft raises no wink")
	check(ANATOMY_ACT.wink_mode(0.0, true, 0) == 1, "the tip at her lips winks on its own")
	check(ANATOMY_ACT.wink_mode(0.0, false, 0) == 0, "a pulled-out shaft waits before any climax")
	check(ANATOMY_ACT.wink_mode(0.1, false, 1) == 2, "a pulled-out shaft after a climax winks often")
	var wink_act: Node = ANATOMY_ACT.new()
	wink_act.call("_start_wink", ANATOMY_ACT.ACT_WINK_S, 1.0)
	check(absf(float(wink_act.get("_wink_left")) - ANATOMY_ACT.ACT_WINK_S) < 0.001,
		"an act wink arms its countdown")
	check(is_equal_approx(float(wink_act.get("_wink_beats")), 1.0), "an act wink is one beat")
	wink_act.call("reset")
	check(is_zero_approx(float(wink_act.get("_wink_left"))), "reset clears the act wink")
	wink_act.free()

	# The body coat shader works in NearBody vertex space; the anatomy pose is in bone space.
	var bind := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0.1, 0.2, 0.3))
	var mesh_xf := Transform3D(Basis(Vector3.RIGHT, -0.3), Vector3(0.0, 0.55, 0.29))
	var point := Vector3(0.01, -0.02, 0.03)
	var local := ANATOMY.body_local_point(bind, mesh_xf, point)
	check((mesh_xf.affine_inverse() * (bind * local)).is_equal_approx(point),
		"body-local point round-trips through the bind pose")
	var local_dir := ANATOMY.body_local_direction(bind, mesh_xf, Vector3.BACK)
	check(absf(local_dir.length() - 1.0) < 0.0001, "body-local direction stays unit length")

	# The rig coat patch only replaces the flank_jiggle include and one call; a shader without
	# those hooks is left alone instead of being half-patched.
	check(bool(SETTINGS.body_coat_deform.default), "body coat deform is on by default")
	check(near(float(SETTINGS.anal_still.default), 0.0), "anal still zone is off by default")
	check(near(float(SETTINGS.still_oval.default), 1.5),
		"still zones are taller than they are wide")
	check(near(float(SETTINGS.still_fade.default), 0.6),
		"still zones fade over 0.6 of their radius")
	check(near(float(SETTINGS.still_height_mm.default), 25.0),
		"the vulva still zone sits 25 mm above the opening by default")
	check(not bool(SETTINGS.draw_still_zones.default), "still-zone debug rings are off by default")
	var zones := STILL_ZONES.new()
	root.add_child(zones)
	zones.call("setup")
	check(zones.get_child_count() == 4, "four debug rings are built")
	zones.call("update", Transform3D.IDENTITY, Vector3.ZERO, Basis.IDENTITY, 0.1,
		Vector3(0.0, 0.1, 0.0), 0.05, 0.7, 0.25, true)
	check(zones.visible, "debug rings show when asked")
	var outer: MeshInstance3D = zones.get_child(0)
	check(outer.global_transform.basis.get_scale().is_equal_approx(Vector3(0.1, 0.07, 0.1)),
		"the outer ring is the oval ellipsoid")
	zones.call("update", Transform3D.IDENTITY, Vector3.ZERO, Basis.IDENTITY, 0.1,
		Vector3(0.0, 0.1, 0.0), 0.05, 0.7, 0.25, false)
	check(not zones.visible, "debug rings hide when asked")
	zones.free()
	var expected_radius := maxf(0.022 * 2.2 * 0.742 * 1.3, 0.045)
	check(near(ANATOMY.anal_still_radius_for(0.022, 2.2, 0.742, 1.0), expected_radius),
		"anal still radius follows the cup's outer ring")
	check(is_zero_approx(ANATOMY.anal_still_radius_for(0.022, 2.2, 0.742, 0.0)),
		"anal still multiplier 0 disables the zone")
	# The controller keeps the coat accessors the runtime uses for the jiggle handoff.
	var coat_owner := ANATOMY.new()
	for method: String in ["is_attached", "body_coat_mesh", "body_coat_material",
			"body_outline_material"]:
		check(coat_owner.has_method(method), "the controller exposes %s" % method)
	check(not bool(coat_owner.call("is_attached")), "a fresh controller is not attached")
	coat_owner.free()

	# A despawned body can already have no surfaces; clearing the coat must not index surface 0.
	var thin_body := MeshInstance3D.new()
	thin_body.mesh = ArrayMesh.new()
	var thin_coat := COAT.new()
	thin_coat.set("_body_mesh", thin_body)
	thin_coat.set("_body_material", ShaderMaterial.new())
	thin_coat.call("clear_mesh")
	check(true, "a surface-less coat clear completes")
	thin_body.free()

	# A normal surface still loses its override on clear.
	var real_body := MeshInstance3D.new()
	real_body.mesh = BoxMesh.new()
	real_body.set_surface_override_material(0, ShaderMaterial.new())
	var real_coat := COAT.new()
	real_coat.set("_body_mesh", real_body)
	real_coat.set("_body_material", ShaderMaterial.new())
	real_coat.call("clear_mesh")
	check(real_body.get_surface_override_material(0) == null,
		"the coat clear removes the surface override")
	real_body.free()

	var patch_source := Shader.new()
	patch_source.code = "shader_type spatial;\n" \
		+ "#include \"includes/base-cel-shader.gdshaderinc\"\n" \
		+ "#include \"res://world/characters/hybrid_mare/flank_jiggle.gdshaderinc\"\n" \
		+ "void vertex() { VERTEX += flank_jiggle(VERTEX); }"
	var patched := COAT_PATCH.patched(patch_source)
	check(patched != null, "the coat shader patch finds its two hooks")
	if patched != null:
		check(patched.code.contains("body_coat_deform.gdshaderinc"),
			"the patch swaps the include")
		check(patched.code.contains("body_coat_deform(VERTEX)"),
			"the patch swaps the deform call")
		check(patched.code.contains(
			"res://addons/cel-shader/includes/base-cel-shader.gdshaderinc"),
			"the patch makes the cel includes absolute")
	var unpatched := Shader.new()
	unpatched.code = "shader_type spatial;"
	check(COAT_PATCH.patched(unpatched) == null, "a shader without the hooks is left alone")

	for pony: Node in [twilight, filly, stallion, off_roster, no_id, no_identity, player,
			meta_first]:
		if is_instance_valid(pony):
			pony.free()
	print("ANATOMY_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
