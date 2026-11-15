extends SceneTree
## The pose session facade: the standing and missionary config sync, the bed frame follow, the
## bone snapshots, the modifiers and the pose diagnostics.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/poses/test_session.gd

const SESSION := preload("res://mods/unfplap/poses/service.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")
const ACT_COMMANDS := preload("res://mods/unfplap/shared/act_commands.gd")
const SPECS := preload("res://mods/unfplap/shared/pose_specs.gd")
const POSE_SPEC := preload("res://mods/unfplap/poses/pose_spec.gd")
const TRANSITION_SPEC := preload("res://mods/unfplap/poses/transition_spec.gd")
const AUTHORED := preload("res://mods/unfplap/poses/authored_pose.gd")
const STRETCH := preload("res://mods/unfplap/poses/idle_stretch.gd")
const VIEW := preload("res://mods/unfplap/shared/pose_view.gd")
const POSE := preload("res://mods/unfplap/poses/skeleton_pose.gd")

const STRETCH_FAKE := "res://mods/unfplap/tests/fixtures/idle_stretch_fake.gd"
const STRETCH_MISSING := "res://mods/idle_life/not_a_real_stretch.gd"

var failures := 0
var checks := 0


class FakePony extends Node3D:
	var skeleton: Variant = null
	var hair_skeleton: Variant = null
	var body_scale := 0.66


class FakeActBody extends Node:
	var sink: Array = []

	func apply(_frame: Transform3D, _scale: float) -> void:
		sink.append("anon")

	func remove() -> void:
		sink.append("remove")


## The one field `body_sway` publishes at detach, plus the values a pose request reads.
class FakeFacts extends RefCounted:
	var standing_sway_offset := Vector3.ONE
	var state := 2
	var player_pony := false
	var headset_view := false
	var features: Dictionary = {}


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
	_check_begin_refused()
	_check_standing_begin()
	_check_bed_frame()
	_check_bones()
	_check_diagnostics()
	_check_stretch()
	_check_render_write()
	_check_effective_paths()
	_check_state_machine()
	_check_refusals()
	_check_commands()
	_check_target_snapshot()
	_check_release_abort()
	_check_pose_changed()
	_check_no_act_exit()

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
	var live: Dictionary = session.pose_config
	session._view.settings_group = CATALOG.STANDING
	var applied: bool = session.sync_standing_config({
		"chin_up_deg": 40.0,
		"neck_down_deg": 20.0,
		"tail": {"yaw_deg": 50.0, "pitch_deg": 30.0},
	})
	check(applied, "the standing config applies")
	check(is_same(live, session.pose_config), "the sync keeps the live config object")
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
	check(is_same(live, session.pose_config), "an empty presentation keeps the live config object")
	check(near(float(session.pose_config.get("chin_up_deg", 0.0)),
		float(SETTINGS.chin_up_deg.default)), "an empty presentation falls back to the defaults")
	session._view.settings_group = CATALOG.MISSIONARY
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
	var view: RefCounted = session.view()
	check(view != null and is_same(view, session.view()), "the session owns one pose view")
	check(view.id == CATALOG.MISSIONARY, "the begin fills the view pose")
	check(view.family == "bed", "the begin fills the view family")
	check(view.pose_state == VIEW.STEADY, "the begin marks the view steady")
	check(is_same(view.pose_config, session.pose_config),
		"the view shares the session's live config")
	check(session.pose_node.mode == POSE.MODE_SINGLE
		and session.pose_node.from_driver == POSE.MISSIONARY_PATH,
		"the begin takes the single missionary path")
	var live: Dictionary = session.pose_config
	check(is_same(live, session.pose_node.pose_config),
		"the pose node shares the session's config object")
	session.pose_config["oral_pitch"] = 0.4
	check(near(float(session.pose_node.pose_config.get("oral_pitch", 0.0)), 0.4),
		"an in-place anatomy key reaches the pose node")
	session.sync_missionary_config()
	check(is_same(live, session.pose_config) and is_same(live, session.pose_node.pose_config),
		"a live sync keeps the same object on the node")
	check(session.tail_lay != null, "the missionary tail lay is installed")
	check(session.pose_logged == false and session.pose_trace_frames == 0,
		"a fresh session starts its logs clean")
	var tail_lay: Node = session.tail_lay
	var pose_modifier: Node = session.pose_node
	var children := body.get_child_count()
	check(not session.begin({
		"pose_id": CATALOG.MISSIONARY,
		"id": "twilight_sparkle",
		"features": {},
		"bed": null,
		"presentation": {},
		"pose_config": {},
		"look_point": Vector3.ZERO,
		"camera_position": Vector3.INF,
	}), "a second begin is refused")
	check(body.get_child_count() == children, "a refused begin adds no second pose")
	session.leave_pose_start()
	check(session.tail_lay == null, "the pose-start leave frees the tail lay")
	check(tail_lay.get_parent() == null and tail_lay.is_queued_for_deletion(),
		"the tail lay is detached before it is freed")
	session.release_pose()
	check(session.pose_node == null, "the pose release frees the modifier")
	check(pose_modifier.get_parent() == null and pose_modifier.is_queued_for_deletion(),
		"the pose modifier is detached before it is freed")
	session.release_pose()
	check(session.pose_node == null, "a second pose release is a no-op")
	check(session.pose_id == "" and session.id == "",
		"the pose release clears the act identity")
	check(session.features.is_empty(), "the pose release clears the features")
	check(session.pose_config.is_empty(), "the pose release clears the live config")
	check(session.bed_frame == null, "the pose-start leave clears the bed frame")
	check(session.view().id == "" and session.view().pose_state == VIEW.IDLE,
		"the pose release clears the view")
	check(session.view().pose_config.is_empty(), "the pose release drops the view config")
	check(session.view().pose_id == "", "the pose release clears the compatibility id")
	check(str(session.base_info().get("reason", "")) == "pose=",
		"the released session names no pose")
	body.free()
	hair.free()
	pony.free()


