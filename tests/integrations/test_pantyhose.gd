extends "res://mods/unfplap/tests/support/suite.gd"
## The Pantyhose & Panties world adapter and the garment hull: the depth field, the transform
## mapping, the surface overrides, the cloth follower, the act-start undress and the debug controls.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/integrations/test_pantyhose.gd

const HULL := preload("res://mods/unfplap/anatomy/garment_hull.gd")
const PONIES := preload("res://mods/unfplap/ponies/service.gd")
const CONTROLLER := preload("res://mods/unfplap/anatomy/controller.gd")
const INTEGRATION := preload("res://mods/unfplap/integrations/pantyhose.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")
const CUT_SHADER := preload("res://mods/unfplap/integrations/shaders/pantyhose_cut.gdshader")
const SHEER_SHADER := preload("res://mods/unfplap/integrations/shaders/pantyhose_sheer.gdshader")
const ANATOMY_SCENE := "res://mods/unfplap/assets/anatomy/mare/mare_bits_v2.scn"
const SCHEMA := preload("res://world/ai/pony_action_schema.gd")
## The live coat uniforms `FlankTouch` writes, with the game's `flank_jiggle.gdshaderinc` names.
const COAT_SHADER_CODE := "shader_type spatial;\n" \
	+ "uniform float jiggle_amount = 0.0;\n" \
	+ "uniform float jiggle_time = 0.0;\n" \
	+ "uniform vec3 jiggle_center = vec3(0.0);\n" \
	+ "uniform vec3 jiggle_normal = vec3(0.0, 0.0, 1.0);\n" \
	+ "uniform float jiggle_radius = 0.12;\n" \
	+ "void vertex() { VERTEX += vec3(0.0); }\n" \
	+ "void fragment() { ALBEDO = vec3(1.0); }\n"
## The ten hull instance uniforms plus the six jiggle ones: Godot's per-shader ceiling.
const INSTANCE_UNIFORM_LIMIT := 16
const SHADER_DIR := "res://mods/unfplap/integrations/shaders/"



class FakeAnatomy extends Node:
	signal act_started(pony: Node3D)

	var hull: Variant = null
	var xform := Transform3D.IDENTITY
	var visible := true
	var parent_node: Node3D = null
	var rebuilds := 0

	func garment_hull(_pony: Node) -> Variant:
		return hull

	func garment_transform(_pony: Node) -> Transform3D:
		return xform

	func garment_visible(_pony: Node) -> bool:
		return visible

	func garment_parent(_pony: Node) -> Node3D:
		return parent_node

	func garment_hull_rebuild() -> void:
		rebuilds += 1


class FixtureHost extends Node:
	var anatomy: Node
	var game: Node


class FakeGame extends Node:
	var mares: Array = []


class FakeIdentity extends Resource:
	var id := ""


class FakePony extends Node3D:
	var identity: Variant = null


## The game's `FlankTouch`: the `[material, mesh]` pairs `_process` writes the wobble into every
## frame, the body it belongs to, and the decal-era fields the helper must ignore.
class FakeFlank extends Node3D:
	var _jiggle_targets: Array = []
	var _body: Variant = null
	var _jiggle_index := -1
	var _jiggle_age := 0.0
	var _jiggle_amount := 0.0
	var marks: Array = []


class FakeWardrobe extends Node:
	var calls: Array[String] = []
	## What `wanted()` answers: {kind: colour index}, like the game's wardrobe.
	var wanted_map: Dictionary = {}
	var season := "winter"

	func wanted(_id: String, _season: String) -> Dictionary:
		return wanted_map

	func set_worn(id: String, spoken: String, on: bool) -> String:
		calls.append("set_worn:%s:%s:%s" % [id, spoken, str(on)])
		if on:
			wanted_map[spoken] = 0
		else:
			wanted_map.erase(spoken)
		return spoken

	func dress(pony: Node3D, id: String, season: String) -> void:
		calls.append("dress:%s:%s:%s" % [id, season, pony.name])

	func _season() -> String:
		return season


class FakeCoordinator extends Node:
	var executors: Dictionary = {}
	var commits: Array[Dictionary] = []
	var wardrobe: Node = null
	var refuse := false

	func commit(id: String, actions: Array, targets: Dictionary, turn: int) -> String:
		commits.append({"id": id, "actions": actions.duplicate(true), "targets": targets, "turn": turn})
		if refuse:
			return "Not now"
		# The game's executor runs the wardrobe itself, not the adapter: keep `calls` adapter-only.
		for action: Variant in actions:
			if wardrobe != null:
				wardrobe.wanted_map.erase(str((action as Dictionary).get("kind", "")))
		return ""


class FakeDirector extends Node:
	var actions: Node = null
	var _turn_id := 7

func run() -> void:
	_check_hull_fixture()
	_check_hull_real()
	_check_transform()
	_check_bulge()
	_check_sheer()
	_check_two_surfaces()
	_check_multi_mare()
	_check_jiggle()
	_check_jiggle_space()
	_check_jiggle_targets()
	_check_jiggle_malformed()
	_check_process_priority()
	_check_shader_sync()
	_check_jiggle_two_mares()
	_check_jiggle_without_lift()
	_check_jiggle_lifecycle()
	_check_undress()
	_check_overlay_parenting()
	_check_debug()
	finish()


# --------------------------------------------------------------------------- hull builder

## One outer quad at z 0.01, one inner quad behind it at z -0.02 and a `closed` shape that raises
## one outer corner. The field takes the maximum Z per cell, so it takes the outer surface and the
## shape and the inner quad never wins.
func _fixture_mesh() -> ArrayMesh:
	var verts := PackedVector3Array([
		Vector3(0.0, 0.0, 0.01), Vector3(0.02, 0.0, 0.01),
		Vector3(0.02, 0.02, 0.01), Vector3(0.0, 0.02, 0.01),
		Vector3(0.0, 0.0, -0.02), Vector3(0.02, 0.0, -0.02),
		Vector3(0.02, 0.02, -0.02), Vector3(0.0, 0.02, -0.02),
	])
	var normals := PackedVector3Array([
		Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK,
		Vector3.FORWARD, Vector3.FORWARD, Vector3.FORWARD, Vector3.FORWARD,
	])
	var indices := PackedInt32Array([0, 1, 2, 0, 2, 3, 4, 5, 6, 4, 6, 7])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var shape_verts := verts.duplicate()
	shape_verts[0] = Vector3(0.0, 0.0, 0.03)
	var shape: Array = []
	shape.resize(Mesh.ARRAY_MAX)
	shape[Mesh.ARRAY_VERTEX] = shape_verts
	shape[Mesh.ARRAY_NORMAL] = normals
	# An act shape that must not enter the rest field.
	var anal_verts := verts.duplicate()
	anal_verts[0] = Vector3(0.0, 0.0, 0.06)
	var anal_shape: Array = []
	anal_shape.resize(Mesh.ARRAY_MAX)
	anal_shape[Mesh.ARRAY_VERTEX] = anal_verts
	anal_shape[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_blend_shape("closed")
	mesh.add_blend_shape("anal_extreme")
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [shape, anal_shape])
	return mesh


