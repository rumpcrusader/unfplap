extends RefCounted
## Scene work for the bed/couch rest and the cuddle rejoin; the runtime owns the act state.
## Contract: `docs/rest.md`

const WORLD := preload("res://mods/unfplap/world/api.gd")
const GAME := preload("res://mods/unfplap/world/game.gd")
const MATTRESS := preload("res://world/life/couch/mattress.gd")
const COUCH_EXIT := preload("res://world/life/couch/exit_space.gd")
const ACT_STATE := preload("res://mods/unfplap/shared/act_state.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")

const CUDDLE_REJOIN_SETTLE_S := 1.5
const CUDDLE_REJOIN_RETRY_S := 0.5
const CUDDLE_REJOIN_WINDOW_S := 30.0
const STATE_IDLE := ACT_STATE.State.IDLE

## Scene handles. The runtime binds them on every access.
var pony: Node3D = null
var bed: Node3D = null

## Host boundary. `context` returns the live act values the decisions need; `restore_scene`
## returns the pre-act player/pony/camera snapshot. A missing callback is a no-op.
var context := Callable()
var restore_scene := Callable()


## The live act values one rejoin decision reads; a missing value keeps its absent default.
class Context extends RefCounted:
	var serial := -1
	var state := -1
	var state_known := false
	var player_pony := false
	var headset := false
	var summary_grade := "neutral"
	var summary_known := false
	var satisfaction := 0.0
	var aftercare_min := 10

	static func from_dict(data: Dictionary) -> Context:
		var out := Context.new()
		out.serial = int(data.get("serial", -1))
		if data.has("state"):
			out.state = int(data["state"])
			out.state_known = true
		out.player_pony = bool(data.get("player_pony", false))
		out.headset = bool(data.get("headset", false))
		var summary: Variant = data.get("summary", {})
		if summary is Dictionary and not (summary as Dictionary).is_empty():
			out.summary_known = true
			out.summary_grade = str((summary as Dictionary).get("grade", "neutral"))
		out.satisfaction = float(data.get("satisfaction", 0.0))
		out.aftercare_min = int(data.get("aftercare_min", 10))
		return out


## One resolved game couch rest: the live node the rejoin seats through, or the guest transform a
## bed rest reports. A missing member answers its typed zero.
class RestState extends RefCounted:
	var node: Node3D = null
	var guest := Transform3D(Basis.IDENTITY, Vector3.INF)

	static func of_node(value: Node3D) -> RestState:
		var out := RestState.new()
		out.node = value
		return out

	static func of_guest(value: Transform3D) -> RestState:
		var out := RestState.new()
		out.guest = value
		return out

	func valid() -> bool:
		return is_instance_valid(node)

	func has_guest() -> bool:
		return guest.origin.is_finite() and guest.origin.length_squared() > 0.0

	func seats() -> Array[Node3D]:
		return GAME.couch_seats(node)

	func open() -> bool:
		return GAME.couch_open(node)

	func invite(target: Node3D, seat: Node3D) -> bool:
		return GAME.couch_invite(node, target, seat)

	func approach(seat: Node3D) -> Vector3:
		return GAME.couch_approach(node, seat)

	func mare_fits() -> bool:
		return GAME.couch_mare_fits(node)

	func cooldown_until(target: Node3D) -> int:
		return GAME.couch_cooldown_until(node, target)


func bind(pony_node: Node3D, bed_node: Node3D) -> void:
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
		var shared := shared_bed_rest(bed)
		if shared != null and shared.has_guest():
			return shared.guest
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
	var player: Node3D = player_node()
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
func shared_bed_rest(bed_node: Node3D) -> RestState:
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
		var seats := GAME.couch_seats(node)
		if seats.size() < 2:
			continue
		var rest := GAME.couch_pony_transform(node, seats[1])
		if not rest.origin.is_finite():
			continue
		if rest.origin.length_squared() < 0.01 \
				or rest.origin.distance_to(bed_node.global_position) > 4.0:
			continue
		return RestState.of_guest(rest)
	return null


