extends SceneTree
## The pose-scope/act-scope teardown split: the two leave steps keep the pose node, the live config
## and the view; the final release clears them and repeats safely; no pose-scope step reaches an
## act exit.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/poses/test_pose_teardown.gd

const SESSION := preload("res://mods/unfplap/poses/service.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")
const VIEW := preload("res://mods/unfplap/shared/pose_view.gd")

const SERVICE_PATH := "res://mods/unfplap/poses/service.gd"
## The runtime's act-exit names a pose-scope step must never call.
const ACT_EXIT := ["release_pose(", "_end_session(", "_unlock_player(", "_restore_pony_bones(",
	"_restore_camera(", "_restore_look(", "_release_nav(", "_free_pose("]

var failures := 0
var checks := 0


class FakePony extends Node3D:
	var skeleton: Variant = null
	var hair_skeleton: Variant = null
	var body_scale := 1.0


## The act-body handle the transition test injects: the session owns it, so it must accept the
## service's pair binding and its act-exit restore.
class FakeActBody extends Node:
	var pairs: Array = []

	func set_pose_assets(from_value: Variant, to_value: Variant, weight: float) -> void:
		pairs.append([from_value, to_value, weight])

	func remove() -> void:
		pass


## The face provider pair for the transition: his mouth and her opening, mutable.
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


func run() -> void:
	_check_missionary_scope()
	_check_standing_scope()
	_check_body_tail_scope()
	_check_transition_path()
	_check_facesit_transition()
	_check_no_act_exit()
	print("POSE_TEARDOWN_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("POSE_TEARDOWN_PASS")
	quit(0 if failures == 0 else 1)


## A fitted body tail chain for the princess-style fixtures: no devkit hair tail.
func _add_body_tail(body: Skeleton3D) -> void:
	var parent := body.find_bone("pony_hips")
	for i: int in range(1, 6):
		var bone := body.add_bone("pony_tail_0%d" % i)
		body.set_bone_parent(bone, parent)
		var rest := Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.08))
		body.set_bone_rest(bone, rest)
		body.set_bone_pose(bone, rest)
		parent = bone


## One live session over a fake pony, a body and hair skeleton, and a bed for the missionary frame.
## The pose begins before the assertions so every leave step meets a live act.
func _fixture(pose: String, features: Dictionary, body_tail := false) -> Dictionary:
	var pony := FakePony.new()
	root.add_child(pony)
	var body := Skeleton3D.new()
	body.add_bone("pony_hips")
	if body_tail:
		_add_body_tail(body)
	var hair := Skeleton3D.new()
	if not body_tail:
		hair.add_bone("mTail1")
	pony.skeleton = body
	pony.hair_skeleton = hair
	var bed := Node3D.new()
	bed.name = "Bed"
	root.add_child(bed)
	var session: RefCounted = SESSION.new()
	session.bind(null, pony)
	check(session.begin({
		"pose_id": pose,
		"id": "twilight_sparkle",
		"features": features,
		"bed": bed,
		"presentation": {},
		"pose_config": {},
		"look_point": Vector3.ZERO,
		"camera_position": Vector3.INF,
	}), "the %s pose begins" % pose)
	return {"session": session, "pony": pony, "body": body, "hair": hair, "bed": bed}


## The staged teardown after the assertions: the leave steps are idempotent, so a fixture that
## already released its pose just runs the same three calls again.
func _free_fixture(made: Dictionary) -> void:
	var session: RefCounted = made["session"]
	session.leave_pose_start()
	session.leave_pose_body()
	session.release_pose()
	var body: Skeleton3D = made["body"]
	var hair: Skeleton3D = made["hair"]
	var pony: FakePony = made["pony"]
	var bed: Node3D = made["bed"]
	root.remove_child(bed)
	bed.free()
	body.free()
	hair.free()
	root.remove_child(pony)
	pony.free()


