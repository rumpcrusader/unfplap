extends RefCounted
## The bed/couch rest and cuddle rejoin: the bed anchor, the safe placement on the mattress, the
## return to the stock cuddle, the floor beside the bed and the restore posture. The runtime owns
## the act state and the one teardown ledger; this facade owns the scene work.
## Contract: `docs/rest.md`.

const CATALOG := preload("res://mods/unfplap/poses/catalog.gd")
const MATTRESS := preload("res://world/life/couch/mattress.gd")
const COUCH_EXIT := preload("res://world/life/couch/exit_space.gd")

const CUDDLE_REJOIN_SETTLE_S := 1.5
const CUDDLE_REJOIN_RETRY_S := 0.5
const CUDDLE_REJOIN_WINDOW_S := 30.0
const STATE_IDLE := 0

## Scene handles. The runtime binds them on every access.
var main: Variant = null
var pony: Variant = null
var bed: Variant = null

## Host boundary. `context` returns the live act values the decisions need; `restore_scene`
## returns the pre-act player/pony/camera snapshot. A missing callback is a no-op.
var context := Callable()
var restore_scene := Callable()
var log := Callable()


func bind(main_node: Variant, pony_node: Variant, bed_node: Variant) -> void:
	main = main_node
	pony = pony_node
	bed = bed_node


## Place her on the mattress and settle her upright. Used by the cradle start.
func place_on_bed(anchor: Transform3D) -> void:
	if not is_instance_valid(pony):
		return
	pony.reset_motion(anchor)
	pony.reset_physics_interpolation()
	var tree: SceneTree = pony.get_tree()
	for _i in 3:
		if tree == null:
			break
		await tree.physics_frame
		if not is_instance_valid(pony):
			return
		if act_state() == STATE_IDLE:
			return
		if pony.grounded():
			break
	pony.reset_physics_interpolation()
	if pony.get("posture") != null:
		pony.request_posture("stand")


## The cradle start wants the placement as one step; the runtime keeps the call site.
func place_on_start() -> void:
	await place_on_bed(bed_anchor())


## The place on the mattress: the game's own pony transform for the guest seat when it exists,
## otherwise the mattress top at the side Anon is on.
func bed_anchor() -> Transform3D:
	if not is_instance_valid(pony):
		return Transform3D.IDENTITY
	if is_instance_valid(bed):
		var shared: Variant = shared_bed_rest(bed)
		if shared != null:
			return shared
	var fallback := 0.6
	if is_instance_valid(bed) and bed.has_meta("mattress_top"):
		fallback = float(bed.get_meta("mattress_top"))
	var center: Vector3 = bed.global_position if is_instance_valid(bed) else pony.global_position
	var top: float = center.y
	if is_instance_valid(bed):
		var points: Array[Vector3] = [bed.to_global(Vector3(0.18, 0.0, 0.0)),
			bed.to_global(Vector3(-0.18, 0.0, 0.0))]
		top = MATTRESS.visible_top(bed, points, bed.to_global(Vector3(0.0, fallback, 0.0)).y)
		center = Vector3(bed.global_position.x, top, bed.global_position.z)
	var player: Variant = player_node()
	var player_at: Vector3 = player.global_position if is_instance_valid(player) else pony.global_position
	var side := Vector3.FORWARD
	if is_instance_valid(bed):
		side = bed.global_basis.x
		side.y = 0.0
	if side.length_squared() < 0.0001:
		side = player_at - center
		side.y = 0.0
	side = side.normalized()
	var across := side * signf((player_at - center).dot(side)) * 0.25
	var along: Vector3 = -pony.global_basis.z
	if is_instance_valid(bed):
		along = -bed.global_basis.z
	elif is_instance_valid(player):
		along = -player.global_basis.z
	along.y = 0.0
	if along.length_squared() < 0.0001:
		along = player_at - center
		along.y = 0.0
	along = along.normalized()
	var at: Vector3 = center + across
	at.y = top + 0.02
	return Transform3D(Basis.looking_at(along, Vector3.UP), at)