## A refused begin installs nothing at all: no body skeleton means no pose and no tail lay.
func _check_begin_refused() -> void:
	var made := _session(CATALOG.MISSIONARY)
	var session: RefCounted = made["session"]
	var pony: FakePony = made["pony"]
	check(not session.begin({
		"pose_id": CATALOG.MISSIONARY,
		"id": "twilight_sparkle",
		"features": {},
		"bed": null,
		"presentation": {},
	}), "a pony without a body skeleton is refused")
	check(not session._started and session.pose_node == null and session.tail_lay == null,
		"a refused begin installs nothing")
	check(session.view().id == "" and session.view().pose_state == VIEW.IDLE,
		"a refused begin leaves the view empty")
	root.remove_child(pony)
	pony.free()


## A standing begin with a bed attached saves no bed frame source: only a missionary frame follows.
func _check_standing_begin() -> void:
	var made := _session(CATALOG.STANDING)
	var session: RefCounted = made["session"]
	var pony: FakePony = made["pony"]
	var body := Skeleton3D.new()
	body.add_bone("pony_hips")
	pony.skeleton = body
	var bed := Node3D.new()
	root.add_child(bed)
	check(session.begin({
		"pose_id": CATALOG.STANDING,
		"id": "twilight_sparkle",
		"features": {},
		"bed": bed,
		"presentation": {},
		"look_point": Vector3.ZERO,
		"camera_position": Vector3.INF,
	}), "the standing begin succeeds")
	check(not session.bed_frame_source_saved, "a standing begin saves no bed frame source")
	check(session.view().family == "standing" and session.view().pose_state == VIEW.STEADY,
		"the standing begin fills the view")
	session.release_pose()
	root.remove_child(bed)
	bed.free()
	body.free()
	root.remove_child(pony)
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
	session.leave_pose_start()
	check(session.bed_frame == null, "the pose-start leave clears the bed frame")
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
	session.rig_missing_bones = ["poison"]
	var before: int = AUTHORED.revision
	check(AUTHORED.reload_file().is_empty(), "the posed base reloads")
	check(AUTHORED.revision == before + 1, "a reload bumps the asset revision")
	var refreshed: Array = session.rig_missing()
	check(not refreshed.has("poison"), "a reload re-runs the rig check")
	check(int(session.rig_revision) == AUTHORED.revision, "the rig cache records the revision")
	var spare: RefCounted = AUTHORED.new()
	check(str(spare.call("load_file", AUTHORED.PATH)).is_empty(), "a spare asset loads")
	check(int(spare.get("version")) > 0, "the spare asset carries its version")
	check(not str(spare.call("load_file",
		"res://mods/unfplap/tests/fixtures/not_a_pose.txt")).is_empty(),
		"a missing path fails the load")
	check(int(spare.get("version")) == 0, "a failed load reports version 0")
	session.leave_pose_start()
	check(not session.rig_checked, "the pose-start leave clears the rig cache")
	root.remove_child(body)
	body.free()
	root.remove_child(pony)
	pony.free()


## The external Idle Life holder: install order, the body-sway base, removal and fallback.
func _standing_stretch_scene(logs: Array[String]) -> Dictionary:
	var made := _session(CATALOG.STANDING)
	var session: RefCounted = made["session"]
	var pony: FakePony = made["pony"]
	var body := Skeleton3D.new()
	body.name = "Body"
	body.add_bone("pony_hips")
	pony.skeleton = body
	root.add_child(body)
	session.log = func(text: String) -> void: logs.append(text)
	session.begin({
		"pose_id": CATALOG.STANDING,
		"id": "twilight_sparkle",
		"features": {"standing_body_sway": true},
		"bed": null,
		"presentation": {},
		"pose_config": {},
		"look_point": Vector3.ZERO,
		"camera_position": Vector3.INF,
	})
	return {"session": session, "pony": pony, "body": body}


