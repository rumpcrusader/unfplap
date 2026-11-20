extends RefCounted
## One act's anatomy bridge: handles, the typed context, the act's bodies and the action gates.
## Contract: `docs/anatomy.md` (`## Act bridge`).

const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility/service.gd")
const FACTS := preload("res://mods/unfplap/anatomy/facts.gd")
const ACT_HOST := preload("res://mods/unfplap/anatomy/act_host.gd")
const VR_ACT := preload("res://mods/unfplap/vr/service.gd")

const ACT_STATE := preload("res://mods/unfplap/shared/act_state.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")
const STATE_ACTIVE := ACT_STATE.State.ACTIVE
const STATE_CLIMAX := ACT_STATE.State.CLIMAX

## The typed host; every callback is optional.
var host: ACT_HOST = null
## The typed per-act context. The persistent controller reads it; the act writes it.
var facts: RefCounted = FACTS.new()
## The persistent anatomy controller, the per-act handle and the act's own bodies.
var controller: Node
var act: Node
## The service-owned missionary Anon body. It is an opaque handle: the bridge calls it and never
## creates or frees it.
var missionary_anon: Node
var vr_act: Node
## The contact family the last pose change carried. The oral contact switch reads it.
var contact_family := ""
var contact_kind := ""
var _contact_seen := false


## Bind the host callbacks. The bridge is created once per act; the runtime re-binds it on every
## access so a suite can build a runtime without entering the tree.
func bind(host_in: ACT_HOST) -> void:
	host = host_in
	facts.perf_note = host.perf_note()
	facts.perf_on = host.perf_enabled()
	facts.log = host.log()
	facts.body_coat_smack = host.body_coat_smack()


## The persistent controller's refresh. The facade owns the service; the bridge only keeps the
## handle. A missing or ineligible controller detaches the old one.
func refresh() -> void:
	var pony: Variant = host.pony()
	if not is_instance_valid(pony):
		_bind_reactions(pony, null)
		return
	var service: Variant = host.anatomy_service()
	var eligibility_service: Variant = host.eligibility_service()
	var target_ok: bool = eligibility_service != null \
		and eligibility_service.call("eligible", pony, ELIGIBILITY.Target.ANATOMY)
	if not SETTINGS.anatomy_on() or not target_ok:
		if service != null and service.has_method("detach_controller"):
			service.call("detach_controller", pony)
		elif is_instance_valid(controller):
			controller.call("detach")
			controller.queue_free()
		controller = null
		_bind_reactions(pony, null)
		return
	if service == null or not service.has_method("controller_for"):
		controller = null
		_bind_reactions(pony, null)
		return
	controller = service.call("controller_for", pony, host.runtime())
	_bind_reactions(pony, controller)
	if is_instance_valid(controller):
		controller.call("refresh")


## Hand the reactions facade her node and the anatomy controller. The facade keeps the scene it
## jiggles and smacks; the runtime's rump anchor and the standing offer read it outside an act.
func _bind_reactions(pony_node: Variant, controller_in: Variant) -> void:
	var reactions: Variant = host.reactions()
	if reactions != null and reactions.has_method("bind_scene"):
		reactions.call("bind_scene", pony_node, controller_in)


## The persistent controller is online. The facade's `controller_for` is the only owner.
func available() -> bool:
	return is_instance_valid(controller)


## The per-act handle is live. The runtime's tick only calls the bridge when it is.
func act_available() -> bool:
	return is_instance_valid(act)


## The pose view the act reads for the mouth contact.
func _mouth_contact() -> bool:
	facts.pose_view = host.pose_view()
	return facts.mouth_contact()


## True while the view names the face contact. The pose service's future face driver reads the
## view; the geometry owner reads this helper.
func _face_contact() -> bool:
	facts.pose_view = host.pose_view()
	return facts.face_contact()


## The per-act handle. The controller's `begin_act` creates it; the bridge resets the facts first.
func begin_act() -> void:
	facts.penetration_m = 0.0
	facts.climaxes = 0
	facts.auto_pace = 1.0
	facts.fluid_ground_y = 0.0
	facts.penetration_reach = 0.2
	sync_facts()
	act = null
	if not is_instance_valid(controller):
		return
	act = controller.call("begin_act")


