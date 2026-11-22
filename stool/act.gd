extends RefCounted
## One act's footstool handle: reach rule, case loans, stack lifetime and item return.
## Contract: `docs/stool.md`

const ANATOMY := preload("res://mods/unfplap/anatomy/api.gd")
const WORLD := preload("res://mods/unfplap/world/api.gd")
const GAME := preload("res://mods/unfplap/world/game.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const POSE_SPECS := preload("res://mods/unfplap/shared/pose_specs.gd")
const PLAYER_FORM := preload("res://world/life/player_form.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")
const SERVICE := preload("res://mods/unfplap/stool/service.gd")
const PROP := preload("res://mods/unfplap/stool/prop.gd")

## The world-scope stool facade the session creates this handle from. It holds the settings reads
## and the pure/item calls.
var facade: SERVICE = null
var pony: Node3D = null
var player: Node3D = null
## The world anatomy API; the Anon part comes from its handle.
var anatomy: ANATOMY = null

## Live act state.
var active := false
var lifted := false
var failed := false
var count := 0
var height_m := 0.0
var floor_y := 0.0
## The placed stack record and its body, kept for the release.
var prop: PROP.Stack = null
var node: Node3D = null
var tokens: Array[String] = []
var slots: Array[int] = []

## The hotkey's last pair: the reach need and case count read for one scan. The offer's blocked
## note reads it instead of repeating the reads.
var _hotkey_stool_valid := false
var _hotkey_stool_need := 0
var _hotkey_stool_have := 0


## Bind the scene nodes for this act. The runtime refreshes them on every access, so a suite can
## build a runtime without entering the tree.
func bind(facade_node: SERVICE, pony_node: Node3D, player_node: Node3D,
		anatomy_api: ANATOMY) -> void:
	facade = facade_node
	pony = pony_node
	player = player_node
	anatomy = anatomy_api


## Whether the footstool rule can apply at all: standing desktop human Anon, the feature and the
## anatomy controller online.
func applies() -> bool:
	if facade == null:
		return false
	if not SETTINGS.standing_stool.get_bool():
		return false
	if not SETTINGS.anatomy_on():
		return false
	if not is_instance_valid(WORLD.game) or not is_instance_valid(pony):
		return false
	if not is_instance_valid(player):
		return false
	var tree: SceneTree = pony.get_tree()
	if PLAYER_FORM.is_pony(PLAYER_FORM.active(tree)):
		return false
	if GAME.headset_view(WORLD.game):
		return false
	if anatomy == null:
		return false
	return anatomy.anon().showing() or anatomy.entrance_point(pony).is_finite()


## The live vertical gap: her opening above her hooves against his part above his feet.
## Returns NAN when either body or the anatomy is unavailable.
func gap_m() -> float:
	if not applies():
		return NAN
	var anon := anatomy.anon()
	if not anon.prepare():
		return NAN
	var opening := anatomy.entrance_point(pony)
	var part := anon.root_now()
	if not opening.is_finite() or not part.is_finite():
		return NAN
	return facade.gap(opening.y, pony.global_position.y, part.y, player.global_position.y)


func needed_count() -> int:
	var gap := gap_m()
	if not is_finite(gap) or facade == null:
		return 0
	return maxi(0, facade.needed_count(gap))


func required() -> bool:
	return needed_count() > 0


## Whether the last placement attempt failed. The runtime reads it after a standing start.
func has_failed() -> bool:
	return failed


## The first writable case slot that holds a footstool, or -1.
func case_slot() -> int:
	var store := inventory_store()
	if facade == null or store == null:
		return -1
	if not facade.writable(store):
		return -1
	return facade.case_slot(store)


func case_count() -> int:
	var store := inventory_store()
	if facade == null or store == null:
		return 0
	if not facade.writable(store):
		return 0
	return maxi(0, facade.case_count(store))


## The footstool pair for this call. A non-stool pose returns `(-1, -1)`, which tells the gate to
## skip the row. The pair is kept for `hint_pair()` so the blocked note does not repeat the reads.
func hotkey_pair(pose: String) -> Vector2i:
	if not bool(POSE_SPECS.scene(pose).get("stool", false)):
		return Vector2i(-1, -1)
	_hotkey_stool_need = needed_count()
	_hotkey_stool_have = case_count()
	_hotkey_stool_valid = true
	return Vector2i(_hotkey_stool_need, _hotkey_stool_have)


## The footstool pair this call's gate used, so the blocked standing note does not repeat the
## reach and case reads. Before the first pair it falls back to the live reads.
func hint_pair() -> Dictionary:
	if _hotkey_stool_valid:
		return {"need": _hotkey_stool_need, "have": _hotkey_stool_have}
	return {"need": needed_count(), "have": case_count()}


## True only when the footstool stack is the one thing keeping the Make love hint away.
func blocks_start(reasons: PackedStringArray) -> bool:
	var need := needed_count()
	if need <= 0 or case_count() >= need:
		return false
	if reasons.is_empty():
		return false
	for reason: String in reasons:
		if reason != "needs_stool":
			return false
	return true


func state_text() -> String:
	var store := inventory_store()
	var anatomy_ok := anatomy != null
	var opening := Vector3.INF
	if anatomy_ok:
		opening = anatomy.entrance_point(pony)
	var anon := anatomy.anon() if anatomy != null else null
	var part := Vector3.ZERO
	var part_ok := false
	if anon != null and anon.prepare():
		var value := anon.root_now()
		if value.is_finite():
			part = value
			part_ok = true
	var hoof_y: float = pony.global_position.y if is_instance_valid(pony) else 0.0
	var foot_y: float = player.global_position.y if is_instance_valid(player) else 0.0
	var gap := NAN
	if anatomy_ok and part_ok and facade != null \
			and is_instance_valid(pony) and is_instance_valid(player):
		gap = facade.gap(opening.y, hoof_y, part.y, foot_y)
	var threshold := 0.20
	var height := 0.20
	if facade != null:
		threshold = facade.threshold_m()
		height = facade.height_m()
	var need := needed_count()
	var gap_text := "n/a" if not is_finite(gap) else "%.3f" % gap
	var owned := 0
	var free := 0
	if facade != null and store != null:
		owned = facade.owned_count(store)
		free = facade.free_slots(store)
	return "pony=%s applies=%s anatomy=%s part=%s her_opening=%.3f her_hoof=%.3f her_bits=%.3f his_root=%.3f his_feet=%.3f his_bits=%.3f floor_delta=%.3f gap=%s threshold=%.3f height=%.3f required=%s need=%d active=%s count=%d case=%d owned=%d free=%d" % [
		str(pony.name) if is_instance_valid(pony) else "?",
		str(applies()), str(anatomy_ok), str(part_ok),
		opening.y, hoof_y, opening.y - hoof_y, part.y, foot_y, part.y - foot_y,
		hoof_y - foot_y, gap_text, threshold, height, str(required()),
		need, str(active), count, case_count(), owned, free]


## Check out the case units the start needs. A short or unwritable case returns false and gives
## back what it already took.
func take_items(need: int) -> bool:
	var take := maxi(1, need)
	tokens.clear()
	slots.clear()
	var store := inventory_store()
	if facade == null or store == null or not facade.writable(store):
		return false
	for _i: int in take:
		var slot := facade.case_slot(store)
		if slot < 0:
			release()
			return false
		var token := GAME.case_take(store, slot)
		if token.is_empty():
			release()
			return false
		tokens.append(token)
		slots.append(slot)
	count = take
	active = true
	failed = false
	LOG.debug("stool items taken count=%d", [take])
	return true


## Build the stack under the standing spot and return the raised player target. The runtime owns
## the spot; this only places the prop and reports the lift.
func place(target: Vector3, yaw: float, floor: float) -> Vector3:
	if not active or facade == null:
		return target
	var step := facade.height_m()
	var ignore: PhysicsBody3D = null
	if pony is PhysicsBody3D:
		ignore = pony as PhysicsBody3D
	var built := facade.build_prop(facade, Vector3(target.x, floor, target.z), yaw,
		count, step, ignore)
	if built != null and is_instance_valid(built.node):
		prop = built
		node = built.node
		height_m = built.height
		floor_y = floor
		lifted = true
		LOG.debug("stool placed count=%d height=%.3f floor=%.3f at=%s", [
			count, height_m, floor, str(Vector3(target.x, floor, target.z))])
		return Vector3(target.x, floor + height_m + 0.005, target.z)
	failed = true
	LOG.debug("stool placement failed at=%s", [str(Vector3(target.x, floor, target.z))])
	return target


## Remove the act prop and put every case item back. Every exit path calls this.
func release() -> void:
	var was_active := active or not tokens.is_empty()
	if prop != null and facade != null:
		facade.free_prop(prop)
	elif is_instance_valid(node):
		node.queue_free()
	prop = null
	node = null
	if lifted and is_instance_valid(player):
		var at: Vector3 = player.global_position
		var floor := floor_y
		var candidate := floor_y_at(Vector3(at.x, at.y + 0.2, at.z), player)
		if is_finite(candidate) and absf(candidate - floor_y) < 0.5:
			floor = candidate
		player.global_position = Vector3(at.x, floor + 0.002, at.z)
		if player.get("velocity") != null:
			GAME.set_velocity(player, Vector3.ZERO)
		player.reset_physics_interpolation()
		LOG.debug("stool lowered player floor=%.3f", [floor])
	if not tokens.is_empty():
		var store := inventory_store()
		for i: int in tokens.size():
			var token := tokens[i]
			var slot := slots[i] if i < slots.size() else -1
			var returned := false
			if store != null:
				returned = GAME.case_put(store, token, slot)
				if not returned:
					returned = GAME.case_put(store, token, -1)
			if returned:
				LOG.debug("stool returned count=%d/%d slot=%d", [i + 1, tokens.size(), slot])
			else:
				LOG.debug("stool item restore pending token=%s", [token])
		tokens.clear()
		slots.clear()
	if was_active:
		LOG.debug("stool released")
	active = false
	lifted = false
	failed = false
	count = 0
	height_m = 0.0
	floor_y = 0.0


## A fresh start: release anything a failed previous start left behind.
func reset() -> void:
	if active or not tokens.is_empty() or is_instance_valid(node):
		release()
	active = false
	lifted = false
	failed = false
	tokens.clear()
	slots.clear()
	count = 0
	prop = null
	node = null
	height_m = 0.0
	floor_y = 0.0


## The floor under a standing spot. The player is excluded so his own capsule cannot answer.
func floor_y_at(at: Vector3, body: Node3D) -> float:
	if facade != null:
		return facade.floor_y_at(at, body)
	return NAN


func inventory_store() -> Object:
	return GAME.case_store(GAME.inventory(WORLD.game))



