extends SceneTree
## The reaction facade: jiggle tuning, body-coat targets, the act smack, the rump blush and the
## climax hearts.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/reactions/test_reactions.gd

const REACTIONS := preload("res://mods/unfplap/reactions/service.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")
const FLANK_TOUCH := preload("res://world/characters/hybrid_mare/pony_flank_touch.gd")

var failures := 0
var checks := 0


class FakeFlank extends Node:
	var marks: Array = []
	var ages: Array = []
	var _jiggle_targets: Array = []
	var _jiggle_amount := 0.0
	var _jiggle_index := 0
	var jiggle_calls := 0
	var processed := 0

	func _start_jiggle(index: int, _amount: float) -> void:
		jiggle_calls += 1
		_jiggle_index = index
		_jiggle_amount = 1.0

	func wake_tick() -> void:
		pass

	func _process(_delta: float) -> void:
		processed += 1


class FakeTail extends Node:
	var last_strength := 0.0

	func thrust(strength: float) -> void:
		last_strength = strength


class FakeAnatomy extends Node:
	var mesh: MeshInstance3D
	var material: ShaderMaterial
	var outline: ShaderMaterial

	func is_attached() -> bool:
		return true

	func body_coat_mesh() -> MeshInstance3D:
		return mesh

	func body_coat_material() -> ShaderMaterial:
		return material

	func body_outline_material() -> ShaderMaterial:
		return outline


class FakeBoop extends Node:
	var _hearts: Array = []

	func celebrate() -> void:
		_hearts.append({"origin": Vector3(0.0, 1.0, 0.0), "sprite": null})


