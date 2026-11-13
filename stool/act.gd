extends RefCounted
## One act's footstool state: the live reach rule, the case loans, the placed stack and the player
## lift. The runtime creates one per act and keeps the standing placement decision; this handle
## owns the stack lifetime and the item return. Contract: `docs/stool.md`.

const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const PLAYER_FORM := preload("res://world/life/player_form.gd")

## The global stool facade (`main.stool`). It holds the settings reads and the pure/item calls.
var facade: Variant = null
var main: Variant = null
var pony: Variant = null
var player: Variant = null
## The per-act anatomy controller; the player part comes from the anatomy service.
var anatomy_ctl: Variant = null

## Live act state.
var active := false
var lifted := false
var failed := false
var count := 0
var height_m := 0.0
var floor_y := 0.0
var node: Node3D = null
var tokens: Array[String] = []
var slots: Array[int] = []

## Host boundary. A missing callback is a no-op.
var log := Callable()


## Bind the scene nodes for this act. The runtime refreshes them on every access, so a suite can
## build a runtime without entering the tree.
func bind(facade_node: Variant, main_node: Variant, pony_node: Variant, player_node: Variant,
		anatomy_node: Variant) -> void:
	facade = facade_node
	main = main_node
	pony = pony_node
	player = player_node
	anatomy_ctl = anatomy_node


## Whether the footstool rule can apply at all: standing desktop human Anon, the feature and the
## anatomy controller online.
func applies() -> bool:
	if facade == null:
		return false
	if not SETTINGS.standing_stool.get_bool():
		return false
	if not SETTINGS.anatomy_on():
		return false
	if not is_instance_valid(main) or not is_instance_valid(pony) or not pony is Node3D:
		return false
	if not is_instance_valid(player) or not player is Node3D:
		return false
	var tree: SceneTree = pony.get_tree()
	if PLAYER_FORM.is_pony(PLAYER_FORM.active(tree)):
		return false
	if headset_view():
		return false
	if not is_instance_valid(anatomy_ctl) or not anatomy_ctl.has_method("hole_point"):
		return false
	return true


## The live vertical gap: her opening above her hooves against his part above his feet.
## Returns NAN when either body or the anatomy is unavailable.
func gap_m() -> float:
	if not applies():
		return NAN
	var service: Variant = main.get("anatomy")
	if service == null or not service.has_method("player_prepare") \
			or not service.has_method("player_root_now"):
		return NAN
	if not bool(service.call("player_prepare")):
		return NAN
	var opening: Variant = anatomy_ctl.call("hole_point", 0.0)
	var part: Variant = service.call("player_root_now")
	if not opening is Vector3 or not (opening as Vector3).is_finite():
		return NAN
	if not part is Vector3 or not (part as Vector3).is_finite():
		return NAN
	return float(facade.call("gap", (opening as Vector3).y, pony.global_position.y,
		(part as Vector3).y, player.global_position.y))


func needed_count() -> int:
	var gap := gap_m()
	if not is_finite(gap) or facade == null:
		return 0
	return maxi(0, int(facade.call("needed_count", gap)))


func required() -> bool:
	return needed_count() > 0


## The first writable case slot that holds a footstool, or -1.
func case_slot() -> int:
	var store: Variant = inventory_store()
	if facade == null or store == null:
		return -1
	if not bool(facade.call("writable", store)):
		return -1
	return int(facade.call("case_slot", store))


func case_count() -> int:
	var store: Variant = inventory_store()
	if facade == null or store == null:
		return 0
	if not bool(facade.call("writable", store)):
		return 0
	return maxi(0, int(facade.call("case_count", store)))


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
	var store: Variant = inventory_store()
	var anatomy_ok: bool = is_instance_valid(anatomy_ctl) and anatomy_ctl.has_method("hole_point")
	var opening := Vector3.ZERO
	if anatomy_ok:
		var value: Variant = anatomy_ctl.call("hole_point", 0.0)
		if value is Vector3:
			opening = value
	var service: Variant = main.get("anatomy") if is_instance_valid(main) else null
	var part := Vector3.ZERO
	var part_ok := false
	if service != null and service.has_method("player_prepare") \
			and service.has_method("player_root_now"):
		if bool(service.call("player_prepare")):
			var value: Variant = service.call("player_root_now")
			if value is Vector3 and (value as Vector3).is_finite():
				part = value
				part_ok = true
	var hoof_y: float = pony.global_position.y if is_instance_valid(pony) and pony is Node3D else 0.0
	var foot_y: float = player.global_position.y \
		if is_instance_valid(player) and player is Node3D else 0.0
	var gap := NAN
	if anatomy_ok and part_ok and facade != null \
			and is_instance_valid(pony) and is_instance_valid(player):
		gap = float(facade.call("gap", opening.y, hoof_y, part.y, foot_y))
	var threshold := 0.20
	var height := 0.20
	if facade != null:
		threshold = float(facade.call("threshold_m"))
		height = float(facade.call("height_m"))
	var need := needed_count()
	var gap_text := "n/a" if not is_finite(gap) else "%.3f" % gap
	var owned := 0
	var free := 0
	if facade != null and store != null:
		owned = int(facade.call("owned_count", store))
		free = int(facade.call("free_slots", store))
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
	var store: Variant = inventory_store()
	if facade == null or store == null or not bool(facade.call("writable", store)):
		return false
	for _i: int in take:
		var slot := int(facade.call("case_slot", store))
		if slot < 0:
			release()
			return false
		var token := str(store.call("take", slot))
		if token.is_empty():
			release()
			return false
		tokens.append(token)
		slots.append(slot)
	count = take
	active = true
	failed = false
	write_log("stool items taken count=%d" % take)
	return true


