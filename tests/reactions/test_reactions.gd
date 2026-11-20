extends "res://mods/unfplap/tests/support/suite.gd"
## The reaction facade: jiggle tuning, body-coat targets, the act smack, the rump blush and the
## climax hearts.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/reactions/test_reactions.gd

const REACTIONS := preload("res://mods/unfplap/reactions/service.gd")
const GAME := preload("res://mods/unfplap/world/game.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const RUMP_CONE := preload("res://mods/unfplap/shared/rump_cone.gd")
const FLANK_TOUCH := preload("res://world/characters/hybrid_mare/pony_flank_touch.gd")



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


class FakeTail extends SkeletonModifier3D:
	var last_strength := 0.0

	func thrust(strength: float) -> void:
		last_strength = strength


class FakeAnatomy extends Node:
	var mesh: MeshInstance3D
	var material: ShaderMaterial
	var outline: ShaderMaterial
	var target_pairs: Array = []
	var refreshes := 0

	func is_attached() -> bool:
		return true

	func body_coat_mesh() -> MeshInstance3D:
		return mesh

	func body_coat_material() -> ShaderMaterial:
		return material

	func body_outline_material() -> ShaderMaterial:
		return outline

	func body_coat_targets() -> Array:
		return target_pairs

	func body_coat_refresh() -> void:
		refreshes += 1


class FakeBoop extends Node:
	var _hearts: Array = []

	func celebrate() -> void:
		_hearts.append({"origin": Vector3(0.0, 1.0, 0.0), "sprite": null})


class FakePony extends Node3D:
	var boop_node: Variant = null
	var skeleton: Variant = null
	var hair_skeleton: Variant = null

## The act snapshot the facade takes: the block plus the family, size and climax length.
func tune(block := {}, family := "", size := 1.0, climax := 5.0) -> RefCounted:
	var context := REACTIONS.CONTEXT.new()
	context.fill(jiggle_block(block), family, size, climax)
	return context


## The complete `jiggle.*` block the runtime snapshot passes; overrides replace keys.
func jiggle_block(overrides := {}) -> Dictionary:
	var block := {
		"radius": float(SETTINGS.radius.default),
		"center_height_m": float(SETTINGS.center_height_m.default),
		"center_back_m": float(SETTINGS.center_back_m.default),
		"intensity": float(SETTINGS.intensity.default),
		"smack_intensity": float(SETTINGS.smack_intensity.default),
	}
	block.merge(overrides, true)
	return block


func run() -> void:
	_check_defaults()
	_check_body_coat_target()
	_check_radius()
	_check_thrust()
	_check_smack()
	_check_blush()
	_check_hearts()
	_check_accessors()
	_check_rump_point()

	if failures == 0:
		print("REACTIONS_PASS")
	finish()


func _check_defaults() -> void:
	var reactions := REACTIONS.new()
	check(near(reactions.climax_seconds, 5.0), "climax length starts at the shipped default")
	reactions.configure(tune({
		"radius": 0.31,
		"center_height_m": 0.12,
		"center_back_m": 0.2,
		"intensity": 0.4,
		"smack_intensity": 0.6,
	}, "standing", 0.66, 4.0))
	check(reactions.pose_family == "standing", "configure takes the pose family")
	check(near(reactions.size_scale, 0.66), "configure takes the size scale")
	check(near(reactions.climax_seconds, 4.0), "configure takes the climax length")
	check(near(reactions.jiggle_radius_m, 0.31), "configure takes the radius")
	check(near(reactions.jiggle_center_height_m, 0.12), "configure takes the center height")
	check(near(reactions.jiggle_center_back_m, 0.2), "configure takes the center backset")
	check(near(reactions.jiggle_intensity, 0.4), "configure takes the thrust intensity")
	check(near(reactions.jiggle_smack_intensity, 0.6), "configure takes the smack intensity")


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
	check(anatomy.refreshes == 1, "an empty target list refreshes the anatomy coat")
	reactions.body_coat_target()
	check(flank._jiggle_targets.size() == 2, "the body target is not duplicated")
	var near_mesh := MeshInstance3D.new()
	var near_material := ShaderMaterial.new()
	root.add_child(near_mesh)
	anatomy.target_pairs = [[anatomy.material, body], [anatomy.outline, body],
		[near_material, near_mesh]]
	flank._jiggle_targets = []
	reactions.body_coat_target()
	check(flank._jiggle_targets.size() == 3, "the near coat target joins the jiggle targets")
	reactions.body_coat_target()
	check(flank._jiggle_targets.size() == 3, "the near coat target is not duplicated")
	SETTINGS.body_coat_deform.set_bool(false)
	reactions.body_coat_target()
	check(flank._jiggle_targets.size() == 3, "the coat target is skipped when the flag is off")
	SETTINGS.body_coat_deform.set_bool(was_on)
	root.remove_child(near_mesh)
	near_mesh.free()
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
	reactions.configure(tune({"radius": 0.30}))
	reactions.apply_radius()
	check(near(float(material.get_shader_parameter("jiggle_radius")), 0.30),
		"the jiggle radius applies to the targets")
	reactions.configure(tune({"radius": -0.05}))
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
	reactions.configure(tune({"intensity": 0.2, "radius": 0.26}, "standing", 0.66))
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
	reactions.configure(tune({"smack_intensity": 0.5}, "standing", 1.0))
	reactions.smack(0.8)
	check(near(flank._jiggle_amount, 0.04), "the act smack scales the resolved jiggle")
	check(near(tail.last_strength, 0.5), "the standing smack carries the tail jiggle")
	reactions.configure(tune({"smack_intensity": 0.5}, "bed", 0.66))
	tail.last_strength = 0.0
	reactions.smack(0.8)
	check(near(tail.last_strength, 0.0), "the missionary smack does not move the tail")
	reactions.configure(tune({"intensity": 0.2}, "standing", 0.66))
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
	reactions.configure(tune({}, "bed"))
	reactions.add_blush(1.0)
	check(near(reactions.rump_blush, 0.0), "the missionary act has no rump blush")
	reactions.configure(tune({}, "standing"))
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
	reactions.configure(tune({}, "", 1.0, 5.0))
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


## The skeleton-less rump fallback is the shared anchor the standing cone uses.
func _check_rump_point() -> void:
	var pony := FakePony.new()
	root.add_child(pony)
	pony.global_position = Vector3(1.0, 0.0, 2.0)
	pony.rotation_degrees = Vector3(0.0, 35.0, 0.0)
	var reactions := REACTIONS.new()
	reactions.bind_scene(pony, null)
	check(reactions.rump_point().is_equal_approx(RUMP_CONE.approx_point(pony)),
		"the skeleton-less rump point is the shared approximate anchor")
	root.remove_child(pony)
	pony.free()


## The base-game accessors answer the absent flank and boop without a call or a write.
func _check_accessors() -> void:
	var absent := Node.new()
	check(not GAME.celebrate(null), "an absent boop has no celebrate")
	check(not GAME.celebrate(absent), "a node without celebrate has no celebrate")
	check(not GAME.flank_start_jiggle(null, 0, 1.0), "an absent flank has no start jiggle")
	check(not GAME.flank_start_jiggle(absent, 0, 1.0), "a flank without the op has no start jiggle")
	check(is_nan(GAME.flank_jiggle_amount(null)), "an absent flank has no jiggle amount")
	check(is_nan(GAME.flank_jiggle_amount(absent)), "a flank without the member has no jiggle amount")
	GAME.flank_wake_tick(null)
	GAME.flank_wake_tick(absent)
	GAME.flank_process(null, 0.0)
	GAME.flank_process(absent, 0.0)
	GAME.set_flank_jiggle_amount(null, 1.0)
	GAME.set_flank_jiggle_amount(absent, 1.0)
	absent.free()

	var flank := FakeFlank.new()
	flank._jiggle_amount = 0.25
	check(near(GAME.flank_jiggle_amount(flank), 0.25), "the flank's jiggle amount is read")
	GAME.set_flank_jiggle_amount(flank, 0.5)
	check(near(flank._jiggle_amount, 0.5), "the flank's jiggle amount is written")
	check(GAME.flank_start_jiggle(flank, 0, 1.0), "a flank with the op starts its jiggle")
	check(flank.jiggle_calls == 1, "the start jiggle accessor calls the op")
	GAME.flank_wake_tick(flank)
	GAME.flank_process(flank, 0.0)
	check(flank.processed == 1, "the process accessor calls the op")
	flank.free()

	var boop := FakeBoop.new()
	check(GAME.celebrate(boop), "a boop with celebrate answers")
	check(boop._hearts.size() == 1, "the celebrate accessor bursts a heart")
	boop.free()
