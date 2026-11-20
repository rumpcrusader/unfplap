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
const VIEW := preload("res://mods/unfplap/shared/pose_view.gd")
const ACT_FACTS := preload("res://mods/unfplap/shared/act_facts.gd")
const POSE := preload("res://mods/unfplap/poses/skeleton_pose.gd")


var failures := 0
var checks := 0


class FakePony extends Node3D:
	var skeleton: Variant = null
	var hair_skeleton: Variant = null
	var body_scale := 0.66


class FakeSway extends "res://mods/unfplap/poses/body_sway.gd":
	var calls := 0
	var skeletons: Array = []

	func apply_render(sk: Skeleton3D) -> void:
		calls += 1
		skeletons.append(sk)


class FakeProneSway extends "res://mods/unfplap/poses/prone_sway.gd":
	var calls := 0
	var skeletons: Array = []

	func apply_render(sk: Skeleton3D) -> void:
		calls += 1
		skeletons.append(sk)


class FakeActBody extends "res://mods/unfplap/poses/missionary_anon.gd":
	var sink: Array = []
	var assets: Array = []
	var profiles: Array = []
	var weights: Array = []

	func apply(_frame: Transform3D, _scale: float) -> void:
		sink.append("anon")

	func remove() -> void:
		sink.append("remove")

	func set_pose_assets(from_value: AUTHORED, to_value: AUTHORED, weight: float) -> void:
		assets.append([from_value, to_value, weight])

	func pose_changed(profile := "", weight := 1.0) -> void:
		profiles.append([profile, weight])

	func set_weight(weight: float) -> void:
		weights.append(weight)


## The one field `body_sway` publishes at detach, plus the values a pose request reads.
class FakeFacts extends ACT_FACTS:
	func _init() -> void:
		standing_sway_offset = Vector3.ONE
		state = 2


## The face provider pair for the session edge: his mouth and her opening, mutable per tick.
class FakeFacePoints:
	var mouth := Vector3.ZERO
	var opening := Vector3.ZERO

	func mouth_point() -> Vector3:
		return mouth

	func opening_point() -> Vector3:
		return opening


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func near(a: float, b: float, eps := 0.0001) -> bool:
	return absf(a - b) <= eps


## The plain-document edges the suite builds its typed records through.
func _values(raw: Dictionary) -> SESSION.ActPose:
	return SESSION.ActPose.from_dict(raw)


func _request(raw: Dictionary = {}) -> SESSION.PoseRequest:
	return SESSION.PoseRequest.from_dict(raw)


func _block(raw: Dictionary) -> SESSION.SettingsBlock:
	return SESSION.SettingsBlock.from_dict(raw)


func _flags(raw: Dictionary) -> SESSION.FeatureFlags:
	return SESSION.FeatureFlags.from_dict(raw)


func _render(frame: Transform3D = SESSION.NO_FRAME, scale: float = 1.0,
		size: String = "") -> SESSION.RenderFrame:
	return SESSION.RenderFrame.of(frame, scale, size)


func run() -> void:
	_check_config()
	_check_begin()
	_check_begin_refused()
	_check_standing_begin()
	_check_bed_frame()
	_check_ground_frame()
	_check_bones()
	_check_diagnostics()
	_check_standing_asset()
	_check_missing_standing_asset()
	_check_render_write()
	_check_standing_render_write()
	_check_sway_render_write()
	_check_effective_paths()
	_check_state_machine()
	_check_oral_edge()
	_check_facesit_edge()
	_check_refusals()
	_check_commands()
	_check_target_snapshot()
	_check_settings_group_edge()
	_check_asset_adoption()
	_check_asset_reload()
	_check_release_abort()
	_check_pose_changed()
	_check_anon_pair()
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
	session.id = "twilight_sparkle"
	# A start identity for the diagnostics and bed-frame checks; `begin()` still fills the view.
	var spec: Dictionary = SPECS.spec(pose)
	var view: RefCounted = session.view()
	view.id = pose
	view.family = str(spec.get("family", ""))
	view.frame = str(spec.get("frame", ""))
	view.settings_group = str(spec.get("settings_group", ""))
	return {"session": session, "pony": pony}


func _check_config() -> void:
	var made := _session(CATALOG.STANDING)
	var session: RefCounted = made["session"]
	var pony: FakePony = made["pony"]
	session.set_pose_config(_block({"gaps": {"canon": 0.3}}))
	check(near(float(session.pose_config.get("gaps", {}).get("canon", 0.0)), 0.3),
		"the session keeps the base pose config")
	var live: Dictionary = session.pose_config
	session._view.settings_group = CATALOG.STANDING
	var applied: bool = session.sync_standing_config(_block({
		"chin_up_deg": 40.0,
		"neck_down_deg": 20.0,
		"tail": {"yaw_deg": 50.0, "pitch_deg": 30.0},
	}))
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
	session.sync_standing_config(_block({}))
	check(is_same(live, session.pose_config), "an empty presentation keeps the live config object")
	check(near(float(session.pose_config.get("chin_up_deg", 0.0)),
		float(SETTINGS.chin_up_deg.default)), "an empty presentation falls back to the defaults")
	session._view.settings_group = CATALOG.MISSIONARY
	check(not session.sync_standing_config(_block({})), "the missionary pose does not apply standing config")
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
	session.begin(_values({
		"pose_id": CATALOG.MISSIONARY,
		"id": "twilight_sparkle",
		"features": {},
		"bed": null,
		"presentation": {},
		"pose_config": {},
		"look_point": Vector3.ZERO,
		"camera_position": Vector3.INF,
	}))
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
	check(not session.begin(_values({
		"pose_id": CATALOG.MISSIONARY,
		"id": "twilight_sparkle",
		"features": {},
		"bed": null,
		"presentation": {},
		"pose_config": {},
		"look_point": Vector3.ZERO,
		"camera_position": Vector3.INF,
	})), "a second begin is refused")
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
	check(session.id == "",
		"the pose release clears the act identity")
	check(session.features.flags.is_empty(), "the pose release clears the features")
	check(session.pose_config.is_empty(), "the pose release clears the live config")
	check(session.bed_frame == null, "the pose-start leave clears the bed frame")
	check(session.view().id == "" and session.view().pose_state == VIEW.IDLE,
		"the pose release clears the view")
	check(session.view().pose_config.is_empty(), "the pose release drops the view config")
	check(str(session.base_info().reason) == "pose=",
		"the released session names no pose")
	body.free()
	hair.free()
	pony.free()


