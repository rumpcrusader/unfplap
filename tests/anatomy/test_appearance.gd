extends SceneTree
## The anatomy material path: the shader loads, the mesh gets an override material, the coat
## uniforms are accepted, and the material can be rebuilt live.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/anatomy/test_appearance.gd

const APPEARANCE := preload("res://mods/unfplap/anatomy/appearance.gd")
const SHAPES := preload("res://mods/unfplap/anatomy/shapes.gd")

var failures := 0
var checks := 0


class FakeIdentity extends Resource:
	var id := "test_mare"
	var display_name := "Test Mare"
	var filly := false
	var stallion := false
	var coat_fill := Color(0.55, 0.35, 0.75)
	var coat_shade := Color(0.35, 0.2, 0.5)


class FakePony extends Node3D:
	var identity: Resource


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func run() -> void:
	var pony := FakePony.new()
	pony.identity = FakeIdentity.new()
	get_root().add_child(pony)

	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	pony.add_child(mesh)

	var shapes := SHAPES.new()
	shapes.setup(pony, pony)
	shapes.set_mesh(mesh, false)

	var appearance := APPEARANCE.new()
	appearance.setup(pony, shapes)
	appearance.set_mesh(mesh, null)
	appearance.apply_material(false)

	var material := mesh.get_surface_override_material(0) as ShaderMaterial
	check(material != null, "the anatomy mesh gets an override material")
	if material != null:
		check(material.shader != null, "the anatomy shader loads")
		var skin: Variant = material.get_shader_parameter("skin_color")
		check(skin is Color, "the skin color is a color")
		check(material.get_shader_parameter("lip_radius") is float,
			"the lip radius is published to the shader")
		check(material.get_shader_parameter("hole_target") is float,
			"the hole target is published to the shader")

	# Rebuilding the material must keep working after the shapes report a V2 state, without the
	# old variable/method API mismatch.
	shapes.set_mesh(mesh, true)
	check(shapes.v2_anal(), "the V2 shape state reports the anal mesh")
	appearance.apply_material(false)
	check(mesh.get_surface_override_material(0) is ShaderMaterial,
		"the material rebuilds on the V2 state")

	pony.queue_free()
	print("ANATOMY_APPEARANCE_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