## The game's own bed-rest place for a pony lying beside Anon. Using it keeps her along the
## mattress (not across it) and on the drawn bedding.
func shared_bed_rest(bed_node: Node3D) -> Variant:
	if not is_instance_valid(bed_node) or not is_instance_valid(pony):
		return null
	var tree: SceneTree = pony.get_tree()
	if tree == null:
		return null
	for node: Node in tree.get_nodes_in_group("couches"):
		if not node is Node3D or node.get("bed_node") != bed_node:
			continue
		if not node.has_method("pony_transform"):
			continue
		var seats: Variant = node.get("seats")
		if not seats is Array or (seats as Array).size() < 2:
			continue
		var rest: Variant = node.call("pony_transform", (seats as Array)[1])
		if not rest is Transform3D:
			continue
		var t: Transform3D = rest
		if t.origin.length_squared() < 0.01 or t.origin.distance_to(bed_node.global_position) > 4.0:
			continue
		return t
	return null


## A normal bed missionary end returns to the cuddle: Anon lies back on the same bed and she is
## invited into its guest seat, where the stock `CuddleSession` picks her up. The act released the
## bed rest and stood both of them, so this is a fresh stock recline and a fresh guest invite. The
## stock closeness rule still decides (she must welcome hugs and be at least a friend), and a bad
## act or an upset mare stays standing. Every failure is logged and leaves her standing.
func rejoin_bed_cuddle(bed_node: Node3D, act_serial: int) -> void:
	if not is_instance_valid(pony) or not is_instance_valid(bed_node):
		return
	var tree: SceneTree = pony.get_tree()
	if tree == null or not pony.is_inside_tree():
		return
	var ctx := context_values()
	if int(ctx.get("serial", -1)) != act_serial:
		return
	var player: Variant = player_node()
	if not is_instance_valid(main) or not is_instance_valid(player):
		return
	if not player.has_method("sit_on") or not player.has_method("toggle_couch_sleep"):
		write_log("cuddle rejoin skipped reason=no_player_rest")
		return
	var rest: Variant = bed_rest_for(bed_node)
	if rest == null:
		write_log("cuddle rejoin skipped reason=no_bed_rest")
		return
	var seats: Variant = rest.get("seats")
	if not seats is Array or (seats as Array).size() < 2:
		write_log("cuddle rejoin skipped reason=no_seats")
		return
	var player_seat: Variant = (seats as Array)[0]
	var guest_seat: Variant = (seats as Array)[1]
	if not player_seat is Node3D or not guest_seat is Node3D:
		write_log("cuddle rejoin skipped reason=no_seats")
		return
	if player.get("seat") != player_seat:
		if not bool(player.call("sit_on", player_seat)):
			write_log("cuddle rejoin failed reason=sit")
			return
	if not bool(player.get_meta("couch_sleeping", false)):
		if not bool(player.call("toggle_couch_sleep")):
			write_log("cuddle rejoin failed reason=recline")
			return
	# The act restores her still standing on the mattress, and the bed's own front probe rejects a
	# floor half a metre below her feet. Put her on the clear floor beside the bed first.
	stand_beside_bed(rest, guest_seat)
	await tree.create_timer(CUDDLE_REJOIN_SETTLE_S).timeout
	var deadline := Time.get_ticks_msec() + int(CUDDLE_REJOIN_WINDOW_S * 1000.0)
	var note := ""
	while Time.get_ticks_msec() < deadline:
		if not pony.is_inside_tree() or not is_instance_valid(pony) \
				or not is_instance_valid(bed_node):
			return
		var live := context_values()
		if int(live.get("serial", -1)) != act_serial or int(live.get("state", -1)) != STATE_IDLE:
			write_log("cuddle rejoin cancelled reason=act")
			return
		if not bool(player.get_meta("couch_sleeping", false)):
			write_log("cuddle rejoin cancelled reason=stood_up")
			return
		if bool(rest.call("open")) and bool(rest.call("invite", pony, guest_seat)):
			write_log("cuddle rejoin invited bed=%s" % str(bed_node.name))
			return
		note = rejoin_note(rest)
		await tree.create_timer(CUDDLE_REJOIN_RETRY_S).timeout
	write_log("cuddle rejoin failed reason=timeout %s" % note)


## The game's live rest that owns this bed (`world/relationships/shared_bed.gd`).
## `shared_bed_rest()` only returns her transform; the rejoin needs the seats and the invite entry.
func bed_rest_for(bed_node: Node3D) -> Variant:
	if not is_instance_valid(bed_node) or not is_instance_valid(pony):
		return null
	var tree: SceneTree = pony.get_tree()
	if tree == null:
		return null
	for node: Node in tree.get_nodes_in_group("couches"):
		if not node is Node3D or not node.has_method("invite"):
			continue
		if node.get("_bed") != bed_node and node.get("bed_node") != bed_node:
			continue
		var seats: Variant = node.get("seats")
		if seats is Array and (seats as Array).size() >= 2:
			return node
	return null


