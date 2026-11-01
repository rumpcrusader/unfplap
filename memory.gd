extends RefCounted
## AI context and impression writes. Every text is short and non-graphic; the event id makes
## both world_context.record and impressions.commit idempotent.

const HOUSE := preload("res://world/buildings/house_interior.gd")
const PLAYER_FORM := preload("res://world/life/player_form.gd")
const SETTINGS := preload("res://mods/unfunfunf/settings.gd")
const WITNESS_RADIUS_M := 8.0


static func start_event(game: Node, id: String, name: String, event_id: String) -> void:
	var ctx = _context(game)
	if ctx == null:
		return
	ctx.record("intimacy", "You and Anon just started having sex.", [id, "player"], [id, "player"], event_id)


static func cancel_event(game: Node, id: String, name: String, event_id: String) -> void:
	var ctx = _context(game)
	if ctx == null:
		return
	ctx.record("intimacy", "You and Anon stopped having sex before you reached climax.", [id, "player"], [id, "player"], event_id + ":cancel")


static func climax_event(game: Node, id: String, name: String, event_id: String) -> void:
	var ctx = _context(game)
	if ctx == null:
		return
	ctx.record("intimacy", "You and Anon just had sex. You reached climax.", [id, "player"], [id, "player"], event_id + ":climax")


## Pose 2 after the climax. Direct: she is told he came inside her.
static func inside_event(game: Node, id: String, name: String, event_id: String) -> void:
	var ctx = _context(game)
	if ctx == null:
		return
	ctx.record("intimacy", "Anon just came inside you.", [id, "player"], [id, "player"], event_id + ":inside")


## One optional spoken reaction to a named act event. A custom per-character prompt is always
## injected; without one, chattiness decides whether the model gets a default nudge.
static func reaction_for(game: Node, id: String, event: String, event_id: String, fallback: String, valid: Callable) -> void:
	var custom := SETTINGS.event_prompt(id, event)
	if custom.is_empty() and randf() >= SETTINGS.chattiness(id):
		return
	if not is_instance_valid(game) or not game.is_inside_tree():
		return
	var director: Node = game.get_tree().get_first_node_in_group("conversation_director")
	if director == null or not director.has_method("queue_generated_intent"):
		return
	var purpose := custom if not custom.is_empty() else fallback
	if event == "climax":
		purpose += " Include a private first-person [thought: ...] impression of this moment in your reply."
	director.call("queue_generated_intent", id, purpose, event_id + ":reply:" + event, valid, Callable(), true)


static func inside_response(game: Node, id: String, event_id: String, valid: Callable) -> void:
	reaction_for(game, id, "inside", event_id,
		"Anon just came inside you. React briefly in your own voice if you want to; staying quiet or staying close is fine. Do not start another act.",
		valid)


static func stop_event(game: Node, id: String, name: String, event_id: String, reason: String) -> void:
	var ctx = _context(game)
	if ctx == null:
		return
	var text := "You and Anon stopped having sex."
	match reason:
		"unwilling":
			text = "You stopped having sex because you no longer wanted to."
		"picked up":
			text = "Anon picked you up, so you stopped having sex."
		"interrupted":
			text = "Your sex with Anon was interrupted."
		"form change":
			text = "Anon changed form, so the sex stopped."
		"world close":
			text = "The world closed during sex with Anon."
	ctx.record("intimacy", text, [id, "player"], [id, "player"], event_id + ":stop:" + reason)


static func commit_climax(game: Node, id: String, name: String, event_id: String) -> void:
	var ctx = _context(game)
	if ctx == null:
		return
	var impressions: Variant = ctx.get("impressions")
	if impressions == null or not is_instance_valid(impressions):
		return
	impressions.commit(id, {
		"romance": 2,
		"mood": "happy"
	}, event_id + ":gain")


static func witnesses(game: Node, partner_id: String, partner_name: String, serial: int, partner: Node3D) -> void:
	var ctx = _context(game)
	if ctx == null or not is_instance_valid(partner) or not is_instance_valid(game):
		return
	var list: Variant = game.get("mares")
	if not list is Array:
		return
	var here: Node3D = HOUSE.at(partner.get_tree(), partner.global_position)
	var young_player: bool = PLAYER_FORM.is_young(PLAYER_FORM.active(partner.get_tree()))
	if young_player:
		return
	for node: Variant in list:
		if not is_instance_valid(node):
			continue
		var observer: Node3D = node as Node3D
		if observer == null or observer == partner:
			continue
		if observer.global_position.distance_to(partner.global_position) > WITNESS_RADIUS_M:
			continue
		if bool(observer.get("sleeping")):
			continue
		var identity: Variant = observer.get("identity")
		if identity == null or bool(identity.get("filly")):
			continue
		var observer_id := str(observer.get_meta("relationship_id", ""))
		if observer_id.is_empty():
			observer_id = str(identity.get("id"))
		if observer_id.is_empty():
			continue
		var runtime: Variant = observer.get_meta("relationship_runtime")
		if runtime == null or not is_instance_valid(runtime):
			continue
		if not bool(runtime.bonds.adults.get(observer_id, false)):
			continue
		var their_house: Node3D = HOUSE.at(observer.get_tree(), observer.global_position)
		var same_house := here != null and their_house == here
		if not same_house and observer.global_position.distance_to(partner.global_position) > WITNESS_RADIUS_M:
			continue
		var event_id := "witness_%s_%s_%d" % [observer_id, partner_id, serial]
		ctx.record("witnessed_intimacy", "You saw Anon and %s having sex." % partner_name,
			[observer_id, "player", partner_id], [partner_id, "player"], event_id)
		var impressions: Variant = ctx.get("impressions")
		if impressions != null and is_instance_valid(impressions):
			impressions.commit(observer_id, {
				"mood": "surprised",
				"thought": "I walked in on Anon and %s." % partner_name
			}, event_id + ":gain")


static func _context(game: Node) -> Node:
	if not is_instance_valid(game):
		return null
	var ctx: Variant = game.get("world_context")
	if ctx is Node and is_instance_valid(ctx):
		return ctx
	return null