## Two small outer triangles at opposite ends of a wide domain. The gap is much wider than the
## dilation reaches, so the middle keeps the invalid marker.
func _wide_fixture_mesh() -> ArrayMesh:
	var verts := PackedVector3Array([
		Vector3(0.0, 0.0, 0.01), Vector3(0.01, 0.0, 0.01), Vector3(0.01, 0.01, 0.01),
		Vector3(0.2, 0.0, 0.02), Vector3(0.21, 0.0, 0.02), Vector3(0.21, 0.01, 0.02),
	])
	var normals := PackedVector3Array([
		Vector3.BACK, Vector3.BACK, Vector3.BACK,
		Vector3.BACK, Vector3.BACK, Vector3.BACK,
	])
	var indices := PackedInt32Array([0, 1, 2, 3, 4, 5])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _check_hull_fixture() -> void:
	var mesh := _fixture_mesh()
	var hull := HULL.build(mesh, 8, 8, 0)
	check(hull != null, "the fixture hull builds")
	if hull == null:
		return
	var domain := hull.domain
	check(domain.position.x <= -0.0039 and domain.position.y <= -0.0039,
		"the domain starts at the outer footprint minus the margin")
	check(domain.size.x > 0.027 and domain.size.x < 0.029,
		"the domain is the outer footprint plus the margin")
	check(near(hull.z_min, -0.02, 0.00001), "the field starts at the lower inner surface")
	check(near(hull.z_max, 0.03, 0.00001), "the rest closed shape is the field")
	check(hull.z_max < 0.05, "the lower inner surface and the act anal shape are ignored")
	var field := hull.field
	check(field.size() == 64, "the field is resolution squared")
	var highest := 0.0
	for value: float in field:
		highest = maxf(highest, value)
	check(near(highest, 1.0, 0.00001), "the shape peak reaches the top of the range")
	var texture := hull.texture
	check(texture is ImageTexture and texture.get_width() == 8,
		"the field texture matches the resolution")
	var again := HULL.build(mesh, 8, 8, 0)
	check(again.texture == hull.texture, "the field is cached")
	HULL.clear_cache()
	var rebuilt := HULL.build(mesh, 8, 8, 0)
	check(rebuilt.texture != hull.texture, "a rebuild drops the cache")
	var fine := HULL.build(mesh, 16, 16, 2)
	check(fine.resolution_x == 16 and fine.resolution_y == 16 and fine.smoothing == 2,
		"width, height and smoothing are part of the build")
	check(fine.texture.get_width() == 16, "the fine texture is 16 wide")
	var tall := HULL.build(mesh, 16, 32, 0)
	check(tall.resolution_x == 16 and tall.resolution_y == 32
		and tall.texture.get_width() == 16 and tall.texture.get_height() == 32,
		"a non-square hull width and height are honoured")
	var gap := HULL.build(_wide_fixture_mesh(), 16, 16, 0)
	check(gap != null, "the wide fixture hull builds")
	if gap != null:
		var invalid := 0
		for value: float in gap.field:
			if value < 0.0:
				invalid += 1
		check(invalid > 0, "an uncovered cell keeps the invalid marker")
	var unbounded := HULL.build(mesh, 72, 72, 6)
	check(unbounded != null and unbounded.resolution_x == 72 and unbounded.resolution_y == 72
		and unbounded.smoothing == 6,
		"the hull width and height rows are unbounded debug values")
	HULL.clear_cache()


func _check_hull_real() -> void:
	var scene: PackedScene = load(ANATOMY_SCENE)
	check(scene != null, "the anatomy scene loads")
	if scene == null:
		return
	var node: Node = scene.instantiate()
	var mesh: ArrayMesh = null
	if node is MeshInstance3D:
		mesh = (node as MeshInstance3D).mesh as ArrayMesh
	check(mesh != null, "the anatomy mesh loads")
	if mesh == null:
		node.free()
		return
	var hull := HULL.build(mesh, 32, 32, 1)
	check(hull != null, "the real anatomy hull builds")
	if hull == null:
		node.free()
		return
	var domain := hull.domain
	check(domain.size.x > 0.05 and domain.size.x < 0.10, "the domain stays on the rump")
	check(domain.size.y > 0.15 and domain.size.y < 0.25,
		"the anal extreme shape does not stretch the domain")
	check(hull.z_max > 0.015 and hull.z_max < 0.03,
		"the field is the rest closed surface, not the act anal envelope")
	var no_ponut := HULL.build(mesh, 32, 32, 1, 0.0)
	var rest_ponut := HULL.build(mesh, 32, 32, 1, -0.1)
	check(no_ponut.texture != rest_ponut.texture,
		"the rest ponut scale is part of the field")
	var field := hull.field
	var valid := 0
	for value: float in field:
		if value >= 0.0:
			valid += 1
	check(valid > field.size() / 2, "most of the domain is covered")
	node.free()
	HULL.clear_cache()


# --------------------------------------------------------------------------- transform

func _check_transform() -> void:
	var body := Node3D.new()
	body.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 2.0), Vector3(1, 2, 3))
	var mesh := Node3D.new()
	mesh.transform = Transform3D(
		Basis.from_euler(Vector3(0.2, 0.1, 0.0)).scaled(Vector3.ONE * 0.5),
		Vector3(0.1, 0.2, 0.3))
	root.add_child(body)
	root.add_child(mesh)
	var xform := CONTROLLER.garment_transform_for(body, mesh)
	var expected := body.global_transform.affine_inverse() * mesh.global_transform
	check(xform.origin.is_equal_approx(expected.origin), "the body-local inverse is used")
	check(xform.basis.is_equal_approx(expected.basis), "the live mesh basis is carried")
	var z_axis := (xform.basis * Vector3(0.0, 0.0, 1.0)).length()
	check(near(CONTROLLER.garment_margin_local(xform, 5.0), 0.005 / z_axis, 0.000001),
		"the margin is converted by the basis' Z scale")
	# A per-mare placement at rest.
	body.transform = Transform3D.IDENTITY
	mesh.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.682),
		Vector3(0.0, 0.505, 0.284))
	var placed := CONTROLLER.garment_transform_for(body, mesh)
	check(near(placed.origin.y, 0.505, 0.00001) and near(placed.origin.z, 0.284, 0.00001),
		"the per-mare placement origin is carried")
	check(near(CONTROLLER.garment_margin_local(placed, 5.0), 0.005 / 0.682, 0.000001),
		"the default placement scale converts the margin")
	# A live trim moves the mesh transform; the hull follows it.
	var before := placed.origin
	mesh.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.682),
		Vector3(0.0, 0.53, 0.284))
	check(not CONTROLLER.garment_transform_for(body, mesh).origin.is_equal_approx(before),
		"a live trim changes the garment transform")
	body.free()
	mesh.free()


# --------------------------------------------------------------------------- world adapter

func _make_world() -> Dictionary:
	var fake_main := FixtureHost.new()
	var game := FakeGame.new()
	var anatomy := FakeAnatomy.new()
	fake_main.anatomy = anatomy
	PONIES.anatomy = anatomy
	fake_main.game = game
	root.add_child(fake_main)
	root.add_child(game)
	root.add_child(anatomy)
	var integration := INTEGRATION.new()
	integration.name = "TestPantyhose"
	integration.mod_active = func() -> bool: return true
	integration.setup()
	root.add_child(integration)
	integration.on_world(game)
	# The suite drives the clock by hand; the engine must not run a scan between checks.
	integration.set_process(false)
	return {"main": fake_main, "game": game, "anatomy": anatomy, "integration": integration}


func _free_world(scene: Dictionary) -> void:
	var integration: Node = scene["integration"]
	if is_instance_valid(integration):
		integration.call("on_world_closed")
		integration.free()
	PONIES.anatomy = null
	var anatomy: Node = scene["anatomy"]
	if is_instance_valid(anatomy):
		anatomy.free()
	var game: Node = scene["game"]
	if is_instance_valid(game):
		game.free()
	var fake_main: Node = scene["main"]
	if is_instance_valid(fake_main):
		fake_main.free()