## A refused begin installs nothing at all: no body skeleton means no pose and no tail lay.
func _check_begin_refused() -> void:
	var made := _session(CATALOG.MISSIONARY)
	var session: RefCounted = made["session"]
	var pony: FakePony = made["pony"]
	session.view().clear()
	check(not session.begin(_values({
		"pose_id": CATALOG.MISSIONARY,
		"id": "twilight_sparkle",
		"features": {},
		"bed": null,
		"presentation": {},
	})), "a pony without a body skeleton is refused")
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
	check(session.begin(_values({
		"pose_id": CATALOG.STANDING,
		"id": "twilight_sparkle",
		"features": {},
		"bed": bed,
		"presentation": {},
		"look_point": Vector3.ZERO,
		"camera_position": Vector3.INF,
		"size_name": "canon",
	})), "the standing begin succeeds")
	check(not session.bed_frame_source_saved, "a standing begin saves no bed frame source")
	check(session.ground_frame is Transform3D, "the standing begin captures the ground frame")
	check(session.ground_frame_source_saved, "the standing begin saves the ground frame source")
	check(session.pose_node.authored != null and bool(session.pose_node.authored.get("available")),
		"the standing begin installs the standing asset")
	check(session.pose_node.size_name == "canon",
		"the begin carries the supplied size name to the pose node")
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


func _check_ground_frame() -> void:
	var made := _live_session(CATALOG.STANDING)
	var session: RefCounted = made["session"]
	var pony: FakePony = made["pony"]
	var start: Transform3D = session.ground_frame
	var basis_before := start.basis
	pony.global_position += Vector3(1.0, 0.0, -0.5)
	session.sync_ground_frame()
	check((session.ground_frame as Transform3D).origin.is_equal_approx(
		start.origin + Vector3(1.0, 0.0, -0.5)), "the ground frame follows the root")
	pony.rotate_y(0.5)
	session.sync_ground_frame()
	check(not (session.ground_frame as Transform3D).basis.is_equal_approx(basis_before),
		"the ground frame follows the root yaw")
	var still: Transform3D = session.ground_frame
	session.sync_ground_frame()
	check((session.ground_frame as Transform3D).is_equal_approx(still),
		"a still root leaves the frame alone")
	session.release_pose()
	check(session.ground_frame == null, "the release clears the ground frame")
	_free_live(made)


## The standing session resolves its own asset and reports the authored base.
func _check_standing_asset() -> void:
	var made := _live_session(CATALOG.STANDING)
	var session: RefCounted = made["session"]
	check(str(session.base_info().asset_path) == "poses/standing_pose.json",
		"the standing session names the standing asset")
	check(session.authored_ready(), "the standing asset is ready")
	check(str(session.base_info().base) == "authored",
		"the standing base is the authored asset")
	_free_live(made)


## A missing standing asset is refused, and the shared cache is put back for the other suites.
func _check_missing_standing_asset() -> void:
	var made := _session(CATALOG.STANDING)
	var session: RefCounted = made["session"]
	var pony: FakePony = made["pony"]
	var key := AUTHORED.resolve("poses/standing_pose.json")
	var saved: Variant = AUTHORED._shared.get(key)
	var broken: Variant = AUTHORED.new()
	AUTHORED._shared[key] = broken
	check(not session.authored_ready(), "a missing standing asset is not ready")
	check(str(session.authored_reason()).begins_with("pose_asset: "),
		"the reason names the missing asset")
	if saved != null:
		AUTHORED._shared[key] = saved
	else:
		AUTHORED._shared.erase(key)
	root.remove_child(pony)
	pony.free()


## The standing render write reaches the pose evaluator after the frame sync.
func _check_standing_render_write() -> void:
	var made := _live_session(CATALOG.STANDING)
	var session: RefCounted = made["session"]
	session.pose_node.amount = 1.0
	session.pose_node.target_amount = 1.0
	session.render_write(_render())
	check(str(session.pose_node.get("diag_last_base")) == "authored",
		"the standing render write reaches apply_render")
	_free_live(made)


## The pose evaluator owns the 30 body bones, so the session replays the active sway after it.
func _check_sway_render_write() -> void:
	var made := _live_session(CATALOG.STANDING)
	var session: RefCounted = made["session"]
	var body: Skeleton3D = made["body"]
	var standing := FakeSway.new()
	session.body_sway = standing
	session.pose_node.amount = 1.0
	session.pose_node.target_amount = 1.0
	session.render_write(_render())
	check(standing.calls == 1 and standing.skeletons[0] == body,
		"the standing render write replays the body sway after the pose")
	session.body_sway = null
	standing.free()
	_free_live(made)

	var bed := _live_session(CATALOG.MISSIONARY)
	var bed_session: RefCounted = bed["session"]
	var bed_body: Skeleton3D = bed["body"]
	var prone := FakeProneSway.new()
	bed_session.prone_sway = prone
	bed_session.pose_node.amount = 1.0
	bed_session.pose_node.target_amount = 1.0
	bed_session.bed_frame = Transform3D.IDENTITY
	bed_session.pose_node.bed_frame = Transform3D.IDENTITY
	bed_session.render_write(_render(Transform3D.IDENTITY))
	check(prone.calls == 1 and prone.skeletons[0] == bed_body,
		"the bed render write replays the prone sway after the pose")
	bed_session.prone_sway = null
	prone.free()
	_free_live(bed)


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
	var info: Variant = session.base_info()
	check(info.base == "none", "the base is none outside a missionary act")
	check(info.reason == "no ground frame",
		"the reason names the missing ground frame")
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
	session.rig_missing_bones.assign(["poison"])
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


