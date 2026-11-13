extends RefCounted
## One act's anatomy bridge: the persistent controller handle, the per-act handle, the typed
## context, the missionary Anon body, the VR standing controller, the action gates and the
## aim/gaze reads. The runtime creates one per act and keeps the orchestration. Contract:
## `docs/anatomy.md`.

const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")
const ANATOMY := preload("res://mods/unfplap/anatomy/service.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility/service.gd")
const FACTS := preload("res://mods/unfplap/anatomy/facts.gd")
const MISSIONARY_ANON := preload("res://mods/unfplap/poses/missionary_anon.gd")
const VR_ACT := preload("res://mods/unfplap/vr/service.gd")

const STATE_ACTIVE := 2
const STATE_CLIMAX := 3

## The host callbacks. The runtime supplies the scene, the live state and the callbacks; a
## missing callback is a no-op. The bridge never reads the runtime's private fields.
var host: Dictionary = {}
## The typed per-act context. The persistent controller reads it; the act writes it.
var facts: RefCounted = FACTS.new()
## The persistent anatomy controller, the per-act handle and the act's own bodies.
var controller: Node
var act: Node
var missionary_anon: Node
var vr_act: Node


## Bind the host callbacks. The bridge is created once per act; the runtime re-binds it on every
## access so a suite can build a runtime without entering the tree.
func bind(host_in: Dictionary) -> void:
	host = host_in
	facts.perf_note = host.get("perf_note", Callable())
	facts.log = host.get("log", Callable())
	facts.body_coat_smack = host.get("body_coat_smack", Callable())


## The host's live value, or the fallback. The callbacks are the only read path.
func _host(key: String, fallback: Variant = null) -> Variant:
	var value: Variant = host.get(key, null)
	if value is Callable:
		return (value as Callable).call()
	return fallback


## A host callback with arguments. `_host` is for zero-argument reads; this is the raw callable.
func _callback(key: String) -> Callable:
	var value: Variant = host.get(key, null)
	return value as Callable if value is Callable else Callable()


## The persistent controller's refresh. The facade owns the service; the bridge only keeps the
## handle. A missing or ineligible controller detaches the old one.
func refresh() -> void:
	var pony: Variant = _host("pony")
	if not is_instance_valid(pony):
		_bind_reactions(pony, null)
		return
	var service: Variant = _host("anatomy_service")
	var eligibility_service: Variant = _host("eligibility_service")
	var target_ok: bool = eligibility_service != null \
		and eligibility_service.call("eligible", pony, ELIGIBILITY.Target.ANATOMY)
	if not SETTINGS.anatomy_on() or not target_ok or not ANATOMY.assets_exist():
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
	controller = service.call("controller_for", pony, _host("runtime"))
	_bind_reactions(pony, controller)
	if is_instance_valid(controller):
		controller.call("refresh")


## Hand the reactions facade her node and the anatomy controller. The facade keeps the scene it
## jiggles and smacks; the runtime's rump anchor and the standing offer read it outside an act.
func _bind_reactions(pony_node: Variant, controller_in: Variant) -> void:
	var reactions: Variant = _host("reactions")
	if reactions != null and reactions.has_method("bind_scene"):
		reactions.call("bind_scene", pony_node, controller_in)


## The persistent controller is online. The facade's `controller_for` is the only owner.
func available() -> bool:
	return is_instance_valid(controller)


## The per-act handle is live. The runtime's tick only calls the bridge when it is.
func act_available() -> bool:
	return is_instance_valid(act)


## The act's oral state. The controller's act handle owns it.
func anal_active() -> bool:
	return is_instance_valid(act) and bool(act.get("_anal"))


## The pose config the controller's appearance reads. The runtime owns the live config.
func pose_config(cfg: Dictionary) -> void:
	if is_instance_valid(controller):
		controller.call("pose_config", cfg)


## The per-act handle. The controller's `begin_act` creates it; the bridge resets the facts first.
func begin_act(pose_id: String) -> void:
	facts.penetration_m = 0.0
	facts.climaxes = 0
	facts.auto_pace = 1.0
	facts.fluid_ground_y = 0.0
	facts.penetration_reach = 0.2
	sync_facts()
	act = null
	if not is_instance_valid(controller):
		return
	act = controller.call("begin_act", pose_id)


## Write the live act state the persistent controller polls outside the act. The host supplies
## `state`, `pose_id`, `depth`, `bed_frame` and `cycle_phase`.
func sync_facts() -> void:
	facts.state = _host("state", 0)
	facts.pose_id = _host("pose_id", "")
	facts.depth = _host("depth", 0.0)
	facts.bed_frame = _host("bed_frame", null)
	facts.cycle_phase = _host("cycle_phase", "normal")