func _stretch_node(body: Skeleton3D) -> Node:
	return body.get_node_or_null("UnfplapIdleStretch")


func _free_stretch_scene(made: Dictionary) -> void:
	var session: RefCounted = made["session"]
	var pony: FakePony = made["pony"]
	var body: Skeleton3D = made["body"]
	session.leave_pose_body()
	session.release_pose()
	if is_instance_valid(body):
		root.remove_child(body)
		body.free()
	root.remove_child(pony)
	pony.free()


func _check_stretch() -> void:
	STRETCH.pose_path = STRETCH_FAKE
	_check_stretch_act()
	_check_stretch_removal()
	_check_stretch_fallback()
	_check_stretch_render()
	_check_stretch_pose_gate()
	STRETCH.pose_path = STRETCH.POSE_PATH


func _check_stretch_act() -> void:
	var logs: Array[String] = []
	var made := _standing_stretch_scene(logs)
	var session: RefCounted = made["session"]
	var pony: FakePony = made["pony"]
	var body: Skeleton3D = made["body"]
	check(is_instance_valid(session.pose_node), "the standing pose node is built")
	check(not bool(session.pose_node.stretch), "a standing act starts in the normal recipe")
	check(is_instance_valid(session.body_sway), "the standing body sway is installed")
	session.body_sway.set("_cached", true)
	session.pose_node.stretch = true
	session.sync_stretch()
	var holder := _stretch_node(body)
	check(holder != null, "a stretch pose installs the external holder")
	check(holder != null and holder.get_index() + 1 == session.pose_node.get_index(),
		"the external holder runs immediately before the pose node")
	check(holder != null and holder.get_index() < session.body_sway.get_index(),
		"body sway still runs after both pose modifiers")
	check(not bool(session.body_sway.get("_cached")),
		"installing the holder resets body sway's cached hips origin")
	check(pony.has_meta(STRETCH.META_IDLE) and pony.has_meta(STRETCH.META_SIDE),
		"the act's holder stores the episode choice")
	_free_stretch_scene(made)


func _check_stretch_removal() -> void:
	var logs: Array[String] = []
	var made := _standing_stretch_scene(logs)
	var session: RefCounted = made["session"]
	var pony: FakePony = made["pony"]
	var body: Skeleton3D = made["body"]
	session.pose_node.stretch = true
	session.sync_stretch()
	var holder := _stretch_node(body)
	check(holder != null, "the removal check installs a holder")
	session.body_sway.set("_cached", true)
	session.pose_node.stretch = false
	session.sync_stretch()
	check(holder != null and holder.is_queued_for_deletion(), "turning stretch off frees the holder")
	check(not bool(session.body_sway.get("_cached")),
		"removing the holder resets body sway's cached hips origin")
	check(pony.has_meta(STRETCH.META_IDLE),
		"the act's own removal preserves the choice for the next holder")
	var facts := FakeFacts.new()
	session.body_sway.set("facts", facts)
	session.leave_pose_body()
	check(facts.standing_sway_offset == Vector3.ZERO,
		"detaching body sway zeroes the published offset")
	check(pony.has_meta(STRETCH.META_IDLE),
		"the new-act prep preserves the episode choice")
	session.clear_stretch_choice()
	check(not pony.has_meta(STRETCH.META_IDLE) and not pony.has_meta(STRETCH.META_SIDE),
		"the one act teardown clears the episode choice")
	_free_stretch_scene(made)


func _check_stretch_fallback() -> void:
	var logs: Array[String] = []
	STRETCH.pose_path = STRETCH_MISSING
	var made := _standing_stretch_scene(logs)
	var session: RefCounted = made["session"]
	var body: Skeleton3D = made["body"]
	session.pose_node.stretch = true
	session.sync_stretch()
	check(not bool(session.pose_node.stretch),
		"a missing external script turns the act pose back to the normal recipe")
	check(_stretch_node(body) == null, "a missing external script adds no holder")
	var logged := false
	for text: String in logs:
		if text.contains("stretch pose unavailable: idle_life"):
			logged = true
	check(logged, "the fallback logs the reason once")
	STRETCH.pose_path = STRETCH_FAKE
	_free_stretch_scene(made)


func _check_stretch_render() -> void:
	var logs: Array[String] = []
	var made := _standing_stretch_scene(logs)
	var session: RefCounted = made["session"]
	var body: Skeleton3D = made["body"]
	session.pose_node.stretch = true
	session.render_write({})
	var holder := _stretch_node(body)
	check(holder != null, "the render-time write watches the standing stretch toggle")
	check(holder != null and holder.get_index() + 1 == session.pose_node.get_index(),
		"the render-time holder keeps the modifier order")
	_free_stretch_scene(made)


func _check_stretch_pose_gate() -> void:
	var logs: Array[String] = []
	var made := _standing_stretch_scene(logs)
	var session: RefCounted = made["session"]
	var body: Skeleton3D = made["body"]
	session._view.family = "bed"
	session.pose_node.stretch = true
	session.sync_stretch()
	check(_stretch_node(body) == null, "a non-standing pose never installs the stretch")
	_free_stretch_scene(made)


