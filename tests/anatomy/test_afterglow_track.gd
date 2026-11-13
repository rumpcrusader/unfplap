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

	print("ANATOMY_AFTERGLOW_TRACK_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)