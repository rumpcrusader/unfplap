extends RefCounted
## Once in a while, when the player and a willing Marefriend are alone in the same house, record
## a short context event so she may speak an offer. Strictly private: any other pony in the house
## or within AI_OFFER_RADIUS_M (including a sleeping pony or a filly/colt) suppresses it.

const HOUSE := preload("res://world/buildings/house_interior.gd")
const AI_OFFER_RADIUS_M := 8.0
const DEBOUNCE_S := 600.0


static func tick(main) -> void:
	if not is_instance_valid(main):
		return
	var game = main.game
	var player = main.player
	if not is_instance_valid(game) or not is_instance_valid(player):
		return
	var tree: SceneTree = main.get_tree()
	if tree == null:
		return
	var house: Node3D = HOUSE.at(tree, player.global_position)
	if house == null:
		return
	var ctx: Variant = game.get("world_context")
	if ctx == null or not is_instance_valid(ctx):
		return
	var section: Dictionary = Mods.state("unfunfunf")
	var offers: Dictionary = section.get("offers", {})
	var now := Time.get_unix_time_from_system()
	var list: Variant = game.get("mares")
	if not list is Array:
		return
	for node: Variant in list:
		if not is_instance_valid(node):
			continue
		var pony: Node3D = node as Node3D
		if pony == null:
			continue
		var runtime: Variant = main.runtime_for(pony)
		if runtime == null or not is_instance_valid(runtime):
			continue
		if not bool(runtime.call("can_offer")):
			continue
		var id := str(pony.get_meta("relationship_id", ""))
		if id.is_empty():
			continue
		if now - float(offers.get(id, -100000.0)) < DEBOUNCE_S:
			continue
		var their_house: Node3D = HOUSE.at(tree, pony.global_position)
		if their_house != house:
			continue
		var blocked := false
		for other: Variant in list:
			if not is_instance_valid(other) or other == pony:
				continue
			var actor: Node3D = other as Node3D
			if actor == null:
				continue
			var other_house: Node3D = HOUSE.at(tree, actor.global_position)
			if other_house == house or actor.global_position.distance_to(pony.global_position) <= AI_OFFER_RADIUS_M:
				blocked = true
				break
		if blocked:
			continue
		ctx.record("situation",
			"You are alone in the house with Anon. If you want to, you may offer to have sex.",
			[id], [id], "intimacy_offer_%s_%d" % [id, int(now)])
		offers[id] = now
		section["offers"] = offers
		Mods.save_changed()
		return