## Rejoin the stock cuddle after a normal bed end.
## Only once the act is fully IDLE, and a bad act leaves her standing.
func rejoin_bed_cuddle(bed_node: Node3D, act_serial: int) -> void:
	if not is_instance_valid(pony) or not is_instance_valid(bed_node):
		return
	var tree: SceneTree = pony.get_tree()
	if tree == null or not pony.is_inside_tree():
		return
	var ctx := context_values()
	if ctx.serial != act_serial:
		return
	var player: Node3D = player_node()
	if not is_instance_valid(WORLD.game) or not is_instance_valid(player):
		return
	if not player.has_method("sit_on") or not player.has_method("toggle_couch_sleep"):
		LOG.debug("cuddle rejoin skipped reason=no_player_rest")
		return
	var rest := bed_rest_for(bed_node)
	if rest == null:
		LOG.debug("cuddle rejoin skipped reason=no_bed_rest")
		return
	var seats := rest.seats()
	if seats.size() < 2:
		LOG.debug("cuddle rejoin skipped reason=no_seats")
		return
	var player_seat: Node3D = seats[0]
	var guest_seat: Node3D = seats[1]
	if player.get("seat") != player_seat:
		if not WORLD.anon().sit_on(player_seat):
			LOG.debug("cuddle rejoin failed reason=sit")
			return
	if not bool(player.get_meta("couch_sleeping", false)):
		if not WORLD.anon().toggle_couch_sleep():
			LOG.debug("cuddle rejoin failed reason=recline")
			return
	# The front probe won't accept the mattress floor, so move her first.
	stand_beside_bed(rest, guest_seat)
	await tree.create_timer(CUDDLE_REJOIN_SETTLE_S).timeout
	var deadline := Time.get_ticks_msec() + int(CUDDLE_REJOIN_WINDOW_S * 1000.0)
	var note := ""
	while Time.get_ticks_msec() < deadline:
		if not pony.is_inside_tree() or not is_instance_valid(pony) \
				or not is_instance_valid(bed_node):
			return
		var live := context_values()
		if live.serial != act_serial or live.state != STATE_IDLE:
			LOG.debug("cuddle rejoin cancelled reason=act")
			return
		if not bool(player.get_meta("couch_sleeping", false)):
			LOG.debug("cuddle rejoin cancelled reason=stood_up")
			return
		if rest.open() and rest.invite(pony, guest_seat):
			LOG.debug("cuddle rejoin invited bed=%s", [str(bed_node.name)])
			return
		note = rejoin_note(rest)
		await tree.create_timer(CUDDLE_REJOIN_RETRY_S).timeout
	LOG.debug("cuddle rejoin failed reason=timeout %s", [note])


## The game's live rest that owns this bed (`world/relationships/shared_bed.gd`).
## `shared_bed_rest()` only returns her transform; the rejoin needs the seats and the invite entry.
func bed_rest_for(bed_node: Node3D) -> RestState:
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
		if GAME.couch_seats(node).size() >= 2:
			return RestState.of_node(node)
	return null


## Stand her on clear floor beside the bed; the restore leaves her on the mattress.
func stand_beside_bed(rest: RestState, seat: Node3D) -> void:
	if not is_instance_valid(pony) or not is_instance_valid(seat) or rest == null:
		return
	var profile: Variant = pony.get("profile")
	var clearance := float(profile.get("clearance")) if profile != null else 1.2
	var radius := float(profile.get("radius")) if profile != null else 0.25
	var front := rest.approach(seat)
	var fallback: Vector3 = seat.global_position
	if front.is_finite():
		fallback = front
	var at: Vector3 = COUCH_EXIT.find_exit(pony, seat, fallback, clearance, radius)
	if not at.is_finite():
		LOG.debug("cuddle rejoin floor=no_space")
		return
	var pose: Transform3D = pony.global_transform
	pose.origin = at
	var euler: Vector3 = pose.basis.get_euler()
	if absf(euler.x) > 0.01 or absf(euler.z) > 0.01:
		# A support-recovery tilt would fight the collider every tick; keep the facing yaw.
		pose.basis = Basis(Vector3.UP, euler.y) * Basis.from_scale(pose.basis.get_scale())
	pony.reset_motion(pose)
	if pony.get("velocity") != null:
		GAME.set_velocity(pony, Vector3.ZERO)
	pony.reset_physics_interpolation()
	LOG.debug("cuddle rejoin floor=%s", [str(at)])


## A compact state dump for the timeout line. Read-only: the stock invite stays the authority.
func rejoin_note(rest: RestState) -> String:
	var parts := PackedStringArray()
	if is_instance_valid(pony):
		var status: Dictionary = pony.posture_status() if pony.has_method("posture_status") else {}
		parts.append("posture=" + str(status.get("requested", "")))
		parts.append("grounded=" + str(pony.grounded()))
		var nav: Node = pony.get_node_or_null("Navigator")
		if nav != null:
			parts.append("nav=" + str(nav.get("command_owner")))
		var until := rest.cooldown_until(pony) if rest != null else 0
		var left := until - Time.get_ticks_msec()
		if left > 0:
			parts.append("cooldown=%dms" % left)
	parts.append("fits=" + str(rest != null and rest.mare_fits()))
	return " ".join(parts)


## A bed missionary end that can return to the cuddle: desktop human Anon at the unforced end of an
## act that did not go badly. A skipped summary falls back to the aftercare readiness rule.
func rejoin_wanted(values: Context) -> bool:
	if values.player_pony or values.headset:
		return false
	if not is_instance_valid(WORLD.game) or not is_instance_valid(player_node()):
		return false
	if values.summary_known:
		return values.summary_grade != "bad"
	return values.satisfaction >= float(values.aftercare_min)


## Give the bed back: restore the pre-act scene and stand her. A bed missionary act that ended well
## is re-seated and re-invited by `rejoin_bed_cuddle()` after the session is fully back to IDLE.
func restore_posture(frame: String, _rejoin_cuddle: bool) -> void:
	if not is_instance_valid(pony):
		return
	# The act's own snapshot puts the player, the pony and the camera back, so the rejoin starts
	# from the same standing spot the act began at.
	if frame == "bed" and restore_scene.is_valid():
		restore_scene.call()
	if pony.get("posture") != null:
		pony.request_posture("stand")


func player_node() -> Node3D:
	return WORLD.player


func context_values() -> Context:
	if not context.is_valid():
		return Context.new()
	var value: Variant = context.call()
	return Context.from_dict(value if value is Dictionary else {})


func act_state() -> int:
	var values := context_values()
	return values.state if values.state_known else STATE_IDLE