## The render-time step: the avatar park, the Anon placement, her pose write and the eye camera, in
## that order, and nothing outside the bed family.
func _check_render_write() -> void:
	var made := _session(CATALOG.MISSIONARY)
	var session: RefCounted = made["session"]
	var pony: FakePony = made["pony"]
	var order: Array[String] = []
	var body := FakeActBody.new()
	body.sink = order
	root.add_child(body)
	session.act_body = body
	session._view.family = "bed"
	session.hide_avatar = func() -> void: order.append("hide")
	session.eye_camera = func() -> void: order.append("eye")
	session.render_write({"bed_frame": Transform3D.IDENTITY,
		"body_scale": 0.66, "eye_camera_active": false})
	check(order == ["hide", "anon"], "the render write parks the avatar and places the Anon body")
	session.render_write({"bed_frame": Transform3D.IDENTITY,
		"body_scale": 0.66, "eye_camera_active": true})
	check(order == ["hide", "anon", "hide", "anon", "eye"],
		"the eye camera runs after the pose write")
	order.clear()
	session._view.family = "standing"
	session.render_write({"eye_camera_active": true})
	check(order.is_empty(), "a standing render write places no Anon body or eye camera")
	session._view.family = "bed"
	session.act_body = null
	session.hide_avatar = Callable()
	session.eye_camera = Callable()
	session.render_write({"eye_camera_active": true})
	check(order.is_empty(), "absent render callbacks are no-ops")
	root.remove_child(body)
	body.free()
	root.remove_child(pony)
	pony.free()


## One live session over a fake pony with a body skeleton and typed facts.
func _live_session(pose: String) -> Dictionary:
	var made := _session(pose)
	var session: RefCounted = made["session"]
	var pony: FakePony = made["pony"]
	var body := Skeleton3D.new()
	body.add_bone("pony_hips")
	pony.skeleton = body
	session.facts = FakeFacts.new()
	check(session.begin({
		"pose_id": pose,
		"id": "twilight_sparkle",
		"features": {},
		"bed": null,
		"presentation": {},
		"pose_config": {},
		"look_point": Vector3.ZERO,
		"camera_position": Vector3.INF,
	}), "the %s pose begins for the request suite" % pose)
	return {"session": session, "pony": pony, "body": body}


func _free_live(made: Dictionary) -> void:
	var session: RefCounted = made["session"]
	session.release_pose()
	var body: Skeleton3D = made["body"]
	if is_instance_valid(body):
		body.free()
	var pony: FakePony = made["pony"]
	if is_instance_valid(pony):
		root.remove_child(pony)
		pony.free()


## The effective driver/delta paths: a row's own driver, its base chain (`standing_test`) and a
## missing row or empty chain.
func _check_effective_paths() -> void:
	var made := _session(CATALOG.STANDING)
	var session: RefCounted = made["session"]
	var pony: FakePony = made["pony"]
	var registry: RefCounted = session._registry
	check(session._effective_driver(registry.spec(CATALOG.STANDING)) == POSE.STANDING_PATH,
		"the standing row resolves its driver")
	check(session._effective_driver(registry.spec(CATALOG.STANDING_TEST)) == POSE.STANDING_PATH,
		"standing_test resolves its base's driver")
	check(session._effective_driver(registry.spec(CATALOG.MISSIONARY)) == POSE.MISSIONARY_PATH,
		"the missionary row resolves its driver")
	check(session._effective_driver(null) == "", "a missing spec resolves no driver")
	check(session._effective_delta(registry.spec(CATALOG.STANDING_TEST)) == "",
		"standing_test carries no delta")
	var chained: Variant = _synthetic_spec(session, "synthetic_chain")
	chained.base = CATALOG.STANDING_TEST
	check(session._effective_driver(chained) == POSE.STANDING_PATH,
		"a base chain resolves the standing driver")
	var orphan: Variant = _synthetic_spec(session, "synthetic_orphan")
	orphan.base = ""
	check(session._effective_driver(orphan) == "",
		"a row without a driver or base resolves empty")
	root.remove_child(pony)
	pony.free()


