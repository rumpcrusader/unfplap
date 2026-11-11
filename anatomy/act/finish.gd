extends RefCounted
## The act's finish state: inside/outside selection, the finish droplets and the afterglow rest
## depth. It owns only finish data; the act drives shapes and the runtime owns the climax event.
##
## See `docs/anatomy.md` (`## Act anatomy`).

const SETTINGS := preload("res://mods/unfplap/settings.gd")
const CATALOG := preload("res://mods/unfplap/poses/catalog.gd")

const PULLED_OUT_PHASE := 0.35
const ANON_FLUID_COLOR := Color(0.98, 0.97, 0.93, 0.96)

var anatomy: Node
var pony: Node3D
var main: Node
var pose := ""

var _pull_out := false
var _finish_out := false
var _finished_inside := false
var _bed_rest := 0.8


func setup(anatomy_node: Node, pony_node: Node3D, main_node: Node, pose_id: String) -> void:
	anatomy = anatomy_node
	pony = pony_node
	main = main_node
	pose = pose_id
	reset()


func reset() -> void:
	_pull_out = false
	_finish_out = false
	_finished_inside = false
	_bed_rest = 0.8


func toggle(state: int) -> void:
	if not SETTINGS.anatomy_finish.get_bool() or state not in [2, 3]:
		return
	_pull_out = not _pull_out
	if is_instance_valid(main) and main.has_method("anatomy_status"):
		main.call("anatomy_status",
			"Finish: %s" % ("pull out" if _pull_out else "stay in"), 2.0)


func pull_out_selected() -> bool:
	return _pull_out


func finish_out() -> bool:
	return _finish_out


func finished_inside() -> bool:
	return _finished_inside


func on_finish(depth: float, oral: bool, fluid_ground_y: float) -> void:
	if not SETTINGS.anatomy_finish.get_bool():
		_finish_out = false
		_finished_inside = false
		return
	_finish_out = _pull_out or depth < PULLED_OUT_PHASE
	if _finish_out:
		if SETTINGS.anatomy_fluid.get_bool():
			_spurts_on_her(0)
	elif not oral:
		_finished_inside = true
		if _fluid_ready(fluid_ground_y):
			_timer(0.7, _inside_leak)


## One afterglow step; returns the resting penetration in metres.
func afterglow_step(delta: float, reach: float) -> float:
	_bed_rest = move_toward(_bed_rest, 0.0 if _finish_out else 0.8, delta * 1.6)
	return _bed_rest * reach


func withdraw() -> void:
	if not SETTINGS.anatomy_fluid.get_bool():
		_finished_inside = false
		return
	var fluid := _fluid_node()
	if _finished_inside and is_instance_valid(fluid):
		fluid.call("spray", _hole_point(), _hole_out(), 34, 0.55, 0.0105, ANON_FLUID_COLOR)
		fluid.call("drip", Callable(self, "_hole_point"), 5.0, 11.0, 0.009, ANON_FLUID_COLOR)
	_finished_inside = false


func teardown() -> void:
	_finished_inside = false
	_finish_out = false
	_pull_out = false
	_bed_rest = 0.8


func _service() -> Variant:
	return main.get("anatomy") if is_instance_valid(main) else null


func _part() -> Variant:
	var service: Variant = _service()
	if service == null or not service.has_method("part"):
		return null
	return service.call("part")


func _spurts_on_her(pulse: int) -> void:
	var part: Variant = _part()
	var fluid := _fluid_node()
	if pulse >= 4 or not is_instance_valid(part) or not bool(part.call("showing")) \
			or not is_instance_valid(fluid):
		return
	if pulse == 0:
		_timer(0.55, _spurts_on_her.bind(1))
		return
	var rear := _hole_rear()
	var up_and_over := -Vector3(rear.x, 0.0, rear.z).normalized() + Vector3.UP * 0.55
	if pose == CATALOG.MISSIONARY:
		var mesh: Variant = anatomy.call("winking_mesh")
		if is_instance_valid(mesh):
			up_and_over = (mesh as Node3D).global_basis.y.normalized() + Vector3.UP * 0.45
	fluid.call("spray", part.call("tip_world"), up_and_over, 20 - pulse * 3,
		2.3 - pulse * 0.35, 0.0095, ANON_FLUID_COLOR)
	_timer(0.38, _spurts_on_her.bind(pulse + 1))


func _inside_leak() -> void:
	if not SETTINGS.anatomy_fluid.get_bool():
		return
	var fluid := _fluid_node()
	if not is_instance_valid(fluid):
		return
	fluid.call("drip", Callable(self, "_hole_point"), 9.0, 8.0, 0.009, ANON_FLUID_COLOR)


func _fluid_node() -> Node3D:
	if not is_instance_valid(anatomy):
		return null
	return anatomy.call("fluid") as Node3D


func _fluid_ready(ground_y: float) -> bool:
	if not SETTINGS.anatomy_fluid.get_bool():
		return false
	var fluid := _fluid_node()
	if not is_instance_valid(fluid):
		return false
	fluid.set("ground_y", ground_y)
	return true


func _hole_point() -> Vector3:
	return anatomy.call("hole_point", 0.0)


func _hole_rear() -> Vector3:
	return anatomy.call("hole_rear")


func _hole_out() -> Vector3:
	return _hole_rear() + Vector3.DOWN * 0.3


func _timer(seconds: float, callback: Callable) -> void:
	if not is_instance_valid(pony) or not pony.is_inside_tree():
		return
	var tree := pony.get_tree()
	if tree != null:
		tree.create_timer(seconds).timeout.connect(callback)