func _pony(id: String) -> FakePony:
	var pony := FakePony.new()
	pony.name = id.capitalize()
	var identity := FakeIdentity.new()
	identity.id = id
	pony.identity = identity
	pony.set_meta("relationship_id", id)
	root.add_child(pony)
	return pony


func _garment_mesh(material: Material) -> ArrayMesh:
	var verts := PackedVector3Array([
		Vector3(0.0, 0.0, 0.0), Vector3(0.01, 0.0, 0.0), Vector3(0.0, 0.01, 0.0),
	])
	var normals := PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK])
	var indices := PackedInt32Array([0, 1, 2])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if material != null:
		mesh.surface_set_material(0, material)
	return mesh


func _garment(pony: Node3D, kind: String, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = "Wear_" + kind
	node.mesh = _garment_mesh(material)
	pony.add_child(node)
	return node


## The pantyhose has a main piece and a skirt surface, each with its own material.
func _two_surface_mesh(main_material: Material, skirt_material: Material) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for material: Material in [main_material, skirt_material]:
		var verts := PackedVector3Array([
			Vector3(0.0, 0.0, 0.0), Vector3(0.01, 0.0, 0.0), Vector3(0.0, 0.01, 0.0),
		])
		var normals := PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK])
		var indices := PackedInt32Array([0, 1, 2])
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_INDEX] = indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)
	return mesh


func _material(shader: Shader) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	material.render_priority = 2
	material.set_shader_parameter("colour", Color(0.1, 0.2, 0.3, 1.0))
	material.set_shader_parameter("rough", 0.31)
	return material


func _hull() -> HULL.Hull:
	return HULL.build(_fixture_mesh(), 2, 2, 0)


func _inst_float(node: MeshInstance3D, name: String) -> float:
	var value: Variant = node.get_instance_shader_parameter(name)
	if value == null:
		return 0.0
	if value is float:
		return value as float
	if value is int:
		return float(value)
	return NAN


func _inst_vec3(node: MeshInstance3D, name: String) -> Vector3:
	var value: Variant = node.get_instance_shader_parameter(name)
	if value == null:
		return Vector3.ZERO
	return value as Vector3 if value is Vector3 else Vector3.INF


## `FlankTouch.impact()` places its mark at the hit point pushed out by the surface normal; the
## adapter must not read that mark, only the live material values below.
func _attach_flank(pony: Node3D) -> FakeFlank:
	var flank := FakeFlank.new()
	flank.name = "FlankTouch"
	pony.add_child(flank)
	return flank


## The pony's drawn body mesh, the pair partner of the coat material. It is in the tree so
## `is_visible_in_tree()` answers like the game's own body.
func _body_mesh(pony: Node3D, xform := Transform3D.IDENTITY, shown := true,
		node_name := "MareBody") -> MeshInstance3D:
	var body := MeshInstance3D.new()
	body.name = node_name
	body.mesh = _garment_mesh(null)
	body.transform = xform
	body.visible = shown
	pony.add_child(body)
	return body


## The live wobble `FlankTouch._process()` writes into one coat material, in that mesh's own space.
func _wobble(coat: ShaderMaterial, amount: float, age := 0.0,
		center := Vector3(0.0, 1.0, 0.2), outward := Vector3.BACK) -> void:
	coat.set_shader_parameter("jiggle_amount", amount)
	coat.set_shader_parameter("jiggle_time", age)
	coat.set_shader_parameter("jiggle_center", center)
	coat.set_shader_parameter("jiggle_normal", outward)


## `FlankTouch._process()` writes the wobble into each `[material, mesh]` pair in that mesh's own
## space every frame; the fake body and its coat material are the pair the adapter must read.
func _set_jiggle(flank: FakeFlank, body: MeshInstance3D, coat: ShaderMaterial,
		center: Vector3, outward: Vector3, amount: float, age := 0.0) -> void:
	_wobble(coat, amount, age, center, outward)
	flank._body = body
	flank._jiggle_targets = [[coat, body]]


## The decal-era fields, deliberately disagreeing with the coat material: a mark far from the hit
## and a raw age and amount the helper must never read.
func _poison(flank: FakeFlank) -> void:
	var mark := Decal.new()
	mark.name = "Mark"
	flank.add_child(mark)
	mark.global_position = Vector3(50.0, 50.0, 50.0)
	flank.marks = [mark]
	flank._jiggle_index = 0
	flank._jiggle_age = 9.0
	flank._jiggle_amount = 9.0


func _coat_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = COAT_SHADER_CODE
	var material := ShaderMaterial.new()
	material.shader = shader
	return material


func _check_bulge() -> void:
	var scene := _make_world()
	var game: FakeGame = scene["game"]
	var anatomy: FakeAnatomy = scene["anatomy"]
	var integration: Node = scene["integration"]
	# The lift checks pin the lift on its own; the cloth jiggle has its own checks below.
	var jiggle_before := SETTINGS.pantyhose_jiggle.get_bool()
	SETTINGS.pantyhose_jiggle.set_bool(false)
	integration.call("apply_live_settings")
	var pony := _pony("rarity")
	game.mares = [pony]
	var material := _material(CUT_SHADER)
	var garment := _garment(pony, "panties-satin", material)
	anatomy.hull = _hull()
	anatomy.xform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.5),
		Vector3(0.0, 1.0, 2.0))
	integration.call("scan")
	var override := garment.get_surface_override_material(0)
	check(override is ShaderMaterial, "the worn piece gets a compatibility override")
	if override is ShaderMaterial:
		var compat := override as ShaderMaterial
		check(compat.shader == CUT_SHADER, "the cut look uses the copied cut shader")
		check(compat.render_priority == 2, "the original render priority is copied")
		check(near(float(compat.get_shader_parameter("rough")), 0.31, 0.00001),
			"the look parameters are copied")
		check(compat.get_shader_parameter("hull_texture") != null,
			"the shared hull texture is set")
	check(garment.mesh.surface_get_material(0) == material, "the shared mesh is not mutated")
	check(near(float(garment.get_instance_shader_parameter("hull_on")), 1.0, 0.00001),
		"the hull is on")
	var origin: Variant = garment.get_instance_shader_parameter("hull_origin")
	check(origin is Vector3 and near((origin as Vector3).y, 1.0, 0.00001),
		"the per-mare origin is set")
	var z_axis: Variant = garment.get_instance_shader_parameter("hull_basis_z")
	check(z_axis is Vector3 and near((z_axis as Vector3).length(), 0.5, 0.00001),
		"the basis carries the placement scale")
	# The shader works in anatomy-local metres, so a margin is divided by the anatomy scale.
	var margin := float(SETTINGS.pantyhose_hull_margin_mm.default) / 1000.0 / 0.5
	check(near(float(garment.get_instance_shader_parameter("hull_margin")), margin, 0.00001),
		"the outer margin is anatomy-local")
	var min_margin := float(SETTINGS.pantyhose_hull_min_margin_mm.default) / 1000.0 / 0.5
	check(near(float(garment.get_instance_shader_parameter("hull_min_margin")), min_margin, 0.00001),
		"the minimum margin is anatomy-local")
	anatomy.xform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.5),
		Vector3(0.0, 2.0, 0.0))
	integration.call("_process", 0.016)
	var moved: Variant = garment.get_instance_shader_parameter("hull_origin")
	check(moved is Vector3 and near((moved as Vector3).y, 2.0, 0.00001),
		"the hull follows the anatomy every frame")
	anatomy.xform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.5),
		Vector3(0.0, 1.0, 2.0))
	anatomy.visible = false
	integration.call("scan")
	check(garment.get_surface_override_material(0) == null,
		"a hidden anatomy restores the override")
	check(near(float(garment.get_instance_shader_parameter("hull_on")), 0.0, 0.00001),
		"a hidden anatomy turns the hull off")
	anatomy.visible = true
	integration.call("scan")
	check(garment.get_surface_override_material(0) != null, "the override returns")
	var before := SETTINGS.pantyhose_bulge.get_bool()
	SETTINGS.pantyhose_bulge.set_bool(false)
	integration.call("apply_live_settings")
	integration.call("scan")
	check(garment.get_surface_override_material(0) == null,
		"turning the bulge off restores the cloth")
	SETTINGS.pantyhose_bulge.set_bool(before)
	integration.call("apply_live_settings")
	integration.call("scan")
	check(garment.get_surface_override_material(0) != null, "turning the bulge on lifts it again")
	SETTINGS.pantyhose_jiggle.set_bool(jiggle_before)
	integration.call("apply_live_settings")
	garment.free()
	pony.free()
	_free_world(scene)