## Stand her on the nearest clear floor beside the bed. The act's restore leaves her on the
## mattress, and `shared_bed._front_for()` drops a floor more than half a metre below her feet.
func stand_beside_bed(rest: Node, seat: Node3D) -> void:
	if not is_instance_valid(pony) or not is_instance_valid(seat):
		return
	var profile: Variant = pony.get("profile")
	var clearance := float(profile.get("clearance")) if profile != null else 1.2
	var radius := float(profile.get("radius")) if profile != null else 0.25
	var front: Variant = rest.call("approach", seat)
	var fallback: Vector3 = seat.global_position
	if front is Vector3 and (front as Vector3).is_finite():
		fallback = front
	var at: Vector3 = COUCH_EXIT.find_exit(pony, seat, fallback, clearance, radius)
	if not at.is_finite():
		write_log("cuddle rejoin floor=no_space")
		return
	var pose: Transform3D = pony.global_transform
	pose.origin = at
	var euler: Vector3 = pose.basis.get_euler()
	if absf(euler.x) > 0.01 or absf(euler.z) > 0.01:
		# A support-recovery tilt would fight the collider every tick; keep the facing yaw.
		pose.basis = Basis(Vector3.UP, euler.y) * Basis.from_scale(pose.basis.get_scale())
	pony.reset_motion(pose)
	if pony.get("velocity") != null:
		pony.set("velocity", Vector3.ZERO)
	pony.reset_physics_interpolation()
	write_log("cuddle rejoin floor=%s" % str(at))


## A compact state dump for the timeout line. Read-only: the stock invite stays the authority.
func rejoin_note(rest: Node) -> String:
	var parts := PackedStringArray()
	if is_instance_valid(pony):
		var status: Dictionary = pony.posture_status() if pony.has_method("posture_status") else {}
		parts.append("posture=" + str(status.get("requested", "")))
		parts.append("grounded=" + str(pony.grounded()))
		var nav: Node = pony.get_node_or_null("Navigator")
		if nav != null:
			parts.append("nav=" + str(nav.get("command_owner")))
		var cooldowns: Variant = rest.get("_cooldowns")
		if cooldowns is Dictionary:
			var until := int((cooldowns as Dictionary).get(pony.get_instance_id(), 0))
			var left := until - Time.get_ticks_msec()
			if left > 0:
				parts.append("cooldown=%dms" % left)
	parts.append("fits=" + str(rest.get("_mare_fits")))
	return " ".join(parts)


## A bed missionary end that can return to the cuddle: desktop human Anon at the unforced end of an
## act that did not go badly. With act history off there is no summary, so the aftercare readiness
## rule is the fallback.
func rejoin_wanted(values: Dictionary) -> bool:
	if bool(values.get("player_pony", false)) or bool(values.get("headset", false)):
		return false
	if not is_instance_valid(main) or not is_instance_valid(player_node()):
		return false
	var summary: Variant = values.get("summary", {})
	if summary is Dictionary and not (summary as Dictionary).is_empty():
		return str((summary as Dictionary).get("grade", "neutral")) != "bad"
	return float(values.get("satisfaction", 0.0)) >= float(values.get("aftercare_min", 10))


## Give the bed back: restore the pre-act scene and stand her. A bed missionary act that ended well
## is re-seated and re-invited by `rejoin_bed_cuddle()` after the session is fully back to IDLE.
func restore_posture(pose_id: String, _rejoin_cuddle: bool) -> void:
	if not is_instance_valid(pony):
		return
	# The act's own snapshot puts the player, the pony and the camera back, so the rejoin starts
	# from the same standing spot the act began at.
	if pose_id == CATALOG.MISSIONARY and restore_scene.is_valid():
		restore_scene.call()
	if pony.get("posture") != null:
		pony.request_posture("stand")


func player_node() -> Variant:
	return main.player if is_instance_valid(main) else null


func context_values() -> Dictionary:
	if not context.is_valid():
		return {}
	var value: Variant = context.call()
	return value if value is Dictionary else {}


func act_state() -> int:
	return int(context_values().get("state", STATE_IDLE))


func write_log(text: String) -> void:
	if log.is_valid():
		log.call(text)
