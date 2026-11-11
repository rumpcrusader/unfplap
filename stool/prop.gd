extends RefCounted
## Scene adapter for the standing act's footstool stack. See docs/stool.md.

const SHOP_ITEMS := preload("res://world/shop/shop_items.gd")
const ITEM := preload("res://mods/unfplap/stool/item.gd")

## The base-game visual's natural height is about 0.39 m. These are fallback values only.
const FALLBACK_HEIGHT := 0.39
const FALLBACK_SIZE := Vector3(0.55, 0.39, 0.45)
const MIN_TOP_X := 0.46
const MIN_TOP_Z := 0.40
const MIN_STEP_M := 0.01


## Build a static stool stack at `at` (its base sits on that floor point). Returns
## {"node": StaticBody3D, "height": float, "count": int, "step": float}, or {} when the host is
## invalid. `ignore` is the partner pony: the stack must not push her while Anon stands on it.
static func build(host: Node, at: Vector3, yaw: float, count := 1,
		step_height := 0.20, ignore: PhysicsBody3D = null) -> Dictionary:
	if not is_instance_valid(host) or not at.is_finite() or not is_finite(yaw):
		return {}
	var steps := maxi(1, count)
	var step := maxf(step_height, MIN_STEP_M)
	var total := float(steps) * step
	var body := StaticBody3D.new()
	body.name = "UnfplapStool"
	body.collision_layer = 1
	body.collision_mask = 0
	var visuals: Array[Node3D] = []
	for _i: int in steps:
		var visual := _shop_visual()
		if visual != null:
			body.add_child(visual)
			visuals.append(visual)
	body.global_transform = Transform3D(Basis(Vector3.UP, yaw), at)
	host.add_child(body)
	var natural := AABB()
	if not visuals.is_empty():
		var value: Variant = visuals[0].get("bounds")
		if value is AABB:
			natural = value
	var top_x := FALLBACK_SIZE.x
	var top_z := FALLBACK_SIZE.z
	if natural.size.y >= 0.05:
		var factor := step / natural.size.y
		for i: int in visuals.size():
			visuals[i].scale = Vector3.ONE * factor
			visuals[i].position.y = float(i) * step
		top_x = maxf(natural.size.x * factor, MIN_TOP_X)
		top_z = maxf(natural.size.z * factor, MIN_TOP_Z)
	else:
		for visual: Node3D in visuals:
			body.remove_child(visual)
			visual.queue_free()
		body.add_child(_fallback_stack(steps, step))
		top_x = FALLBACK_SIZE.x
		top_z = FALLBACK_SIZE.z
	var shape := BoxShape3D.new()
	shape.size = Vector3(top_x, total, top_z)
	var holder := CollisionShape3D.new()
	holder.name = "StoolTop"
	holder.shape = shape
	holder.position = Vector3(0.0, total * 0.5, 0.0)
	body.add_child(holder)
	if ignore is PhysicsBody3D and is_instance_valid(ignore):
		body.add_collision_exception_with(ignore)
		ignore.add_collision_exception_with(body)
		body.set_meta("stool_ignore", ignore)
	return {"node": body, "height": total, "count": steps, "step": step}


## Remove the prop from the physics space before the player is lowered through it. Both sides of
## the pony exception are cleared first so a freed stack cannot leave a stale collision pair.
static func remove(prop: Variant) -> void:
	if not prop is Node:
		return
	var node := prop as Node
	if not is_instance_valid(node):
		return
	var ignore: Variant = node.get_meta("stool_ignore", null)
	if node is PhysicsBody3D and ignore is PhysicsBody3D and is_instance_valid(ignore):
		(node as PhysicsBody3D).remove_collision_exception_with(ignore)
		(ignore as PhysicsBody3D).remove_collision_exception_with(node)
	var parent := node.get_parent()
	if parent != null:
		parent.remove_child(node)
	node.queue_free()


static func _shop_visual() -> Node3D:
	var scene: PackedScene = SHOP_ITEMS.scene(ITEM.ID)
	if scene == null:
		return null
	var value: Variant = scene.instantiate()
	return value as Node3D


static func _fallback_stack(steps: int, step: float) -> MeshInstance3D:
	var total := float(steps) * step
	var mesh := BoxMesh.new()
	mesh.size = Vector3(FALLBACK_SIZE.x, total, FALLBACK_SIZE.z)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("6b4a2f")
	material.roughness = 0.9
	mesh.material = material
	var node := MeshInstance3D.new()
	node.name = "StoolFallback"
	node.mesh = mesh
	node.position.y = total * 0.5
	return node