func _check_sheer() -> void:
	var scene := _make_world()
	var game: FakeGame = scene["game"]
	var anatomy: FakeAnatomy = scene["anatomy"]
	var integration: Node = scene["integration"]
	var pony := _pony("fluttershy")
	game.mares = [pony]
	var garment := _garment(pony, "pantyhose-sheer", _material(SHEER_SHADER))
	anatomy.hull = _hull()
	anatomy.xform = Transform3D.IDENTITY
	integration.call("scan")
	var override := garment.get_surface_override_material(0)
	check(override is ShaderMaterial and (override as ShaderMaterial).shader == SHEER_SHADER,
		"the sheer look uses the copied sheer shader")
	garment.free()
	pony.free()
	_free_world(scene)


func _check_two_surfaces() -> void:
	var scene := _make_world()
	var game: FakeGame = scene["game"]
	var anatomy: FakeAnatomy = scene["anatomy"]
	var integration: Node = scene["integration"]
	var pony := _pony("rarity")
	game.mares = [pony]
	var main_material := _material(CUT_SHADER)
	main_material.set_shader_parameter("rough", 0.2)
	var skirt_material := _material(CUT_SHADER)
	skirt_material.set_shader_parameter("rough", 0.8)
	var mesh := _two_surface_mesh(main_material, skirt_material)
	var node := MeshInstance3D.new()
	node.name = "Wear_pantyhose-sheer"
	node.mesh = mesh
	pony.add_child(node)
	anatomy.hull = _hull()
	anatomy.xform = Transform3D.IDENTITY
	integration.call("scan")
	var first := node.get_surface_override_material(0) as ShaderMaterial
	var second := node.get_surface_override_material(1) as ShaderMaterial
	check(first != null and second != null, "both surfaces get an override")
	check(first != second, "each source material keeps its own compatibility material")
	if first != null:
		check(near(float(first.get_shader_parameter("rough")), 0.2, 0.00001),
			"the main look is copied")
	if second != null:
		check(near(float(second.get_shader_parameter("rough")), 0.8, 0.00001),
			"the skirt look is copied")
	check(mesh.surface_get_material(0) == main_material
		and mesh.surface_get_material(1) == skirt_material,
		"the shared mesh keeps its own materials")
	node.free()
	pony.free()
	_free_world(scene)


func _check_multi_mare() -> void:
	var scene := _make_world()
	var game: FakeGame = scene["game"]
	var anatomy: FakeAnatomy = scene["anatomy"]
	var integration: Node = scene["integration"]
	var first := _pony("rarity")
	var second := _pony("applejack")
	game.mares = [first, second]
	var first_garment := _garment(first, "panties-lace", _material(CUT_SHADER))
	var second_garment := _garment(second, "pantyhose-fishnet", _material(CUT_SHADER))
	anatomy.hull = _hull()
	# The fake service returns one transform; the two nodes must still carry independent values.
	anatomy.xform = Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0))
	integration.call("scan")
	check(first_garment.get_surface_override_material(0) != null
		and second_garment.get_surface_override_material(0) != null,
		"both mares get their own override")
	var first_origin: Variant = first_garment.get_instance_shader_parameter("hull_origin")
	var second_origin: Variant = second_garment.get_instance_shader_parameter("hull_origin")
	check(first_origin is Vector3 and second_origin is Vector3,
		"both mares carry an instance origin")
	anatomy.xform = Transform3D(Basis.IDENTITY, Vector3(0.0, 2.0, 0.0))
	integration.call("scan")
	var moved: Variant = second_garment.get_instance_shader_parameter("hull_origin")
	check(moved is Vector3 and near((moved as Vector3).y, 2.0, 0.00001),
		"the instance value follows that mare's transform")
	first_garment.free()
	second_garment.free()
	first.free()
	second.free()
	_free_world(scene)


# --------------------------------------------------------------------------- cloth jiggle

## The cloth follows the live uniform values `FlankTouch` writes on the drawn body's coat material,
## mapped into the worn node's own space; the decal, the raw age and the raw amount are not read.
func _check_jiggle() -> void:
	var scene := _make_world()
	var game: FakeGame = scene["game"]
	var anatomy: FakeAnatomy = scene["anatomy"]
	var integration: Node = scene["integration"]
	var pony := _pony("rarity")
	game.mares = [pony]
	var garment := _garment(pony, "panties-satin", _material(CUT_SHADER))
	garment.transform = Transform3D(Basis(Vector3.UP, PI / 2.0).scaled(Vector3.ONE * 0.5),
		Vector3(1.0, 2.0, 3.0))
	anatomy.hull = _hull()
	anatomy.xform = Transform3D.IDENTITY
	var body := _body_mesh(pony, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 2.0),
		Vector3(0.0, 1.0, 0.0)))
	var coat := _coat_material()
	var flank := _attach_flank(pony)
	_set_jiggle(flank, body, coat, Vector3(0.1, 0.2, 0.3), Vector3.BACK, 0.02, 0.25)
	_poison(flank)
	integration.call("scan")
	check(garment.get_surface_override_material(0) is ShaderMaterial,
		"the jiggle keeps the compatibility override")
	# The body's scale 2 into the worn node's scale 0.5: the amplitude and the radius grow fourfold.
	check(near(_inst_float(garment, "garment_jiggle_amount"), 0.08, 0.0001),
		"the coat amplitude travels through the target/garment scale ratio")
	check(near(_inst_float(garment, "garment_jiggle_amount") * 0.5, 0.02 * 2.0, 0.0001),
		"the cloth moves by the coat's own world distance")
	check(near(_inst_float(garment, "garment_jiggle_time"), 0.25, 0.00001),
		"the wobble age is the coat material's own age")
	check(near(_inst_float(garment, "garment_jiggle_radius"), 0.48, 0.0001),
		"the stock coat radius travels through the scale ratio")
	check(_inst_vec3(garment, "garment_jiggle_center").distance_to(Vector3(4.8, -1.2, -1.6)) < 0.0001,
		"the coat's hit spot is mapped through the target and the garment transforms")
	check(_inst_vec3(garment, "garment_jiggle_normal").distance_to(Vector3.LEFT) < 0.0001,
		"the outward coat normal is mapped through the target and the garment transforms")
	check(_inst_vec3(garment, "garment_jiggle_up").distance_to(Vector3.UP) < 0.0001,
		"the body's up is mapped through the target and the garment transforms")
	coat.set_shader_parameter("jiggle_time", 0.5)
	integration.call("scan")
	check(near(_inst_float(garment, "garment_jiggle_time"), 0.5, 0.00001),
		"the wobble follows the coat material every frame")
	coat.set_shader_parameter("jiggle_radius", 0.3)
	integration.call("scan")
	check(near(_inst_float(garment, "garment_jiggle_radius"), 1.2, 0.0001),
		"the act's tuned coat radius is borrowed")
	coat.set_shader_parameter("jiggle_radius", -0.05)
	integration.call("scan")
	check(near(_inst_float(garment, "garment_jiggle_radius"), 0.48, 0.0001),
		"a negative coat radius falls back to the stock spread")
	coat.set_shader_parameter("jiggle_radius", null)
	integration.call("scan")
	check(near(_inst_float(garment, "garment_jiggle_radius"), 0.48, 0.0001),
		"an unset coat radius falls back to the stock spread")
	coat.set_shader_parameter("jiggle_amount", null)
	integration.call("scan")
	check(near(_inst_float(garment, "garment_jiggle_amount"), 0.0, 0.00001),
		"the coat's finished wobble clears the cloth")
	check(near(_inst_float(garment, "hull_on"), 1.0, 0.00001),
		"a finished wobble keeps the lift on the worn piece")
	garment.free()
	pony.free()
	_free_world(scene)


