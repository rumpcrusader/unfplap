extends SceneTree
## The pose-owned oral turn: the forward capture, the eased root and facing, the opening anchor
## while turning and the live mouth once settled, the reverse weight mapping, the soft-kiss timer
## and the one restore. The turn is pure scene math with host callables.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/poses/test_oral_turn.gd

const TURN := preload("res://mods/unfplap/poses/oral_turn.gd")
const VIEW := preload("res://mods/unfplap/shared/pose_view.gd")

var failures := 0
var checks := 0


class FakePony extends Node3D:
	pass


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func near(a: float, b: float, eps := 0.001) -> bool:
	return absf(a - b) <= eps


func _live() -> Dictionary:
	var pony := FakePony.new()
	pony.position = Vector3(1.0, 0.0, 2.0)
	pony.basis = Basis(Vector3.UP, 0.6)
	root.add_child(pony)
	var view: RefCounted = VIEW.new()
	view.from_config = {"marker": 1}
	view.to_config = {"marker": 2}
	view.contact_kind = "opening"
	var kisses: Array = []
	var turn: RefCounted = TURN.new()
	turn.bind(pony,
		func() -> Vector3: return pony.to_global(Vector3(0.0, 1.3, 0.5)),
		func() -> Vector3: return Vector3(3.0, 0.0, 4.0),
		func() -> void: kisses.append(true))
	return {"pony": pony, "view": view, "turn": turn, "kisses": kisses}


func _free(made: Dictionary) -> void:
	var pony: FakePony = made["pony"]
	root.remove_child(pony)
	pony.free()


func run() -> void:
	_check_forward()
	_check_reverse()
	print("ORAL_TURN_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("ORAL_TURN_PASS")
	quit(0 if failures == 0 else 1)


func _check_forward() -> void:
	var made := _live()
	var pony: FakePony = made["pony"]
	var view: RefCounted = made["view"]
	var turn: RefCounted = made["turn"]
	var kisses: Array = made["kisses"]
	var from: Vector3 = pony.global_position
	var from_basis: Basis = pony.global_transform.basis.orthonormalized()
	check(turn.begin(true, view), "the forward turn captures the pony")
	check(turn.active, "the forward turn is live")
	check(pony.global_position.is_equal_approx(from), "the capture does not move her")

	turn.tick(0.4, view, 0.0)
	check(pony.global_position.is_equal_approx(from), "weight zero holds the captured root")
	check(is_zero_approx(view.facing_amount), "weight zero holds the identity facing")
	check((view.contact_target as Vector3).is_equal_approx(Vector3(3.0, 0.0, 4.0)),
		"the opening anchors the turn")

	turn.tick(0.4, view, 0.5)
	check(pony.global_position.distance_to(from) > 0.01,
		"the turn moves her toward the mirrored anchor")
	check(near(view.facing_amount, 0.5), "the half weight is the half facing")
	check(view.facing.is_equal_approx(Basis(Vector3.UP, PI * 0.5) * from_basis),
		"the facing is the halved UP turn from the capture")
	check((view.contact_target as Vector3).is_equal_approx(Vector3(3.0, 0.0, 4.0)),
		"the opening still anchors while she turns")
	check(view.from_config.has("oral_pitch") and view.to_config.has("oral_pitch"),
		"the style keys reach both config sides")

	turn.tick(0.2, view, 1.0)
	check(is_equal_approx(view.facing_amount, 1.0), "full weight holds the half turn")
	check(pony.global_position.distance_to(from) > 0.01,
		"full weight has carried her to the mirrored anchor")
	var mouth: Vector3 = pony.to_global(Vector3(0.0, 1.3, 0.5))
	var opening_distance: float = (view.contact_target as Vector3).distance_to(mouth)
	view.contact_kind = "mouth"
	for i in 8:
		turn.tick(0.25, view, 1.0)
	check((view.contact_target as Vector3).distance_to(mouth)
		< opening_distance, "a settled mouth contact follows the live mouth")
	check((view.contact_target as Vector3).is_finite(), "the mouth anchor is finite")

	check(kisses.is_empty(), "the kiss timer waits before the first beat")
	turn.tick(5.0, view, 1.0)
	check(kisses.size() == 1, "the soft kiss fires after the idle interval")
	_free(made)


func _check_reverse() -> void:
	var made := _live()
	var pony: FakePony = made["pony"]
	var view: RefCounted = made["view"]
	var turn: RefCounted = made["turn"]
	var from: Vector3 = pony.global_position
	var from_basis: Basis = pony.global_transform.basis.orthonormalized()
	turn.begin(true, view)
	turn.tick(1.0, view, 1.0)
	var turned: Vector3 = pony.global_position
	var turned_basis: Basis = view.facing
	view.contact_kind = "mouth"
	turn.begin(false, view)
	turn.tick(0.0, view, 0.0)
	check(pony.global_position.distance_to(turned) < 0.001,
		"the reverse starts from the turned frame")
	check(near(view.facing_amount, 1.0), "the reverse starts at full facing")
	turn.tick(1.0, view, 1.0)
	check(pony.global_position.is_equal_approx(from),
		"the reverse returns the captured root at full weight")
	check(is_zero_approx(view.facing_amount), "the reverse returns the identity facing")
	turn.restore(view)
	check(pony.global_position.is_equal_approx(from), "the restore keeps the captured root")
	check(pony.global_transform.basis.orthonormalized().is_equal_approx(from_basis),
		"the restore returns the captured facing")
	check(not turn.active, "the restore clears the live turn")
	check(not view.from_config.has("oral_pitch") and not view.to_config.has("oral_pitch"),
		"the restore erases the oral keys")
	check(view.facing.is_equal_approx(Basis.IDENTITY) and is_zero_approx(view.facing_amount),
		"the restore clears the view facing")
	check((view.contact_target as Vector3) == Vector3.INF,
		"the restore clears the contact target")
	var before: Vector3 = pony.global_position
	turn.restore(view)
	check(pony.global_position.is_equal_approx(before), "a second restore is a no-op")
	check(turned_basis.is_equal_approx(Basis(Vector3.UP, PI) * from_basis),
		"the forward turn reached the half turn")
	_free(made)
