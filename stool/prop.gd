extends RefCounted
## Scene adapter for the standing act's footstool prop. See docs/stool.md.

const SHOP_ITEMS := preload("res://world/shop/shop_items.gd")
const ITEM := preload("res://mods/unfplap/stool/item.gd")

## The base-game visual's measured top is about 0.39 m. This is the fallback only.
const FALLBACK_HEIGHT := 0.39
const FALLBACK_SIZE := Vector3(0.55, 0.39, 0.45)
const MIN_TOP_X := 0.46
const MIN_TOP_Z := 0.40


## Build a static stool at `at` (its base sits on that floor point). Returns
## {"node": StaticBody3D, "height": float}, or {} when the host is invalid.
static func build(host: Node, at: Vector3, yaw: float) -> Dictionary:
	if not is_instance_valid(host) or not at.is_finite() or not is_finite(yaw):
		return {}
	var body := StaticBody3D.new()
	body.name = "UnfplapStool"
	body.collision_layer = 1
	body.collision_mask = 0
	var visual: Node3D = _shop_visual()
	if visual != null:
		body.add_child(visual)
	body.global_transform = Transform3D(Basis(Vector3.UP, yaw), at)
	host.add_child(body)
	var bounds := AABB()
	if visual != null:
		var value: Variant = visual.get("bounds")
		if value is AABB:
			bounds = value
	if bounds.size.y < 0.05:
		if visual != null:
			body.remove_child(visual)
			visual.queue_free()
		bounds = AABB(Vector3(-FALLBACK_SIZE.x * 0.5, 0.0, -FALLBACK_SIZE.z * 0.5),
			FALLBACK_SIZE)
		body.add_child(_fallback_visual())
	var height := maxf(bounds.size.y, 0.05)
	var top_size := Vector3(maxf(bounds.size.x, MIN_TOP_X), height,
		maxf(bounds.size.z, MIN_TOP_Z))
	var shape := BoxShape3D.new()
	shape.size = top_size
	var holder := CollisionShape3D.new()
	holder.name = "StoolTop"
	holder.shape = shape
	holder.position = Vector3(bounds.get_center().x, height * 0.5, bounds.get_center().z)
	body.add_child(holder)
	return {"node": body, "height": height}


## Remove the prop from the physics space before the player is lowered through it.
static func remove(prop: Variant) -> void:
	if not prop is Node:
		return
	var node := prop as Node
	if not is_instance_valid(node):
		return
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


static func _fallback_visual() -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = FALLBACK_SIZE
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("6b4a2f")
	material.roughness = 0.9
	mesh.material = material
	var node := MeshInstance3D.new()
	node.name = "StoolFallback"
	node.mesh = mesh
	node.position.y = FALLBACK_HEIGHT * 0.5
	return node
