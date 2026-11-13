extends SceneTree
## The pose session facade: the standing and missionary config sync, the bed frame follow, the
## bone snapshots, the chin modifier and the pose diagnostics.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/poses/test_session.gd

const SESSION := preload("res://mods/unfplap/poses/service.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")

var failures := 0
var checks := 0


class FakePony extends Node3D:
	var skeleton: Variant = null
	var hair_skeleton: Variant = null
	var body_scale := 0.66


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func near(a: float, b: float, eps := 0.0001) -> bool:
	return absf(a - b) <= eps


func run() -> void:
	_check_config()
	_check_begin()
	_check_bed_frame()
	_check_bones()
	_check_chin()
	_check_diagnostics()
	_check_render_write()

	print("POSE_SESSION_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("POSE_SESSION_PASS")
	quit(0 if failures == 0 else 1)


func _session(pose: String) -> Dictionary:
	var pony := FakePony.new()
	root.add_child(pony)
	var session: RefCounted = SESSION.new()
	session.bind(null, pony)
	session.pose_id = pose
	session.id = "twilight_sparkle"
	return {"session": session, "pony": pony}


func _check_config() -> void:
	var made := _session(CATALOG.STANDING)
	var session: RefCounted = made["session"]
	var pony: FakePony = made["pony"]
	session.set_pose_config({"gaps": {"canon": 0.3}})
	check(near(float(session.pose_config.get("gaps", {}).get("canon", 0.0)), 0.3),
		"the session keeps the base pose config")
	var applied: bool = session.sync_standing_config({
		"chin_up_deg": 40.0,
		"neck_down_deg": 20.0,
		"tail": {"yaw_deg": 50.0, "pitch_deg": 30.0},
	})
	check(applied, "the standing config applies")
	check(near(float(session.pose_config.get("chin_up_deg", 0.0)), 40.0),
		"the presentation chin wins")
	check(near(float(session.pose_config.get("neck_down_deg", 0.0)), 20.0),
		"the presentation neck wins")
	check(near(float(session.pose_config.get("tail_aside", 0.0)), deg_to_rad(50.0)),
		"the presentation tail yaw reaches the pose")
	check(near(float(session.pose_config.get("tail_lift", 0.0)), deg_to_rad(30.0)),
		"the presentation tail pitch reaches the pose")
	check(session.pose_config.has("gaps"), "the character pose overrides survive the sync")
	session.sync_standing_config({})
	check(near(float(session.pose_config.get("chin_up_deg", 0.0)),
		float(SETTINGS.chin_up_deg.default)), "an empty presentation falls back to the defaults")
	session.pose_id = CATALOG.MISSIONARY
	check(not session.sync_standing_config({}), "the missionary pose does not apply standing config")
	var applied_missionary: bool = session.sync_missionary_config()
	check(applied_missionary, "the missionary config applies")
	check(not session.pose_config.is_empty(), "the missionary config re-reads the character pose")
	root.remove_child(pony)
	pony.free()


func _check_begin() -> void:
	var made := _session(CATALOG.MISSIONARY)
	var session: RefCounted = made["session"]
	var pony: FakePony = made["pony"]
	var body := Skeleton3D.new()
	body.add_bone("pony_hips")
	var hair := Skeleton3D.new()
	hair.add_bone("mTail1")
	pony.skeleton = body
	pony.hair_skeleton = hair
	session.begin({
		"pose_id": CATALOG.MISSIONARY,
		"id": "twilight_sparkle",
		"features": {},
		"bed": null,
		"presentation": {},
		"pose_config": {},
		"look_point": Vector3.ZERO,
		"camera_position": Vector3.INF,
	})
	check(is_instance_valid(session.pose_node), "the pose modifier is built")
	check(session.pose_node.get_parent() == body, "the pose modifier rides the body skeleton")
	check(session.pose_node.mode == "missionary", "the posture mode is set")
	check(session.tail_lay != null, "the missionary tail lay is installed")
	check(session.pose_logged == false and session.pose_trace_frames == 0,
		"a fresh session starts its logs clean")
	session.release_start()
	check(session.tail_lay == null, "the pose release frees the tail lay")
	session.release_pose()
	check(session.pose_node == null, "the pose release frees the modifier")
	body.free()
	hair.free()
	pony.free()


func _check_bed_frame() -> void:
	var made := _session(CATALOG.MISSIONARY)
	var session: RefCounted = made["session"]
	var pony: FakePony = made["pony"]
	var bed := Node3D.new()
	root.add_child(bed)
	session.bed_node = bed
	session.bed_frame = Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0))
	session.bed_frame_source = Transform3D.IDENTITY
	session.bed_frame_source_saved = true
	bed.position = Vector3(1.0, 0.0, 0.0)
	session.sync_bed_frame()
	check((session.bed_frame as Transform3D).origin.is_equal_approx(Vector3(1.0, 1.0, 0.0)),
		"the bed frame follows the bed")
	bed.position = Vector3(1.0, 0.0, 0.0)
	session.sync_bed_frame()
	check((session.bed_frame as Transform3D).origin.is_equal_approx(Vector3(1.0, 1.0, 0.0)),
		"a still bed leaves the frame alone")
	session.bed_frame_source_saved = false
	bed.position = Vector3(2.0, 0.0, 0.0)
	session.sync_bed_frame()
	check((session.bed_frame as Transform3D).origin.is_equal_approx(Vector3(1.0, 1.0, 0.0)),
		"an unsaved bed source skips the follow")
	session.release_start()
	check(session.bed_frame == null, "the pose release clears the bed frame")
	root.remove_child(bed)
	bed.free()
	root.remove_child(pony)
	pony.free()


