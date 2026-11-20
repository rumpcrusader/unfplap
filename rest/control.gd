extends RefCounted
## Releases a managed bed/couch rest without standing the pony.
## Order matters: the pony_seating entry must go first, or a seated entry whose owner no longer
## matches the navigator calls request_posture("stand") on the next tick.

const GAME := preload("res://mods/unfplap/world/game.gd")


static func release_managed(pony: Node3D) -> bool:
	if not is_instance_valid(pony) or not pony.is_inside_tree():
		return true
	var tree := pony.get_tree()
	if tree == null:
		return true
	if in_sleep_rest(pony):
		return false

	# 1. The seating system owns the actual seat pose and the `seated` meta.
	var seating: Node = tree.get_first_node_in_group("pony_seating")
	if seating != null:
		var id := pony.get_instance_id()
		var users: Variant = seating.get("_users")
		if users is Dictionary and (users as Dictionary).has(id):
			var phase := GAME.seating_phase(seating, id)
			if phase == "climbing":
				return false
			if phase == "approach":
				return false
			GAME.seating_release_entry(seating, id)

	# 2. The shared bed guest or couch occupant entry.
	for node: Variant in tree.get_nodes_in_group("couches"):
		if not is_instance_valid(node):
			continue
		var guest: Variant = node.get("_guest")
		if guest is Dictionary and not (guest as Dictionary).is_empty():
			var actor: Variant = (guest as Dictionary).get("actor")
			if actor == pony:
				GAME.couch_finish_guest(node)
				return true
	for node: Variant in tree.get_nodes_in_group("couches"):
		if not is_instance_valid(node):
			continue
		var id := pony.get_instance_id()
		var ponies: Variant = node.get("_ponies")
		if ponies is Dictionary and (ponies as Dictionary).has(id):
			GAME.couch_release_pony(node, id)
			return true
	return true


static func in_sleep_rest(pony: Node3D) -> bool:
	if not is_instance_valid(pony):
		return true
	if bool(pony.get("sleeping")):
		return true
	var rest: Node = pony.get_node_or_null("CradleRest")
	if rest != null and bool(rest.get("asleep")):
		return true
	return false