## A rotated body and a rotated, trimmed garment: the bob runs along the body's up, not the
## garment's own +Y, and the mapped values round-trip to the coat's world hit.
func _check_jiggle_space() -> void:
	var scene := _make_world()
	var game: FakeGame = scene["game"]
	var anatomy: FakeAnatomy = scene["anatomy"]
	var integration: Node = scene["integration"]
	var pony := _pony("fluttershy")
	game.mares = [pony]
	var garment := _garment(pony, "pantyhose-sheer", _material(SHEER_SHADER))
	garment.transform = Transform3D(
		Basis.from_euler(Vector3(0.0, 0.4, PI / 2.0)).scaled(Vector3.ONE * 0.5),
		Vector3(1.0, 0.5, 2.0))
	anatomy.hull = _hull()
	var body := _body_mesh(pony, Transform3D(
		Basis.from_euler(Vector3(0.6, 0.0, 0.0)).scaled(Vector3.ONE * 2.0),
		Vector3(0.0, 1.0, 0.5)))
	var coat := _coat_material()
	var flank := _attach_flank(pony)
	_set_jiggle(flank, body, coat, Vector3(0.0, 0.1, 0.2), Vector3(0.0, 0.6, 1.0), 0.03, 0.1)
	integration.call("scan")
	var inverse := garment.global_transform.affine_inverse()
	var body_up := (body.global_transform.basis * Vector3.UP).normalized()
	var up := _inst_vec3(garment, "garment_jiggle_up")
	check(up.distance_to((inverse.basis * body_up).normalized()) < 0.0001,
		"the up axis is the body's up in the garment's own space")
	check((garment.global_transform.basis * up).normalized().distance_to(body_up) < 0.0001,
		"the cloth's bob runs along the body's up in world space")
	check(up.distance_to(Vector3.UP) > 0.1,
		"a rotated garment does not bob along its own +Y")
	var hit := body.global_transform * Vector3(0.0, 0.1, 0.2)
	check((garment.global_transform * _inst_vec3(garment, "garment_jiggle_center")).distance_to(hit)
		< 0.0001, "the mapped centre round-trips to the coat's world hit spot")
	var outward := (body.global_transform.basis * Vector3(0.0, 0.6, 1.0)).normalized()
	check((garment.global_transform.basis * _inst_vec3(garment, "garment_jiggle_normal"))
		.normalized().distance_to(outward) < 0.0001,
		"the mapped normal round-trips to the coat's world outward normal")
	check(near(_inst_float(garment, "garment_jiggle_amount") * 0.5, 0.03 * 2.0, 0.0001),
		"a rotated trim keeps the coat's world amplitude")
	garment.free()
	pony.free()
	_free_world(scene)


## The reference pair: a visible one first, then the game body, then the first pair with live
## values. Everything else in `_jiggle_targets` is ignored.
func _check_jiggle_targets() -> void:
	var scene := _make_world()
	var game: FakeGame = scene["game"]
	var anatomy: FakeAnatomy = scene["anatomy"]
	var integration: Node = scene["integration"]
	var pony := _pony("rarity")
	game.mares = [pony]
	var garment := _garment(pony, "panties-lace", _material(CUT_SHADER))
	anatomy.hull = _hull()
	var flank := _attach_flank(pony)
	var body := _body_mesh(pony, Transform3D.IDENTITY, false)
	var visible_body := _body_mesh(pony, Transform3D(Basis.IDENTITY, Vector3(0.1, 0.0, 0.0)),
		true, "Wear_near")
	var spare_body := _body_mesh(pony, Transform3D(Basis.IDENTITY, Vector3(0.2, 0.0, 0.0)),
		true, "MareBody_far")
	var body_coat := _coat_material()
	var visible_coat := _coat_material()
	var spare_coat := _coat_material()
	_wobble(body_coat, 0.01, 0.1)
	_wobble(visible_coat, 0.02, 0.2)
	_wobble(spare_coat, 0.03, 0.3)
	flank._body = body
	flank._jiggle_targets = [[body_coat, body], [visible_coat, visible_body],
		[spare_coat, spare_body]]
	integration.call("scan")
	check(near(_inst_float(garment, "garment_jiggle_amount"), 0.02, 0.0001),
		"a visible coat target wins over the hidden body")
	visible_body.visible = false
	spare_body.visible = false
	integration.call("scan")
	check(near(_inst_float(garment, "garment_jiggle_amount"), 0.01, 0.0001),
		"the game body is the fallback while every target is hidden")
	flank._jiggle_targets = [[spare_coat, spare_body], [visible_coat, visible_body]]
	integration.call("scan")
	check(near(_inst_float(garment, "garment_jiggle_amount"), 0.03, 0.0001),
		"a hidden target that is not the body starts the first-pair fallback")
	flank._jiggle_targets = ["junk", [null, null], [spare_coat, spare_body]]
	integration.call("scan")
	check(near(_inst_float(garment, "garment_jiggle_amount"), 0.03, 0.0001),
		"a malformed pair before the first live one is skipped")
	var loose := _body_mesh(pony, Transform3D.IDENTITY, true, "LooseBody")
	loose.get_parent().remove_child(loose)
	flank._body = null
	flank._jiggle_targets = [[visible_coat, loose], [spare_coat, spare_body]]
	integration.call("scan")
	check(near(_inst_float(garment, "garment_jiggle_amount"), 0.03, 0.0001),
		"a target mesh outside the tree is not a wobble")
	flank._body = body
	spare_body.visible = true
	flank._jiggle_targets = [[body_coat, body], [spare_coat, spare_body]]
	integration.call("scan")
	check(near(_inst_float(garment, "garment_jiggle_amount"), 0.03, 0.0001),
		"a visible pair wins even when the body comes first")
	loose.free()
	garment.free()
	pony.free()
	_free_world(scene)


