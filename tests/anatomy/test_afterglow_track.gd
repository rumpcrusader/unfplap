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
const VIEW := preload("res://mods/unfplap/shared/pose_view.gd")

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

	func set_aim(normal: Vector3, opening: Vector3, pitch := 0.0) -> void:
		aim_normal = normal
		aim_opening = opening
		aim_pitch_deg = pitch

	func set_bed_inset(metres: float) -> void:
		bed_inset_m = metres


class FakeAnatomy extends Node:
	var mesh: MeshInstance3D
	var opening := Vector3(0.0, 0.5, 1.0)
	var rear := Vector3(0.0, 0.0, 1.0)
	var part_node: Node
	var tracks: Array = []

	func part() -> Node:
		return part_node

	func player_track(target: Vector3, rear_axis: Vector3, up: Vector3, bed: bool,
			penetration_m: float, delta: float, mare_anchor: Node3D, attached := true) -> void:
		tracks.append({
			"target": target,
			"rear": rear_axis,
			"up": up,
			"bed": bed,
			"penetration_m": penetration_m,
			"delta": delta,
			"mare_anchor": mare_anchor,
			"attached": attached,
		})

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


## One afterglow tick on a fake rig. Returns the act, anatomy and part for assertions.
func _afterglow_tick(pose_id: String) -> Array:
	var pony := FakePony.new()
	var anatomy := FakeAnatomy.new()
	var mesh := MeshInstance3D.new()
	var holder := Node3D.new()
	anatomy.add_child(holder)
	holder.add_child(mesh)
	var part := FakePart.new()
	root.add_child(pony)
	root.add_child(anatomy)
	root.add_child(part)
	anatomy.mesh = mesh
	anatomy.part_node = part
	var act: Node = ACT.new()
	act.call("setup", pony, anatomy, Callable(), Callable())
	var facts := FACTS.new()
	facts.penetration_reach = 0.2
	var view: Variant = VIEW.new()
	view.id = pose_id
	view.family = "bed" if pose_id == CATALOG.MISSIONARY else "standing"
	view.frame = "bed" if pose_id == CATALOG.MISSIONARY else "ground"
	facts.pose_view = view
	act.call("afterglow_tick", 0.25, facts)
	return [act, anatomy, part]


func run() -> void:
	var rig := _afterglow_tick(CATALOG.MISSIONARY)
	var act: Node = rig[0]
	var anatomy: FakeAnatomy = rig[1]
	var part: FakePart = rig[2]
	check(anatomy.tracks.size() == 1, "the afterglow tracks the part once")
	if anatomy.tracks.size() == 1:
		var track: Dictionary = anatomy.tracks[0]
		check(not bool(track["bed"]), "the afterglow keeps the attached alignment, not the bed holder")
		check(bool(track["attached"]), "the afterglow tracks the attached part")
		check((track["target"] as Vector3).is_equal_approx(Vector3(0.0, 0.5, 1.0)),
			"the afterglow tracks the live opening")
		check((track["rear"] as Vector3).is_equal_approx(Vector3(0.0, 0.0, 1.0)),
			"the afterglow passes the opening's rear axis")
		check(near(float(track["penetration_m"]), 0.0),
			"the afterglow rests the part at her entrance")
		check(part.aim_opening.is_equal_approx(Vector3(0.0, 0.5, 1.0)),
			"the part aims at the live opening")
		check(part.aim_normal.is_equal_approx(Vector3(0.0, 0.0, 1.0)),
			"the part aims along the resolved opening normal")
		check(is_zero_approx(part.aim_pitch_deg), "the afterglow clears the anal aim tilt")
		check(near(part.bed_inset_m, SETTINGS.part_inset_m.get_num()),
			"the held bed act keeps the missionary inset")
	act.call("teardown")
	act.free()
	anatomy.free()
	part.free()

	var standing := _afterglow_tick(CATALOG.STANDING)
	var standing_act: Node = standing[0]
	var standing_part: FakePart = standing[2]
	check(is_zero_approx(standing_part.bed_inset_m),
		"a standing afterglow clears the missionary inset")
	standing_act.call("teardown")
	standing_act.free()

	# The oral afterglow keeps the mouth anchor only while the pose view still holds the mouth
	# contact; the runtime releases it on the afterglow entry, and the part returns to the opening.
	var oral_rig := _afterglow_tick(CATALOG.STANDING)
	var oral_act: Node = oral_rig[0]
	var oral_anatomy: FakeAnatomy = oral_rig[1]
	var oral_part: FakePart = oral_rig[2]
	var oral_facts := FACTS.new()
	oral_facts.penetration_reach = 0.2
	var oral_view: Variant = VIEW.new()
	oral_view.family = "standing"
	oral_view.contact_kind = "mouth"
	oral_view.contact_target = Vector3(0.3, 0.9, 1.1)
	oral_facts.pose_view = oral_view
	oral_anatomy.tracks.clear()
	oral_act.call("afterglow_tick", 0.25, oral_facts)
	check(oral_anatomy.tracks.size() == 1, "the oral afterglow tracks the part once")
	if oral_anatomy.tracks.size() == 1:
		var oral_track: Dictionary = oral_anatomy.tracks[0]
		check((oral_track["target"] as Vector3).is_equal_approx(oral_view.contact_target),
			"the oral afterglow tracks the pose view's mouth anchor")
		check((oral_track["rear"] as Vector3).is_zero_approx(),
			"the mouth anchor drops the vulva rear axis")
		check(oral_part.aim_opening.is_equal_approx(oral_view.contact_target),
			"the oral part aims at the mouth anchor")
		check(oral_part.aim_normal.is_zero_approx(),
			"the mouth anchor uses the auto aim")
	var holes_on := SETTINGS.anatomy_holes.get_bool()
	SETTINGS.anatomy_holes.set_bool(true)
	oral_act.call("toggle_hole", 2)
	check(not bool(oral_act.get("_anal")),
		"the mouth contact refuses the hole")
	SETTINGS.anatomy_holes.set_bool(holes_on)
	oral_view.contact_kind = "opening"
	oral_view.contact_target = Vector3.INF
	oral_anatomy.tracks.clear()
	oral_act.call("afterglow_tick", 0.25, oral_facts)
	check(oral_anatomy.tracks.size() == 1, "the released afterglow tracks the part once")
	if oral_anatomy.tracks.size() == 1:
		var released: Dictionary = oral_anatomy.tracks[0]
		check((released["target"] as Vector3).is_equal_approx(Vector3(0.0, 0.5, 1.0)),
			"the released afterglow returns to the opening")
	oral_act.call("teardown")
	oral_act.free()
	oral_anatomy.free()
	oral_part.free()

	print("ANATOMY_AFTERGLOW_TRACK_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)