func _check_bones() -> void:
	var made := _session(CATALOG.STANDING)
	var session: RefCounted = made["session"]
	var pony: FakePony = made["pony"]
	var body := Skeleton3D.new()
	body.add_bone("pony_hips")
	body.add_bone("pony_head")
	var hair := Skeleton3D.new()
	hair.add_bone("mPelvis")
	pony.skeleton = body
	pony.hair_skeleton = hair
	root.add_child(body)
	root.add_child(hair)
	body.set_bone_pose_rotation(1, Quaternion(Vector3.RIGHT, 0.5))
	hair.set_bone_pose_rotation(0, Quaternion(Vector3.UP, 0.25))
	session.snapshot_bones()
	body.set_bone_pose_rotation(1, Quaternion.IDENTITY)
	hair.set_bone_pose_rotation(0, Quaternion.IDENTITY)
	session.restore_bones()
	check(body.get_bone_pose_rotation(1).is_equal_approx(Quaternion(Vector3.RIGHT, 0.5)),
		"the body bone snapshot restores")
	check(hair.get_bone_pose_rotation(0).is_equal_approx(Quaternion(Vector3.UP, 0.25)),
		"the hair bone snapshot restores")
	check(session.saved_bones.is_empty() and session.saved_hair.is_empty(),
		"the snapshot clears after the restore")
	root.remove_child(body)
	body.free()
	root.remove_child(hair)
	hair.free()
	root.remove_child(pony)
	pony.free()


func _check_chin() -> void:
	var made := _session(CATALOG.STANDING)
	var session: RefCounted = made["session"]
	var pony: FakePony = made["pony"]
	var body := Skeleton3D.new()
	pony.skeleton = body
	root.add_child(body)
	session.set_chin(12.5)
	check(is_instance_valid(session.chin_modifier), "the chin modifier is created")
	check(near(float(session.chin_modifier.get("chin_deg")), 12.5), "the chin angle applies")
	check(session.chin_modifier.get_parent() == body, "the chin modifier rides the body skeleton")
	session.set_chin(-4.0)
	check(near(float(session.chin_modifier.get("chin_deg")), -4.0), "the chin angle updates")
	check(session.chin_modifier.get_index() == body.get_child_count() - 1,
		"the chin modifier stays last")
	root.remove_child(body)
	body.free()
	root.remove_child(pony)
	pony.free()


func _check_diagnostics() -> void:
	var made := _session(CATALOG.STANDING)
	var session: RefCounted = made["session"]
	var pony: FakePony = made["pony"]
	check(near(session.basis_amount(), 0.0), "a missing pose has no weight")
	var info: Dictionary = session.base_info()
	check(str(info.get("base", "")) == "none", "the base is none outside a missionary act")
	check(str(info.get("reason", "")).begins_with("pose="), "the reason names the pose")
	var rows: Array = session.state_rows(0)
	check(rows.size() >= 3, "the state rows carry the base, frame and scale")
	check(str(rows[0]).contains("pose=standing"), "the state row names the pose")
	var body := Skeleton3D.new()
	pony.skeleton = body
	root.add_child(body)
	var missing: Array = session.rig_missing()
	check(not missing.is_empty(), "a bare rig is missing the authored bones")
	check(str(session.rig_reason(missing)).begins_with("pose_rig: missing"),
		"the rig reason names the missing bones")
	check(session.rig_missing() == missing, "the rig check is cached per skeleton")
	session.release_start()
	check(not session.rig_checked, "the pose release clears the rig cache")
	root.remove_child(body)
	body.free()
	root.remove_child(pony)
	pony.free()


## The render-time step: the Anon placement, her pose write and the eye camera, in that order,
## and nothing outside a missionary act.
func _check_render_write() -> void:
	var made := _session(CATALOG.MISSIONARY)
	var session: RefCounted = made["session"]
	var pony: FakePony = made["pony"]
	var order: Array[String] = []
	session.place_anon = func(_frame: Variant, _scale: float) -> void: order.append("anon")
	session.eye_camera = func() -> void: order.append("eye")
	session.render_write({"pose_id": CATALOG.MISSIONARY, "bed_frame": Transform3D.IDENTITY,
		"body_scale": 0.66, "eye_camera_active": false})
	check(order == ["anon"], "the render write places the Anon body without the eye camera")
	session.render_write({"pose_id": CATALOG.MISSIONARY, "bed_frame": Transform3D.IDENTITY,
		"body_scale": 0.66, "eye_camera_active": true})
	check(order == ["anon", "anon", "eye"], "the eye camera runs after the pose write")
	order.clear()
	session.render_write({"pose_id": CATALOG.STANDING, "eye_camera_active": true})
	check(order.is_empty(), "a standing act has no render write")
	session.place_anon = Callable()
	session.eye_camera = Callable()
	session.render_write({"pose_id": CATALOG.MISSIONARY, "eye_camera_active": true})
	check(order.is_empty(), "absent render callbacks are no-ops")
	root.remove_child(pony)
	pony.free()
