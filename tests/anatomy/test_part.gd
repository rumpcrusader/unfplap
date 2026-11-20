extends "res://mods/unfplap/tests/support/suite.gd"
## The player part and the act's part seam: prepare/encounter, the tip and root, the bed holder,
## `reset_state`, the throb/girth/length shaping, the controller's part handle, the face contact's
## parked part and the act wink scheduler.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/anatomy/test_part.gd

const ANATOMY := preload("res://mods/unfplap/anatomy/controller.gd")
const ANATOMY_ACT := preload("res://mods/unfplap/anatomy/act.gd")
const ANATOMY_SERVICE := preload("res://mods/unfplap/anatomy/service.gd")
const FACTS := preload("res://mods/unfplap/anatomy/facts.gd")
const PLAYER_PART := preload("res://mods/unfplap/anatomy/player.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const VIEW := preload("res://mods/unfplap/shared/pose_view.gd")


class FakeIdentity extends "res://mods/unfplap/tests/support/fakes/fake_identity.gd":
	pass

class FakePony extends Node3D:
	var identity: Resource
	var rig: Node
	var skeleton: Skeleton3D
	var hair_skeleton: Skeleton3D
	var hair_link: Node
	var head_width := 1.0
	var head_width_factor := 1.0
	var _far_mesh_shown := false


class FakeAnatomy extends "res://mods/unfplap/anatomy/controller.gd":
	var calls: Array[String] = []

	func _clear_part() -> void:
		calls.append("clear")


## The face-mode anatomy: records the shape drive and returns a live winking mesh. The opening is
## fixed, so the normal opening path's aim and track calls are observable.
class FakeFaceAnatomy extends "res://mods/unfplap/anatomy/controller.gd":
	var calls: Array = []
	var mesh: MeshInstance3D
	var opening := Vector3(0.1, 0.2, 0.3)
	var part_node: PLAYER_PART = null
	var tracks: Array = []
	var form_fit := ""

	func part() -> PLAYER_PART:
		return part_node

	func form_fit_id() -> String:
		return form_fit

	func player_track(target: Vector3, rear: Vector3, up: Vector3, bed: bool,
			penetration_m: float, delta: float, mare_anchor: Node3D, attached := true) -> void:
		tracks.append([target, rear, up, bed, penetration_m, delta, mare_anchor, attached])

	func animate(_closed: float, _seconds: float) -> void:
		calls.append(["animate"])

	func winking_mesh() -> MeshInstance3D:
		return mesh

	func set_fill(value: float) -> void:
		calls.append(["fill", value])

	func set_grip(value: float) -> void:
		calls.append(["grip", value])

	func set_anal_grip(value: float) -> void:
		calls.append(["anal_grip", value])

	func set_shaft(_pivot: Vector3, _axis: Vector3, _length: float,
			_radii: PackedFloat32Array) -> void:
		calls.append(["shaft"])

	func clear_shaft() -> void:
		calls.append(["clear_shaft"])

	func drive(value: float) -> void:
		calls.append(["drive", value])

	func hole_point(_mix := 0.0) -> Vector3:
		return opening

	func hole_rear(_mix := 0.0) -> Vector3:
		return Vector3(0.0, 0.0, 1.0)


## The player part in the face-mode test: the encounter calls are the park/restore proof, and the
## aim/inset setters count any write the parked path must never make.
class FakeFacePart extends "res://mods/unfplap/anatomy/player.gd":
	var encounters: Array[bool] = []
	var showing_state := false
	var aim_normal_writes := 0
	var aim_opening_writes := 0
	var inset_writes := 0
	var tracks: Array = []

	func set_aim(normal: Vector3, opening: Vector3, pitch := 0.0) -> void:
		aim_normal = normal
		aim_opening = opening
		aim_pitch_deg = pitch
		aim_normal_writes += 1
		aim_opening_writes += 1

	func set_bed_inset(metres: float) -> void:
		bed_inset_m = metres
		inset_writes += 1

	func track(target: Vector3, rear: Vector3, up: Vector3, bed: bool,
			penetration_m: float, delta: float, mare_anchor: Node3D, attached := true) -> void:
		tracks.append([target, rear, up, bed, penetration_m, delta, mare_anchor, attached])

	func encounter(on: bool) -> void:
		encounters.append(on)
		showing_state = on

	func showing() -> bool:
		return showing_state

	func girth_at(_point: Vector3) -> float:
		return 0.01

	func root_now() -> Vector3:
		return Vector3.INF

	func tip_world() -> Vector3:
		return Vector3.INF

	func tip_center() -> Vector3:
		return Vector3.INF


func _pony(id: String, filly := false, stallion := false) -> FakePony:
	var pony := FakePony.new()
	var identity := FakeIdentity.new()
	identity.id = id
	identity.filly = filly
	identity.stallion = stallion
	pony.identity = identity
	pony.set_meta("relationship_id", id)
	return pony


## The last call recorded for a shape/aim name, or an empty array.
func _last_call(calls: Array, name: String) -> Array:
	for i: int in range(calls.size() - 1, -1, -1):
		var row: Variant = calls[i]
		if row is Array and not (row as Array).is_empty() and str((row as Array)[0]) == name:
			return row as Array
	return []


## The face contact parks the part and the vulva: no player track, no aim/inset write, neutral
## fill/grip/anal and a neutral drive. The first opening tick restores the part once and resumes
## the normal shape and aim path; the hole toggle refuses while the face owns the contact.
func _check_face_contact() -> void:
	var anatomy := FakeFaceAnatomy.new()
	anatomy.set_process(false)
	root.add_child(anatomy)
	var host := Node3D.new()
	root.add_child(host)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	host.add_child(mesh)
	anatomy.mesh = mesh
	var pony := _pony("twilight_sparkle")
	root.add_child(pony)
	var sk := Skeleton3D.new()
	sk.add_bone("pony_hips")
	pony.add_child(sk)
	pony.skeleton = sk
	var part := FakeFacePart.new()
	root.add_child(part)
	anatomy.part_node = part
	var act: Node = ANATOMY_ACT.new()
	root.add_child(act)
	act.setup(pony, anatomy)
	var view: RefCounted = VIEW.new()
	view.family = "bed"
	view.frame = "bed"
	view.contact_kind = "face"
	view.contact_target = Vector3(0.4, 0.5, 0.6)
	var facts: RefCounted = FACTS.new()
	facts.state = 2
	facts.pose_view = view
	facts.depth = 0.2
	facts.size_scale = 1.0
	facts.penetration_m = 0.1
	facts.penetration_reach = 0.2
	facts.bed_frame = Transform3D.IDENTITY

	act.tick(0.016, facts)
	check(anatomy.tracks.is_empty(), "the face contact never tracks the part")
	check(part.encounters == [false], "the first face tick parts the part once")
	check(part.aim_normal_writes == 0 and part.aim_opening_writes == 0,
		"the face contact writes no aim")
	check(part.inset_writes == 0 and is_zero_approx(part.bed_inset_m),
		"the face contact writes no bed inset")
	var fill := _last_call(anatomy.calls, "fill")
	var grip := _last_call(anatomy.calls, "grip")
	var drive := _last_call(anatomy.calls, "drive")
	check(not fill.is_empty() and is_zero_approx(float(fill[1])),
		"the face contact zeroes the fill")
	check(not grip.is_empty() and is_zero_approx(float(grip[1])),
		"the face contact zeroes the grip")
	check(not _last_call(anatomy.calls, "clear_shaft").is_empty(),
		"the face contact clears the shaft")
	check(not drive.is_empty()
		and is_equal_approx(float(drive[1]), ANATOMY_ACT.WINKING_REST_OPEN),
		"the face contact holds the neutral closed shape")
	check(act.contact_point().is_equal_approx(view.contact_target),
		"the face contact point is the view's target")
	check(act.contact_normal().is_zero_approx(),
		"the face contact carries no normal")

	act.tick(0.016, facts)
	check(part.encounters == [false], "a second face tick does not part the part again")
	check(anatomy.tracks.is_empty(), "the face contact still never tracks the part")
	check(is_same(act.facts(), facts), "the act keeps the context it was ticked with")
	var holes_on := SETTINGS.anatomy_holes.get_bool()
	SETTINGS.anatomy_holes.set_bool(true)
	act.call("toggle_hole", 2)
	check(not act.anal_turned(), "the hole toggle refuses in the face contact")
	SETTINGS.anatomy_holes.set_bool(holes_on)

	view.contact_kind = "opening"
	view.contact_target = Vector3.INF
	act.tick(0.016, facts)
	check(part.encounters == [false, true], "the first opening tick restores the part once")
	check(not act.face_parted(), "the face flag clears on the opening contact")
	check(anatomy.tracks.size() == 1, "the opening contact resumes the player track")
	check(part.aim_opening_writes >= 1 and part.aim_normal_writes >= 1,
		"the opening contact resumes the aim writes")
	check(part.inset_writes >= 1, "the bed opening contact restores the bed inset")
	fill = _last_call(anatomy.calls, "fill")
	check(not fill.is_empty() and float(fill[1]) > 0.0,
		"the opening contact resumes the fill drive")

	act.call("teardown")
	act.free()
	root.remove_child(part)
	part.free()
	root.remove_child(pony)
	pony.free()
	root.remove_child(anatomy)
	anatomy.free()
	root.remove_child(host)
	host.free()


## The anatomy mesh's own +Z is the outward normal. It must not be flipped by the hips sign: a
## body fit or a shape can put the opening in front of the hip bone as the measurement sees it.
func _check_normal_source() -> void:
	var anatomy := FakeFaceAnatomy.new()
	anatomy.opening = Vector3(0.0, 0.5, -0.3)
	anatomy.set_process(false)
	root.add_child(anatomy)
	var pony := _pony("twilight_sparkle")
	root.add_child(pony)
	var sk := Skeleton3D.new()
	sk.add_bone("pony_hips")
	pony.add_child(sk)
	pony.skeleton = sk
	var act: Node = ANATOMY_ACT.new()
	root.add_child(act)
	act.setup(pony, anatomy)
	var normal: Variant = act.call("_compute_normal", null)
	check(normal is Vector3 and (normal as Vector3).is_equal_approx(Vector3(0.0, 0.0, 1.0)),
		"the anatomy rear stays outward even with the opening in front of the hips")
	act.call("teardown")
	act.free()
	root.remove_child(pony)
	pony.free()
	root.remove_child(anatomy)
	anatomy.free()


## A body swap clears the pelvis handshake without touching the act's mesh or throb state.
func _check_pelvis_reset() -> void:
	var part: Node = PLAYER_PART.new()
	part.set("hip_offset_applied", Vector3(0.1, 0.0, 0.2))
	part.set("aim_normal", Vector3.BACK)
	part.set("aim_opening", Vector3.ONE)
	part.set("aim_pitch_deg", 3.0)
	part.set("_p_smooth", 0.12)
	part.set("_p_started", true)
	part.call("reset_pelvis")
	check((part.get("hip_offset_applied") as Vector3).is_zero_approx(),
		"the pelvis reset clears the applied offset")
	check((part.call("hip_offset_wanted") as Vector3).is_zero_approx(),
		"the pelvis reset clears the wanted offset")
	check((part.get("aim_normal") as Vector3).is_zero_approx()
		and (part.get("aim_opening") as Vector3).is_zero_approx(),
		"the pelvis reset clears the aim")
	check(not bool(part.get("_p_started")), "the pelvis reset reseeds the next penetration")
	part.free()


func run() -> void:
	_check_face_contact()
	_check_normal_source()
	_check_pelvis_reset()

	# Climax clears the shape once and arms the wink pulses; the tick keeps driving the hug so
	# the lips stay on the shaft through the climax instead of closing on nothing.
	var anatomy_act: Node = ANATOMY_ACT.new()
	var fake_anatomy := FakeAnatomy.new()
	anatomy_act.anatomy = fake_anatomy
	anatomy_act.on_climax()
	check(fake_anatomy.calls.size() == 1 and fake_anatomy.calls[0] == "clear",
		"climax clears the shape once")
	check(absf(anatomy_act.wink_left() - ANATOMY_ACT.CLIMAX_WINK_S) < 0.001,
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

	# The controller owns the player-part handle and forwards the act's track, so the act never
	# needs the facade.
	var part_owner := ANATOMY.new()
	var tracked_part := FakeFacePart.new()
	part_owner.set_part(tracked_part)
	check(part_owner.part() == tracked_part, "the controller exposes the pushed part")
	part_owner.player_track(Vector3.ONE, Vector3.BACK, Vector3.UP, false, 0.1, 0.016, null, true)
	check(tracked_part.tracks.size() == 1, "the controller forwards the part track")
	part_owner.set_part(null)
	check(part_owner.part() == null, "a cleared part handle reads as absent")
	part_owner.free()
	tracked_part.free()

	# A closing world removes the player body, and the part under its Hips, from the tree before
	# `world_closed` reaches the facade. That teardown reset must not read or write world
	# transforms, and it still collects the bed holder.
	var detached_host := Node3D.new()
	root.add_child(detached_host)
	var detached_part: Node = PLAYER_PART.new()
	root.add_child(detached_part)
	var detached_mesh := MeshInstance3D.new()
	detached_mesh.mesh = BoxMesh.new()
	detached_mesh.set_surface_override_material(0, ShaderMaterial.new())
	detached_host.add_child(detached_mesh)
	var detached_holder := Node3D.new()
	detached_host.add_child(detached_holder)
	detached_part.set("_mesh", detached_mesh)
	detached_part.set("_bed_holder", detached_holder)
	detached_part.set("_ready_amount", 1.0)
	var detached_place := detached_mesh.transform
	root.remove_child(detached_host)
	check(not bool(detached_part.call("showing")), "a parted-out mesh is not showing")
	check(not (detached_part.call("root_now") as Vector3).is_finite(),
		"a parted-out part reports no root")
	detached_part.call("reset_state")
	check(detached_part.get("_bed_holder") == null, "a parted-out reset collects the bed holder")
	check(detached_mesh.transform.is_equal_approx(detached_place),
		"a parted-out reset leaves the mesh placement alone")
	detached_part.queue_free()
	detached_host.free()

	# A part built on a body that has left the tree is dropped and rebuilt on the current body,
	# so a following act is not handed a mesh that can never be seen.
	var stale_part: Node = PLAYER_PART.new()
	root.add_child(stale_part)
	var stale_host := Node3D.new()
	var stale_mesh := MeshInstance3D.new()
	stale_mesh.mesh = BoxMesh.new()
	stale_host.add_child(stale_mesh)
	stale_part.set("_mesh", stale_mesh)
	var fake_body := Node3D.new()
	var fake_skeleton := Skeleton3D.new()
	fake_skeleton.add_bone("Hips")
	fake_body.add_child(fake_skeleton)
	root.add_child(fake_body)
	stale_part.set("player_body", fake_body)
	check(bool(stale_part.call("prepare")), "a parted-out part rebuilds on the current body")
	var rebuilt: Variant = stale_part.get("_mesh")
	check(rebuilt is MeshInstance3D and rebuilt != stale_mesh
		and (rebuilt as MeshInstance3D).is_inside_tree(),
		"the rebuilt part is a new in-tree mesh")
	var rebuilt_id := (rebuilt as Node).get_instance_id()
	check(bool(stale_part.call("prepare")), "prepare stays true for a built part")
	check((stale_part.get("_mesh") as Node).get_instance_id() == rebuilt_id,
		"prepare is idempotent and keeps the built mesh")
	stale_host.free()
	stale_part.queue_free()
	fake_body.queue_free()

	# Her act wink: quiet at her lips, frequent once a climax has been pulled out of her.
	check(ANATOMY_ACT.wink_mode(0.6, true, 2) == 0, "a thrusting shaft raises no wink")
	check(ANATOMY_ACT.wink_mode(0.0, true, 0) == 1, "the tip at her lips winks on its own")
	check(ANATOMY_ACT.wink_mode(0.0, false, 0) == 0, "a pulled-out shaft waits before any climax")
	check(ANATOMY_ACT.wink_mode(0.1, false, 1) == 2, "a pulled-out shaft after a climax winks often")
	var wink_act: Node = ANATOMY_ACT.new()
	wink_act.call("_start_wink", ANATOMY_ACT.ACT_WINK_S, 1.0)
	check(absf(wink_act.wink_left() - ANATOMY_ACT.ACT_WINK_S) < 0.001,
		"an act wink arms its countdown")
	check(is_equal_approx(wink_act.wink_beats(), 1.0), "an act wink is one beat")
	wink_act.call("reset")
	check(is_zero_approx(wink_act.wink_left()), "reset clears the act wink")
	wink_act.free()

	# The facade's debug scale is typed: a Vector3, and infinite when no part is showing.
	var facade: Node = ANATOMY_SERVICE.new()
	root.add_child(facade)
	facade.call("setup")
	var debug_scale: Vector3 = facade.player_debug_scale()
	check(debug_scale == Vector3.INF, "no player part answers an infinite debug scale")
	facade.call("shutdown")
	root.remove_child(facade)
	facade.free()

	# The act's controller handle is the concrete controller script: its part and fluid answers
	# are typed, and a detached controller answers null rather than an untyped object.
	var detached := ANATOMY.new()
	check(detached.part() == null, "a controller with no player part answers null")
	check(detached.fluid() == null, "a detached controller answers no fluid node")
	detached.free()

	finish()