## Write the live act state the persistent controller polls outside the act. The host supplies
## `state`, `pose_view`, `depth`, `bed_frame` and `cycle_phase`.
func sync_facts() -> void:
	facts.state = host.state()
	facts.pose_view = host.pose_view()
	facts.depth = host.depth()
	facts.bed_frame = host.bed_frame()
	facts.cycle_phase = host.cycle_phase()


## The pose family from the runtime's pose view: `bed` for missionary, `standing` for standing.
func pose_family() -> String:
	facts.pose_view = host.pose_view()
	return facts.family()


## One pose-change hook: carry the view family and contact for the contact switch, without
## rebuilding the controller, the act or the bodies. A shared keep is a cheap no-op.
func pose_changed(view: Variant) -> void:
	if view == null:
		return
	var family := str(view.family)
	var kind := str(view.contact_kind)
	if _contact_seen and family == contact_family and kind == contact_kind:
		return
	_contact_seen = true
	contact_family = family
	contact_kind = kind


## The live context the act reads. The host writes the extra fields; the bridge writes the
## penetration, climax, size and auto values.
func context() -> RefCounted:
	sync_facts()
	facts.penetration_m = host.penetration_m()
	facts.climaxes = host.climaxes()
	facts.size_scale = host.size_scale()
	facts.auto_pace = host.auto_pace()
	facts.fluid_ground_y = host.fluid_ground_y()
	facts.penetration_reach = host.penetration_reach()
	return facts


## Tick the act with this tick's typed context.
func tick(delta: float) -> void:
	if not is_instance_valid(act):
		return
	act.call("tick", delta, context())


## The act's end: the bridge owns the bodies and the VR handle.
## The pose session frees the missionary body; the bridge only restores it.
func end() -> void:
	if is_instance_valid(controller) and controller.has_method("end_act"):
		controller.call("end_act")
	elif is_instance_valid(act):
		act.call("end")
		act.call("teardown")
		act.queue_free()
	act = null
	if is_instance_valid(missionary_anon):
		missionary_anon.call("remove")
	vr_stop()


## The facade's live refresh. The controller owns the settings and identity reads; the facts are
## re-read first so a refresh after the act cannot rebuild the material for the old pose.
func apply_live() -> void:
	sync_facts()
	if is_instance_valid(controller):
		controller.call("apply_live")


## Detach the persistent controller. The world's anatomy service owns the detach.
func detach() -> void:
	var pony: Variant = host.pony()
	var service: Variant = host.anatomy_service()
	if service != null and service.has_method("detach_controller"):
		service.call("detach_controller", pony)
	elif is_instance_valid(controller):
		controller.call("detach")
		controller.queue_free()
	controller = null


## The action gates. The host supplies the state; the bridge reads the settings.
func hole_ready() -> bool:
	return is_instance_valid(act) and host.state() in [STATE_ACTIVE, STATE_CLIMAX] \
		and SETTINGS.anatomy_holes.get_bool() and not _mouth_contact() and not _face_contact()


## The oral gate: open both ways, so N can also request the return edge.
func oral_ready() -> bool:
	return is_instance_valid(act) and host.state() == STATE_ACTIVE \
		and pose_family() == "standing" and SETTINGS.anatomy_oral.get_bool()


func actions_ready() -> bool:
	return hole_ready() or oral_ready()


## Re-assert the oral mouth shape after the base game stopped her speech.
func hold_oral_mouth() -> void:
	if is_instance_valid(act):
		act.call("hold_oral_mouth")


## The edge's viseme event: the D shape, or the clear on contact release.
func set_oral_viseme(letter: String) -> void:
	if is_instance_valid(act):
		act.call("set_oral_viseme", letter)


## The mouth point the pose turn follows once it has settled.
func mouth_point() -> Vector3:
	if not is_instance_valid(act):
		return Vector3.ZERO
	var value: Variant = act.call("oral_mouth_point")
	return value if value is Vector3 and (value as Vector3).is_finite() else Vector3.ZERO