## The begin state and the forward/reverse debug edge: the request codes, the transition view, the
## status/switch log, completion and the settled target.
func _check_state_machine() -> void:
	var made := _live_session(CATALOG.STANDING)
	var session: RefCounted = made["session"]
	var view: RefCounted = session.view()
	check(view.pose_state == VIEW.STEADY and session._state == VIEW.STEADY,
		"the begin settles the session and the view steady")
	check(view.id == CATALOG.STANDING and view.from_id == CATALOG.STANDING
		and view.to_id == CATALOG.STANDING,
		"the begin fills the start pose on both sides")
	check(view.edge_id == "" and view.weight == 1.0 and session._run == null,
		"the begin starts no edge")
	var pose_node: Node = session.pose_node
	check(pose_node.mode == POSE.MODE_SINGLE
		and pose_node.from_driver == POSE.STANDING_PATH
		and pose_node.to_driver == POSE.STANDING_PATH,
		"the begin resolves both sides to the standing driver")
	var live_config: Dictionary = session.pose_config
	var result: Dictionary = session.request_pose(CATALOG.STANDING_TEST, "test", {"act_state": 2})
	check(bool(result.get("ok", false)) and str(result.get("code", "")) == "ok",
		"the forward debug request is accepted")
	check(str(result.get("edge", "")) == "standing__standing_test",
		"the forward request names the authored edge")
	check(view.pose_state == VIEW.TRANSITIONING and session._state == VIEW.TRANSITIONING,
		"the request enters the transition state")
	check(view.id == CATALOG.STANDING_TEST, "the view follows the requested target")
	check(view.from_id == CATALOG.STANDING and view.to_id == CATALOG.STANDING_TEST,
		"the view carries both transition sides")
	check(view.edge_id == "standing__standing_test" and near(view.edge_t, 0.0),
		"the view carries the live edge and its clock")
	check(near(view.weight, 1.0), "the held base keeps the view fully weighted")
	check(is_same(view.from_config, live_config), "the from side is the live config")
	check(not is_same(view.to_config, live_config), "the to side is a separate target snapshot")
	check(is_same(view.to_config, session._target_config),
		"the view shares the session target snapshot")
	check(view.to_config.has("gaps") and view.to_config.has("chin_up_deg"),
		"the target snapshot uses the standing settings block")
	check(view.to_config.has("neck_down_deg") and view.to_config.has("tail_aside")
		and view.to_config.has("tail_lift"),
		"the target snapshot carries the standing presentation")
	check(_same_config(view.to_config, live_config),
		"the debug target config equals the live standing config")
	check(pose_node.mode == POSE.MODE_SINGLE
		and pose_node.from_driver == POSE.STANDING_PATH
		and pose_node.to_driver == POSE.STANDING_PATH,
		"the debug pair holds the single standing path")
	check(is_same(pose_node._from_config, live_config)
		and is_same(pose_node._to_config, view.to_config),
		"the evaluator keeps the live from config and the target to config")
	check(str(view.presentation.get("profile", "")) == "standing_test",
		"the view carries the target presentation profile")
	check(str(view.controls.get("set", "")) == "standing_test",
		"the view carries the target control set")

	var before_id := str(view.id)
	var before_edge := str(view.edge_id)
	var same_result: Dictionary = session.request_pose(CATALOG.STANDING_TEST, "test", {"act_state": 2})
	check(str(same_result.get("code", "")) == "same", "a second identical request is same")
	var busy_result: Dictionary = session.request_pose(CATALOG.STANDING, "test", {"act_state": 2})
	check(str(busy_result.get("code", "")) == "busy", "a request during an edge is busy")
	check(view.id == before_id and view.edge_id == before_edge,
		"a refused request leaves the view alone")

	var logs: Array[String] = []
	session.log = func(text: String) -> void: logs.append(text)
	session.tick(0.0)
	check(near(view.edge_t, 0.0), "the first tick reads the edge at zero")
	var status_logged := false
	var controls_switch := false
	var presentation_switch := false
	for text: String in logs:
		if text.contains("pose status %s: test" % CATALOG.STANDING_TEST):
			status_logged = true
		if text.contains("pose switch controls: %s" % CATALOG.STANDING_TEST):
			controls_switch = true
		if text.contains("pose switch presentation: %s" % CATALOG.STANDING_TEST):
			presentation_switch = true
	check(status_logged, "the status event is logged")
	check(controls_switch and presentation_switch, "both authored switches are logged")
	view.to_config["adopt_marker"] = 17
	session.tick(0.6)
	check(view.pose_state == VIEW.STEADY and session._state == VIEW.STEADY,
		"the completed edge settles the state steady")
	check(view.id == CATALOG.STANDING_TEST and view.from_id == CATALOG.STANDING_TEST
		and view.to_id == CATALOG.STANDING_TEST,
		"the completed edge keeps the target pose")
	check(view.edge_id == "" and near(view.edge_t, 0.0) and near(view.weight, 1.0),
		"the completed edge clears the clock and restores the weight")
	check(is_same(view.from_config, live_config) and is_same(view.to_config, live_config),
		"the completed edge points both sides at the live config")
	check(int(live_config.get("adopt_marker", 0)) == 17,
		"the complete adopts the target into the live config object")
	check(is_same(session.pose_node.pose_config, live_config),
		"the complete keeps the live config on the pose node")
	check(session.pose_node.mode == POSE.MODE_SINGLE
		and session.pose_node.from_driver == POSE.STANDING_PATH,
		"the completed edge settles the evaluator on the target")
	check(is_same(session.pose_config, live_config) and session.pose_id == CATALOG.STANDING,
		"the live config and the session start pose are untouched")
	live_config.erase("adopt_marker")
	check(session._run == null and session._target_id == "",
		"the completed edge drops the run and the target")
	var before_tick_id := str(view.id)
	session.tick(0.6)
	check(view.id == before_tick_id, "a tick after completion is a no-op")

	var reverse: Dictionary = session.request_pose(CATALOG.STANDING, "test", {"act_state": 2})
	check(str(reverse.get("code", "")) == "ok", "the reverse debug request is accepted")
	check(str(reverse.get("edge", "")) == "standing_test__standing",
		"the reverse request names the reverse edge")
	session.tick(0.0)
	session.tick(0.6)
	check(view.id == CATALOG.STANDING and view.pose_state == VIEW.STEADY,
		"the reverse edge settles back on standing")
	check(session.request_command("thrust"), "the standing control set allows thrust again")
	_free_live(made)