## A null, zero or malformed field is what `FlankTouch._end_jiggle()` and a renamed game field
## leave behind: the cloth stays rigid and the lift stays on.
func _check_jiggle_malformed() -> void:
	var scene := _make_world()
	var game: FakeGame = scene["game"]
	var anatomy: FakeAnatomy = scene["anatomy"]
	var integration: Node = scene["integration"]
	var pony := _pony("applejack")
	game.mares = [pony]
	var garment := _garment(pony, "panties-cotton", _material(CUT_SHADER))
	anatomy.hull = _hull()
	var body := _body_mesh(pony)
	var coat := _coat_material()
	var flank := _attach_flank(pony)
	_set_jiggle(flank, body, coat, Vector3(0.0, 0.1, 0.2), Vector3.BACK, 0.02, 0.3)
	integration.call("scan")
	check(near(_inst_float(garment, "garment_jiggle_amount"), 0.02, 0.0001),
		"the fixture starts wobbling")
	var broken: Array = [
		["amount", 0.0], ["amount", -0.02], ["amount", null], ["amount", "0.02"],
		["time", null], ["time", "0.3"],
		["center", null], ["center", "here"],
		["normal", null], ["normal", Vector3.ZERO],
	]
	for row: Array in broken:
		_set_jiggle(flank, body, coat, Vector3(0.0, 0.1, 0.2), Vector3.BACK, 0.02, 0.3)
		coat.set_shader_parameter("jiggle_" + str(row[0]), row[1])
		integration.call("scan")
		check(near(_inst_float(garment, "garment_jiggle_amount"), 0.0, 0.00001),
			"a %s of %s is not a wobble" % [str(row[0]), str(row[1])])
		check(near(_inst_float(garment, "hull_on"), 1.0, 0.00001),
			"a broken %s keeps the lift" % str(row[0]))
	_set_jiggle(flank, body, coat, Vector3(0.0, 0.1, 0.2), Vector3.BACK, 0.02, 0.3)
	flank._jiggle_targets = []
	integration.call("scan")
	check(near(_inst_float(garment, "garment_jiggle_amount"), 0.0, 0.00001),
		"an ended coat wobble clears the cloth")
	_set_jiggle(flank, body, coat, Vector3(0.0, 0.1, 0.2), Vector3.BACK, 0.02, 0.3)
	flank._jiggle_targets = [[StandardMaterial3D.new(), body]]
	integration.call("scan")
	check(near(_inst_float(garment, "garment_jiggle_amount"), 0.0, 0.00001),
		"a target material without the game's uniforms leaves the cloth rigid")
	_set_jiggle(flank, body, coat, Vector3(0.0, 0.1, 0.2), Vector3.BACK, 0.02, 0.3)
	flank.set_script(null)
	integration.call("scan")
	check(near(_inst_float(garment, "garment_jiggle_amount"), 0.0, 0.00001),
		"a flank without the fields leaves the cloth rigid")
	garment.free()
	pony.free()
	_free_world(scene)


## The garment pass is pinned after the coat's own `FlankTouch._process`, so both read the same
## frame's wobble.
func _check_process_priority() -> void:
	var scene := _make_world()
	var integration: Node = scene["integration"]
	var pony := _pony("rarity")
	var flank := _attach_flank(pony)
	check(int(flank.process_priority) == 0, "the game's flank touch processes at the default 0")
	check(int(integration.process_priority) > int(flank.process_priority),
		"the garment pass runs after the coat's own wobble")
	check(int(integration.process_priority) == INTEGRATION.PROCESS_PRIORITY,
		"the adapter uses its declared process priority")
	integration.call("on_world_closed")
	check(int(integration.process_priority) == INTEGRATION.PROCESS_PRIORITY,
		"a world close keeps the order")
	pony.free()
	_free_world(scene)


## The shader half of the sync: the field is evaluated at the rest cloth vertex, the hull lift runs
## after it, the offset is added last, and the six jiggle uniforms plus the ten hull ones are
## exactly Godot's sixteen.
func _check_shader_sync() -> void:
	var common := FileAccess.get_file_as_string(SHADER_DIR + "pantyhose_common.gdshaderinc")
	var jiggle := FileAccess.get_file_as_string(SHADER_DIR + "pantyhose_jiggle.gdshaderinc")
	check(not common.is_empty() and not jiggle.is_empty(), "the copied shader includes load")
	var hull_count := _count_instance_uniforms(common)
	var jiggle_count := _count_instance_uniforms(jiggle)
	check(hull_count == 10, "the hull block declares ten instance uniforms")
	check(jiggle_count == 6, "the jiggle block declares six instance uniforms")
	check(hull_count + jiggle_count == INSTANCE_UNIFORM_LIMIT,
		"the copied shaders stay inside Godot's sixteen instance uniforms")
	for declaration: String in ["instance uniform float garment_jiggle_amount",
			"instance uniform float garment_jiggle_time",
			"instance uniform vec3 garment_jiggle_center",
			"instance uniform vec3 garment_jiggle_normal",
			"instance uniform float garment_jiggle_radius",
			"instance uniform vec3 garment_jiggle_up"]:
		check(jiggle.contains(declaration), "the jiggle include declares %s" % declaration)
	check(jiggle.contains("vec3 hosiery_jiggle(vec3 vertex)"),
		"the jiggle include exposes hosiery_jiggle(vec3)")
	check(not jiggle.contains("HOSIERY_JIGGLE_VERTEX"), "the old vertex macro is gone")
	for shader: Shader in [CUT_SHADER, SHEER_SHADER]:
		var code := shader.code
		var name := shader.resource_path.get_file()
		check(_count_instance_uniforms(code) == 0,
			"%s declares no instance uniform of its own" % name)
		var evaluate := code.find("vec3 cloth_jiggle = hosiery_jiggle(VERTEX);")
		var hull := code.find("HOSIERY_HULL_VERTEX")
		var add := code.find("VERTEX += cloth_jiggle;")
		check(evaluate >= 0 and hull > evaluate and add > hull,
			"%s evaluates the wobble at the rest vertex, lifts, then adds it" % name)


## The declaration lines only: a comment mentioning the word is not a uniform.
static func _count_instance_uniforms(text: String) -> int:
	var count := 0
	for line: String in text.split("\n"):
		if line.begins_with("instance uniform "):
			count += 1
	return count


func _check_jiggle_two_mares() -> void:
	var scene := _make_world()
	var game: FakeGame = scene["game"]
	var anatomy: FakeAnatomy = scene["anatomy"]
	var integration: Node = scene["integration"]
	var first := _pony("rarity")
	var second := _pony("applejack")
	game.mares = [first, second]
	var material := _material(CUT_SHADER)
	var first_garment := _garment(first, "panties-lace", material)
	var second_garment := _garment(second, "pantyhose-fishnet", material)
	anatomy.hull = _hull()
	anatomy.xform = Transform3D.IDENTITY
	var first_body := _body_mesh(first)
	var second_body := _body_mesh(second, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.1)))
	var first_coat := _coat_material()
	var second_coat := _coat_material()
	var first_flank := _attach_flank(first)
	var second_flank := _attach_flank(second)
	_set_jiggle(first_flank, first_body, first_coat, Vector3(0.1, 1.0, 0.2), Vector3.BACK, 0.02, 0.1)
	_set_jiggle(second_flank, second_body, second_coat, Vector3(0.4, 1.1, 0.3), Vector3.BACK, 0.01, 0.4)
	integration.call("scan")
	check(first_garment.get_surface_override_material(0) ==
		second_garment.get_surface_override_material(0),
		"the two mares share the one compatibility material")
	check(near(_inst_float(first_garment, "garment_jiggle_amount"), 0.02, 0.0001)
		and near(_inst_float(second_garment, "garment_jiggle_amount"), 0.01, 0.0001),
		"each mare's cloth carries her own coat amplitude")
	check(near(_inst_float(first_garment, "garment_jiggle_time"), 0.1, 0.0001)
		and near(_inst_float(second_garment, "garment_jiggle_time"), 0.4, 0.0001),
		"each mare's cloth carries her own wobble age")
	check(_inst_vec3(first_garment, "garment_jiggle_center").distance_to(
		_inst_vec3(second_garment, "garment_jiggle_center")) > 0.1,
		"the two mares keep independent wobble centres")
	first_coat.set_shader_parameter("jiggle_amount", null)
	first_flank._jiggle_targets = []
	integration.call("scan")
	check(near(_inst_float(first_garment, "garment_jiggle_amount"), 0.0, 0.00001),
		"a finished wobble clears that mare's cloth")
	check(first_garment.get_surface_override_material(0) != null,
		"a finished wobble keeps the lift on the worn piece")
	check(near(_inst_float(second_garment, "garment_jiggle_amount"), 0.01, 0.0001),
		"ending one mare's wobble leaves the other's")
	first_garment.free()
	second_garment.free()
	first.free()
	second.free()
	_free_world(scene)


