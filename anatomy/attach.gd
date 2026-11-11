extends RefCounted
## Persistent anatomy attachment: the mesh, anchor, dock, fluid and visibility. One per
## controller. It owns nodes only; the controller still owns placement, shapes, coat and
## appearance setup and teardown.
##
## See `docs/anatomy.md` (`## Architecture`).

const SETTINGS := preload("res://mods/unfplap/settings.gd")
const CLIMAX_FLUID := preload("res://mods/unfplap/anatomy/fluid.gd")
const GEOMETRY := preload("res://mods/unfplap/anatomy/geometry.gd")

const ANATOMY_NAME := "UnfplapAnatomy"
const ANCHOR_NAME := "UnfplapAnatomyAnchor"
const FLUID_NAME := "UnfplapAnatomyFluid"
const DOCK_NAME := "OpenPonyDock"
const VISIBILITY_POLL_S := 0.2
const IDLE_FLUID_COLOR := Color(0.9, 0.93, 1.0, 0.72)
## Idle heat discharge: droplets leave the vulva opening along the ground and fall under the
## fluid node's gravity. Speed and count scale with the Discharge debug setting; the vertical
## speed is the Fluid Y speed setting.
const IDLE_FLUID_SPEED := 0.9
## Ignore the body ellipsoid for this long after a discharge spawn, so a drop leaving the vulva
## flies instead of sticking to the rump and creeping down to the tail.
const IDLE_FLUID_CLEAR_S := 0.2

var controller: Node
var pony: Node3D
var facts: RefCounted

var mesh: MeshInstance3D
var skeleton: Skeleton3D
var bone_inverse := Transform3D.IDENTITY
var mare_bits_path := ""
var attached := false
## The game's dock, cached so detach restores its original visibility.
var dock: MeshInstance3D
var dock_was_visible := true
var fluid_node: Node3D
var last_error := ""

var _visibility_init := false
var _shown := false
var _teats_shown := false
var _strip_shown := false


func setup(controller_node: Node, pony_node: Node3D, facts_node: RefCounted) -> void:
	controller = controller_node
	pony = pony_node
	facts = facts_node


## Load the selected mesh and install it under `pony_hips`. The controller refines the mesh and
## wires placement/shapes/coat/appearance after this returns true.
func attach(selected_path: String) -> bool:
	last_error = ""
	if attached:
		return true
	if not is_instance_valid(pony):
		last_error = "no pony"
		return false
	var skeleton_value: Variant = pony.get("skeleton")
	if not skeleton_value is Skeleton3D:
		last_error = "no skeleton"
		return false
	skeleton = skeleton_value as Skeleton3D
	var bone := skeleton.find_bone("pony_hips")
	if bone < 0:
		last_error = "no pony_hips bone"
		return false
	var scene: PackedScene = load(selected_path)
	if scene == null:
		last_error = "asset missing"
		return false
	var instance: Node = scene.instantiate()
	var found: MeshInstance3D = instance as MeshInstance3D
	if found == null:
		for child: Node in instance.find_children("*", "MeshInstance3D", true, false):
			found = child as MeshInstance3D
			break
	if found == null:
		instance.queue_free()
		last_error = "no mesh in asset"
		return false
	found.owner = null
	if found.get_parent() != null:
		found.get_parent().remove_child(found)
	if instance != found:
		instance.queue_free()
	found.name = ANATOMY_NAME
	var anchor := BoneAttachment3D.new()
	anchor.name = ANCHOR_NAME
	anchor.bone_name = "pony_hips"
	skeleton.add_child(anchor)
	anchor.add_child(found)
	mesh = found
	bone_inverse = skeleton.get_bone_global_rest(bone).affine_inverse()
	mare_bits_path = selected_path
	var dock_value: Variant = pony.find_child(DOCK_NAME, true, false)
	dock = dock_value as MeshInstance3D
	if is_instance_valid(dock):
		dock_was_visible = dock.visible
	attached = true
	_visibility_init = false
	if pony.has_signal("physical_reaction") \
			and not pony.physical_reaction.is_connected(_on_physical_reaction):
		pony.physical_reaction.connect(_on_physical_reaction)
	return true


## Swap the winking mesh in place. The controller keeps the same mesh node, placement, coat and
## appearance; it only has to tell the shape module which is loaded.
func reload_mare_bits(selected_path: String) -> bool:
	if not attached or not is_instance_valid(mesh):
		return false
	if selected_path == mare_bits_path:
		return true
	var scene: PackedScene = load(selected_path)
	if scene == null:
		return false
	var instance: Node = scene.instantiate()
	var source: MeshInstance3D = instance as MeshInstance3D
	if source == null:
		for child: Node in instance.find_children("*", "MeshInstance3D", true, false):
			source = child as MeshInstance3D
			break
	if source == null or source.mesh == null:
		instance.queue_free()
		return false
	var refined: Variant = GEOMETRY.refined_winking_mesh(source.mesh as ArrayMesh)
	instance.queue_free()
	if refined == null:
		return false
	mesh.mesh = refined
	mare_bits_path = selected_path
	return true


