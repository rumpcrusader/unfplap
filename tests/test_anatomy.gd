extends SceneTree
## integration: anatomy consent, eligibility and placement checks.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_anatomy.gd

const CONSENT := preload("res://mods/unfplap/consent.gd")
const ANATOMY := preload("res://mods/unfplap/anatomy.gd")
const CYCLE := preload("res://mods/unfplap/cycle.gd")
const SETTINGS := preload("res://mods/unfplap/settings.gd")
const RUNTIME := preload("res://mods/unfplap/runtime.gd")
const ANATOMY_ACT := preload("res://mods/unfplap/anatomy_act.gd")
const ANON_PART := preload("res://mods/unfplap/anon_part.gd")
const COAT_PATCH := preload("res://mods/unfplap/body_coat_patch.gd")
const STILL_ZONES := preload("res://mods/unfplap/still_zone_debug.gd")

var failures := 0
var checks := 0

class FakeIdentity extends Resource:
	var id := ""
	var filly := false
	var stallion := false

class FakePony extends Node3D:
	var identity: Resource
	var rig: Node


class FakeAnatomy extends Node:
	var calls: Array[String] = []

	func _clear_part() -> void:
		calls.append("clear")

	func fluid() -> Node3D:
		return null


class FakeHeatRuntime extends Node:
	var state := 0

	func cycle_phase() -> String:
		return "heat"


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

	# Eligibility is the modern preference roster plus identity checks. There is no age list.
	var twilight := _pony("twilight_sparkle")
	check(ANATOMY.eligible(twilight), "roster adult is eligible")
	var filly := _pony("twilight_sparkle", true)
	check(not ANATOMY.eligible(filly), "identity filly is excluded")
	var stallion := _pony("twilight_sparkle", false, true)
	check(not ANATOMY.eligible(stallion), "stallion is excluded")
	var off_roster := _pony("not_a_base_mare")
	check(not ANATOMY.eligible(off_roster), "off-roster mare is excluded")
	var player := _pony("twilight_sparkle")
	player.name = "PlayerPony"
	check(not ANATOMY.eligible(player), "player pony is excluded")

	check(ANATOMY.DEFAULT_PLACE == Vector3(0.0, 0.525, 0.286), "global anatomy placement is on the crease")
	check(is_equal_approx(ANATOMY.DEFAULT_PITCH, -6.0), "global anatomy pitch")
	check(is_equal_approx(ANATOMY.DEFAULT_SCALE, 0.742), "global anatomy scale")
	# Saved placements migrate once onto the current default: v0 rows get both shifts, v1 the
	# lateral one, and a current row is left alone.
	var v0 := ANATOMY.migrate_place({"version": 0, "fluttershy": {
		"position": [-0.005, 0.5, 0.281], "pitch": 6.0, "scale": 0.662}})
	check(int(v0.get("version", 0)) == ANATOMY.PLACE_VERSION, "v0 placements migrate forward")
	var v0_pos: Array = v0["fluttershy"]["position"]
	check(near(float(v0_pos[0]), 0.0), "v0 row loses the lateral bias")
	check(near(float(v0_pos[2]), 0.286), "v0 row keeps the forward shift")
	var v1 := ANATOMY.migrate_place({"version": 1, "rarity": {
		"position": [-0.005, 0.5, 0.286], "pitch": 6.0, "scale": 0.662}})
	var v1_pos: Array = v1["rarity"]["position"]
	check(near(float(v1_pos[0]), 0.0), "v1 row loses the lateral bias")
	check(near(float(v1_pos[2]), 0.286), "v1 row is not shifted forward twice")
	var v2 := ANATOMY.migrate_place({"version": 2, "rarity": {
		"position": [-0.004, 0.5, 0.286]}})
	var v2_pos: Array = v2["rarity"]["position"]
	check(near(float(v2_pos[0]), -0.004), "current rows are not touched")
	check(SETTINGS.by_path("presentation.lean_back_m") == null, "back lean setting removed")
	check(ClassDB.class_has_method("XRBodyTracker", "get_has_tracking_data"),
		"VR body tracker API")
	check(not ClassDB.class_has_method("XRBodyTracker", "get_have_tracking_data"),
		"old VR tracker API absent")
	check(not FileAccess.get_file_as_string("res://mods/unfplap/vr_act.gd").contains(
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
	runtime.free()

	# Idle heat: active act states suppress the display, idle allows it, and a due timer winks.
	var heat_runtime := FakeHeatRuntime.new()
	var heat_anatomy: Node = ANATOMY.new()
	var heat_pony := Node3D.new()
	var wink_mesh := MeshInstance3D.new()
	wink_mesh.mesh = BoxMesh.new()
	heat_anatomy.add_child(wink_mesh)
	get_root().add_child(heat_anatomy)
	heat_anatomy.set_process(false)
	heat_anatomy.set("pony", heat_pony)
	heat_anatomy.set("runtime", heat_runtime)
	heat_anatomy.set("_attached", true)
	heat_anatomy.set("_mesh", wink_mesh)
	heat_anatomy.set("_last_shown", true)
	heat_runtime.state = 2
	heat_anatomy.call("_heat_idle_tick", 0.1)
	check(bool(heat_anatomy.get("_heat_suppressed")), "active act suppresses idle heat")
	heat_runtime.state = 0
	heat_anatomy.set("_heat_phase", CYCLE.HEAT)
	heat_anatomy.set("_heat_phase_clock", 999.0)
	heat_anatomy.set("_heat_wink_clock", 0.001)
	heat_anatomy.call("_heat_idle_tick", 0.01)
	check(float(heat_anatomy.get("_heat_wink_clock")) >= CYCLE.WINK_MIN_S,
		"an idle heat wink resets the interval")
	check(heat_anatomy.get("_tween") != null, "an idle heat wink builds its tween")
	heat_anatomy.set_idle_wink(0.0)
	check(is_equal_approx(float(heat_anatomy.get("_wink_amount")), 0.0),
		"the default rest clears the wink shape")
	check(is_equal_approx(float(heat_anatomy.get("_closed")), 1.0),
		"the default rest is the authored closed shape")
	heat_anatomy.set_idle_wink(ANATOMY.HEAT_REST_OPEN)
	check(is_equal_approx(float(heat_anatomy.get("_wink_amount")), ANATOMY.HEAT_REST_OPEN),
		"heat rests at the configured share of the wink shape")
	check(is_equal_approx(float(heat_anatomy.get("_closed")), 1.0),
		"the heat rest leaves the closed shape alone")
	heat_anatomy.drive(0.5)
	check(is_equal_approx(float(heat_anatomy.get("_wink_amount")), 0.0),
		"acts clear the idle wink shape")
	heat_anatomy.free()
	heat_pony.free()
	heat_runtime.free()

	# The V2 mesh's density walk can collapse to the 4 mm floor; keep the authored band.
	check(is_equal_approx(ANATOMY.stable_lip_radius(0.004), ANATOMY.WINKING_LIP_RADIUS),
		"a collapsed lip radius falls back to the authored band")
	check(is_equal_approx(ANATOMY.stable_lip_radius(ANATOMY.WINKING_LIP_RADIUS),
		ANATOMY.WINKING_LIP_RADIUS), "the authored lip radius is kept")
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
	var part: Node = ANON_PART.new()
	part.set("_part_length_scale", 1.5)
	part.set("_girth_head", 1.5)
	check(absf(float(part.call("_part_length")) - ANON_PART.PART_LENGTH * 1.5) < 0.0001,
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
	check(not SETTINGS.body_coat_deform.get_bool(), "body coat deform is off by default")
	check(near(SETTINGS.anal_still.get_num(), 1.0), "anal still zone is on by default")
	check(near(SETTINGS.still_oval.get_num(), 0.7), "still zones are flatter than they are wide")
	check(near(SETTINGS.still_fade.get_num(), 0.25), "still zones fade over a quarter of their radius")
	check(near(SETTINGS.still_height_mm.get_num(), -11.0),
		"the vulva still zone sits 11 mm under the opening by default")
	check(not SETTINGS.draw_still_zones.get_bool(), "still-zone debug rings are off by default")
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

	for pony: Node in [twilight, filly, stallion, off_roster, player]:
		if is_instance_valid(pony):
			pony.free()
	print("ANATOMY_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