## The live context the act reads. The host writes the extra fields; the bridge writes the
## penetration, climax, size and auto values.
func context() -> RefCounted:
	sync_facts()
	facts.penetration_m = _host("penetration_m", 0.0)
	facts.climaxes = _host("climaxes", 0)
	facts.size_scale = _host("size_scale", 1.0)
	facts.auto_pace = _host("auto_pace", 1.0)
	facts.fluid_ground_y = _host("fluid_ground_y", 0.0)
	facts.penetration_reach = _host("penetration_reach", 0.2)
	return facts


## Tick the act and apply the oral turn's facing inside the same physics frame.
func tick(delta: float) -> void:
	if not is_instance_valid(act):
		return
	act.call("tick", delta, context())
	apply_facing()


## Apply the oral turn's facing after the act tick. The standing camera owns the facing override.
func apply_facing() -> void:
	if not is_instance_valid(act) or _host("pose_id", "") != CATALOG.STANDING:
		return
	var facing: Variant = act.call("facing")
	if not facing is Dictionary or (facing as Dictionary).is_empty():
		return
	var value: Dictionary = facing
	var basis: Basis = value.get("basis", Basis.IDENTITY)
	var facing_cb: Callable = _callback("anatomy_facing")
	if facing_cb.is_valid():
		facing_cb.call(basis, float(value.get("amount", 0.0)))


## The act's end. The controller owns the act; the bridge owns the bodies and the VR handle.
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
		missionary_anon.queue_free()
		missionary_anon = null
	vr_stop()


## The facade's live refresh. The controller owns the settings and identity reads.
func apply_live() -> void:
	if is_instance_valid(controller):
		controller.call("apply_live")


## Detach the persistent controller. The world's anatomy service owns the detach.
func detach() -> void:
	var pony: Variant = _host("pony")
	var service: Variant = _host("anatomy_service")
	if service != null and service.has_method("detach_controller"):
		service.call("detach_controller", pony)
	elif is_instance_valid(controller):
		controller.call("detach")
		controller.queue_free()
	controller = null


## The action gates. The host supplies the state; the bridge reads the settings.
func hole_ready() -> bool:
	return is_instance_valid(act) and _host("state", 0) in [STATE_ACTIVE, STATE_CLIMAX] \
		and SETTINGS.anatomy_holes.get_bool() \
		and not bool(act.call("oral_active"))


func oral_ready() -> bool:
	return is_instance_valid(act) and _host("state", 0) == STATE_ACTIVE \
		and _host("pose_id", "") == CATALOG.STANDING and SETTINGS.anatomy_oral.get_bool()


func finish_ready() -> bool:
	return is_instance_valid(act) and _host("state", 0) in [STATE_ACTIVE, STATE_CLIMAX] \
		and SETTINGS.anatomy_finish.get_bool()


func actions_ready() -> bool:
	return hole_ready() or oral_ready() or finish_ready()


func oral_active() -> bool:
	return is_instance_valid(act) and bool(act.call("oral_active"))


func finish_pull_out() -> bool:
	return is_instance_valid(act) and bool(act.call("pull_out_selected"))


func toggle_hole() -> void:
	if is_instance_valid(act):
		act.call("toggle_hole", _host("state", 0))


func toggle_oral() -> void:
	if is_instance_valid(act):
		act.call("toggle_oral", _host("state", 0))


func toggle_finish() -> void:
	if is_instance_valid(act):
		act.call("toggle_finish", _host("state", 0))


## The stock flank smack reaction on the persistent controller.
func react() -> void:
	if is_instance_valid(controller):
		controller.call("react")


## The act's own withdrawal, climax, finish and afterglow hooks.
func withdraw() -> void:
	if is_instance_valid(act):
		act.call("withdraw")


func on_climax() -> void:
	if is_instance_valid(act):
		act.call("on_climax")


func on_finish() -> void:
	if is_instance_valid(act):
		act.call("on_finish")


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


## The standing camera's facing override. The host's `anatomy_facing` owns the call.
func facing(basis: Basis, amount: float) -> void:
	var facing_cb: Callable = _callback("anatomy_facing")
	if facing_cb.is_valid():
		facing_cb.call(basis, amount)


## The status label. The host's `anatomy_status` owns the label.
func status(text: String, seconds := 2.0) -> void:
	var status_cb: Callable = _callback("status")
	if status_cb.is_valid():
		status_cb.call(text, seconds)