## The render-time step: the Anon placement, her pose write and the live eye view, in that order,
## and nothing outside the bed family.
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
	session.eye_camera = func() -> void: order.append("eye")
	session.render_write(_render(Transform3D.IDENTITY, 0.66))
	check(order == ["anon", "eye"], "the render write places the Anon body and then the eye view")
	order.clear()
	session._view.family = "standing"
	session.render_write(_render())
	check(order.is_empty(), "a standing render write places no Anon body or eye view")
	session._view.family = "bed"
	session.act_body = null
	session.eye_camera = Callable()
	session.render_write(_render())
	check(order.is_empty(), "an absent eye callback is a no-op")
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
	check(session.begin(_values({
		"pose_id": pose,
		"id": "twilight_sparkle",
		"features": {},
		"bed": null,
		"presentation": {},
		"pose_config": {},
		"look_point": Vector3.ZERO,
		"camera_position": Vector3.INF,
	})), "the %s pose begins for the request suite" % pose)
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


## The begin state and the forward/reverse debug edge: the request codes, the transition view,
## completion and the settled target.
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
	var result: SESSION.PoseResult = session.request_pose(CATALOG.STANDING_TEST, "test", _request({"act_state": 2}))
	check(result.ok and result.code == "ok",
		"the forward debug request is accepted")
	check(result.edge == "standing__standing_test",
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
	var same_result: SESSION.PoseResult = session.request_pose(CATALOG.STANDING_TEST, "test", _request({"act_state": 2}))
	check(same_result.code == "same", "a second identical request is same")
	var busy_result: SESSION.PoseResult = session.request_pose(CATALOG.STANDING, "test", _request({"act_state": 2}))
	check(busy_result.code == "busy", "a request during an edge is busy")
	check(view.id == before_id and view.edge_id == before_edge,
		"a refused request leaves the view alone")

	session.tick(0.0)
	check(near(view.edge_t, 0.0), "the first tick reads the edge at zero")
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
	check(is_same(session.pose_config, live_config) and view.id == CATALOG.STANDING_TEST,
		"the live config and the view target are untouched")
	live_config.erase("adopt_marker")
	check(session._run == null and session._target_id == "",
		"the completed edge drops the run and the target")
	var before_tick_id := str(view.id)
	session.tick(0.6)
	check(view.id == before_tick_id, "a tick after completion is a no-op")

	var reverse: SESSION.PoseResult = session.request_pose(CATALOG.STANDING, "test", _request({"act_state": 2}))
	check(reverse.code == "ok", "the reverse debug request is accepted")
	check(reverse.edge == "standing_test__standing",
		"the reverse request names the reverse edge")
	session.tick(0.0)
	session.tick(0.6)
	check(view.id == CATALOG.STANDING and view.pose_state == VIEW.STEADY,
		"the reverse edge settles back on standing")
	check(session.request_command("thrust"), "the standing control set allows thrust again")
	_free_live(made)


## The standing oral pair: the forward turn, the contact switch at 0.9, the control lock, the
## speech/viseme events, the settled delta, the afterglow contact release and the reverse restore.
func _check_oral_edge() -> void:
	var made := _live_session(CATALOG.STANDING)
	var session: RefCounted = made["session"]
	var pony: FakePony = made["pony"]
	var view: RefCounted = session.view()
	var speech_stops: Array = []
	var visemes: Array[String] = []
	var kisses: Array = []
	session.mouth_point = func() -> Vector3: return pony.to_global(Vector3(0.0, 1.3, 0.5))
	session.opening_point = func() -> Vector3: return Vector3(0.8, 0.0, 1.2)
	session.oral_speech_stop = func() -> void: speech_stops.append(true)
	session.oral_viseme = func(value: String) -> void: visemes.append(value)
	session.oral_kiss = func() -> void: kisses.append(true)
	var from: Vector3 = pony.global_position
	var from_basis: Basis = pony.global_transform.basis.orthonormalized()
	var frame_start: Transform3D = session.ground_frame
	var forward: SESSION.PoseResult = session.request_pose(CATALOG.STANDING_ORAL, "oral",
		_request({"act_state": 2, "consent": "oral", "features": {"anatomy_oral": true}}))
	check(forward.ok, "the oral forward request is accepted")
	check(forward.edge == "standing__standing_oral",
		"the oral forward request names its edge")
	check(view.id == CATALOG.STANDING_ORAL and view.pose_state == VIEW.TRANSITIONING,
		"the oral forward fills the target and enters the transition")
	check(view.contact_kind == "opening", "the oral forward keeps the opening before 0.9")
	check(is_same(view.to_config, session._target_config),
		"the oral target is the standing settings snapshot")
	check(session.pose_node.mode == POSE.MODE_BLEND,
		"the oral delta pair takes the two-base blend")
	check(session.pose_node.from_delta == "" and session.pose_node.to_delta
		== "poses/standing_oral_recipe.gd",
		"the forward edge blends standing into the oral delta")

	session.tick(0.0)
	check(speech_stops.size() == 1, "the speech stop fires once at the start")
	check(visemes == ["D"], "the D viseme opens at the start")
	check(near(view.weight, 0.0) and pony.global_position.is_equal_approx(from),
		"the zero-weight oral turn has not moved her")
	check(view.to_config.has("oral_pitch") and view.to_config.has("oral_roll"),
		"the turn writes its keys into the target snapshot")
	session.tick(0.45)
	check(view.weight > 0.0 and view.weight < 1.0, "the oral blend eases through the edge")
	check(view.contact_kind == "opening", "the contact waits for 0.9")
	check(pony.global_position.distance_to(from) > 0.001,
		"the oral turn moves her toward the mirrored anchor")
	check(view.facing_amount > 0.0 and view.facing_amount < 1.0,
		"the oral turn publishes its eased facing")
	session.sync_ground_frame()
	check(not (session.ground_frame as Transform3D).origin.is_equal_approx(frame_start.origin),
		"the oral turn moves the ground frame")
	session.tick(0.45)
	check(view.contact_kind == "mouth", "the contact switches to the mouth at 0.9")
	check(session.request_command(ACT_COMMANDS.ORAL), "the oral lock allows oral")
	check(session.request_command(ACT_COMMANDS.POSE_BACK), "the oral lock allows pose_back")
	check(session.request_command(ACT_COMMANDS.END), "the oral lock allows end")
	for command_id: String in [ACT_COMMANDS.THRUST, ACT_COMMANDS.LEAN, ACT_COMMANDS.CARESS,
			ACT_COMMANDS.KISS, ACT_COMMANDS.HOLE, ACT_COMMANDS.POSE_FORWARD]:
		check(not session.request_command(command_id),
			"the oral lock denies %s" % command_id)
	session.tick(0.7)
	check(view.pose_state == VIEW.STEADY and view.id == CATALOG.STANDING_ORAL,
		"the oral forward settles on the target")
	check(view.contact_kind == "mouth", "the settled oral pose keeps the mouth contact")
	check(is_equal_approx(view.facing_amount, 1.0),
		"the oral turn holds its full facing")
	check(session.pose_node.mode == POSE.MODE_SINGLE
		and session.pose_node.from_delta == "poses/standing_oral_recipe.gd",
		"the settled oral pose runs the delta in the single path")
	check(session.pose_config.has("oral_pitch") and session.pose_config.has("oral_roll"),
		"the settled live config keeps the oral keys")
	check(str(view.controls.get("set", "")) == "standing_oral",
		"the settled view uses the oral control set")
	var turned_position: Vector3 = pony.global_position
	session.tick(0.5)
	check(session._run == null and view.id == CATALOG.STANDING_ORAL,
		"a steady oral tick keeps the pose")
	check(pony.global_position.is_equal_approx(turned_position),
		"a steady oral tick holds her turned position")
	check(kisses.is_empty(), "no soft kiss fires before the idle timer")
	session.tick(4.6)
	check(kisses.size() == 1, "the soft kiss fires on the idle timer")

	# The afterglow releases the mouth contact but holds the turned frame and the neck keys.
	session.release_mouth_contact()
	check(view.contact_kind == "opening", "the afterglow releases the mouth contact")
	check(visemes.has(""), "the contact release clears the viseme")
	check(pony.global_position.is_equal_approx(turned_position) \
		and is_equal_approx(view.facing_amount, 1.0),
		"the afterglow keeps the turned frame")
	check(session.pose_config.has("oral_pitch"), "the afterglow keeps the neck keys")

	var reverse: SESSION.PoseResult = session.request_pose(CATALOG.STANDING, "oral",
		_request({"act_state": 2, "features": {"anatomy_oral": true}}))
	check(reverse.ok, "the oral reverse request is accepted")
	check(reverse.edge == "standing_oral__standing",
		"the oral reverse request names its edge")
	session.tick(0.0)
	check(view.contact_kind == "opening", "the reverse contact is released at zero")
	check(not session.request_command(ACT_COMMANDS.ORAL),
		"the reverse lock denies oral")
	check(session.request_command(ACT_COMMANDS.END), "the reverse lock keeps end")
	session.tick(1.6)
	check(view.pose_state == VIEW.STEADY and view.id == CATALOG.STANDING,
		"the oral reverse settles back on standing")
	check(pony.global_position.is_equal_approx(from),
		"the reverse restores the captured root")
	check(is_zero_approx(view.facing_amount),
		"the reverse clears the facing amount")
	check(pony.global_transform.basis.orthonormalized().is_equal_approx(from_basis),
		"the reverse restores the captured facing")
	session.sync_ground_frame()
	check((session.ground_frame as Transform3D).origin.is_equal_approx(frame_start.origin),
		"the reverse returns the ground frame")
	check(not session.pose_config.has("oral_pitch") and not view.to_config.has("oral_pitch"),
		"the reverse erases the oral keys")
	check(session.pose_node.mode == POSE.MODE_SINGLE
		and session.pose_node.from_delta == "",
		"the settled standing pose drops the delta")
	check(session.request_command(ACT_COMMANDS.THRUST),
		"the standing control set returns after the oral turn")
	_free_live(made)

	# A refusal leaves the root and the view steady.
	var refused_made := _live_session(CATALOG.STANDING)
	var refused: RefCounted = refused_made["session"]
	var refused_pony: FakePony = refused_made["pony"]
	var refused_view: RefCounted = refused.view()
	refused.mouth_point = func() -> Vector3: return refused_pony.to_global(Vector3.UP)
	refused.opening_point = func() -> Vector3: return Vector3(1.0, 0.0, 1.0)
	var before: Vector3 = refused_pony.global_position
	for case: Dictionary in [
		{"act_state": 2, "consent": "oral", "features": {}},
		{"act_state": 2, "features": {"anatomy_oral": true}},
		{"act_state": 2, "consent": "oral", "features": {}},
	]:
		var result: SESSION.PoseResult = refused.request_pose(CATALOG.STANDING_ORAL, "oral", _request(case))
		check(result.code == "refused",
			"the oral requirement refuses %s" % str(case))
	check(refused_view.id == CATALOG.STANDING and refused_view.pose_state == VIEW.STEADY,
		"a refused oral request leaves the view steady")
	check(refused_pony.global_position.is_equal_approx(before),
		"a refused oral request leaves the root alone")
	check(refused._run == null and refused_view.contact_kind == "opening",
		"a refused oral request starts no edge and keeps the opening contact")
	_free_live(refused_made)


## The bed face-sit pair: the forward edge from missionary, the contact switch starting the face
## driver, the control set, the settled asset/config, the reverse restore and the act exit.
func _check_facesit_edge() -> void:
	var made := _live_session(CATALOG.MISSIONARY)
	var session: RefCounted = made["session"]
	var view: RefCounted = session.view()
	var points := FakeFacePoints.new()
	points.mouth = Vector3(0.0, 0.82, 0.65)
	points.opening = Vector3(0.0, 0.34, 0.45)
	session.bed_frame = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.65, 0.0))
	session.face_point = Callable(points, "mouth_point")
	session.opening_point = Callable(points, "opening_point")
	var forward: SESSION.PoseResult = session.request_pose(CATALOG.BED_FACESIT, "facesit",
		_request({"act_state": 2}))
	check(forward.ok, "the face-sit forward request is accepted")
	check(forward.edge == "missionary__bed_facesit",
		"the face-sit forward request names its edge")
	check(view.id == CATALOG.BED_FACESIT and view.pose_state == VIEW.TRANSITIONING,
		"the face-sit forward fills the target and enters the transition")
	check(view.contact_kind == "opening", "the face-sit forward keeps the opening before 0.9")
	check(str(view.presentation.get("hud_label", "")) == "Face-sit",
		"the face-sit target carries its HUD label")
	check(session.pose_node.mode == POSE.MODE_BLEND,
		"the two different authored bed assets take the two-base blend")
	check(str(session.pose_node.from_authored.get("path")).ends_with("missionary_pose.json"),
		"the from side is the missionary asset")
	check(str(session.pose_node.to_authored.get("path")).ends_with("bed_facesit_pose.json"),
		"the to side is the face-sit asset")

	var busy: SESSION.PoseResult = session.request_pose(CATALOG.MISSIONARY, "facesit", _request({"act_state": 2}))
	check(busy.code == "busy",
		"a request while the face-sit edge runs is busy")
	session.tick(0.0)
	check(view.contact_kind == "opening", "the face-sit contact waits for 0.9")
	session.tick(0.45)
	check(view.contact_kind == "opening", "the face-sit contact has not switched before 0.9")
	session.tick(0.45)
	check(view.contact_kind == "face", "the face-sit contact switches at 0.9")
	check(session._face_driver != null and bool(session._face_driver.get("active")),
		"the contact switch begins the face driver")
	var held: Vector3 = session.pose_node.contact_offset
	check(held.is_finite(), "the face driver writes a finite pose offset")
	points.mouth += Vector3(0.02, 0.0, 0.0)
	session.tick(0.5)
	check(not session.pose_node.contact_offset.is_equal_approx(held),
		"the face driver follows the moved mouth")
	check(near(view.contact_target.distance_to(points.mouth), 0.0),
		"the view's contact target is the live mouth")
	session.tick(0.7)
	check(view.pose_state == VIEW.STEADY and view.id == CATALOG.BED_FACESIT,
		"the face-sit forward settles on the target")
	check(view.contact_kind == "face", "the settled face-sit keeps the face contact")
	check(session.pose_node.mode == POSE.MODE_SINGLE
		and str(session.pose_node.authored.get("path")).ends_with("bed_facesit_pose.json"),
		"the settled face-sit runs its own asset in the single path")
	check(is_same(session.pose_node.authored, session.authored_asset()),
		"the camera reads the adopted face-sit asset")
	check(str(view.controls.get("set", "")) == "facesit",
		"the settled view uses the face-sit control set")
	for command_id: String in [ACT_COMMANDS.THRUST, ACT_COMMANDS.LEAN, ACT_COMMANDS.CARESS,
			ACT_COMMANDS.END]:
		check(session.request_command(command_id),
			"the face-sit control set allows %s" % command_id)
	for command_id: String in [ACT_COMMANDS.KISS, ACT_COMMANDS.HOLE,
			ACT_COMMANDS.ORAL, ACT_COMMANDS.POSE_BACK, ACT_COMMANDS.POSE_FORWARD]:
		check(not session.request_command(command_id),
			"the face-sit control set denies %s" % command_id)
	var same: SESSION.PoseResult = session.request_pose(CATALOG.BED_FACESIT, "facesit", _request({"act_state": 2}))
	check(same.code == "same", "a same-pose request is reported as same")
	var bad_phase: SESSION.PoseResult = session.request_pose(CATALOG.MISSIONARY, "facesit",
		_request({"act_state": 1}))
	check(bad_phase.code == "bad_phase",
		"a face-sit request outside ACTIVE is refused")

	var reverse: SESSION.PoseResult = session.request_pose(CATALOG.MISSIONARY, "facesit",
		_request({"act_state": 2}))
	check(reverse.ok, "the face-sit reverse request is accepted")
	check(reverse.edge == "bed_facesit__missionary",
		"the face-sit reverse request names its edge")
	session.tick(0.0)
	check(view.contact_kind == "opening", "the reverse contact is restored at zero")
	check(not bool(session._face_driver.get("active")),
		"the reverse contact switch deactivates the face driver")
	check(session.pose_node.contact_offset.is_zero_approx(),
		"the reverse contact switch zeroes the pose offset")
	session.tick(1.2)
	check(view.pose_state == VIEW.STEADY and view.id == CATALOG.MISSIONARY,
		"the face-sit reverse settles back on missionary")
	check(session.pose_node.mode == POSE.MODE_SINGLE
		and str(session.pose_node.authored.get("path")).ends_with("missionary_pose.json"),
		"the settled reverse runs the missionary asset")
	check(session.request_command(ACT_COMMANDS.KISS),
		"the missionary control set returns after the face-sit")
	_free_live(made)