## Build the stack under the standing spot and return the raised player target. The runtime owns
## the spot; this only places the prop and reports the lift.
func place(target: Vector3, yaw: float, floor: float) -> Vector3:
	if not active or facade == null:
		return target
	var step := float(facade.call("height_m"))
	var ignore: PhysicsBody3D = null
	if pony is PhysicsBody3D:
		ignore = pony as PhysicsBody3D
	var built: Dictionary = {}
	if facade.has_method("build_prop"):
		built = facade.call("build_prop", facade, Vector3(target.x, floor, target.z), yaw,
			count, step, ignore)
	var built_node: Variant = built.get("node")
	if built_node is Node3D and is_instance_valid(built_node):
		node = built_node
		height_m = float(built.get("height", 0.0))
		floor_y = floor
		lifted = true
		write_log("stool placed count=%d height=%.3f floor=%.3f at=%s" % [
			count, height_m, floor, str(Vector3(target.x, floor, target.z))])
		return Vector3(target.x, floor + height_m + 0.005, target.z)
	failed = true
	write_log("stool placement failed at=%s" % str(Vector3(target.x, floor, target.z)))
	return target


## Remove the act prop and put every case item back. Every exit path calls this.
func release() -> void:
	var was_active := active or not tokens.is_empty()
	if is_instance_valid(node):
		if facade != null and facade.has_method("free_prop"):
			facade.call("free_prop", node)
		else:
			node.queue_free()
	node = null
	if lifted and is_instance_valid(player) and player is Node3D:
		var at: Vector3 = player.global_position
		var floor := floor_y
		var candidate := floor_y_at(Vector3(at.x, at.y + 0.2, at.z), player)
		if is_finite(candidate) and absf(candidate - floor_y) < 0.5:
			floor = candidate
		player.global_position = Vector3(at.x, floor + 0.002, at.z)
		if player.get("velocity") != null:
			player.set("velocity", Vector3.ZERO)
		player.reset_physics_interpolation()
		write_log("stool lowered player floor=%.3f" % floor)
	if not tokens.is_empty():
		var store: Variant = inventory_store()
		for i: int in tokens.size():
			var token := tokens[i]
			var slot := slots[i] if i < slots.size() else -1
			var returned := false
			if store != null:
				returned = bool(store.call("put", token, slot))
				if not returned:
					returned = bool(store.call("put", token, -1))
			if returned:
				write_log("stool returned count=%d/%d slot=%d" % [i + 1, tokens.size(), slot])
			else:
				write_log("stool item restore pending token=%s" % token)
		tokens.clear()
		slots.clear()
	if was_active:
		write_log("stool released")
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
	node = null
	height_m = 0.0
	floor_y = 0.0


## The floor under a standing spot. The player is excluded so his own capsule cannot answer.
func floor_y_at(at: Vector3, body: Variant) -> float:
	if facade != null and facade.has_method("floor_y_at"):
		return float(facade.call("floor_y_at", at, body))
	return NAN


func inventory_store() -> Variant:
	if not is_instance_valid(main) or not is_instance_valid(main.game):
		return null
	var inventory: Variant = main.game.get("inventory")
	if not is_instance_valid(inventory):
		return null
	return inventory.get("inventory")


func headset_view() -> bool:
	return is_instance_valid(main) and is_instance_valid(main.game) \
		and bool(main.game.get("headset_view"))


func write_log(text: String) -> void:
	if log.is_valid():
		log.call(text)