## The pose-start step clears the rig cache, the tail lay and the bed frame; the pose node, the
## modifiers, the live config and the view survive. The pose-body step then drops the modifiers.
func _check_missionary_scope() -> void:
	var made := _fixture(CATALOG.MISSIONARY, {"missionary_body_motion": true})
	var session: RefCounted = made["session"]
	var view: RefCounted = session.view()
	var config: Dictionary = session.pose_config
	var pose_node: Node = session.pose_node
	var prone_sway: Node = session.prone_sway
	var tail_lay: Node = session.tail_lay
	check(pose_node != null and pose_node.get_parent() != null,
		"the begin installs the pose node")
	check(tail_lay != null, "the missionary begin installs the tail lay")
	check(prone_sway != null, "the missionary begin installs the prone sway")
	check(session.bed_frame is Transform3D, "the missionary begin saves the bed frame")
	check(view.pose_state == VIEW.STEADY and view.id == CATALOG.MISSIONARY,
		"the live pose fills the view")
	check(not config.is_empty() and is_same(config, view.pose_config),
		"the live pose fills the config and the view shares it")
	check(session.rig_checked, "the begin caches the rig check")

	session.leave_pose_start()
	check(not session.rig_checked and session.rig_missing_bones.is_empty(),
		"the pose-start leave clears the rig cache")
	check(session.tail_lay == null and tail_lay.get_parent() == null
		and tail_lay.is_queued_for_deletion(),
		"the pose-start leave frees the tail lay")
	check(session.bed_frame == null and not session.bed_frame_source_saved,
		"the pose-start leave clears the bed frame")
	check(session.pose_node == pose_node and pose_node.get_parent() != null,
		"the pose-start leave keeps the pose node")
	check(session.prone_sway == prone_sway and prone_sway.get_parent() != null,
		"the pose-start leave keeps the modifiers")
	check(is_same(session.pose_config, config) and not config.is_empty(),
		"the pose-start leave keeps the live config")
	check(view.pose_state == VIEW.STEADY and view.id == CATALOG.MISSIONARY,
		"the pose-start leave keeps the view")

	session.leave_pose_body()
	check(session.prone_sway == null and prone_sway.get_parent() == null
		and prone_sway.is_queued_for_deletion(),
		"the pose-body leave frees the extra modifiers")
	check(session.pose_node == pose_node and pose_node.get_parent() != null,
		"the pose-body leave keeps the pose node")
	check(session.tail == null, "the missionary pose has no standing tail")
	check(is_same(session.pose_config, config) and not config.is_empty(),
		"the pose-body leave keeps the live config")
	check(view.pose_state == VIEW.STEADY and view.id == CATALOG.MISSIONARY,
		"the pose-body leave keeps the view")

	session.release_pose()
	check(session.pose_node == null and pose_node.get_parent() == null
		and pose_node.is_queued_for_deletion(),
		"the final release frees the pose node")
	check(session.id == "" and session.features.is_empty(),
		"the final release clears the act identity and features")
	check(session.pose_config.is_empty() and config.is_empty(),
		"the final release clears the live config")
	check(session.bed_frame == null and not session._started,
		"the final release clears the remaining pose state")
	check(view.pose_state == VIEW.IDLE and view.id == "",
		"the final release returns the view to idle")
	check(view.pose_config.is_empty() and view.camera.is_empty() and view.modifiers.is_empty()
		and view.forms.is_empty() and view.views.is_empty(),
		"the final release drops the view config and profiles")

	session.release_pose()
	check(session.pose_node == null and view.pose_state == VIEW.IDLE
		and view.id == "",
		"a second final release is a no-op")
	_free_fixture(made)


