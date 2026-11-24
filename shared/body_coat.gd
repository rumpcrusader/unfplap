extends RefCounted
## The drawn body coat: the mesh and surface the coat shader and the caress should use.
##
## A source body can hide the game's MareBody and draw its own, so the hidden one is never touched;
## this picks the visible coat instead.

const BODY_INCLUDE := "res://world/characters/hybrid_mare/flank_jiggle.gdshaderinc"
## The game coat surface, and the changelings pack's own coat surface.
const BODY_MATERIAL_NAMES := ["MareBody", "cq_Body"]


## The visible body coat for this pony: {mesh, surface, skeleton}, or {} when there is none.
static func resolve(pony: Variant) -> Dictionary:
	if pony == null or not is_instance_valid(pony):
		return {}
	var model: Variant = pony.get("_model")
	if not model is Node or not is_instance_valid(model):
		return {}
	var bodies: Array[MeshInstance3D] = []
	for node: Node in (model as Node).find_children("*", "MeshInstance3D", true, false):
		var body := node as MeshInstance3D
		if not is_instance_valid(body) or body.mesh == null \
				or body.mesh.get_surface_count() == 0 or not body.visible:
			continue
		bodies.append(body)
	# The game body wins while it is the drawn one. Its surface 0 is the body even when a test
	# scene carries no dressing material.
	for body: MeshInstance3D in bodies:
		if String(body.name) != "MareBody":
			continue
		var surface := coat_surface(body)
		return entry(body, maxi(surface, 0), pony)
	# A source body: the drawn coat.
	for body: MeshInstance3D in bodies:
		var surface := coat_surface(body)
		if surface >= 0:
			return entry(body, surface, pony)
	return {}


## One body entry, with the skeleton its skin reads.
static func entry(body: MeshInstance3D, surface: int, pony: Variant) -> Dictionary:
	var sk: Variant = null
	if not body.skeleton.is_empty():
		sk = body.get_node_or_null(body.skeleton)
	if not sk is Skeleton3D and pony != null and is_instance_valid(pony):
		sk = pony.get("skeleton")
	return {"mesh": body, "surface": surface, "skeleton": sk}


## The surface whose material is the game body coat: the coat include, or a coat material name.
static func coat_surface(body: MeshInstance3D) -> int:
	if not is_instance_valid(body) or body.mesh == null:
		return -1
	for i in body.mesh.get_surface_count():
		var source: Variant = body.mesh.surface_get_material(i)
		if source is Material:
			var name := String((source as Material).resource_name)
			if name in BODY_MATERIAL_NAMES:
				return i
	for i in body.mesh.get_surface_count():
		var active: Variant = body.get_active_material(i)
		if active is ShaderMaterial:
			var shader: Variant = (active as ShaderMaterial).shader
			if shader is Shader and (shader as Shader).code.contains(BODY_INCLUDE):
				return i
	return -1