## Every refusal code, in the order the state module reports it, plus the synthetic asset and
## requirement cases the shipped debug pair does not carry.
func _check_refusals() -> void:
	var made := _live_session(CATALOG.STANDING)
	var session: RefCounted = made["session"]
	var view: RefCounted = session.view()
	var same: Dictionary = session.request_pose(CATALOG.STANDING, "test", {"act_state": 2})
	check(str(same.get("code", "")) == "same", "the start pose is same")
	for phase: int in [1, 3, 4, 5]:
		var result: Dictionary = session.request_pose(CATALOG.STANDING_TEST, "test",
			{"act_state": phase})
		check(str(result.get("code", "")) == "bad_phase",
			"act state %d is bad_phase" % phase)
	var no_edge: Dictionary = session.request_pose(CATALOG.MISSIONARY, "test", {"act_state": 2})
	check(str(no_edge.get("code", "")) == "no_edge", "a pair without an edge is no_edge")
	var form: Dictionary = session.request_pose(CATALOG.STANDING_TEST, "test",
		{"act_state": 2, "forms": ["unicorn"]})
	check(str(form.get("code", "")) == "unsupported_form", "an unsupported form refuses")
	var view_result: Dictionary = session.request_pose(CATALOG.STANDING_TEST, "test",
		{"act_state": 2, "views": ["seat"]})
	check(str(view_result.get("code", "")) == "unsupported_view", "an unsupported view refuses")
	var locked: Dictionary = session.request_pose(CATALOG.STANDING_TEST, "test",
		{"act_state": 2, "locked": true})
	check(str(locked.get("code", "")) == "locked", "a locked request refuses")
	check(view.id == CATALOG.STANDING and view.pose_state == VIEW.STEADY,
		"every refusal leaves the view steady on the start pose")
	_free_live(made)

	var fresh_made := _session(CATALOG.STANDING)
	var fresh: RefCounted = fresh_made["session"]
	var fresh_pony: FakePony = fresh_made["pony"]
	fresh.facts = FakeFacts.new()
	var not_steady: Dictionary = fresh.request_pose(CATALOG.STANDING_TEST, "test",
		{"act_state": 2})
	check(str(not_steady.get("code", "")) == "not_steady",
		"a session that has not begun is not_steady")
	root.remove_child(fresh_pony)
	fresh_pony.free()

	var refused_made := _live_session(CATALOG.STANDING)
	var refused: RefCounted = refused_made["session"]
	var refused_view: RefCounted = refused.view()
	for case: Array in [
		["synthetic_feature", {"features": ["missing_feature"]}, {}],
		["synthetic_consent", {"consent": "needed"}, {}],
		["synthetic_stretch", {"stretch": "inactive"}, {"stretch": true}],
	]:
		var target := str(case[0])
		_synthetic_spec(refused, target)
		_synthetic_edge(refused, CATALOG.STANDING, target, case[1] as Dictionary)
		var request: Dictionary = case[2] as Dictionary
		request["act_state"] = 2
		var result: Dictionary = refused.request_pose(target, "test", request)
		check(str(result.get("code", "")) == "refused",
			"the %s requirement refuses" % target)
	check(refused_view.id == CATALOG.STANDING and refused_view.pose_state == VIEW.STEADY,
		"a refused requirement leaves the view steady")
	_free_live(refused_made)

	var missing_made := _live_session(CATALOG.STANDING)
	var missing: RefCounted = missing_made["session"]
	var missing_view: RefCounted = missing.view()
	var missing_spec: Variant = _synthetic_spec(missing, "synthetic_missing")
	missing_spec.base = ""
	missing_spec.delta = ""
	missing_spec.driver = ""
	_synthetic_edge(missing, CATALOG.STANDING, "synthetic_missing", {})
	var missing_result: Dictionary = missing.request_pose("synthetic_missing", "test",
		{"act_state": 2})
	check(str(missing_result.get("code", "")) == "missing_asset",
		"a target without an asset is missing_asset")
	check(missing_view.id == CATALOG.STANDING and missing_view.pose_state == VIEW.STEADY,
		"a missing asset leaves the view steady")
	_free_live(missing_made)