## The standing pose keeps its modifiers and its tail through both leave steps; only the final
## release frees the pose node and the tail.
func _check_standing_scope() -> void:
	var made := _fixture(CATALOG.STANDING, {"standing_body_sway": true})
	var session: RefCounted = made["session"]
	var body: Skeleton3D = made["body"]
	var view: RefCounted = session.view()
	var config: Dictionary = session.pose_config
	var pose_node: Node = session.pose_node
	var body_sway: Node = session.body_sway
	var tail: Variant = session.tail
	check(body_sway != null and body_sway.get_parent() == body,
		"the standing begin installs body sway")
	check(tail != null and tail.get_parent() != null, "the standing begin installs the tail")
	check(view.pose_state == VIEW.STEADY and view.id == CATALOG.STANDING,
		"the standing begin fills the view")
	check(session.ground_frame is Transform3D,
		"the standing begin captures the ground frame")

	session.leave_pose_start()
	check(session.ground_frame == null,
		"the pose-start leave clears the ground frame")
	check(session.body_sway == body_sway and body_sway.get_parent() == body,
		"the pose-start leave keeps the extra modifiers")
	check(session.tail == tail and tail.get_parent() != null,
		"the pose-start leave keeps the standing tail")
	check(session.pose_node == pose_node and pose_node.get_parent() == body,
		"the pose-start leave keeps the pose node")
	check(is_same(session.pose_config, config) and view.pose_state == VIEW.STEADY,
		"the pose-start leave keeps the config and the view")

	session.leave_pose_body()
	check(session.body_sway == null and body_sway.get_parent() == null
		and body_sway.is_queued_for_deletion(),
		"the pose-body leave frees the extra modifiers")
	check(session.pose_node == pose_node and pose_node.get_parent() == body,
		"the pose-body leave keeps the pose node")
	check(session.tail == tail and tail.get_parent() != null,
		"the pose-body leave keeps the standing tail")
	check(is_same(session.pose_config, config) and not config.is_empty()
		and view.pose_state == VIEW.STEADY,
		"the pose-body leave keeps the config and the view")

	session.release_pose()
	check(session.pose_node == null and pose_node.get_parent() == null,
		"the standing final release frees the pose node")
	check(session.tail == null and tail.get_parent() == null
		and tail.is_queued_for_deletion(),
		"the standing final release frees the tail")
	check(session.pose_config.is_empty() and view.pose_state == VIEW.IDLE and view.id == "",
		"the standing final release clears the config and the view")
	check(session.ground_frame == null,
		"the standing final release clears the ground frame")
	_free_fixture(made)


## A fitted body tail has no devkit hair chain; both the standing tail and the bed tail lay must
## install on the body skeleton instead.
func _check_body_tail_scope() -> void:
	var made := _fixture(CATALOG.STANDING, {}, true)
	var session: RefCounted = made["session"]
	var body: Skeleton3D = made["body"]
	var tail: Variant = session.tail
	check(tail != null and tail.get_parent() == body,
		"the standing tail installs on a fitted body skeleton")
	_free_fixture(made)

	var bed_made := _fixture(CATALOG.MISSIONARY, {}, true)
	var bed_session: RefCounted = bed_made["session"]
	var bed_body: Skeleton3D = bed_made["body"]
	var tail_lay: Variant = bed_session.tail_lay
	check(tail_lay != null and tail_lay.get_parent() == bed_body,
		"the bed tail lay installs on a fitted body skeleton")
	_free_fixture(bed_made)


## The live debug edge: the request and tick path keeps the pose node, the config and the view, and
## every transition function stays clear of an act exit.
func _check_transition_path() -> void:
	var made := _fixture(CATALOG.STANDING, {"standing_body_sway": true})
	var session: RefCounted = made["session"]
	var view: RefCounted = session.view()
	var config: Dictionary = session.pose_config
	var pose_node: Node = session.pose_node
	var body_sway: Node = session.body_sway
	var act_body := FakeActBody.new()
	session.act_body = act_body
	session.pose_changed(view)
	check(session.act_body == act_body and act_body.get_parent() == null,
		"a pose change keeps the act body")
	var result: Dictionary = session.request_pose(CATALOG.STANDING_TEST, "test", {"act_state": 2})
	check(str(result.get("code", "")) == "ok", "the transition path starts the debug edge")
	check(view.pose_state == VIEW.TRANSITIONING and session._state == VIEW.TRANSITIONING,
		"the transition path enters the transition state")
	session.pose_changed(view)
	check(session.body_sway == body_sway and body_sway.get_parent() == made["body"],
		"the transition reconcile keeps the shared modifier")
	session.tick(0.0)
	check(session.pose_node == pose_node and is_same(session.pose_config, config),
		"the transition tick keeps the pose and the live config")
	check(view.id == CATALOG.STANDING_TEST and view.pose_state == VIEW.TRANSITIONING,
		"the transition tick keeps the target view")
	session.tick(0.6)
	check(view.pose_state == VIEW.STEADY and view.id == CATALOG.STANDING_TEST,
		"the transition completes steady on the target")
	check(session._started and is_same(session.pose_config, config),
		"the transition completion keeps the session and the live config")
	var text := FileAccess.get_file_as_string(SERVICE_PATH)
	for name: String in ["request_pose", "tick", "_fill_transition_view", "_absorb_switches",
			"_absorb_events"]:
		var body := _func_body(text, name)
		check(not body.is_empty(), "poses/service.gd exposes %s()" % name)
		for call: String in ACT_EXIT:
			check(not body.contains(call), "%s does not call %s" % [name, call])
	_free_fixture(made)
	check(act_body.is_queued_for_deletion(), "the act exit frees the act body once")