func detach() -> void:
	if is_instance_valid(pony) and pony.has_signal("physical_reaction") \
			and pony.physical_reaction.is_connected(_on_physical_reaction):
		pony.physical_reaction.disconnect(_on_physical_reaction)
	_apply_dock(false)
	if is_instance_valid(fluid_node):
		fluid_node.queue_free()
	fluid_node = null
	if is_instance_valid(mesh):
		var anchor := mesh.get_parent()
		mesh.queue_free()
		mesh = null
		if is_instance_valid(anchor):
			anchor.queue_free()
	skeleton = null
	bone_inverse = Transform3D.IDENTITY
	mare_bits_path = ""
	attached = false
	_visibility_init = false
	_shown = false
	_teats_shown = false
	_strip_shown = false
	dock = null


func is_attached() -> bool:
	return attached


## True when the current poll has the mesh visible. Far meshes and act-only hiding both skip the
## idle heat display.
func visible() -> bool:
	return _shown


## Re-evaluate the mesh, dock and part visibility. The controller calls this at its visibility
## poll cadence and after attach/settings changes.
func apply_visibility(act_visible: bool) -> void:
	if not attached or not is_instance_valid(pony):
		return
	var far := bool(pony.get("_far_mesh_shown")) if pony.get("_far_mesh_shown") != null else false
	var teats_on := SETTINGS.teats.get_bool()
	var strip_on := SETTINGS.skin_strip.get_bool()
	var show := not far and act_visible
	var teats_show := show and teats_on
	var strip_show := show and strip_on
	if _visibility_init and show == _shown and teats_show == _teats_shown \
			and strip_show == _strip_shown:
		return
	_visibility_init = true
	_shown = show
	_teats_shown = teats_show
	_strip_shown = strip_show
	if is_instance_valid(mesh):
		mesh.visible = show
	_apply_dock(show)
	if is_instance_valid(controller) and controller.has_method("apply_part_visibility"):
		controller.call("apply_part_visibility", show, teats_on, strip_on)


## One persistent fluid node per pony, reused by every act and the idle heat discharge.
func fluid() -> Node3D:
	if not attached or not is_instance_valid(pony):
		return null
	if not is_instance_valid(fluid_node):
		fluid_node = CLIMAX_FLUID.new()
		fluid_node.name = FLUID_NAME
		pony.add_child(fluid_node)
	fluid_node.set("perf_note", facts.perf_note if facts != null else Callable())
	fluid_node.set("skeleton", pony.get("skeleton"))
	fluid_node.set("body_scale",
		float(pony.get("body_scale")) if pony.get("body_scale") != null else 1.0)
	return fluid_node


func idle_discharge(count: int) -> void:
	if not SETTINGS.anatomy_fluid.get_bool():
		return
	if not is_instance_valid(pony) or not pony.is_inside_tree() or not is_instance_valid(mesh):
		return
	var amount := maxf(SETTINGS.drip.get_num(), 0.0)
	if amount <= 0.0:
		return
	var node := fluid()
	if not is_instance_valid(node):
		return
	node.set("ground_y", pony.global_position.y)
	var shots := maxi(1, int(round(float(count) * amount)))
	node.call("spray", _hole_point(), _discharge_direction(), shots,
		IDLE_FLUID_SPEED * amount, maxf(SETTINGS.fluid_size.get_num(), 0.0001),
		IDLE_FLUID_COLOR, IDLE_FLUID_CLEAR_S, SETTINGS.fluid_y_speed.get_num())


func _on_physical_reaction(kind: String) -> void:
	if kind == "flank_smack" and facts != null:
		facts.smack_body_coat()


func _apply_dock(anatomy_shown: bool) -> void:
	if not is_instance_valid(dock):
		return
	if not anatomy_shown:
		dock.visible = dock_was_visible
		return
	# A dock the game hid before anatomy attached (the princesses' fitted body hides it) stays
	# hidden: the anatomy must not re-show a dock the body art does not use.
	dock.visible = dock_was_visible and SETTINGS.show_dock.get_bool()


func _hole_point() -> Vector3:
	if is_instance_valid(controller) and controller.has_method("hole_point"):
		var value: Variant = controller.call("hole_point", 0.0)
		if value is Vector3:
			return value
	return Vector3.ZERO


func _hole_rear() -> Vector3:
	if is_instance_valid(controller) and controller.has_method("hole_rear"):
		var value: Variant = controller.call("hole_rear")
		if value is Vector3:
			return value
	return Vector3.BACK


## Horizontal direction away from the body. The anatomy mesh's own rear axis is used unless it
## points back into the body; the vertical speed comes from the Fluid Y speed setting.
func _discharge_direction() -> Vector3:
	var rear := _hole_rear()
	var out := Vector3(rear.x, 0.0, rear.z)
	if out.length_squared() < 0.000001:
		out = Vector3.BACK
	out = out.normalized()
	if is_instance_valid(pony):
		var away := _hole_point() - pony.global_position
		away.y = 0.0
		if away.length_squared() > 0.000001 and out.dot(away.normalized()) < 0.0:
			out = -out
	return out