## The real control profiles, the reserved `end`, the edge lock and the standing_test block.
func _check_commands() -> void:
	var made := _live_session(CATALOG.STANDING)
	var session: RefCounted = made["session"]
	for command_id: String in [ACT_COMMANDS.THRUST, ACT_COMMANDS.LEAN, ACT_COMMANDS.CARESS,
			ACT_COMMANDS.KISS, ACT_COMMANDS.ORAL, ACT_COMMANDS.HOLE, ACT_COMMANDS.FINISH,
			ACT_COMMANDS.POSE_BACK, ACT_COMMANDS.POSE_FORWARD, ACT_COMMANDS.END]:
		check(session.request_command(command_id),
			"the standing profile allows %s" % command_id)
	check(session.request_command(ACT_COMMANDS.END), "end is always allowed")
	check(not session.request_command("nonsense"), "an unknown command is refused")
	check(not session.request_command(""), "an empty command is refused")
	var result: Dictionary = session.request_pose(CATALOG.STANDING_TEST, "test", {"act_state": 2})
	check(str(result.get("code", "")) == "ok", "the command check starts the debug edge")
	for command_id: String in [ACT_COMMANDS.THRUST, ACT_COMMANDS.LEAN, ACT_COMMANDS.CARESS,
			ACT_COMMANDS.KISS, ACT_COMMANDS.ORAL, ACT_COMMANDS.HOLE, ACT_COMMANDS.FINISH,
			ACT_COMMANDS.POSE_BACK, ACT_COMMANDS.POSE_FORWARD]:
		check(not session.request_command(command_id),
			"the standing_test profile blocks %s" % command_id)
	check(session.request_command(ACT_COMMANDS.END), "end stays allowed in standing_test")
	_free_live(made)

	var missionary_made := _live_session(CATALOG.MISSIONARY)
	var missionary: RefCounted = missionary_made["session"]
	for command_id: String in [ACT_COMMANDS.THRUST, ACT_COMMANDS.LEAN, ACT_COMMANDS.CARESS,
			ACT_COMMANDS.KISS, ACT_COMMANDS.HOLE, ACT_COMMANDS.FINISH, ACT_COMMANDS.END]:
		check(missionary.request_command(command_id),
			"the missionary profile allows %s" % command_id)
	for command_id: String in [ACT_COMMANDS.ORAL, ACT_COMMANDS.POSE_BACK,
			ACT_COMMANDS.POSE_FORWARD]:
		check(not missionary.request_command(command_id),
			"the missionary profile blocks %s" % command_id)
	_free_live(missionary_made)

	var lock_made := _live_session(CATALOG.STANDING)
	var lock_session: RefCounted = lock_made["session"]
	_synthetic_spec(lock_session, "synthetic_lock", "standing")
	_synthetic_edge(lock_session, CATALOG.STANDING, "synthetic_lock", {},
		{"kind": "lock", "block": ["thrust"]})
	var lock_result: Dictionary = lock_session.request_pose("synthetic_lock", "test",
		{"act_state": 2})
	check(str(lock_result.get("code", "")) == "ok", "the lock edge starts")
	check(not lock_session.request_command(ACT_COMMANDS.THRUST), "the lock block denies thrust")
	check(lock_session.request_command(ACT_COMMANDS.LEAN),
		"the lock leaves a command outside its block allowed")
	check(lock_session.request_command(ACT_COMMANDS.END), "the lock leaves end allowed")
	_free_live(lock_made)


## A live settings edit refreshes the target snapshot in place; `standing_test` never reads a
## settings group of its own.
func _check_target_snapshot() -> void:
	var made := _live_session(CATALOG.STANDING)
	var session: RefCounted = made["session"]
	var view: RefCounted = session.view()
	var result: Dictionary = session.request_pose(CATALOG.STANDING_TEST, "test", {"act_state": 2})
	check(str(result.get("code", "")) == "ok", "the snapshot check starts the debug edge")
	var target: Dictionary = view.to_config
	check(target.has("gaps"), "the target snapshot starts on the standing block")
	check(_same_config(target, session.pose_config),
		"the debug target matches the live standing config")
	session.apply_live_settings()
	check(is_same(view.to_config, target), "a live edit keeps the target snapshot object")
	check(target.has("gaps") and target.has("chin_up_deg") and target.has("neck_down_deg"),
		"the refreshed target still carries the standing pose keys")
	check(is_same(session._target_config, target),
		"the session keeps the same target snapshot")
	_free_live(made)


