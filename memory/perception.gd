extends RefCounted
## Scene adapter: the only reader of the witness perception — ponies, awareness, sleeping, the
## house lookup and the age rule (through the eligibility capability answer).

const HOUSE := preload("res://world/buildings/house_interior.gd")
const AWARENESS := preload("res://world/ai/pony_awareness.gd")
const PLAYER_FORM := preload("res://world/life/player_form.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility.gd")
const FACTS := preload("res://mods/unfplap/memory/facts.gd")
const TEXT := preload("res://mods/unfplap/memory/text.gd")


## Adult ponies who can perceive the act right now, plus the sense they used. Read-only: it
## commits nothing. Young ponies are never included.
static func observers(game: Node, service: ELIGIBILITY, partner: Node3D) -> Array:
	var out: Array = []
	if game == null or service == null or not is_instance_valid(partner):
		return out
	if not partner.is_inside_tree():
		return out
	if PLAYER_FORM.is_young(PLAYER_FORM.active(partner.get_tree())):
		return out
	var list: Variant = game.get("mares")
	if not list is Array:
		return out
	var awareness := AWARENESS.new()
	for node: Variant in list:
		if not is_instance_valid(node):
			continue
		var observer: Node3D = node as Node3D
		if observer == null or observer == partner or not observer.is_inside_tree():
			continue
		if bool(observer.get("sleeping")):
			continue
		if service.witness_age(observer) != ELIGIBILITY.Age.ADULT:
			continue
		var observer_id := _pony_id(observer)
		if observer_id.is_empty():
			continue
		var seen := awareness.visible(observer, partner)
		var heard := false if seen else awareness.can_hear(observer, partner, AWARENESS.HEARING_RANGE)
		if not seen and not heard:
			continue
		var row := FACTS.Observer.new()
		row.id = observer_id
		row.node = observer
		row.sense = FACTS.Sense.SIGHT if seen else FACTS.Sense.SOUND
		row.indoors = HOUSE.at(observer.get_tree(), observer.global_position) != null
		out.append(row)
	return out


## One event per observer, private to her (`witnesses = [observer_id]`). Adults are told what it
## was; fillies and colts get a perception with the place they saw it from, and the game's story
## summary infers a memory they could actually hold. Returns the recorded rows for the debug log.
static func witnesses(game: Node, service: ELIGIBILITY, partner_id: String,
		partner_name: String, serial: int, partner: Node3D) -> Array:
	var out: Array = []
	if game == null or service == null or not is_instance_valid(partner):
		return out
	if not partner.is_inside_tree():
		return out
	if PLAYER_FORM.is_young(PLAYER_FORM.active(partner.get_tree())):
		return out
	var list: Variant = game.get("mares")
	if not list is Array:
		return out
	var awareness := AWARENESS.new()
	for node: Variant in list:
		if not is_instance_valid(node):
			continue
		var observer: Node3D = node as Node3D
		if observer == null or observer == partner or not observer.is_inside_tree():
			continue
		if bool(observer.get("sleeping")):
			continue
		var identity: Variant = observer.get("identity")
		if identity == null:
			continue
		var observer_id := _pony_id(observer)
		if observer_id.is_empty():
			continue
		var kind := service.witness_age(observer)
		if kind == ELIGIBILITY.Age.NONE:
			continue
		var young := kind == ELIGIBILITY.Age.YOUNG
		var seen := awareness.visible(observer, partner)
		var heard := false
		if not seen:
			heard = awareness.can_hear(observer, partner, AWARENESS.HEARING_RANGE)
		if not seen and not heard:
			continue
		var indoors: bool = HOUSE.at(observer.get_tree(), observer.global_position) != null
		var place := str(AWARENESS.place_at(observer.global_position).get("id", ""))
		var text := TEXT.witness_text(partner_name, young, indoors, serial)
		var event_id := "witness_%s_%s_%d" % [observer_id, partner_id, serial]
		var ctx: Variant = game.get("world_context")
		if ctx is Node and is_instance_valid(ctx):
			ctx.record(TEXT.witness_kind(young), text, [observer_id], [partner_id, "player"],
				event_id, place)
			var impressions: Variant = ctx.get("impressions")
			if impressions is Node and is_instance_valid(impressions):
				impressions.commit(observer_id,
					TEXT.witness_impression(partner_name, young, indoors), event_id + ":gain")
		var row := FACTS.Witness.new()
		row.id = observer_id
		row.young = young
		row.sense = FACTS.Sense.SIGHT if seen else FACTS.Sense.SOUND
		row.indoors = indoors
		row.distance = observer.global_position.distance_to(partner.global_position)
		row.place = place
		row.text = text
		out.append(row)
	return out


static func _pony_id(observer: Node3D) -> String:
	var id := str(observer.get_meta("relationship_id", ""))
	if not id.is_empty():
		return id
	var identity: Variant = observer.get("identity")
	return str(identity.get("id")) if identity != null else ""
