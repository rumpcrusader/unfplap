extends SceneTree
## The held afterglow keeps the act's attached player-part alignment: the part stays on Anon's
## Hips and turns to the current opening normal instead of riding the detached bed holder, which
## rolls it upside down in the lying pose.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/anatomy/test_afterglow_track.gd

const ACT := preload("res://mods/unfplap/anatomy/act.gd")
const FACTS := preload("res://mods/unfplap/anatomy/facts.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")

var failures := 0
var checks := 0


class FakePart extends Node:
	var showing_value := true
	var aim_normal := Vector3.ZERO
	var aim_opening := Vector3.ZERO
	var aim_pitch_deg := 0.0
	var bed_inset_m := 0.0

	func showing() -> bool:
		return showing_value


class FakeService extends Node:
	var part_node: Node
	var tracks: Array = []

	func part() -> Node:
		return part_node

	func player_track(target: Vector3, rear: Vector3, up: Vector3, bed: bool,
			penetration_m: float, delta: float, mare_anchor: Node3D, attached := true) -> void:
		tracks.append({
			"target": target,
			"rear": rear,
			"up": up,
			"bed": bed,
			"penetration_m": penetration_m,
			"delta": delta,
			"mare_anchor": mare_anchor,
			"attached": attached,
		})


class FakeAnatomy extends Node:
	var mesh: MeshInstance3D
	var opening := Vector3(0.0, 0.5, 1.0)
	var rear := Vector3(0.0, 0.0, 1.0)

	func winking_mesh() -> MeshInstance3D:
		return mesh

	func hole_point(_mix := 0.0) -> Vector3:
		return opening

	func hole_rear(_mix := 0.0) -> Vector3:
		return rear

	func animate(_value: float, _seconds: float) -> void:
		pass


class FakePony extends Node3D:
	pass


## A minimal oral turn: the act reads only the mix, the anchor and the pose delta.
class FakeOral extends RefCounted:
	var oral_mix := 0.0
	var point := Vector3(0.0, 0.4, 0.9)
	var delta: Dictionary = {}

	func mix() -> float:
		return oral_mix

	func anchor() -> Vector3:
		return point

	func write_pose_delta(config: Dictionary) -> void:
		if delta.is_empty():
			config.erase("oral_pitch")
			config.erase("oral_yaw")
			config.erase("oral_roll")
			return
		for key: String in delta:
			config[key] = delta[key]

	func reset() -> void:
		pass

	func teardown() -> void:
		pass


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func near(a: float, b: float, eps := 0.0001) -> bool:
	return absf(a - b) <= eps


## One afterglow tick on a fake rig. Returns the act, service and part for assertions.
func _afterglow_tick(pose_id: String) -> Array:
	var service := FakeService.new()
	var pony := FakePony.new()
	var anatomy := FakeAnatomy.new()
	var mesh := MeshInstance3D.new()
	var holder := Node3D.new()
	anatomy.add_child(holder)
	holder.add_child(mesh)
	var part := FakePart.new()
	root.add_child(service)
	root.add_child(pony)
	root.add_child(anatomy)
	root.add_child(part)
	anatomy.mesh = mesh
	service.part_node = part
	var act: Node = ACT.new()
	act.call("setup", service, pony, anatomy, pose_id, Callable(), Callable())
	var facts := FACTS.new()
	facts.penetration_reach = 0.2
	act.call("afterglow_tick", 0.25, facts)
	return [act, service, part]


func run() -> void:
	var rig := _afterglow_tick(CATALOG.MISSIONARY)
	var act: Node = rig[0]
	var service: FakeService = rig[1]
	var part: FakePart = rig[2]
	check(service.tracks.size() == 1, "the afterglow tracks the part once")
	if service.tracks.size() == 1:
		var track: Dictionary = service.tracks[0]
		check(not bool(track["bed"]), "the afterglow keeps the attached alignment, not the bed holder")
		check(bool(track["attached"]), "the afterglow tracks the attached part")
		check((track["target"] as Vector3).is_equal_approx(Vector3(0.0, 0.5, 1.0)),
			"the afterglow tracks the live opening")
		check((track["rear"] as Vector3).is_equal_approx(Vector3(0.0, 0.0, 1.0)),
			"the afterglow passes the opening's rear axis")
		check(near(float(track["penetration_m"]), 0.16),
			"the afterglow passes the resting share of the reach")
		check(part.aim_opening.is_equal_approx(Vector3(0.0, 0.5, 1.0)),
			"the part aims at the live opening")
		check(part.aim_normal.is_equal_approx(Vector3(0.0, 0.0, 1.0)),
			"the part aims along the resolved opening normal")
		check(is_zero_approx(part.aim_pitch_deg), "the afterglow clears the anal aim tilt")
		check(near(part.bed_inset_m, SETTINGS.part_inset_m.get_num()),
			"the held bed act keeps the missionary inset")
	act.call("teardown")
	act.free()
	service.free()
	part.free()

	var standing := _afterglow_tick(CATALOG.STANDING)
	var standing_act: Node = standing[0]
	var standing_part: FakePart = standing[2]
	check(is_zero_approx(standing_part.bed_inset_m),
		"a standing afterglow clears the missionary inset")
	standing_act.call("teardown")
	standing_act.free()

	# Oral afterglow: the part stays on the mouth anchor instead of snapping to the vulva, and
	# the oral pose delta is written and erased through the same call.
	var oral_rig := _afterglow_tick(CATALOG.STANDING)
	var oral_act: Node = oral_rig[0]
	var oral_service: FakeService = oral_rig[1]
	var oral_part: FakePart = oral_rig[2]
	var oral := FakeOral.new()
	oral.oral_mix = 1.0
	oral_act.set("_oral_turn", oral)
	oral_service.tracks.clear()
	oral_act.call("afterglow_tick", 0.25, FACTS.new())
	check(oral_service.tracks.size() == 1, "the oral afterglow tracks the part once")
	if oral_service.tracks.size() == 1:
		var oral_track: Dictionary = oral_service.tracks[0]
		check((oral_track["target"] as Vector3).is_equal_approx(oral.point),
			"the oral afterglow tracks the mouth anchor, not the vulva")
		check((oral_track["rear"] as Vector3).is_zero_approx(),
			"the mouth anchor drops the vulva rear axis")
		check(oral_part.aim_opening.is_equal_approx(oral.point),
			"the oral part aims at the mouth anchor")
		check(oral_part.aim_normal.is_zero_approx(),
			"the mouth anchor uses the auto aim")
	var config := {"oral_pitch": 2.0}
	oral.delta = {"oral_pitch": 0.5, "oral_yaw": 0.25, "oral_roll": 0.1}
	oral_act.call("pose_config", config)
	check(near(float(config.get("oral_pitch", 0.0)), 0.5) and config.has("oral_roll"),
		"the act writes a live oral pose delta")
	oral.delta = {}
	oral_act.call("pose_config", config)
	check(not config.has("oral_pitch") and not config.has("oral_yaw") \
		and not config.has("oral_roll"), "the act erases a released oral pose delta")
	oral_act.call("teardown")
	oral_act.free()
	oral_service.free()
	oral_part.free()

	print("ANATOMY_AFTERGLOW_TRACK_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)