## The face-sit pair: both edges keep the pose node, the live config and the view; the contact
## switch begins and restores the face driver; the one act exit restores and frees once.
func _check_facesit_transition() -> void:
	var made := _fixture(CATALOG.MISSIONARY, {})
	var session: RefCounted = made["session"]
	var view: RefCounted = session.view()
	var config: Dictionary = session.pose_config
	var pose_node: Node = session.pose_node
	var points := FakeFacePoints.new()
	points.mouth = Vector3(0.0, 0.82, 0.65)
	points.opening = Vector3(0.0, 0.34, 0.45)
	session.face_point = Callable(points, "mouth_point")
	session.opening_point = Callable(points, "opening_point")
	var act_body := FakeActBody.new()
	session.act_body = act_body
	var forward: Dictionary = session.request_pose(CATALOG.BED_FACESIT, "facesit",
		{"act_state": 2})
	check(str(forward.get("code", "")) == "ok", "the face-sit transition starts")
	check(view.pose_state == VIEW.TRANSITIONING and view.id == CATALOG.BED_FACESIT,
		"the face-sit transition enters the target view")
	session.tick(0.0)
	session.tick(0.45)
	session.tick(0.45)
	check(view.contact_kind == "face", "the face-sit transition switches the contact")
	check(session._face_driver != null and bool(session._face_driver.get("active")),
		"the face-sit contact begins the driver")
	session.tick(0.7)
	check(view.pose_state == VIEW.STEADY and view.id == CATALOG.BED_FACESIT,
		"the face-sit transition completes steady")
	check(session.pose_node == pose_node and is_same(session.pose_config, config),
		"the face-sit forward keeps the pose node and the live config")
	check(session._started, "the face-sit forward keeps the session")
	var held: Vector3 = pose_node.contact_offset
	check(held.is_finite(), "the face-sit pose node carries the live offset")
	var reverse: Dictionary = session.request_pose(CATALOG.MISSIONARY, "facesit",
		{"act_state": 2})
	check(str(reverse.get("code", "")) == "ok", "the face-sit reverse starts")
	session.tick(0.0)
	check(view.contact_kind == "opening", "the reverse restores the opening contact")
	check(not bool(session._face_driver.get("active")),
		"the reverse restores the face driver")
	check(pose_node.contact_offset.is_zero_approx(),
		"the reverse zeroes the pose node's offset")
	session.tick(1.2)
	check(view.pose_state == VIEW.STEADY and view.id == CATALOG.MISSIONARY,
		"the face-sit reverse completes steady")
	check(session.pose_node == pose_node and is_same(session.pose_config, config),
		"the face-sit reverse keeps the pose node and the live config")
	session.release_pose()
	check(session.pose_node == null and pose_node.is_queued_for_deletion(),
		"the face-sit act exit frees the pose node once")
	check(session._face_driver != null and not bool(session._face_driver.get("active")),
		"the face-sit act exit leaves the driver inactive")
	check(act_body.is_queued_for_deletion(), "the face-sit act exit frees the act body once")
	_free_fixture(made)


## The pose-scope steps are the seam a transition calls: they must not reach an act exit.
func _check_no_act_exit() -> void:
	var text := FileAccess.get_file_as_string(SERVICE_PATH)
	for name: String in ["leave_pose_start", "leave_pose_body"]:
		var body := _func_body(text, name)
		check(not body.is_empty(), "poses/service.gd exposes %s()" % name)
		for call: String in ACT_EXIT:
			check(not body.contains(call), "%s does not call %s" % [name, call])


func _func_body(text: String, name: String) -> String:
	var needle := "func " + name + "("
	var start := text.find(needle)
	if start < 0:
		return ""
	var next := text.find("\nfunc ", start + needle.length())
	if next < 0:
		next = text.length()
	return text.substr(start, next - start)