## The act body's mouth point; INF when the body is missing, inactive or non-finite.
func face_point() -> Vector3:
	if not is_instance_valid(missionary_anon) or not bool(missionary_anon.get("active")):
		return Vector3.INF
	var value: Variant = missionary_anon.call("mouth_point")
	return value if value is Vector3 and (value as Vector3).is_finite() else Vector3.INF


func toggle_hole() -> void:
	if is_instance_valid(act):
		act.call("toggle_hole", host.state())


## The oral command: request the standing oral edge, or its return when active.
## Consent rides the call; the edge requirements check the feature, not this.
func toggle_oral(pose: Variant, display_name: String, features_block: Dictionary) -> void:
	var live: Variant = pose.view()
	var from_id := str(live.id) if live != null else ""
	var target := CATALOG.STANDING_ORAL if from_id == CATALOG.STANDING else CATALOG.STANDING
	var request := {}
	var consent := false
	var service: Variant = host.anatomy_service()
	if service != null and service.has_method("consent") and target == CATALOG.STANDING_ORAL:
		consent = bool(service.call("consent", host.pony(), "oral"))
		if consent:
			request["consent"] = "oral"
	request["act_state"] = host.state()
	request["features"] = features_block
	var result: Dictionary = pose.request_pose(target, "oral", request)
	if bool(result.get("ok", false)):
		_write_log("oral pose %s -> %s: ok" % [from_id, target])
		return
	_write_log("oral pose %s -> %s refused: %s (%s)" % [
		from_id, target, str(result.get("code", "")), str(result.get("reason", ""))])
	if target == CATALOG.STANDING_ORAL and not consent:
		status("%s is not into that" % display_name)
	elif service != null:
		status(str(result.get("reason", "")))



## The stock flank smack reaction on the persistent controller.
func react() -> void:
	if is_instance_valid(controller):
		controller.call("react")


## The act's own climax and afterglow hooks.
func on_climax() -> void:
	if is_instance_valid(act):
		act.call("on_climax")


func afterglow_tick(delta: float) -> void:
	if is_instance_valid(act):
		act.call("afterglow_tick", delta, context())


## The act's opening, normal and rear, in world space. The zero vector means the act is absent.
func normal() -> Vector3:
	if not is_instance_valid(act):
		return Vector3.ZERO
	var value: Variant = act.call("opening_normal")
	if value is Vector3 and (value as Vector3).is_finite():
		return value
	return Vector3.ZERO


func opening() -> Vector3:
	if not is_instance_valid(act):
		return Vector3.ZERO
	var value: Variant = act.call("hole_point")
	if value is Vector3 and (value as Vector3).is_finite():
		return value
	return Vector3.ZERO


func rear() -> Vector3:
	if not is_instance_valid(act):
		return Vector3.ZERO
	var value: Variant = act.call("hole_rear")
	if value is Vector3 and (value as Vector3).is_finite():
		return value
	return Vector3.ZERO


## The standing camera's facing override used to live here. It now reads the pose view's
## `facing`/`facing_amount` directly, so the bridge no longer carries a facing path.
func status(text: String, seconds := 2.0) -> void:
	var status_cb: Callable = host.status()
	if status_cb.is_valid():
		status_cb.call(text, seconds)


func _write_log(text: String) -> void:
	if facts.log.is_valid():
		facts.log.call(text)


## The missionary Anon body is the act's own body. The host creates it in the camera mode; the
## bridge owns its handle and the reads.
func set_missionary_anon(node: Variant) -> void:
	missionary_anon = node


func refresh_palm() -> void:
	if is_instance_valid(missionary_anon):
		missionary_anon.call("refresh_palm")


func diag_row(face: Vector3, vulva: Vector3) -> String:
	if is_instance_valid(missionary_anon):
		return str(missionary_anon.call("diag_row", face, vulva))
	return ""


func missionary_anon_body() -> Variant:
	return missionary_anon


func bed_active() -> bool:
	return is_instance_valid(missionary_anon) and bool(missionary_anon.get("active"))


