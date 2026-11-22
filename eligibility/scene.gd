extends RefCounted
## The eligibility service's one scene boundary: a live body by id, or a named shape's identity.
## It is the only eligibility file that reads the world; the service keeps no scene state.

const WORLD := preload("res://mods/unfplap/world/api.gd")
const PONY_ID := preload("res://mods/unfplap/shared/pony_id.gd")

## Shape id -> its scene identity. Cleared with the world.
var _shape_identities: Dictionary = {}


## The world closed: the cached shape identities belonged to it.
func clear() -> void:
	_shape_identities.clear()


## The live body for a shape id, when one is loaded. It is the authority for a provider mod's
## off-roster mare.
func live_pony(id: String) -> Node:
	for pony: Node3D in WORLD.mares():
		if PONY_ID.of(pony) == id:
			return pony
	return null


## The population scene's identity for a shape that is not live. The population's `available`
## map is the catalogue the pack copies from; the scene's root carries its identity resource.
func shape_identity(id: String) -> Resource:
	if _shape_identities.has(id):
		return _shape_identities[id] as Resource
	var identity: Resource = null
	var scene := WORLD.shape_scene(id)
	if scene == null:
		_shape_identities[id] = identity
		return null
	var state := scene.get_state()
	if state.get_node_count() > 0:
		for i in state.get_node_property_count(0):
			if state.get_node_property_name(0, i) == &"identity":
				identity = state.get_node_property_value(0, i) as Resource
				break
	_shape_identities[id] = identity
	return identity
