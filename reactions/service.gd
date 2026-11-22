extends RefCounted
## Thrust and climax presentation: the rump jiggle, its coat target, the smack, the rump blush
## and the heart bursts.
##
## Contract: `docs/reactions.md`.

const CONTEXT := preload("res://mods/unfplap/reactions/context.gd")
const FLANK_TOUCH := preload("res://world/characters/hybrid_mare/pony_flank_touch.gd")
const WORLD := preload("res://mods/unfplap/world/api.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const ANATOMY := preload("res://mods/unfplap/anatomy/api.gd")
const RUMP_CONE := preload("res://mods/unfplap/shared/rump_cone.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")

## The stock jiggle clamps its own impulse to 0.3..1.0; this scales the resolved amount.
const JIGGLE_RUMP_SCALE := 2.8

const RUMP_BLUSH_MIN_STRENGTH := 0.55
const RUMP_BLUSH_STEP := 0.0525
const RUMP_BLUSH_MAX := 0.375
const RUMP_BLUSH_DECAY := 0.006

## Scene handles. The runtime binds them; tests may inject a fake flank and anatomy.
var pony: Node3D = null
var flank: Node = null
var anatomy: ANATOMY = null
## The standing tail modifier, null outside a standing act.
var tail: SkeletonModifier3D = null

## Per-act configuration. `configure()` receives the runtime's act snapshot.
var pose_family := ""
var size_scale := 1.0
var jiggle_radius_m: float
var jiggle_center_height_m: float
var jiggle_center_back_m: float
var jiggle_intensity: float
var jiggle_smack_intensity: float
var climax_seconds := 5.0

## Live reaction state.
var rump_blush := 0.0
var _rump_decal: Decal
var _jiggle_logged := false
var _radius_materials: Array = []
var _heart_elapsed := 0.0
var _heart_index := 0
var _heart_times: Array[float] = []
var _heart_counts: Array[int] = []


## Bind the act's pony and the anatomy API; a test may inject its fake flank.
func bind_scene(pony_node: Node3D, anatomy_api: ANATOMY, flank_ctl: Node = null) -> void:
	pony = pony_node
	anatomy = anatomy_api
	if flank_ctl != null:
		flank = flank_ctl
	_follow_coat()


## Ask anatomy to register its current and future coat/outline materials with the flank.
func _follow_coat() -> void:
	if anatomy == null or not is_instance_valid(pony):
		return
	if not is_instance_valid(flank):
		flank = pony.get_node_or_null("FlankTouch")
	if is_instance_valid(flank):
		anatomy.follow_body_coat(pony, flank)


## The standing tail modifier changes with the pose, so the pose builder binds it.
func bind_tail(tail_ctl: SkeletonModifier3D) -> void:
	tail = tail_ctl


## Take the act's reaction tuning from the runtime's settings snapshot.
func configure(context: CONTEXT) -> void:
	pose_family = context.pose_family
	size_scale = context.size_scale
	climax_seconds = context.climax_seconds
	jiggle_radius_m = context.jiggle_radius
	jiggle_center_height_m = context.jiggle_center_height
	jiggle_center_back_m = context.jiggle_center_back
	jiggle_intensity = context.jiggle_intensity
	jiggle_smack_intensity = context.jiggle_smack_intensity


## Start a fresh act. Clears the per-act visual state; the configuration survives.
func begin_act() -> void:
	rump_blush = 0.0
	_jiggle_logged = false
	_heart_elapsed = 0.0
	_heart_index = 0
	_heart_times.clear()
	_heart_counts.clear()


## Teardown: free the decal, drop the tail and put the stock radius back.
func end_act() -> void:
	if is_instance_valid(_rump_decal):
		_rump_decal.queue_free()
	_rump_decal = null
	rump_blush = 0.0
	tail = null
	_heart_elapsed = 0.0
	_heart_index = 0
	_heart_times.clear()
	_heart_counts.clear()
	restore_radius()


## The runtime's patched coat no longer matches the game's shader check, so re-add the targets on
## every thrust; the setting is read live so a smack outside an act still reaches them.
func body_coat_target() -> void:
	if not SETTINGS.body_coat_deform.get_bool():
		return
	_follow_coat()


## The thrust's rump wobble. `FlankTouch` holds one jiggle at a time, so both flanks share the
## one center.
func thrust(weight: float) -> void:
	if not is_instance_valid(pony):
		return
	if not is_instance_valid(flank):
		flank = pony.get_node_or_null("FlankTouch")
	if not is_instance_valid(flank) or not flank.has_method("_start_jiggle"):
		return
	WORLD.flank(flank).wake_tick()
	var marks: Variant = flank.get("marks")
	if not marks is Array or (marks as Array).size() < 2:
		return
	var mark: Variant = (marks as Array)[0]
	if not mark is Decal:
		return
	var back: Vector3 = pony.global_basis.z.normalized()
	var normal := back
	if normal.length_squared() < 0.001:
		return
	var at: Vector3 = pony.global_position + Vector3.UP * RUMP_CONE.APPROX_HEIGHT \
		+ back * RUMP_CONE.APPROX_BACK
	var sk: Variant = pony.get("skeleton")
	if sk is Skeleton3D:
		var skeleton := sk as Skeleton3D
		var left := skeleton.find_bone("pony_femur_L")
		var right := skeleton.find_bone("pony_femur_R")
		if left >= 0 and right >= 0:
			var a := skeleton.global_transform * skeleton.get_bone_global_pose(left).origin
			var b := skeleton.global_transform * skeleton.get_bone_global_pose(right).origin
			at = (a + b) * 0.5 + Vector3.UP * jiggle_center_height_m \
				+ back * jiggle_center_back_m
	var across := Vector3.UP.cross(normal).normalized()
	if across.length_squared() < 0.5:
		across = Vector3.RIGHT
	var decal := mark as Decal
	decal.global_transform = Transform3D(Basis(across, normal, across.cross(normal)).orthonormalized(), at + normal * 0.015)
	decal.visible = false
	# The stock jiggle clamps its own impulse to 0.3..1. Pass a full stroke and scale the
	# resolved amount here, so a soft stroke can wobble almost not at all.
	var wobble := clampf(weight, 0.0, 1.0)
	WORLD.flank(flank).start_jiggle(0, 1.0)
	body_coat_target()
	# One shader center now covers both flanks, so scale the resolved amount up. Smaller ponies
	# get less shader travel from the same thrust impulse.
	var amount := WORLD.flank(flank).jiggle_amount()
	if not is_nan(amount):
		WORLD.flank(flank).set_jiggle_amount(amount * wobble * JIGGLE_RUMP_SCALE
			* size_scale * jiggle_intensity)
		# The stock jiggle already ran a frame at the full amount; refresh it so a soft thrust does
		# not pop.
		WORLD.flank(flank).process(0.0)
	apply_radius()
	if not _jiggle_logged:
		_jiggle_logged = true
		var targets: Variant = flank.get("_jiggle_targets")
		LOG.debug("jiggle rump at=%s root=%s normal=%s targets=%d index=%d mark=%s", [
			str(at), str(pony.global_position), str(normal),
			(targets as Array).size() if targets is Array else -1,
			int(flank.get("_jiggle_index")), str(decal.global_position)])


## The tail impulse that rides the same thrust wave. Standing only.
func tail_thrust(weight: float) -> void:
	if pose_family != "standing" or not is_instance_valid(tail):
		return
	tail.thrust(weight * size_scale * jiggle_intensity)


## A smack has already started the native cheek jiggle. Carry it into the same tail-base
## propagation as a thrust.
func smack(_strength: float) -> void:
	if not is_instance_valid(pony):
		return
	if is_instance_valid(flank):
		body_coat_target()
		var amount := WORLD.flank(flank).jiggle_amount()
		if not is_nan(amount):
			WORLD.flank(flank).set_jiggle_amount(amount * jiggle_smack_intensity)
	apply_radius()
	if pose_family == "standing" and is_instance_valid(tail):
		tail.thrust(size_scale * jiggle_smack_intensity)


## Set the shared rump wobble radius on every active jiggle target material.
func apply_radius() -> void:
	if not is_instance_valid(flank):
		return
	var targets: Variant = flank.get("_jiggle_targets")
	if not targets is Array:
		return
	var radius := jiggle_radius_m
	for target_v: Variant in targets:
		if not target_v is Array or (target_v as Array).is_empty():
			continue
		var mat_v: Variant = (target_v as Array)[0]
		if not mat_v is ShaderMaterial:
			continue
		var mat := mat_v as ShaderMaterial
		mat.set_shader_parameter("jiggle_radius", radius)
		if not _radius_materials.has(mat):
			_radius_materials.append(mat)


## Remove the radius override so stock/base-game jiggles use the shader default again.
func restore_radius() -> void:
	for mat_v: Variant in _radius_materials:
		if mat_v is ShaderMaterial and is_instance_valid(mat_v):
			(mat_v as ShaderMaterial).set_shader_parameter("jiggle_radius", null)
	_radius_materials.clear()


## The act has its own rump blush and smack mark, so the stock redness mark is cleared at act
## start; a smack outside the act keeps it.
func clear_stock_marks() -> void:
	if not is_instance_valid(pony):
		return
	flank = pony.get_node_or_null("FlankTouch")
	if not is_instance_valid(flank):
		return
	var marks: Variant = flank.get("marks")
	if not marks is Array:
		return
	var ages: Variant = flank.get("ages")
	for i: int in (marks as Array).size():
		var mark: Variant = (marks as Array)[i]
		if mark is Decal:
			(mark as Decal).visible = false
		if ages is Array and i < (ages as Array).size():
			ages[i] = 1000.0
	LOG.debug("stock flank marks cleared count=%d", [(marks as Array).size()])


## A strong thrust builds the standing rump blush. The decal is created on the first step.
func add_blush(impact: float) -> void:
	if pose_family != "standing":
		return
	if impact < RUMP_BLUSH_MIN_STRENGTH:
		return
	rump_blush = minf(RUMP_BLUSH_MAX, rump_blush + RUMP_BLUSH_STEP)
	_ensure_rump_decal()


## Decay and place the standing rump blush decal.
func blush_tick(delta: float) -> void:
	if pose_family != "standing":
		return
	if rump_blush > 0.0:
		rump_blush = maxf(0.0, rump_blush - RUMP_BLUSH_DECAY * delta)
	if not is_instance_valid(_rump_decal):
		return
	if rump_blush <= 0.001:
		_rump_decal.visible = false
		return
	var point := rump_point()
	if not is_instance_valid(pony):
		return
	var back: Vector3 = pony.global_basis.z.normalized()
	var across := Vector3.UP.cross(back).normalized()
	if not point.is_finite() or across.length_squared() < 0.5:
		return
	var basis := Basis(across, back, across.cross(back)).orthonormalized()
	_rump_decal.global_transform = Transform3D(basis, point + back * 0.015)
	_rump_decal.albedo_mix = rump_blush
	_rump_decal.visible = true


func _ensure_rump_decal() -> void:
	if is_instance_valid(_rump_decal):
		return
	if not is_instance_valid(pony):
		return
	if not is_instance_valid(flank):
		flank = pony.get_node_or_null("FlankTouch")
	var texture: Variant = FLANK_TOUCH.texture
	if not texture is Texture2D:
		return
	var decal := Decal.new()
	decal.name = "UnfplapRumpBlush"
	decal.texture_albedo = texture
	decal.modulate = Color("de5263")
	decal.size = Vector3(0.16, 0.10, 0.18)
	decal.upper_fade = 0.2
	decal.lower_fade = 0.25
	decal.normal_fade = 0.6
	decal.cull_mask = 1 << 19
	decal.albedo_mix = 0.0
	decal.visible = false
	pony.add_child(decal)
	_rump_decal = decal


## The rump center: the hind-femur midpoint plus the tuned height and backset, with the
## body-position fallback when the skeleton is unavailable.
func rump_point() -> Vector3:
	if not is_instance_valid(pony):
		return Vector3.INF
	var back: Vector3 = pony.global_basis.z.normalized()
	var point: Vector3 = RUMP_CONE.approx_point(pony)
	var sk: Variant = pony.get("skeleton")
	if sk is Skeleton3D:
		var skeleton := sk as Skeleton3D
		var left := skeleton.find_bone("pony_femur_L")
		var right := skeleton.find_bone("pony_femur_R")
		if left >= 0 and right >= 0:
			var a := skeleton.global_transform * skeleton.get_bone_global_pose(left).origin
			var b := skeleton.global_transform * skeleton.get_bone_global_pose(right).origin
			point = (a + b) * 0.5 + Vector3.UP * 0.08 + back * 0.10
	return point


## Three pulses: four bursts at the start, two after at least one second, one after at least
## another second. The dock burst is separate and fires from the runtime's climax transition.
func schedule_hearts() -> void:
	_heart_elapsed = 0.0
	_heart_index = 0
	_heart_times.clear()
	_heart_counts.clear()
	_heart_times.append(0.0)
	_heart_counts.append(4)
	var latest := maxf(1.0, climax_seconds - 0.4)
	var second := randf_range(1.0, minf(2.4, latest))
	var third := randf_range(second + 1.0, maxf(second + 1.0, latest))
	_heart_times.append(second)
	_heart_counts.append(2)
	_heart_times.append(third)
	_heart_counts.append(1)


func hearts_tick(delta: float) -> void:
	if _heart_times.is_empty():
		return
	_heart_elapsed += delta
	while _heart_index < _heart_times.size() and _heart_elapsed >= _heart_times[_heart_index]:
		var count := _heart_counts[_heart_index] if _heart_index < _heart_counts.size() else 1
		var at := _heart_times[_heart_index]
		_heart_index += 1
		for i: int in count:
			hearts_burst()
		LOG.debug("climax hearts pulse t=%.2f count=%d", [at, count])


## Same effect as a boop (five drifting hearts, her heart colours) without counting a boop or
## restarting the blush/squeak reaction.
func hearts_burst() -> void:
	WORLD.face(pony).celebrate()


## A boop-heart burst moved to `origin` while keeping its random spread and drift.
func hearts_burst_at(origin: Vector3) -> void:
	if not is_instance_valid(pony) or not origin.is_finite():
		return
	var boop := WORLD.pony(pony).boop()
	if boop == null:
		return
	var stored: Variant = boop.get("_hearts")
	if not stored is Array:
		return
	var hearts: Array = stored
	var before := hearts.size()
	if not WORLD.face(pony).celebrate():
		return
	if hearts.size() <= before:
		return
	var first: Dictionary = hearts[before]
	var first_origin: Vector3 = first.get("origin", origin)
	var shift: Vector3 = origin - first_origin
	for i: int in range(before, hearts.size()):
		var heart: Dictionary = hearts[i]
		var old: Vector3 = heart.get("origin", origin)
		var moved := old + shift
		heart["origin"] = moved
		var sprite: Variant = heart.get("sprite")
		if sprite is Node3D:
			(sprite as Node3D).global_position = moved
	LOG.debug("climax dock hearts=%d", [(hearts.size() - before)])


## Her dock is the tail base on the hair skeleton; fall back to the hips if it is unavailable.
func dock_point() -> Vector3:
	if not is_instance_valid(pony):
		return Vector3.INF
	if not pony.is_inside_tree():
		return pony.position
	var hair: Variant = pony.get("hair_skeleton")
	if hair is Skeleton3D:
		var tail_bone := (hair as Skeleton3D).find_bone("mTail1")
		if tail_bone >= 0:
			return (hair as Skeleton3D).global_transform * (hair as Skeleton3D).get_bone_global_pose(tail_bone).origin
	var body: Variant = pony.get("skeleton")
	if body is Skeleton3D:
		var hips := (body as Skeleton3D).find_bone("pony_hips")
		if hips >= 0:
			return (body as Skeleton3D).global_transform * (body as Skeleton3D).get_bone_global_pose(hips).origin \
				+ pony.global_basis.z.normalized() * 0.18 + Vector3.UP * 0.05
	return pony.global_position + Vector3.UP * 0.7