## The placement debug controls. The controller owns the placement.
func place(op: String, value := 0.0) -> String:
	if not is_instance_valid(controller):
		return "Anatomy is not attached."
	match op:
		"save":
			controller.call("save_place")
		"reset":
			controller.call("reset_place")
		"text":
			return str(controller.call("place_text"))
		_:
			controller.call("nudge", op, value)
	return str(controller.call("place_text"))


## The missionary Anon body is the act's own body. The host creates it in the camera mode; the
## bridge owns its handle and the reads.
func set_missionary_anon(node: Variant) -> void:
	missionary_anon = node


func install_missionary_anon() -> bool:
	if not is_instance_valid(missionary_anon):
		return false
	return bool(missionary_anon.call("install", _host("act_facts")))


func refresh_palm() -> void:
	if is_instance_valid(missionary_anon):
		missionary_anon.call("refresh_palm")


func apply_missionary_anon(frame: Transform3D, body_scale: float) -> void:
	if is_instance_valid(missionary_anon):
		missionary_anon.call("apply", frame, body_scale)


func diag_row(face: Vector3, vulva: Vector3) -> String:
	if is_instance_valid(missionary_anon):
		return str(missionary_anon.call("diag_row", face, vulva))
	return ""


func missionary_anon_body() -> Variant:
	return missionary_anon


func bed_active() -> bool:
	return is_instance_valid(missionary_anon) and bool(missionary_anon.get("active"))


func bed_avatar() -> Variant:
	if is_instance_valid(missionary_anon):
		return missionary_anon.get("avatar")
	return null


## Her gaze target in missionary: the authored Anon's face. The host supplies the camera and the
## kiss; the bridge supplies the offset and the fallback.
func gaze_point() -> Vector3:
	var camera: Variant = _host("missionary_camera")
	if is_instance_valid(missionary_anon) and bool(missionary_anon.get("active")):
		var point: Variant = missionary_anon.call("eye_point")
		if point is Vector3 and (point as Vector3).is_finite():
			var aim: Vector3 = point
			aim.y += SETTINGS.gaze_offset_mm_for(SETTINGS.pony_size_name()) / 1000.0
			if camera != null and camera.has_method("head_look_point_at"):
				return camera.call("head_look_point_at", aim)
	if camera != null and camera.has_method("head_look_point"):
		var kiss: Variant = _host("kiss_controller")
		if kiss != null and kiss.has_method("mouth_view"):
			return camera.call("head_look_point", kiss.call("mouth_view"))
	return Vector3.ZERO


## The game's eye modifier still points at the standing player rig. In missionary the pupils
## follow the same gaze target the head solve uses.
func aim_eyes() -> void:
	var pony: Variant = _host("pony")
	if not is_instance_valid(pony):
		return
	var target := gaze_point()
	var pose: Variant = _host("pose")
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


## The VR standing controller. The host owns the player and the avatar; the bridge owns the
## handle and the headset's forward and depth.
func vr_start() -> void:
	vr_stop()
	var main: Variant = _host("main")
	if not is_instance_valid(main) or not is_instance_valid(main.player):
		return
	var avatar := main.player.find_child("AnonBody", true, false) as Node3D
	if not is_instance_valid(avatar):
		return
	var cameras: Array = main.player.find_children("*", "XRCamera3D", true, false)
	var origins: Array = main.player.find_children("*", "XROrigin3D", true, false)
	if cameras.is_empty() or origins.is_empty():
		return
	var runtime: Variant = _host("runtime")
	if not is_instance_valid(runtime):
		return
	vr_act = VR_ACT.new()
	vr_act.name = "UnfplapVrAct"
	vr_act.set("bridge", self)
	vr_act.set("align", _callback("align"))
	vr_act.set("touch", _callback("touch"))
	vr_act.set("pony_source", _callback("pony"))
	vr_act.set("player", main.player)
	vr_act.set("hip_target", avatar.get("_hip_target"))
	vr_act.set("camera", cameras[0])
	vr_act.set("origin", origins[0])
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
	var pony: Variant = _host("pony")
	if is_instance_valid(pony):
		return -pony.global_basis.z.normalized()
	return Vector3.FORWARD


func vr_depth(value: float) -> void:
	if _host("state", 0) not in [STATE_ACTIVE, STATE_CLIMAX]:
		return
	var thrust := _callback("thrust_move")
	if thrust.is_valid():
		thrust.call(value - float(_host("depth", 0.0)), float(_host("now_s", 0.0)))
	var set_penetration := _callback("set_penetration_m")
	if set_penetration.is_valid():
		set_penetration.call(float(_host("depth", 0.0)) * float(_host("penetration_reach", 0.2)))