func _check_jiggle_without_lift() -> void:
	var scene := _make_world()
	var game: FakeGame = scene["game"]
	var anatomy: FakeAnatomy = scene["anatomy"]
	var integration: Node = scene["integration"]
	var bulge_before := SETTINGS.pantyhose_bulge.get_bool()
	var jiggle_before := SETTINGS.pantyhose_jiggle.get_bool()
	SETTINGS.pantyhose_jiggle.set_bool(true)
	integration.call("apply_live_settings")
	var pony := _pony("fluttershy")
	game.mares = [pony]
	var garment := _garment(pony, "pantyhose-sheer", _material(SHEER_SHADER))
	anatomy.hull = _hull()
	anatomy.visible = false
	var body := _body_mesh(pony)
	var coat := _coat_material()
	var flank := _attach_flank(pony)
	_set_jiggle(flank, body, coat, Vector3(0.0, 1.0, 0.3), Vector3.BACK, 0.02, 0.1)
	integration.call("scan")
	check(garment.get_surface_override_material(0) is ShaderMaterial,
		"a hidden anatomy still carries the cloth jiggle")
	check(near(_inst_float(garment, "hull_on"), 0.0, 0.00001), "a hidden anatomy leaves the lift off")
	check(near(_inst_float(garment, "garment_jiggle_amount"), 0.02, 0.0001),
		"a hidden anatomy keeps the wobble")
	anatomy.visible = true
	integration.call("scan")
	check(near(_inst_float(garment, "hull_on"), 1.0, 0.00001), "the lift returns with the anatomy")
	SETTINGS.pantyhose_jiggle.set_bool(false)
	integration.call("apply_live_settings")
	integration.call("scan")
	check(garment.get_surface_override_material(0) is ShaderMaterial,
		"turning the jiggle off keeps the lift in place")
	check(near(_inst_float(garment, "garment_jiggle_amount"), 0.0, 0.00001),
		"turning the jiggle off clears the cloth wobble")
	SETTINGS.pantyhose_jiggle.set_bool(true)
	integration.call("apply_live_settings")
	integration.call("scan")
	check(near(_inst_float(garment, "garment_jiggle_amount"), 0.02, 0.0001),
		"turning the jiggle on takes the live wobble again")
	SETTINGS.pantyhose_bulge.set_bool(false)
	integration.call("apply_live_settings")
	integration.call("scan")
	check(garment.get_surface_override_material(0) is ShaderMaterial,
		"turning the lift off keeps the cloth shader for the jiggle")
	check(near(_inst_float(garment, "hull_on"), 0.0, 0.00001), "turning the lift off sets the hull off")
	check(near(_inst_float(garment, "garment_jiggle_amount"), 0.02, 0.0001),
		"turning the lift off keeps the wobble")
	check(_inst_vec3(garment, "garment_jiggle_up").distance_to(Vector3.UP) < 0.0001,
		"the up axis is written without a lift too")
	SETTINGS.pantyhose_jiggle.set_bool(false)
	integration.call("apply_live_settings")
	integration.call("scan")
	check(garment.get_surface_override_material(0) == null,
		"both flags off restore the pack material")
	check(near(_inst_float(garment, "garment_jiggle_amount"), 0.0, 0.00001),
		"both flags off clear the cloth wobble")
	check(_inst_vec3(garment, "garment_jiggle_up").is_equal_approx(Vector3.UP),
		"both flags off restore the up default")
	SETTINGS.pantyhose_bulge.set_bool(bulge_before)
	SETTINGS.pantyhose_jiggle.set_bool(jiggle_before)
	integration.call("apply_live_settings")
	garment.free()
	pony.free()
	_free_world(scene)


func _check_jiggle_lifecycle() -> void:
	var scene := _make_world()
	var game: FakeGame = scene["game"]
	var anatomy: FakeAnatomy = scene["anatomy"]
	var integration: Node = scene["integration"]
	var pony := _pony("rarity")
	game.mares = [pony]
	var garment := _garment(pony, "panties-satin", _material(CUT_SHADER))
	anatomy.hull = _hull()
	var body := _body_mesh(pony)
	var coat := _coat_material()
	integration.call("scan")
	check(garment.get_surface_override_material(0) is ShaderMaterial,
		"a worn piece without a flank keeps the lift")
	check(near(_inst_float(garment, "garment_jiggle_amount"), 0.0, 0.00001),
		"a missing flank is a quiet no-op")
	var flank := _attach_flank(pony)
	_set_jiggle(flank, body, coat, Vector3(0.0, 1.0, 0.3), Vector3.BACK, 0.02, 0.1)
	integration.call("scan")
	check(near(_inst_float(garment, "garment_jiggle_amount"), 0.02, 0.0001),
		"a flank that appears the next pass jiggles the cloth")
	game.mares = []
	integration.call("scan")
	check(near(_inst_float(garment, "garment_jiggle_amount"), 0.0, 0.00001),
		"a dropped garment clears the wobble")
	check(garment.get_surface_override_material(0) == null,
		"a dropped garment restores the pack material")
	game.mares = [pony]
	integration.call("scan")
	check(near(_inst_float(garment, "garment_jiggle_amount"), 0.02, 0.0001),
		"the wobble returns with the re-discovered piece")
	integration.call("on_world_closed")
	check(near(_inst_float(garment, "garment_jiggle_amount"), 0.0, 0.00001),
		"a world close clears the cloth wobble")
	check(garment.get_surface_override_material(0) == null,
		"a world close restores the pack material")
	integration.call("on_world", game)
	integration.set_process(false)
	integration.call("scan")
	check(near(_inst_float(garment, "garment_jiggle_amount"), 0.02, 0.0001),
		"a new world takes the live wobble again")
	integration.call("shutdown")
	check(near(_inst_float(garment, "garment_jiggle_amount"), 0.0, 0.00001),
		"a shutdown clears the cloth wobble")
	check(garment.get_surface_override_material(0) == null,
		"a shutdown restores the pack material")
	garment.free()
	pony.free()
	_free_world(scene)


# --------------------------------------------------------------------------- act undress

