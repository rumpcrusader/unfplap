extends SceneTree
## The anatomy mesh and the body coat: the refined winking mesh, the V2 anal keys, the rig and
## near-palette shader patch, the vulva cut and the still zones.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/anatomy/test_coat.gd

const ANATOMY := preload("res://mods/unfplap/anatomy/controller.gd")
const BODY_COAT_SURFACE := preload("res://mods/unfplap/shared/body_coat.gd")
const COAT := preload("res://mods/unfplap/anatomy/coat.gd")
const COAT_PATCH := preload("res://mods/unfplap/anatomy/body_coat_patch.gd")
const GEOMETRY := preload("res://mods/unfplap/anatomy/geometry.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const STILL_ZONES := preload("res://mods/unfplap/anatomy/still_zone_debug.gd")

var failures := 0
var checks := 0

class NearCoatPony extends Node3D:
	var _near: Dictionary = {}


class FakeCoatPony extends Node3D:
	var _model: Node3D


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
	# The V2 mesh's density walk can collapse to the 4 mm floor; keep the authored band.
	check(is_equal_approx(GEOMETRY.stable_lip_radius(0.004), GEOMETRY.WINKING_LIP_RADIUS),
		"a collapsed lip radius falls back to the authored band")
	check(is_equal_approx(GEOMETRY.stable_lip_radius(GEOMETRY.WINKING_LIP_RADIUS),
		GEOMETRY.WINKING_LIP_RADIUS), "the authored lip radius is kept")
	check(is_equal_approx(GEOMETRY.stable_lip_radius(0.030), 0.030),
		"a nearby measured lip radius is kept")

	# The refined mare bits mesh leaves the default resting mesh alone and masks the anal rim out
	# of the authored `closed` shape.
	var wink_scene: PackedScene = load(ANATOMY.MARE_BITS_PATH)
	var wink_root: Node = wink_scene.instantiate()
	var wink_mi := wink_root as MeshInstance3D
	var source_mesh := wink_mi.mesh as ArrayMesh
	var refined_mesh := GEOMETRY.refined_winking_mesh(source_mesh)
	check(refined_mesh != null, "the winking mesh rebuilds")
	if refined_mesh != null:
		check(refined_mesh.get_blend_shape_count() >= 2, "the wink keeps its shape keys")
		check(str(refined_mesh.get_blend_shape_name(0)) == "closed",
			"the closed shape keeps its name")
		check(wink_mi.find_blend_shape_by_name("wink") >= 0,
			"the mare bits mesh has the clitoris wink key")
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

	# The mare bits mesh owns the anal hole: the cup/ring are gone.
	var v2_scene: PackedScene = load(ANATOMY.MARE_BITS_PATH)
	var v2_root: Node = v2_scene.instantiate()
	var v2_mi := v2_root as MeshInstance3D
	var v2_mesh := v2_mi.mesh as ArrayMesh
	check(v2_mesh.get_blend_shape_count() >= 8, "the mare bits mesh keeps its anal keys")
	check(v2_mi.find_blend_shape_by_name("wink") >= 0,
		"the mesh has the clitoris wink key")
	for shape_name: String in ["anal_open", "anal_stretch", "anal_overstretch",
			"anal_extreme", "ponut_scale"]:
		check(v2_mi.find_blend_shape_by_name(shape_name) >= 0,
			"the mesh has the %s key" % shape_name)
	var v2_arrays: Array = v2_mesh.surface_get_arrays(0)
	var v2_colors: Variant = v2_arrays[Mesh.ARRAY_COLOR]
	check(v2_colors != null and (v2_colors as PackedColorArray).size()
		== (v2_arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(),
		"the mare bits colours cover every vertex")
	var folds := 0
	var clits := 0
	if v2_colors != null:
		for c: Color in v2_colors:
			if c.a > 0.9:
				folds += 1
			elif c.a > 0.4:
				clits += 1
	check(folds > 500, "the inner folds keep their mask")
	check(clits > 200, "the clitoris keeps its mask")
	get_root().add_child(v2_mi)
	v2_mi.transform = Transform3D.IDENTITY
	var v2_anatomy: Node = ANATOMY.new()
	v2_anatomy.shapes.set_mesh(v2_mi)
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

	# The generic bind helper maps anatomy-local points into the body's rest space.
	var bind := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0.1, 0.2, 0.3))
	var mesh_xf := Transform3D(Basis(Vector3.RIGHT, -0.3), Vector3(0.0, 0.55, 0.29))
	var point := Vector3(0.01, -0.02, 0.03)
	var local := GEOMETRY.body_local_point(bind, mesh_xf, point)
	check((mesh_xf.affine_inverse() * (bind * local)).is_equal_approx(point),
		"body-local point round-trips through the bind pose")
	var local_dir := GEOMETRY.body_local_direction(bind, mesh_xf, Vector3.BACK)
	check(absf(local_dir.length() - 1.0) < 0.0001, "body-local direction stays unit length")

	# The rig coat patch only replaces the flank_jiggle include and one call; a shader without
	# those hooks is left alone instead of being half-patched.
	check(bool(SETTINGS.body_coat_deform.default), "body coat deform is on by default")
	check(near(float(SETTINGS.coat_hole.default), 0.7),
		"the coat hole uses 70% of the lip radius across by default")
	check(float(SETTINGS.coat_hole_height.default) > float(SETTINGS.coat_hole.default),
		"the coat hole is a taller-than-wide ellipse by default")
	check(near(float(SETTINGS.coat_hole_depth_mm.default), 30.0),
		"the coat hole reaches 30 mm behind the opening by default")
	check(near(float(SETTINGS.anal_still.default), 0.0), "anal still zone is off by default")
	check(near(float(SETTINGS.still_oval.default), 1.5),
		"still zones are taller than they are wide")
	check(near(float(SETTINGS.still_fade.default), 0.3),
		"still zones fade over 0.3 of their radius")
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
	var expected_radius := maxf(0.022 * 2.2 * 1.3, 0.045 / 0.742)
	check(near(GEOMETRY.anal_still_radius_for(0.022, 2.2, 0.742, 1.0, 0.0),
		expected_radius), "anal still radius follows the cup's outer ring")
	check(is_zero_approx(GEOMETRY.anal_still_radius_for(0.022, 2.2, 0.742, 0.0, 0.0)),
		"anal still multiplier 0 disables the zone")
	# The controller keeps the coat accessors the runtime uses for the jiggle handoff.
	var coat_owner := ANATOMY.new()
	for method: String in ["is_attached", "body_coat_mesh", "body_coat_material",
			"body_outline_material", "body_coat_targets"]:
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

	# The drawn coat: a source body that hides the game MareBody still resolves its visible
	# coat, and the game body wins while it is visible.
	var coat_shader := Shader.new()
	coat_shader.code = "shader_type spatial;\n" \
		+ "#include \"res://world/characters/hybrid_mare/flank_jiggle.gdshaderinc\"\n" \
		+ "void vertex() { VERTEX += flank_jiggle(VERTEX); }\n"
	var coat_material := ShaderMaterial.new()
	coat_material.shader = coat_shader
	var coat_mesh := ArrayMesh.new()
	var coat_arrays := []
	coat_arrays.resize(Mesh.ARRAY_MAX)
	coat_arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	coat_arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP])
	coat_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, coat_arrays)
	coat_mesh.surface_set_material(0, coat_material)
	var coat_model := Node3D.new()
	get_root().add_child(coat_model)
	var hidden_game_body := MeshInstance3D.new()
	hidden_game_body.name = "MareBody"
	hidden_game_body.mesh = coat_mesh
	hidden_game_body.visible = false
	coat_model.add_child(hidden_game_body)
	var source_body := MeshInstance3D.new()
	source_body.name = "ChrysalisBody"
	source_body.mesh = coat_mesh
	coat_model.add_child(source_body)
	var coat_pony := FakeCoatPony.new()
	coat_pony._model = coat_model
	var drawn := BODY_COAT_SURFACE.resolve(coat_pony)
	check(drawn.get("mesh") == source_body,
		"a hidden game body falls back to the drawn source coat")
	check(int(drawn.get("surface", -1)) == 0, "the drawn coat surface is found")
	hidden_game_body.visible = true
	var drawn_game := BODY_COAT_SURFACE.resolve(coat_pony)
	check(drawn_game.get("mesh") == hidden_game_body, "a visible game body is the drawn coat")
	coat_pony.free()
	coat_model.queue_free()

	var patch_source := Shader.new()
	patch_source.code = "shader_type spatial;\n" \
		+ "#include \"includes/base-cel-shader.gdshaderinc\"\n" \
		+ "#include \"res://world/characters/hybrid_mare/flank_jiggle.gdshaderinc\"\n" \
		+ "void vertex() { VERTEX += flank_jiggle(VERTEX); }\n" \
		+ "void fragment() { ALBEDO = vec3(1.0); }"
	var patched := COAT_PATCH.patched(patch_source)
	check(patched != null, "the coat shader patch finds its two required hooks")
	if patched != null:
		check(patched.code.contains("body_coat_deform.gdshaderinc"),
			"the patch swaps the include")
		check(patched.code.contains("body_coat_deform(VERTEX)"),
			"the patch swaps the deform call")
		check(patched.code.contains(
			"body_coat_vertex = (body_coat_anatomy_inverse * vec4(VERTEX, 1.0)).xyz;"),
			"the patch records the anatomy-local coat position")
		check(patched.code.contains("body_coat_vulva_cut(body_coat_vertex)"),
			"the patch cuts the coat inside the vulva opening")
		check(patched.code.contains("res://addons/cel-shader/includes/base-cel-shader.gdshaderinc"),
			"the patch makes the cel includes absolute")
	var no_fragment := Shader.new()
	no_fragment.code = "shader_type spatial;\n" \
		+ "#include \"res://world/characters/hybrid_mare/flank_jiggle.gdshaderinc\"\n" \
		+ "void vertex() { VERTEX += flank_jiggle(VERTEX); }"
	var deform_only := COAT_PATCH.patched(no_fragment)
	check(deform_only != null and deform_only.code.contains("body_coat_deform(VERTEX)"),
		"a shader without a fragment hook still gets the coat deform")
	check(deform_only == null or not deform_only.code.contains("body_coat_vulva_cut"),
		"a shader without a fragment hook leaves the vulva cut out")
	var near_source := Shader.new()
	near_source.code = "shader_type spatial;\n" \
		+ "const int ENTRIES = 32;\n" \
		+ "varying flat int pal;\n" \
		+ "#include \"res://world/characters/hybrid_mare/flank_jiggle.gdshaderinc\"\n" \
		+ "uniform float jiggle_entry[ENTRIES];\n" \
		+ "void vertex() { pal = 0; VERTEX += flank_jiggle(VERTEX) * jiggle_entry[pal]; }\n" \
		+ "void fragment() { ALBEDO = vec3(1.0); }"
	var near_patched := COAT_PATCH.patched(near_source)
	check(near_patched != null, "the near palette shader patch finds its hooks")
	if near_patched != null:
		check(near_patched.code.contains("uniform float body_coat_entry[ENTRIES];"),
			"the near patch adds the body entry mask")
		check(near_patched.code.contains("body_coat_deform(body_coat_posed)"),
			"the near patch swaps in the coat deform")
		check(near_patched.code.contains("body_coat_vulva_cut(body_coat_vertex)"),
			"the near patch cuts the body entry")
		check(near_patched.code.contains(
			"body_coat_entry[pal] > 0.5 && body_coat_vulva_cut(body_coat_vertex)"),
			"the near cut is gated on the body palette entry")
	var unpatched := Shader.new()
	unpatched.code = "shader_type spatial;"
	check(COAT_PATCH.patched(unpatched) == null, "a shader without the hooks is left alone")
	var game_body: Shader = load("res://addons/cel-shader/cel-shader-base.gdshader")
	var game_near: Shader = load("res://world/characters/hybrid_mare/near_pony.gdshader")
	var game_near_occlusion: Shader = load(
		"res://world/characters/hybrid_mare/near_pony_occlusion.gdshader")
	var game_near_outline: Shader = load(
		"res://world/characters/hybrid_mare/near_pony_outline.gdshader")
	check(COAT_PATCH.patched(game_body) != null, "the real body shader patches")
	check(COAT_PATCH.patched(game_near) != null, "the real near pony shader patches")
	var compiled := ShaderMaterial.new()
	for source: Shader in [game_body, game_near, game_near_occlusion, game_near_outline]:
		var real_patch := COAT_PATCH.patched(source)
		check(real_patch != null, "the real coat shader compiles")
		if real_patch != null:
			compiled.shader = real_patch
	for setting in [SETTINGS.anal_body_depth_mm, SETTINGS.coat_spread, SETTINGS.coat_hole,
			SETTINGS.coat_hole_height, SETTINGS.coat_hole_depth_mm, SETTINGS.jiggle_still,
			SETTINGS.anal_still, SETTINGS.still_oval, SETTINGS.still_fade,
			SETTINGS.still_height_mm]:
		check(setting.low <= -1000.0 and setting.high >= 1000.0,
			"%s is an unbounded debug row" % setting.name)

	var near_pony := NearCoatPony.new()
	root.add_child(near_pony)
	var near_body := MeshInstance3D.new()
	near_body.name = "MareBody"
	near_pony.add_child(near_body)
	var near_head := MeshInstance3D.new()
	near_head.name = "Head"
	near_pony.add_child(near_head)
	var near_mesh := MeshInstance3D.new()
	near_pony.add_child(near_mesh)
	var near_coat_source := Shader.new()
	near_coat_source.code = "shader_type spatial;\n" \
		+ "const int ENTRIES = 32;\n" \
		+ "varying flat int pal;\n" \
		+ "#include \"res://world/characters/hybrid_mare/flank_jiggle.gdshaderinc\"\n" \
		+ "uniform float jiggle_entry[ENTRIES];\n" \
		+ "void vertex() { pal = 0; VERTEX += flank_jiggle(VERTEX) * jiggle_entry[pal]; }\n" \
		+ "void fragment() { ALBEDO = vec3(1.0); }"
	var palette := ShaderMaterial.new()
	palette.shader = near_coat_source
	var hull := ShaderMaterial.new()
	hull.shader = near_coat_source
	palette.next_pass = hull
	var entries := [[near_pony.get_path_to(near_body), 0],
		[near_pony.get_path_to(near_head), 0]]
	near_pony._near = {"groups": [{"mi": near_mesh,
		"group": {"variants": {"full": {"outputs": [{"entries": entries}]}}},
		"built": {"full": {"materials": [palette]}}}]}
	var near_coat := COAT.new()
	near_coat.setup(near_pony, null)
	near_coat.set("_body_mesh", near_body)
	near_coat.set("_body_patched", true)
	near_coat.call("_refresh_near")
	check(palette.shader != near_coat_source and hull.shader != near_coat_source,
		"the merged near body and outline are patched")
	var near_mask: Variant = palette.get_shader_parameter("body_coat_entry")
	check(near_mask is PackedFloat32Array and (near_mask as PackedFloat32Array).size() == 32,
		"the near palette gets a full body-entry mask")
	if near_mask is PackedFloat32Array:
		var mask := near_mask as PackedFloat32Array
		check(mask[0] > 0.5 and mask[1] < 0.5,
			"only the MareBody palette entry gets the coat deform")
	near_coat.call("restore")
	check(palette.shader == near_coat_source and hull.shader == near_coat_source,
		"the near palette shaders restore exactly")
	near_pony.free()

	print("ANATOMY_COAT_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