## Every refusal code, in the order the state module reports it, plus the synthetic asset and
## requirement cases the shipped debug pair does not carry.
func _check_refusals() -> void:
	var made := _live_session(CATALOG.STANDING)
	var session: RefCounted = made["session"]
	var view: RefCounted = session.view()
	var same: SESSION.PoseResult = session.request_pose(CATALOG.STANDING, "test", _request({"act_state": 2}))
	check(same.code == "same", "the start pose is same")
	for phase: int in [1, 3, 4, 5]:
		var result: SESSION.PoseResult = session.request_pose(CATALOG.STANDING_TEST, "test",
			_request({"act_state": phase}))
		check(result.code == "bad_phase",
			"act state %d is bad_phase" % phase)
	var no_edge: SESSION.PoseResult = session.request_pose(CATALOG.MISSIONARY, "test", _request({"act_state": 2}))
	check(no_edge.code == "no_edge", "a pair without an edge is no_edge")
	var form: SESSION.PoseResult = session.request_pose(CATALOG.STANDING_TEST, "test",
		_request({"act_state": 2, "forms": ["unicorn"]}))
	check(form.code == "unsupported_form", "an unsupported form refuses")
	var view_result: SESSION.PoseResult = session.request_pose(CATALOG.STANDING_TEST, "test",
		_request({"act_state": 2, "views": ["seat"]}))
	check(view_result.code == "unsupported_view", "an unsupported view refuses")
	var locked: SESSION.PoseResult = session.request_pose(CATALOG.STANDING_TEST, "test",
		_request({"act_state": 2, "locked": true}))
	check(locked.code == "locked", "a locked request refuses")
	check(view.id == CATALOG.STANDING and view.pose_state == VIEW.STEADY,
		"every refusal leaves the view steady on the start pose")
	_free_live(made)

	var fresh_made := _session(CATALOG.STANDING)
	var fresh: RefCounted = fresh_made["session"]
	var fresh_pony: FakePony = fresh_made["pony"]
	fresh.facts = FakeFacts.new()
	var not_steady: SESSION.PoseResult = fresh.request_pose(CATALOG.STANDING_TEST, "test",
		_request({"act_state": 2}))
	check(not_steady.code == "not_steady",
		"a session that has not begun is not_steady")
	root.remove_child(fresh_pony)
	fresh_pony.free()

	var refused_made := _live_session(CATALOG.STANDING)
	var refused: RefCounted = refused_made["session"]
	var refused_view: RefCounted = refused.view()
	for case: Array in [
		["synthetic_feature", {"features": ["missing_feature"]}, {}],
		["synthetic_consent", {"consent": "needed"}, {}],
	]:
		var target := str(case[0])
		_synthetic_spec(refused, target)
		_synthetic_edge(refused, CATALOG.STANDING, target, case[1] as Dictionary)
		var request := _request(case[2] as Dictionary)
		request.act_state = 2
		var result: SESSION.PoseResult = refused.request_pose(target, "test", request)
		check(result.code == "refused",
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
	var missing_result: SESSION.PoseResult = missing.request_pose("synthetic_missing", "test",
		_request({"act_state": 2}))
	check(missing_result.code == "missing_asset",
		"a target without an asset is missing_asset")
	check(missing_view.id == CATALOG.STANDING and missing_view.pose_state == VIEW.STEADY,
		"a missing asset leaves the view steady")
	_free_live(missing_made)


## The real control profiles, the reserved `end`, the edge lock and the standing_test block.
func _check_commands() -> void:
	var made := _live_session(CATALOG.STANDING)
	var session: RefCounted = made["session"]
	for command_id: String in [ACT_COMMANDS.THRUST, ACT_COMMANDS.LEAN, ACT_COMMANDS.CARESS,
			ACT_COMMANDS.KISS, ACT_COMMANDS.ORAL, ACT_COMMANDS.HOLE,
			ACT_COMMANDS.POSE_BACK, ACT_COMMANDS.POSE_FORWARD, ACT_COMMANDS.END]:
		check(session.request_command(command_id),
			"the standing profile allows %s" % command_id)
	check(session.request_command(ACT_COMMANDS.END), "end is always allowed")
	check(not session.request_command("nonsense"), "an unknown command is refused")
	check(not session.request_command(""), "an empty command is refused")
	var result: SESSION.PoseResult = session.request_pose(CATALOG.STANDING_TEST, "test", _request({"act_state": 2}))
	check(result.code == "ok", "the command check starts the debug edge")
	for command_id: String in [ACT_COMMANDS.THRUST, ACT_COMMANDS.LEAN, ACT_COMMANDS.CARESS,
			ACT_COMMANDS.KISS, ACT_COMMANDS.ORAL, ACT_COMMANDS.HOLE,
			ACT_COMMANDS.POSE_BACK, ACT_COMMANDS.POSE_FORWARD]:
		check(not session.request_command(command_id),
			"the standing_test profile blocks %s" % command_id)
	check(session.request_command(ACT_COMMANDS.END), "end stays allowed in standing_test")
	_free_live(made)

	var missionary_made := _live_session(CATALOG.MISSIONARY)
	var missionary: RefCounted = missionary_made["session"]
	for command_id: String in [ACT_COMMANDS.THRUST, ACT_COMMANDS.LEAN, ACT_COMMANDS.CARESS,
			ACT_COMMANDS.KISS, ACT_COMMANDS.HOLE, ACT_COMMANDS.END]:
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
	var lock_result: SESSION.PoseResult = lock_session.request_pose("synthetic_lock", "test",
		_request({"act_state": 2}))
	check(lock_result.code == "ok", "the lock edge starts")
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
	var result: SESSION.PoseResult = session.request_pose(CATALOG.STANDING_TEST, "test", _request({"act_state": 2}))
	check(result.code == "ok", "the snapshot check starts the debug edge")
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


## The target snapshot follows the target spec's settings_group, not its pose id: a synthetic
## edge into a different group rebuilds the target config from that group, re-merges it in place
## on `apply_live_settings()` and adopts it into the live object on completion.
func _check_settings_group_edge() -> void:
	var made := _live_session(CATALOG.STANDING)
	var session: RefCounted = made["session"]
	var view: RefCounted = session.view()
	_synthetic_spec(session, "synthetic_other_group", "standing", CATALOG.MISSIONARY)
	_synthetic_edge(session, CATALOG.STANDING, "synthetic_other_group", {},
		{"kind": "switch", "at": 0.0, "set": "standing"})
	var live: Dictionary = session.pose_config
	var result: SESSION.PoseResult = session.request_pose("synthetic_other_group", "test",
		_request({"act_state": 2}))
	check(result.code == "ok", "the other-group edge starts")
	var target: Dictionary = view.to_config
	check(is_same(view.from_config, live), "the from side stays the live standing config")
	check(not is_same(target, live), "the to side is a separate target snapshot")
	check(target.has("nuzzle_scale"), "the target snapshot uses the missionary settings block")
	check(not target.has("gaps") and not target.has("chin_up_deg"),
		"the target snapshot does not use the standing block")
	check(_same_config(target, SETTINGS.pose("twilight_sparkle", CATALOG.MISSIONARY).raw()),
		"the target snapshot is the target group's pose config")
	target["stale_marker"] = 1
	session.apply_live_settings()
	check(is_same(view.to_config, target), "a live edit keeps the same target object")
	check(not target.has("stale_marker"),
		"the live edit re-merges the target group in place")
	check(target.has("nuzzle_scale"),
		"the refreshed target keeps the target group's keys")
	session.tick(0.0)
	session.tick(0.6)
	check(view.pose_state == VIEW.STEADY, "the other-group edge settles")
	check(is_same(view.pose_config, live) and is_same(view.from_config, live)
		and is_same(view.to_config, live),
		"completion adopts the target group into the one live config object")
	check(live.has("nuzzle_scale") and not live.has("gaps"),
		"the live config now carries the target group")
	_free_live(made)


## The target asset is adopted even when the two settings groups are equal, and the camera keeps
## the source asset through the edge. The target is a synthetic bed row on the standing asset and
## the missionary settings group, the shape a future face-sit uses.
func _check_asset_adoption() -> void:
	var made := _live_session(CATALOG.MISSIONARY)
	var session: RefCounted = made["session"]
	var view: RefCounted = session.view()
	var missionary: Variant = AUTHORED.shared("poses/missionary_pose.json")
	var standing: Variant = AUTHORED.shared("poses/standing_pose.json")
	check(is_same(session.pose_node.authored, missionary),
		"the missionary begin owns the missionary asset")
	check(is_same(session.authored_asset(), missionary),
		"the published asset is the live rendered asset")
	var target := "synthetic_face_bed"
	_synthetic_bed_spec(session, target)
	_synthetic_edge(session, CATALOG.MISSIONARY, target, {})
	var result: SESSION.PoseResult = session.request_pose(target, "test", _request({"act_state": 2}))
	check(result.code == "ok", "the synthetic bed edge starts")
	check(session.pose_node.mode == POSE.MODE_BLEND,
		"two different authored assets take the blend even with the same driver")
	check(is_same(session.pose_node.from_authored, missionary),
		"the from side is the live missionary asset")
	check(is_same(session.pose_node.to_authored, standing),
		"the to side is the target standing asset")
	check(is_same(session.authored_asset(), missionary),
		"the camera holds the source asset through the edge")
	check(str(view.id) == target, "the view follows the target")
	var info: Variant = session.base_info()
	check(info.live_path == "poses/missionary_pose.json",
		"the base info names the live missionary path")
	check(info.target_path == "poses/standing_pose.json",
		"the base info names the target standing path")
	session.tick(0.0)
	session.tick(0.7)
	check(view.pose_state == VIEW.STEADY, "the synthetic bed edge settles")
	check(session.pose_node.mode == POSE.MODE_SINGLE,
		"the settled pose is single on the target driver")
	check(session.pose_node.from_driver == POSE.STANDING_PATH
		and session.pose_node.to_driver == POSE.STANDING_PATH,
		"the settled pair is the target driver")
	check(is_same(session.pose_node.authored, standing),
		"completion adopts the target asset")
	check(is_same(session.pose_node.from_authored, standing)
		and is_same(session.pose_node.to_authored, standing),
		"completion points both sides at the target asset")
	check(is_same(session._from_asset, standing), "the live side adopts the target asset")
	check(session._target_asset == null, "completion drops the target asset cache")
	check(is_same(session.authored_asset(), standing),
		"the published asset is the target after completion")
	check(session.sync_missionary_config(),
		"the target's settings group still syncs after completion")
	check(is_same(session.pose_node.authored, standing),
		"a live missionary sync does not reset the target asset")
	_free_live(made)


## A reload re-reads the live asset and the running edge's target; outside an edge it re-reads the
## live path once. The shared wrappers keep their identity and their own paths.
func _check_asset_reload() -> void:
	var made := _live_session(CATALOG.MISSIONARY)
	var session: RefCounted = made["session"]
	var target := "synthetic_face_reload"
	_synthetic_bed_spec(session, target)
	_synthetic_edge(session, CATALOG.MISSIONARY, target, {})
	var result: SESSION.PoseResult = session.request_pose(target, "test", _request({"act_state": 2}))
	check(result.code == "ok", "the reload edge starts")
	var source: Variant = session.pose_node.authored
	var wanted: Variant = session.pose_node.to_authored
	var source_path := str(source.get("path"))
	var target_path := str(wanted.get("path"))
	var before: int = AUTHORED.revision
	check(session.reload_authored().is_empty(), "a live edge reloads both assets")
	check(AUTHORED.revision == before + 2, "the live and target paths both advance the revision")
	check(str(source.get("path")) == source_path and str(wanted.get("path")) == target_path,
		"each wrapper still owns its own path")
	check(is_same(session.pose_node.authored, source),
		"the reload keeps the live asset")
	check(is_same(session.pose_node.to_authored, wanted),
		"the reload keeps the target asset on the to side")
	session.tick(0.0)
	session.tick(0.7)
	before = AUTHORED.revision
	check(session.reload_authored().is_empty(), "the settled pose reloads its live asset")
	check(AUTHORED.revision == before + 1, "outside an edge the live path reloads once")
	_free_live(made)


## A release aborts a live edge; the view goes idle and a second release is a no-op.
func _check_release_abort() -> void:
	var made := _live_session(CATALOG.STANDING)
	var session: RefCounted = made["session"]
	var view: RefCounted = session.view()
	var result: SESSION.PoseResult = session.request_pose(CATALOG.STANDING_TEST, "test", _request({"act_state": 2}))
	check(result.code == "ok", "the abort check starts the debug edge")
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


## The act-body adapter reads the session's authored pair: the live asset twice outside an edge,
## the source/target pair at the edge weight on a blend, and the target twice on a switch. The
## profile stays the adapter's own.
func _check_anon_pair() -> void:
	var made := _live_session(CATALOG.STANDING)
	var session: RefCounted = made["session"]
	var view: RefCounted = session.view()
	var body := FakeActBody.new()
	session.act_body = body
	view.anon = {"mode": "act_body", "profile": "missionary"}
	var live: Variant = session.pose_node.authored
	session.pose_changed(view)
	check(body.assets.size() == 1, "the outside-edge fan-out binds the pair once")
	check(is_same(body.assets[0][0], live) and is_same(body.assets[0][1], live)
		and is_equal_approx(float(body.assets[0][2]), 1.0),
		"the outside-edge pair is the live asset twice at full weight")
	check(body.profiles.size() == 1 and str(body.profiles[0][0]) == "missionary",
		"the outside-edge profile is the spec's own")
	check(body.get_parent() == null and not body.is_queued_for_deletion(),
		"a bound adapter is kept, not reinstalled or freed")

	var target := "synthetic_anon_blend"
	_synthetic_spec(session, target)
	_synthetic_edge(session, CATALOG.STANDING, target, {},
		{"kind": "switch", "at": 0.0, "set": "standing"},
		{"anon": {"kind": "blend"}})
	var result: SESSION.PoseResult = session.request_pose(target, "test", _request({"act_state": 2}))
	check(result.code == "ok", "the anon blend edge starts")
	view.anon = {"mode": "act_body", "profile": "missionary"}
	var source_asset := AUTHORED.new()
	var target_asset := AUTHORED.new()
	session._from_asset = source_asset
	session._target_asset = target_asset
	var before_profiles := body.profiles.size()
	for weight: float in [0.0, 0.5, 1.0]:
		view.weight = weight
		session.pose_changed(view)
	var last := body.assets.size() - 1
	check(last >= 2, "the anon blend binds the pair on every weight")
	check(is_same(body.assets[last - 2][0], source_asset)
		and is_same(body.assets[last - 2][1], target_asset)
		and is_zero_approx(float(body.assets[last - 2][2])),
		"the blend's source/target pair starts at weight zero")
	check(is_same(body.assets[last][0], source_asset) and is_same(body.assets[last][1], target_asset)
		and is_equal_approx(float(body.assets[last][2]), 1.0),
		"the blend's source/target pair reaches weight one")
	check(body.weights.size() >= 3 and is_equal_approx(float(body.weights[-1]), 1.0),
		"the blend hands the weight to the adapter")
	check(body.profiles.size() == before_profiles, "a blend never changes the profile")
	_free_live(made)

	var switch_made := _live_session(CATALOG.STANDING)
	var switch_session: RefCounted = switch_made["session"]
	var switch_view: RefCounted = switch_session.view()
	var switch_body := FakeActBody.new()
	switch_session.act_body = switch_body
	var switch_target := "synthetic_anon_switch"
	_synthetic_spec(switch_session, switch_target)
	_synthetic_edge(switch_session, CATALOG.STANDING, switch_target, {},
		{"kind": "switch", "at": 0.0, "set": "standing"},
		{"anon": {"kind": "switch", "at": 0.0, "profile": "missionary_switch"}})
	var switch_result: SESSION.PoseResult = switch_session.request_pose(switch_target, "test",
		_request({"act_state": 2}))
	check(switch_result.code == "ok", "the anon switch edge starts")
	switch_view.anon = {"mode": "act_body", "profile": "missionary"}
	var switch_asset := AUTHORED.new()
	switch_session._target_asset = switch_asset
	switch_session.pose_changed(switch_view)
	check(switch_body.assets.size() == 1
		and is_same(switch_body.assets[0][0], switch_asset)
		and is_same(switch_body.assets[0][1], switch_asset)
		and is_equal_approx(float(switch_body.assets[0][2]), 1.0),
		"an anon switch binds the target asset twice at full weight")
	check(switch_body.profiles.size() == 1
		and str(switch_body.profiles[0][0]) == "missionary_switch",
		"an anon switch names the switched profile")
	_free_live(switch_made)


## A live edge aborted by `_end_session` frees the act body once and never calls an act exit from
## the fan-out. The edge request and the pose-change seam keep the session alive.
func _check_no_act_exit() -> void:
	var made := _live_session(CATALOG.STANDING)
	var session: RefCounted = made["session"]
	var view: RefCounted = session.view()
	var pose_node: Node = session.pose_node
	var config: Dictionary = session.pose_config
	var forward: SESSION.PoseResult = session.request_pose(CATALOG.STANDING_TEST, "test", _request({"act_state": 2}))
	check(forward.code == "ok", "the no-exit check starts the debug edge")
	session.tick(0.0)
	session.tick(0.6)
	var reverse: SESSION.PoseResult = session.request_pose(CATALOG.STANDING, "test", _request({"act_state": 2}))
	check(reverse.code == "ok", "the no-exit check returns to standing")
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
func _synthetic_spec(session: RefCounted, spec_id: String, controls_set := "standing",
		settings_group := "standing") -> Variant:
	var row: Dictionary = SPECS.SPECS[CATALOG.STANDING].duplicate(true)
	row["id"] = spec_id
	row["display_name"] = "Synthetic"
	row["base"] = CATALOG.STANDING
	row["delta"] = ""
	row["driver"] = ""
	row["controls"] = {"set": controls_set}
	row["settings_group"] = settings_group
	row["public"] = false
	row["offerable"] = false
	var spec: Variant = POSE_SPEC.from_dict(spec_id, row, {})
	check(spec != null, "the synthetic spec %s builds" % spec_id)
	session._registry._specs[spec_id] = spec
	return spec


## A synthetic bed row on the standing driver and asset with the missionary settings group: the
## shape a future face-sit uses. Its scene block is a valid bed block, and it is not offered.
func _synthetic_bed_spec(session: RefCounted, spec_id: String) -> Variant:
	var row: Dictionary = SPECS.SPECS[CATALOG.STANDING].duplicate(true)
	row["id"] = spec_id
	row["display_name"] = "Synthetic bed"
	row["family"] = "bed"
	row["frame"] = "bed"
	row["base"] = ""
	row["asset"] = "poses/standing_pose.json"
	row["delta"] = ""
	row["driver"] = POSE.STANDING_PATH
	row["settings_group"] = CATALOG.MISSIONARY
	var scene: Dictionary = (row["scene"] as Dictionary).duplicate(true)
	scene["frame"] = "bed"
	row["scene"] = scene
	row["public"] = false
	row["offerable"] = false
	var spec: Variant = POSE_SPEC.from_dict(spec_id, row, {})
	check(spec != null, "the synthetic bed spec %s builds" % spec_id)
	session._registry._specs[spec_id] = spec
	return spec


## A synthetic validated edge into a synthetic target. `channels` adds or overrides a channel
## record on top of the held base and the controls switch.
func _synthetic_edge(session: RefCounted, from_id: String, to_id: String, requires: Dictionary,
		controls: Dictionary = {"kind": "switch", "at": 0.0, "set": "standing"},
		channels: Dictionary = {}) -> Variant:
	var edge_id := from_id + "__" + to_id
	var block: Dictionary = {"base": {"kind": "hold"}, "controls": controls}
	block.merge(channels, true)
	var document := {
		"version": 1,
		"id": edge_id,
		"from": from_id,
		"to": to_id,
		"phases": ["active"],
		"requires": requires,
		"duration": 0.6,
		"channels": block,
		"events": [],
		"interrupt": {"climax": "hold", "teardown": "abort"},
	}
	var edge: Variant = TRANSITION_SPEC.from_dict(edge_id, document, {})
	check(edge != null, "the synthetic edge %s builds" % edge_id)
	session._registry._edges[edge_id] = edge
	return edge
