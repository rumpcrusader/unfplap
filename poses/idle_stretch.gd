extends RefCounted
## The external Idle Life stretch holder. This is the only repository file that names Idle
## Life's private pose script: it loads the installed `idle_pose.gd` at call time, validates the
## fields it drives, and adds one SkeletonModifier3D to the pony's body skeleton. Idle Life owns
## the pose math; this adapter owns the episode choice, the hold time and the node lifetime.
##
## The choice lives on the pony's metadata so the ask, the presentation and the act reuse one
## variant and side. `finish(true)` is the only path that clears it.

const POSE_PATH := "res://mods/idle_life/idle_pose.gd"
## The fully deepened point of Idle Life 1.4.2's stretch envelope. Holding `time` here keeps the
## pose still instead of letting the idle's own fade-out run.
const HOLD_TIME := 4.0
const LIGHT := "stretch"
const DEEP := "stretch_deep"
const META_IDLE := "unfplap_stretch_idle"
const META_SIDE := "unfplap_stretch_side"
const NODE_NAME := "UnfplapIdleStretch"

## Test seam: a suite points this at a fake SkeletonModifier3D.
static var pose_path := POSE_PATH

var _node: SkeletonModifier3D = null
var _pony: Node3D = null


## Whether the installed script exposes the fields this adapter drives.
func available() -> bool:
	return _valid_script(load(pose_path))


## Add the holder to the pony's skeleton. `hold_now` starts at the deepened pose; otherwise the
## holder ramps from the idle's first moment for the ask.
func begin(pony: Node3D, hold_now := true) -> bool:
	if active():
		return true
	if not is_instance_valid(pony):
		return false
	var skeleton_value: Variant = pony.get("skeleton")
	if not skeleton_value is Skeleton3D:
		return false
	var script: Variant = load(pose_path)
	if not _valid_script(script):
		return false
	var node: Variant = (script as Script).new()
	if not node is SkeletonModifier3D:
		if node is Node:
			(node as Node).free()
		return false
	var choice := _choice(pony)
	node.set("mare", pony)
	node.set("idle", choice["idle"])
	node.set("side", choice["side"])
	node.set("fade", 1.0)
	node.set("time", HOLD_TIME if hold_now else 0.0)
	node.name = NODE_NAME
	var skeleton := skeleton_value as Skeleton3D
	# A holder released earlier in this same frame is still a child until the frame ends. Move its
	# name aside so the replacement keeps the stable name instead of Godot's generated one.
	for child: Node in skeleton.get_children():
		if str(child.name) == NODE_NAME and child.is_queued_for_deletion():
			child.name = "UnfplapIdleStretchFreed%d" % child.get_instance_id()
	skeleton.add_child(node)
	_node = node as SkeletonModifier3D
	_pony = pony
	return true


## Advance the ask ramp toward the held pose. The holder itself reads no clock.
func tick(delta: float) -> void:
	if not active():
		return
	var step := maxf(0.0, delta)
	_node.set("time", minf(HOLD_TIME, float(_node.get("time")) + step))


## Keep the holder immediately before the act or presentation pose node, so the act's oral and
## head-back overlays land on top of the external body pose.
func place_before(other: Node) -> void:
	if not active() or not is_instance_valid(other):
		return
	var parent: Node = _node.get_parent()
	if parent == null or parent != other.get_parent():
		return
	var target := other.get_index()
	if _node.get_index() < target:
		target -= 1
	if _node.get_index() == target:
		return
	parent.move_child(_node, target)


## Release the holder. `clear` also drops the stored episode choice (a cancel or an act teardown);
## the default preserves it for the next stage of the same offer.
func finish(clear := false) -> void:
	if is_instance_valid(_node):
		_node.set("fade", 0.0)
		_node.queue_free()
	_node = null
	if clear and is_instance_valid(_pony):
		clear_choice(_pony)
	_pony = null


func active() -> bool:
	if not is_instance_valid(_node):
		_node = null
		return false
	if _node.is_queued_for_deletion():
		_node = null
		return false
	return true


## The script must instantiate a SkeletonModifier3D carrying every field this adapter writes.
static func _valid_script(script: Variant) -> bool:
	if not script is Script:
		return false
	var probe: Variant = (script as Script).new()
	if not probe is SkeletonModifier3D:
		if probe is Node:
			(probe as Node).free()
		return false
	var fields: Dictionary = {}
	for row: Dictionary in (probe as Object).get_property_list():
		fields[str(row.get("name", ""))] = true
	var ok := fields.has("mare") and fields.has("idle") and fields.has("side") \
		and fields.has("time") and fields.has("fade")
	(probe as Node).free()
	return ok


## One episode's variant and side, rolled once and stored on the pony.
func _choice(pony: Node3D) -> Dictionary:
	var idle := str(pony.get_meta(META_IDLE, ""))
	if idle != LIGHT and idle != DEEP:
		idle = LIGHT if randf() < 0.5 else DEEP
		pony.set_meta(META_IDLE, idle)
	var side := float(pony.get_meta(META_SIDE, 0.0))
	if side == 0.0:
		side = 1.0 if randf() < 0.5 else -1.0
	elif side > 0.0:
		side = 1.0
	else:
		side = -1.0
	pony.set_meta(META_SIDE, side)
	return {"idle": idle, "side": side}


## Drop the episode choice so the next offer rolls fresh.
static func clear_choice(pony: Node3D) -> void:
	if not is_instance_valid(pony):
		return
	if pony.has_meta(META_IDLE):
		pony.remove_meta(META_IDLE)
	if pony.has_meta(META_SIDE):
		pony.remove_meta(META_SIDE)