func _check_undress() -> void:
	var scene := _make_world()
	var game: FakeGame = scene["game"]
	var anatomy: FakeAnatomy = scene["anatomy"]
	var integration: Node = scene["integration"]
	var pony := _pony("rarity")
	# The wardrobe's key is identity.id; a different relationship meta must not reach it.
	pony.set_meta("relationship_id", "rarity_meta")
	game.mares = [pony]
	var wardrobe := FakeWardrobe.new()
	wardrobe.name = "Wardrobe"
	wardrobe.wanted_map = {"panties-lace": 0, "pantyhose-sheer": 0}
	wardrobe.season = "winter"
	wardrobe.add_to_group("pony_wardrobe")
	root.add_child(wardrobe)
	var coordinator := FakeCoordinator.new()
	coordinator.name = "Coordinator"
	coordinator.wardrobe = wardrobe
	coordinator.executors = {"rarity": true}
	root.add_child(coordinator)
	var director := FakeDirector.new()
	director.name = "Director"
	director.actions = coordinator
	director.add_to_group("conversation_director")
	root.add_child(director)

	# Her own take_off action: one commit, the kinds she wears, the director's own turn.
	anatomy.act_started.emit(pony)
	check(coordinator.commits.size() == 1, "the act takes the game's take_off path")
	var row: Dictionary = coordinator.commits[0] if not coordinator.commits.is_empty() else {}
	var acts: Array = row.get("actions", [])
	check(str(row.get("id", "")) == "rarity", "the take_off names her identity id")
	check(int(row.get("turn", -1)) == 7, "the take_off keeps the director's turn")
	check(acts.size() == 2
		and str((acts[0] as Dictionary).get("kind", "")) == "panties-lace"
		and str((acts[1] as Dictionary).get("kind", "")) == "pantyhose-sheer",
		"the take_off actions name the kinds she wears")
	check(acts.all(func(action: Variant) -> bool:
		return str((action as Dictionary).get("type", "")) == "take_off"),
		"both actions are take_off")
	for action: Variant in acts:
		check(SCHEMA.validate((action as Dictionary).duplicate(true),
			{"capabilities": ["take_off"]}) == "",
			"the take_off action passes the game's schema")
	check(acts.size() == 2
		and str((acts[0] as Dictionary).get("id", "")) != str((acts[1] as Dictionary).get("id", "")),
		"the action ids stay unique within the turn")
	check(wardrobe.calls.is_empty(), "the action path does not also call the wardrobe")
	check(wardrobe.wanted_map.is_empty(), "both pieces are off")
	integration.call("scan")
	check(coordinator.commits.size() == 1, "the undress does not repeat on the next scan")
	wardrobe.calls.clear()

	# A refused commit takes the direct path with the wardrobe's own season and id.
	wardrobe.wanted_map = {"panties-lace": 0, "pantyhose-sheer": 0}
	coordinator.refuse = true
	anatomy.act_started.emit(pony)
	check(wardrobe.calls.has("set_worn:rarity:panties-lace:false"),
		"a refused take_off still removes the panties")
	check(wardrobe.calls.has("set_worn:rarity:pantyhose-sheer:false"),
		"a refused take_off still removes the pantyhose")
	check(wardrobe.calls.has("dress:rarity:winter:Rarity"),
		"the fallback dresses her with the wardrobe's season")
	check(not wardrobe.calls.has("set_worn:rarity_meta:panties-lace:false"),
		"the fallback keys by identity, not the relationship meta")
	coordinator.refuse = false
	wardrobe.calls.clear()
	var commits := coordinator.commits.size()

	# A pony the director does not track also takes the direct path.
	wardrobe.wanted_map = {"panties-lace": 0}
	coordinator.executors = {}
	anatomy.act_started.emit(pony)
	check(wardrobe.calls.has("set_worn:rarity:panties-lace:false"),
		"a missing executor takes the direct path")
	wardrobe.calls.clear()
	coordinator.executors = {"rarity": true}

	# Nothing of the pack's is worn: no action, no outcome, no wardrobe call.
	wardrobe.wanted_map = {"scarf": 0}
	anatomy.act_started.emit(pony)
	check(coordinator.commits.size() == commits and wardrobe.calls.is_empty(),
		"a mare with only her winter scarf is not touched")

	var before := SETTINGS.pantyhose_undress.get_bool()
	SETTINGS.pantyhose_undress.set_bool(false)
	integration.call("apply_live_settings")
	wardrobe.wanted_map = {"panties-lace": 0}
	anatomy.act_started.emit(pony)
	check(coordinator.commits.size() == commits and wardrobe.calls.is_empty(),
		"the undress flag can keep her dressed")
	SETTINGS.pantyhose_undress.set_bool(before)
	integration.call("apply_live_settings")
	integration.set("mod_active", func() -> bool: return false)
	anatomy.act_started.emit(pony)
	check(wardrobe.calls.is_empty(), "an absent pantyhose pack leaves the wardrobe alone")
	integration.set("mod_active", func() -> bool: return true)
	wardrobe.free()
	anatomy.act_started.emit(pony)
	director.free()
	coordinator.free()
	pony.free()
	_free_world(scene)


# --------------------------------------------------------------------------- debug

## The heatmap must not be a child of the anatomy mesh and must not require the mesh to be visible:
## a far mesh or act-only hiding would otherwise hide the field the debug view is inspecting.
func _check_overlay_parenting() -> void:
	var scene := _make_world()
	var integration: Node = scene["integration"]
	var pony := _pony("rarity")
	var parent_mesh := MeshInstance3D.new()
	parent_mesh.name = "AnatomyMesh"
	parent_mesh.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.5),
		Vector3(1.0, 2.0, 3.0))
	root.add_child(parent_mesh)
	integration.call("_show_overlay", pony, _hull(), parent_mesh)
	check(bool(integration.call("overlay_active")),
		"the heatmap shows without the anatomy being visible")
	var overlay := integration.get_node_or_null("UnfplapPantyhoseHull") as MeshInstance3D
	check(overlay != null and overlay.get_parent() == integration,
		"the heatmap is parented to the integration, not the anatomy mesh")
	if overlay != null:
		check(overlay.top_level, "the heatmap keeps its own global transform")
		check(overlay.global_transform.origin.is_equal_approx(parent_mesh.global_transform.origin),
			"the heatmap copies the anatomy mesh transform")
		var overlay_mesh := overlay.mesh as ArrayMesh
		check(overlay_mesh != null and overlay_mesh.surface_get_array_len(0) == 9,
			"the heatmap uses shared corner vertices")
	integration.call("_hide_overlay")
	check(not bool(integration.call("overlay_active")), "hiding the heatmap works")
	parent_mesh.free()
	pony.free()
	_free_world(scene)


func _check_debug() -> void:
	var scene := _make_world()
	var anatomy: FakeAnatomy = scene["anatomy"]
	var integration: Node = scene["integration"]
	var game: FakeGame = scene["game"]
	var pony := _pony("rarity")
	game.mares = [pony]
	anatomy.hull = _hull()
	var result := str(integration.call("rebuild_hull"))
	check(result.contains("rebuilt"), "the rebuild button reports its result")
	check(anatomy.rebuilds == 1, "the rebuild clears the shared hull cache once")
	var before := SETTINGS.pantyhose_hull_width.get_num()
	SETTINGS.pantyhose_hull_width.set_num(16.0)
	integration.call("apply_live_settings")
	check(anatomy.rebuilds == 1, "a width edit waits for the debounce")
	integration.call("_process", 0.4)
	check(anatomy.rebuilds == 2, "the debounce rebuilds once")
	SETTINGS.pantyhose_hull_width.set_num(before)
	integration.call("apply_live_settings")
	integration.call("_process", 0.4)
	var show_before := SETTINGS.pantyhose_hull_show.get_bool()
	SETTINGS.pantyhose_hull_show.set_bool(true)
	integration.call("apply_live_settings")
	integration.call("scan")
	check(not bool(integration.call("overlay_active")),
		"the hull overlay is a no-op in headless")
	SETTINGS.pantyhose_hull_show.set_bool(show_before)
	integration.call("apply_live_settings")
	pony.free()
	_free_world(scene)
