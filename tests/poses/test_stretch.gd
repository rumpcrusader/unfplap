extends SceneTree
## The external Idle Life stretch adapter: script validation, the episode choice, the ask ramp,
## the modifier order and cleanup.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/poses/test_stretch.gd

const STRETCH := preload("res://mods/unfplap/poses/idle_stretch.gd")

const FAKE := "res://mods/unfplap/tests/fixtures/idle_stretch_fake.gd"
const MISSING := "res://mods/idle_life/not_a_real_stretch.gd"
const WRONG_BASE := "res://mods/unfplap/integrations/context.gd"
const OUTLINE_ONLY := "res://mods/unfplap/poses/body_sway.gd"
const NODE_NAME := "UnfplapIdleStretch"

var failures := 0
var checks := 0


class FakePony extends Node3D:
	var skeleton: Variant = null


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func _pony() -> FakePony:
	var pony := FakePony.new()
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton"
	pony.add_child(skeleton)
	pony.skeleton = skeleton
	root.add_child(pony)
	return pony


func _holder(pony: FakePony) -> Node:
	var skeleton: Variant = pony.get("skeleton")
	if not skeleton is Skeleton3D:
		return null
	return (skeleton as Skeleton3D).get_node_or_null(NODE_NAME)


func _free_pony(pony: FakePony) -> void:
	if is_instance_valid(pony):
		root.remove_child(pony)
		pony.free()