class FakePony extends Node3D:
	var boop_node: Variant = null
	var skeleton: Variant = null
	var hair_skeleton: Variant = null


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
	_check_defaults()
	_check_body_coat_target()
	_check_radius()
	_check_thrust()
	_check_smack()
	_check_blush()
	_check_hearts()

	print("REACTIONS_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("REACTIONS_PASS")
	quit(0 if failures == 0 else 1)


func _check_defaults() -> void:
	var reactions := REACTIONS.new()
	check(near(reactions.jiggle_radius_m, 0.26), "radius starts at the shipped default")
	check(near(reactions.jiggle_intensity, 0.2), "intensity starts at the shipped default")
	check(near(reactions.jiggle_smack_intensity, 0.45), "smack intensity starts at the shipped default")
	check(near(reactions.climax_seconds, 5.0), "climax length starts at the shipped default")
	reactions.configure({
		"pose_id": CATALOG.STANDING,
		"size_scale": 0.66,
		"climax_seconds": 4.0,
		"jiggle": {
			"radius": 0.31,
			"center_height_m": 0.12,
			"center_back_m": 0.2,
			"intensity": 0.4,
			"smack_intensity": 0.6,
		},
	})
	check(reactions.pose_id == CATALOG.STANDING, "configure takes the pose")
	check(near(reactions.size_scale, 0.66), "configure takes the size scale")
	check(near(reactions.climax_seconds, 4.0), "configure takes the climax length")
	check(near(reactions.jiggle_radius_m, 0.31), "configure takes the radius")
	check(near(reactions.jiggle_center_height_m, 0.12), "configure takes the center height")
	check(near(reactions.jiggle_center_back_m, 0.2), "configure takes the center backset")
	check(near(reactions.jiggle_intensity, 0.4), "configure takes the thrust intensity")
	check(near(reactions.jiggle_smack_intensity, 0.6), "configure takes the smack intensity")
	reactions.configure({})
	check(near(reactions.jiggle_radius_m, 0.26), "an empty context falls back to the shipped defaults")


func _check_body_coat_target() -> void:
	var flank := FakeFlank.new()
	var body := MeshInstance3D.new()
	var anatomy := FakeAnatomy.new()
	anatomy.mesh = body
	anatomy.material = ShaderMaterial.new()
	anatomy.outline = ShaderMaterial.new()
	flank._jiggle_targets = []
	var was_on := SETTINGS.body_coat_deform.get_bool()
	SETTINGS.body_coat_deform.set_bool(true)
	var reactions := REACTIONS.new()
	reactions.bind_scene(null, anatomy, flank)
	root.add_child(flank)
	root.add_child(anatomy)
	root.add_child(body)
	reactions.body_coat_target()
	check(flank._jiggle_targets.size() == 2, "body and outline join the jiggle targets")
	reactions.body_coat_target()
	check(flank._jiggle_targets.size() == 2, "the body target is not duplicated")
	SETTINGS.body_coat_deform.set_bool(false)
	reactions.body_coat_target()
	check(flank._jiggle_targets.size() == 2, "the coat target is skipped when the flag is off")
	SETTINGS.body_coat_deform.set_bool(was_on)
	root.remove_child(anatomy)
	anatomy.free()
	root.remove_child(body)
	body.free()
	root.remove_child(flank)
	flank.free()


func _check_radius() -> void:
	var flank := FakeFlank.new()
	root.add_child(flank)
	var material := ShaderMaterial.new()
	var mesh := Node3D.new()
	root.add_child(mesh)
	flank._jiggle_targets = [[material, mesh]]
	var reactions := REACTIONS.new()
	reactions.bind_scene(null, null, flank)
	reactions.configure({"jiggle": {"radius": 0.30}})
	reactions.apply_radius()
	check(near(float(material.get_shader_parameter("jiggle_radius")), 0.30),
		"the jiggle radius applies to the targets")
	reactions.configure({"jiggle": {"radius": -0.05}})
	reactions.apply_radius()
	check(near(float(material.get_shader_parameter("jiggle_radius")), -0.05),
		"a debug jiggle radius is applied unclamped")
	reactions.restore_radius()
	check(material.get_shader_parameter("jiggle_radius") == null,
		"restoring clears the radius override")
	root.remove_child(mesh)
	mesh.free()
	root.remove_child(flank)
	flank.free()


func _check_thrust() -> void:
	var flank := FakeFlank.new()
	var first_mark := Decal.new()
	var second_mark := Decal.new()
	flank.marks = [first_mark, second_mark]
	flank._jiggle_targets = []
	var pony := FakePony.new()
	root.add_child(pony)
	root.add_child(flank)
	flank.add_child(first_mark)
	flank.add_child(second_mark)
	var reactions := REACTIONS.new()
	reactions.bind_scene(pony, null, flank)
	reactions.configure({"pose_id": CATALOG.STANDING, "size_scale": 0.66,
		"jiggle": {"intensity": 0.2, "radius": 0.26}})
	reactions.thrust(0.8)
	check(flank.jiggle_calls == 1, "a thrust starts one jiggle")
	check(near(flank._jiggle_amount, 0.8 * REACTIONS.JIGGLE_RUMP_SCALE * 0.66 * 0.2),
		"the resolved jiggle amount scales with the stroke, size and intensity")
	check(flank.processed == 1, "the first jiggle frame is refreshed after scaling")
	check(not first_mark.visible, "the rump mark stays hidden as the jiggle center")
	reactions.thrust(0.0)
	check(near(flank._jiggle_amount, 0.0), "a zero-weight stroke settles to no wobble")
	root.remove_child(flank)
	flank.free()
	root.remove_child(pony)
	pony.free()


func _check_smack() -> void:
	var flank := FakeFlank.new()
	flank._jiggle_targets = []
	flank._jiggle_amount = 0.08
	var tail := FakeTail.new()
	var pony := FakePony.new()
	root.add_child(pony)
	root.add_child(tail)
	var reactions := REACTIONS.new()
	reactions.bind_scene(pony, null, flank)
	reactions.bind_tail(tail)
	reactions.configure({"pose_id": CATALOG.STANDING, "size_scale": 1.0,
		"jiggle": {"smack_intensity": 0.5}})
	reactions.smack(0.8)
	check(near(flank._jiggle_amount, 0.04), "the act smack scales the resolved jiggle")
	check(near(tail.last_strength, 0.5), "the standing smack carries the tail jiggle")
	reactions.configure({"pose_id": CATALOG.MISSIONARY, "size_scale": 0.66,
		"jiggle": {"smack_intensity": 0.5}})
	tail.last_strength = 0.0
	reactions.smack(0.8)
	check(near(tail.last_strength, 0.0), "the missionary smack does not move the tail")
	reactions.configure({"pose_id": CATALOG.STANDING, "size_scale": 0.66,
		"jiggle": {"intensity": 0.2}})
	reactions.tail_thrust(0.4)
	check(near(tail.last_strength, 0.4 * 0.66 * 0.2),
		"the thrust tail impulse scales with the stroke and the size")
	root.remove_child(tail)
	tail.free()
	root.remove_child(pony)
	pony.free()


func _check_blush() -> void:
	var was_texture: Variant = FLANK_TOUCH.texture
	if FLANK_TOUCH.texture == null:
		var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
		FLANK_TOUCH.texture = ImageTexture.create_from_image(image)
	var pony := FakePony.new()
	root.add_child(pony)
	var reactions := REACTIONS.new()
	reactions.bind_scene(pony, null)
	reactions.configure({"pose_id": CATALOG.MISSIONARY})
	reactions.add_blush(1.0)
	check(near(reactions.rump_blush, 0.0), "the missionary act has no rump blush")
	reactions.configure({"pose_id": CATALOG.STANDING})
	reactions.add_blush(0.4)
	check(near(reactions.rump_blush, 0.0), "a soft thrust does not start the blush")
	reactions.add_blush(0.9)
	check(near(reactions.rump_blush, REACTIONS.RUMP_BLUSH_STEP), "a strong thrust adds one step")
	check(pony.get_node_or_null("UnfplapRumpBlush") != null, "the first step creates the decal")
	for _i: int in 12:
		reactions.add_blush(1.0)
	check(near(reactions.rump_blush, REACTIONS.RUMP_BLUSH_MAX), "the blush is capped")
	reactions.blush_tick(1.0)
	check(near(reactions.rump_blush, REACTIONS.RUMP_BLUSH_MAX - REACTIONS.RUMP_BLUSH_DECAY),
		"the blush decays over time")
	reactions.blush_tick(200.0)
	check(near(reactions.rump_blush, 0.0), "the blush decays to zero")
	reactions.end_act()
	var decal: Variant = pony.get_node_or_null("UnfplapRumpBlush")
	check(decal == null or (decal as Node).is_queued_for_deletion(),
		"act end frees the blush decal")
	FLANK_TOUCH.texture = was_texture
	root.remove_child(pony)
	pony.free()


func _check_hearts() -> void:
	var boop := FakeBoop.new()
	var pony := FakePony.new()
	pony.boop_node = boop
	var hair := Skeleton3D.new()
	hair.add_bone("mTail1")
	pony.hair_skeleton = hair
	root.add_child(pony)
	root.add_child(boop)
	root.add_child(hair)
	var reactions := REACTIONS.new()
	reactions.bind_scene(pony, null)
	reactions.configure({"climax_seconds": 5.0})
	check(reactions.dock_point().is_equal_approx(Vector3.ZERO), "the dock follows the tail base")
	hair.position = Vector3(1.0, 2.0, 3.0)
	check(reactions.dock_point().is_equal_approx(Vector3(1.0, 2.0, 3.0)),
		"the dock follows a moved hair skeleton")
	reactions.schedule_hearts()
	reactions.hearts_tick(0.01)
	check(boop._hearts.size() == 4, "the first climax pulse bursts four hearts")
	reactions.hearts_tick(10.0)
	check(boop._hearts.size() == 7, "the later pulses add two hearts and one")
	reactions.hearts_tick(1.0)
	check(boop._hearts.size() == 7, "the finished schedule does not burst again")
	reactions.hearts_burst_at(Vector3(2.0, 0.0, 0.0))
	check(boop._hearts.size() == 8, "the dock burst adds one celebrate")
	var heart: Dictionary = boop._hearts[7]
	check((heart["origin"] as Vector3).is_equal_approx(Vector3(2.0, 0.0, 0.0)),
		"the dock burst moves the new hearts to the dock")
	reactions.end_act()
	check(reactions.tail == null, "act end drops the tail handle")
	root.remove_child(hair)
	hair.free()
	root.remove_child(boop)
	boop.free()
	root.remove_child(pony)
	pony.free()