## Her gaze target in missionary: the authored Anon's face. The host supplies the camera and the
## kiss; the bridge supplies the offset and the fallback.
func gaze_point() -> Vector3:
	var camera: Variant = host.missionary_camera()
	if is_instance_valid(missionary_anon) and bool(missionary_anon.get("active")):
		var point: Variant = missionary_anon.call("eye_point")
		if point is Vector3 and (point as Vector3).is_finite():
			var aim: Vector3 = point
			aim.y += SETTINGS.gaze_offset_mm_for(SETTINGS.pony_size_name()) / 1000.0
			if camera != null and camera.has_method("head_look_point_at"):
				return camera.call("head_look_point_at", aim)
	if camera != null and camera.has_method("head_look_point"):
		var kiss: Variant = host.kiss_controller()
		if kiss != null and kiss.has_method("mouth_view"):
			return camera.call("head_look_point", kiss.call("mouth_view"))
	return Vector3.ZERO


## The game's eye modifier still points at the standing player rig. In missionary the pupils
## follow the same gaze target the head solve uses.
func aim_eyes() -> void:
	var pony: Variant = host.pony()
	if not is_instance_valid(pony):
		return
	var target := gaze_point()
	var pose: Variant = host.pose()
	if pose != null and pose.has_method("get"):
		var value: Variant = pose.get("look_point")
		if value is Vector3 and (value as Vector3).is_finite() \
				and (value as Vector3).length_squared() > 0.0001:
			target = value
	if not target.is_finite():
		return
	var eye_motion: Variant = pony.get("eye_motion")
	if eye_motion == null or not is_instance_valid(eye_motion):
		return
	eye_motion.set("target_world", target)
	eye_motion.set("target_weight", 1.0)


## The VR standing controller. The runtime supplies the player scene handles; the bridge owns the
## handle and the headset's forward and depth.
func vr_start() -> void:
	vr_stop()
	var scene: Variant = host.vr_scene()
	if not scene is Dictionary:
		return
	var runtime: Variant = host.runtime()
	if not is_instance_valid(runtime):
		return
	var player: Variant = (scene as Dictionary).get("player")
	var avatar: Variant = (scene as Dictionary).get("avatar")
	var camera: Variant = (scene as Dictionary).get("camera")
	var origin: Variant = (scene as Dictionary).get("origin")
	if not is_instance_valid(player) or not is_instance_valid(avatar) \
			or not is_instance_valid(camera) or not is_instance_valid(origin):
		return
	vr_act = VR_ACT.new()
	vr_act.name = "UnfplapVrAct"
	vr_act.set("bridge", self)
	vr_act.set("align", host.align())
	vr_act.set("touch", host.touch())
	vr_act.set("pony_source", host.pony_callable())
	vr_act.set("command", host.command())
	vr_act.set("player", player)
	vr_act.set("hip_target", (scene as Dictionary).get("hip_target"))
	vr_act.set("camera", camera)
	vr_act.set("origin", origin)
	runtime.add_child(vr_act)


func vr_stop() -> void:
	if is_instance_valid(vr_act):
		vr_act.queue_free()
	vr_act = null


func vr_y_held() -> bool:
	return is_instance_valid(vr_act) and bool(vr_act.get("y_held"))


func vr_forward() -> Vector3:
	if is_instance_valid(act):
		var rear: Vector3 = act.call("hole_rear")
		var forward := Vector3(-rear.x, 0.0, -rear.z).normalized()
		if forward.length_squared() > 0.001:
			return forward
	var pony: Variant = host.pony()
	if is_instance_valid(pony):
		return -pony.global_basis.z.normalized()
	return Vector3.FORWARD


func vr_depth(value: float) -> void:
	if host.state() not in [STATE_ACTIVE, STATE_CLIMAX]:
		return
	var thrust := host.thrust_move()
	if thrust.is_valid():
		thrust.call(value - float(host.depth()), float(host.now_s()))
	var set_penetration := host.set_penetration_m()
	if set_penetration.is_valid():
		set_penetration.call(float(host.depth()) * float(host.penetration_reach()))
