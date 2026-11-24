extends Node
## Scope: pony
## Scene work for the bed/couch rest and the cuddle rejoin; the runtime owns the act state.

const WORLD := preload("res://mods/unfplap/world/api.gd")
const ACT_STATE := preload("res://mods/unfplap/shared/act_state.gd")
const BED := preload("res://mods/unfplap/rest/bed.gd")
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
	await place_on_bed(BED.anchor(pony, bed, player_node()))


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
	if not WORLD.ready() or not is_instance_valid(player):
		return
	if not player.has_method("sit_on") or not player.has_method("toggle_couch_sleep"):
		LOG.debug("cuddle rejoin skipped reason=no_player_rest")
		return
	var rest := BED.rest_for(pony, bed_node)
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
	# The stock front probe rejects a floor more than half a metre below her feet, so move her first.
	stand_beside_bed(rest, guest_seat)
	# The snuggle support reads the reclined hip targets; an earlier invite seats her standing.
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
		# The stock accept path treats a social-talk lease as routine and its invite drops the
		# seat argument, so open the bed here and pass the real guest seat.
		if rest.open() and rest.invite(pony, guest_seat):
			LOG.debug("cuddle rejoin invited bed=%s", [str(bed_node.name)])
			return
		note = rejoin_note(rest)
		await tree.create_timer(CUDDLE_REJOIN_RETRY_S).timeout
	LOG.debug("cuddle rejoin failed reason=timeout %s", [note])


## Stand her on clear floor beside the bed; the restore leaves her on the mattress.
func stand_beside_bed(rest: BED.RestState, seat: Node3D) -> void:
	if not is_instance_valid(pony) or not is_instance_valid(seat) or rest == null:
		return
	var profile: Variant = pony.get("profile")
	var clearance := float(profile.get("clearance")) if profile != null else 1.2
	var radius := float(profile.get("radius")) if profile != null else 0.25
	var front := rest.approach(seat)
	var fallback: Vector3 = seat.global_position
	if front.is_finite():
		fallback = front
	var at: Vector3 = WORLD.bed(seat).exit_point(pony, fallback, clearance, radius)
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
		WORLD.set_velocity(pony, Vector3.ZERO)
	pony.reset_physics_interpolation()
	LOG.debug("cuddle rejoin floor=%s", [str(at)])


## A compact state dump for the timeout line. Read-only: the stock invite stays the authority.
func rejoin_note(rest: BED.RestState) -> String:
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
	if not WORLD.ready() or not is_instance_valid(player_node()):
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
	return WORLD.player_rig()


func context_values() -> Context:
	if not context.is_valid():
		return Context.new()
	var value: Variant = context.call()
	return Context.from_dict(value if value is Dictionary else {})


func act_state() -> int:
	var values := context_values()
	return values.state if values.state_known else STATE_IDLE