## A release aborts a live edge; the view goes idle and a second release is a no-op.
func _check_release_abort() -> void:
	var made := _live_session(CATALOG.STANDING)
	var session: RefCounted = made["session"]
	var view: RefCounted = session.view()
	var result: Dictionary = session.request_pose(CATALOG.STANDING_TEST, "test", {"act_state": 2})
	check(str(result.get("code", "")) == "ok", "the abort check starts the debug edge")
	check(session._run != null, "the edge is running")
	session.release_pose()
	check(session._run == null, "the release aborts the edge")
	check(session._state == VIEW.IDLE and view.pose_state == VIEW.IDLE,
		"the release returns the session and the view to idle")
	check(view.id == "" and view.edge_id == "" and view.from_id == "" and view.to_id == "",
		"the release clears the view identity and transition")
	check(not session._started and session.pose_node == null, "the release frees the pose")
	session.release_pose()
	check(view.pose_state == VIEW.IDLE and session._run == null,
		"a second release is a no-op")
	_free_live(made)


## The pose-change hook: a player-body spec leaves the adapter absent, and the act exit clears the
## anatomy handle before it frees the service-owned body.
func _check_pose_changed() -> void:
	var made := _live_session(CATALOG.STANDING)
	var session: RefCounted = made["session"]
	var view: RefCounted = session.view()
	var body := FakeActBody.new()
	session.act_body = body
	var handles: Array = []
	session.set_act_body = func(value: Variant) -> void:
		handles.append(value)
	session.pose_changed(view)
	check(session.act_body == body, "a player-body spec keeps the service-owned body handle")
	check(str(view.anon.get("mode", "")) == "player_body",
		"the standing spec is the player body")
	session.release_pose()
	check(session.act_body == null and body.is_queued_for_deletion(),
		"the final release frees the act body once")
	check(body.sink.has("remove"), "the released body restores the avatar")
	check(handles.size() == 1 and handles[0] == null,
		"the release clears the anatomy handle before the free")
	_free_live(made)


## A live edge aborted by `_end_session` frees the act body once and never calls an act exit from
## the fan-out. The edge request and the pose-change seam keep the session alive.
func _check_no_act_exit() -> void:
	var made := _live_session(CATALOG.STANDING)
	var session: RefCounted = made["session"]
	var view: RefCounted = session.view()
	var pose_node: Node = session.pose_node
	var config: Dictionary = session.pose_config
	var forward: Dictionary = session.request_pose(CATALOG.STANDING_TEST, "test", {"act_state": 2})
	check(str(forward.get("code", "")) == "ok", "the no-exit check starts the debug edge")
	session.tick(0.0)
	session.tick(0.6)
	var reverse: Dictionary = session.request_pose(CATALOG.STANDING, "test", {"act_state": 2})
	check(str(reverse.get("code", "")) == "ok", "the no-exit check returns to standing")
	session.tick(0.0)
	session.tick(0.6)
	check(session.pose_node == pose_node and pose_node.get_parent() != null,
		"the transition path keeps the pose node")
	check(is_same(session.pose_config, config) and not config.is_empty(),
		"the transition path keeps the live config")
	check(session._started, "the transition path keeps the session started")
	check(view.id == CATALOG.STANDING and view.pose_state == VIEW.STEADY,
		"the transition path leaves a filled view")
	_free_live(made)


## Deep config equality for the live and target snapshots.
func _same_config(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for key: Variant in a:
		if not b.has(key):
			return false
		if a[key] is Dictionary and b[key] is Dictionary:
			if not _same_config(a[key] as Dictionary, b[key] as Dictionary):
				return false
		elif a[key] != b[key]:
			return false
	return true


## A synthetic valid spec row for a target the shipped table does not carry.
func _synthetic_spec(session: RefCounted, spec_id: String, controls_set := "standing") -> Variant:
	var row: Dictionary = SPECS.SPECS[CATALOG.STANDING].duplicate(true)
	row["id"] = spec_id
	row["display_name"] = "Synthetic"
	row["base"] = CATALOG.STANDING
	row["delta"] = ""
	row["driver"] = ""
	row["controls"] = {"set": controls_set}
	row["public"] = false
	row["offerable"] = false
	var spec: Variant = POSE_SPEC.from_dict(spec_id, row, {})
	check(spec != null, "the synthetic spec %s builds" % spec_id)
	session._registry._specs[spec_id] = spec
	return spec


## A synthetic validated edge into a synthetic target.
func _synthetic_edge(session: RefCounted, from_id: String, to_id: String, requires: Dictionary,
		controls: Dictionary = {"kind": "switch", "at": 0.0, "set": "standing"}) -> Variant:
	var edge_id := from_id + "__" + to_id
	var document := {
		"version": 1,
		"id": edge_id,
		"from": from_id,
		"to": to_id,
		"phases": ["active"],
		"requires": requires,
		"duration": 0.6,
		"channels": {"base": {"kind": "hold"}, "controls": controls},
		"events": [],
		"interrupt": {"climax": "hold", "teardown": "abort"},
	}
	var edge: Variant = TRANSITION_SPEC.from_dict(edge_id, document, {})
	check(edge != null, "the synthetic edge %s builds" % edge_id)
	session._registry._edges[edge_id] = edge
	return edge