func run() -> void:
	STRETCH.pose_path = FAKE
	_check_available()
	await _check_hold()
	_check_ramp()
	_check_choice()
	_check_order()
	_check_fallback()
	print("POSE_STRETCH_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("POSE_STRETCH_PASS")
	quit(0 if failures == 0 else 1)


func _check_available() -> void:
	var holder: RefCounted = STRETCH.new()
	check(holder.call("available"), "the fake external script exposes every field")
	STRETCH.pose_path = MISSING
	check(not holder.call("available"), "a missing external script is unavailable")
	STRETCH.pose_path = WRONG_BASE
	check(not holder.call("available"), "a non-modifier script is unavailable")
	STRETCH.pose_path = OUTLINE_ONLY
	check(not holder.call("available"), "a modifier without the stretch fields is unavailable")
	STRETCH.pose_path = FAKE


func _check_hold() -> void:
	var pony := _pony()
	var holder: RefCounted = STRETCH.new()
	check(holder.call("begin", pony, true), "the holder installs on the body skeleton")
	var node := _holder(pony)
	check(node != null, "the holder is named on the skeleton")
	if node != null:
		check(str(node.get("idle")) in [STRETCH.LIGHT, STRETCH.DEEP],
			"the holder starts one of the two stretch variants")
		check(absf(float(node.get("side"))) == 1.0, "the holder starts one side")
		check(is_equal_approx(float(node.get("fade")), 1.0), "the holder starts at full fade")
		check(is_equal_approx(float(node.get("time")), STRETCH.HOLD_TIME),
			"the full holder starts at the deepened point")
		check(node.get("mare") == pony, "the holder points at the pony")
	check(pony.has_meta(STRETCH.META_IDLE), "the episode variant is stored on the pony")
	check(pony.has_meta(STRETCH.META_SIDE), "the episode side is stored on the pony")
	var stored_idle := str(pony.get_meta(STRETCH.META_IDLE))
	var stored_side := float(pony.get_meta(STRETCH.META_SIDE))
	check(holder.call("begin", pony, true), "a repeated begin is idempotent")
	check(_count_holders(pony) == 1, "a repeated begin does not add a second holder")
	var old := node
	holder.call("finish", false)
	check(not holder.call("active"), "finish clears the active handle")
	check(old != null and old.is_queued_for_deletion(), "finish queues the external node")
	check(pony.has_meta(STRETCH.META_IDLE) and pony.has_meta(STRETCH.META_SIDE),
		"finish without clear preserves the episode choice")
	await process_frame
	var again: RefCounted = STRETCH.new()
	check(again.call("begin", pony, true), "a later holder reuses the stored choice")
	var reused := _holder(pony)
	check(reused != null and str(reused.get("idle")) == stored_idle,
		"the presentation/act reuses the ask's variant")
	check(reused != null and is_equal_approx(float(reused.get("side")), stored_side),
		"the presentation/act reuses the ask's side")
	again.call("finish", true)
	check(not pony.has_meta(STRETCH.META_IDLE) and not pony.has_meta(STRETCH.META_SIDE),
		"finish with clear drops the episode choice")
	await process_frame
	_free_pony(pony)


func _count_holders(pony: FakePony) -> int:
	var skeleton: Variant = pony.get("skeleton")
	if not skeleton is Skeleton3D:
		return 0
	var count := 0
	for child: Node in (skeleton as Skeleton3D).get_children():
		if str(child.name) == NODE_NAME:
			count += 1
	return count


func _check_ramp() -> void:
	var pony := _pony()
	var holder: RefCounted = STRETCH.new()
	check(holder.call("begin", pony, false), "the ask holder installs at the first moment")
	var node := _holder(pony)
	check(node != null and is_zero_approx(float(node.get("time"))),
		"the ask holder starts at time zero")
	holder.call("tick", 1.25)
	check(node != null and is_equal_approx(float(node.get("time")), 1.25),
		"the ask ramp advances with the physics delta")
	holder.call("tick", 10.0)
	check(node != null and is_equal_approx(float(node.get("time")), STRETCH.HOLD_TIME),
		"the ask ramp stops at the deepened hold")
	holder.call("tick", -2.0)
	check(node != null and is_equal_approx(float(node.get("time")), STRETCH.HOLD_TIME),
		"a negative delta does not rewind the hold")
	holder.call("finish", true)
	await process_frame
	_free_pony(pony)


func _check_choice() -> void:
	var pony := _pony()
	pony.set_meta(STRETCH.META_IDLE, STRETCH.DEEP)
	pony.set_meta(STRETCH.META_SIDE, -1.0)
	var holder: RefCounted = STRETCH.new()
	check(holder.call("begin", pony, true), "a stored choice installs")
	var node := _holder(pony)
	check(node != null and str(node.get("idle")) == STRETCH.DEEP,
		"the stored variant reaches the external node")
	check(node != null and is_equal_approx(float(node.get("side")), -1.0),
		"the stored side reaches the external node")
	holder.call("finish", true)
	await process_frame
	var rolled: RefCounted = STRETCH.new()
	check(rolled.call("begin", pony, true), "a cleared choice rolls a fresh episode")
	var fresh := _holder(pony)
	check(fresh != null and str(fresh.get("idle")) in [STRETCH.LIGHT, STRETCH.DEEP],
		"the fresh roll picks a valid variant")
	check(fresh != null and absf(float(fresh.get("side"))) == 1.0,
		"the fresh roll picks a side")
	rolled.call("finish", true)
	await process_frame
	_free_pony(pony)


func _check_order() -> void:
	var pony := _pony()
	var skeleton: Skeleton3D = pony.get("skeleton")
	var first := Node3D.new()
	first.name = "UnfplapPose"
	skeleton.add_child(first)
	var last := Node3D.new()
	last.name = "UnfplapChinDebug"
	skeleton.add_child(last)
	var holder: RefCounted = STRETCH.new()
	check(holder.call("begin", pony, true), "the order holder installs")
	var node := _holder(pony)
	holder.call("place_before", first)
	check(node != null and node.get_index() < first.get_index(),
		"the holder is moved before the pose node")
	check(node != null and node.get_index() + 1 == first.get_index(),
		"the holder sits immediately before the pose node")
	var elsewhere := Node3D.new()
	skeleton.add_child(elsewhere)
	holder.call("place_before", elsewhere)
	check(node != null and node.get_index() + 1 == elsewhere.get_index(),
		"the holder is moved before a later node too")
	holder.call("finish", true)
	await process_frame
	_free_pony(pony)


func _check_fallback() -> void:
	var pony := _pony()
	STRETCH.pose_path = MISSING
	var missing: RefCounted = STRETCH.new()
	check(not missing.call("begin", pony, true), "a missing script refuses the holder")
	check(_holder(pony) == null, "a missing script adds no node")
	STRETCH.pose_path = WRONG_BASE
	var wrong: RefCounted = STRETCH.new()
	check(not wrong.call("begin", pony, true), "a non-modifier script refuses the holder")
	STRETCH.pose_path = OUTLINE_ONLY
	var fields: RefCounted = STRETCH.new()
	check(not fields.call("begin", pony, true), "missing stretch fields refuse the holder")
	STRETCH.pose_path = FAKE
	_free_pony(pony)