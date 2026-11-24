extends "res://mods/unfplap/tests/support/suite.gd"
## The modifier-profile reconcile: a pose change keeps the shared owner, installs the target-only
## owners and removes the source-only ones, while `leave_pose_body()` stays the act-exit removal.
## The synthetic profile lives only in the session's test seam, never in the shipped table.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/poses/test_modifier_profile.gd

const SESSION := preload("res://mods/unfplap/poses/api.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")
const SPECS := preload("res://mods/unfplap/shared/pose_specs.gd")
const POSE_SPEC := preload("res://mods/unfplap/poses/pose_spec.gd")
const AUTHORED := preload("res://mods/unfplap/poses/authored_pose.gd")
const ACT_FACTS := preload("res://mods/unfplap/shared/act_facts.gd")
const POSE_STATE := preload("res://mods/unfplap/poses/pose_state.gd")



class FakePony extends Node3D:
	var skeleton: Variant = null
	var hair_skeleton: Variant = null
	var boop_node: Variant = null
	var body_scale := 1.0


class FakeActBody extends "res://mods/unfplap/poses/missionary_anon.gd":
	var profile := ""
	var weight := 1.0

	func pose_changed(value := "", value_weight := 1.0) -> void:
		profile = str(value)
		weight = value_weight

	func set_weight(value: float) -> void:
		weight = value

	func set_pose_assets(_from_value: AUTHORED, _to_value: AUTHORED, _weight: float) -> void:
		pass


class FakeRun extends POSE_STATE.Run:
	pass


func _start(raw: Dictionary) -> SESSION.PoseStart:
	var start := SESSION.PoseStart.new()
	start.pose_id = str(raw.get("pose_id", ""))
	return start


func run() -> void:
	var pony := FakePony.new()
	root.add_child(pony)
	var body := Skeleton3D.new()
	body.add_bone("pony_hips")
	var hair := Skeleton3D.new()
	hair.add_bone("mTail1")
	pony.skeleton = body
	pony.hair_skeleton = hair
	var bed := Node3D.new()
	root.add_child(bed)
	var facts := ACT_FACTS.new()
	facts.pony = pony
	facts.pony_id = "twilight_sparkle"
	facts.bed = bed
	facts.features = {"missionary_body_motion": true, "standing_body_sway": true}
	var session: SESSION = SESSION.new(facts)
	check(session.begin_act(_start({"pose_id": CATALOG.MISSIONARY})),
		"the missionary pose begins")
	var view: RefCounted = session.view()
	var prone: Node = session.prone_sway
	var tail_lay: Node = session.tail_lay
	check(prone != null and tail_lay != null, "the missionary profile installs its owners")

	# The test seam: a profile the shipped table does not carry, sharing only the tail lay with
	# missionary. It proves the reconcile without adding data.
	session.modifier_profiles["synthetic_tail"] = ["tail_lay"]
	check(not SPECS.MODIFIER_PROFILES.has("synthetic_tail"),
		"the synthetic profile is not shipped data")
	_synthetic_spec(session, "synthetic_tail", "synthetic_tail")
	_fill(view, "missionary", "synthetic_tail", "synthetic_tail", "bed", "synthetic_tail")
	session.pose_changed(view)
	check(session.prone_sway == null and prone.get_parent() == null
		and prone.is_queued_for_deletion(),
		"the source-only owner is removed")
	check(session.tail_lay == tail_lay and tail_lay.get_parent() == hair,
		"the shared owner keeps its node and parent")

	# The standing profile installs its target-only owners and removes the tail lay. The standing
	# body sway is enabled; the ear twitch is off, so its feature gate keeps it out.
	_fill(view, "synthetic_tail", CATALOG.STANDING, CATALOG.STANDING, "standing", "standing")
	session.pose_changed(view)
	check(session.tail_lay == null and tail_lay.is_queued_for_deletion(),
		"the target loses the source-only tail lay")
	var sway: Node = session.body_sway
	var tail: Node = session._tail
	check(sway != null and sway.get_parent() == body, "the target-only body sway is installed")
	check(tail != null and tail.get_parent() == hair, "the target-only standing tail is installed")
	check(session.ear_twitch == null, "the disabled feature keeps its owner out")

	# The live settings edit enters the same reconcile with the new feature flags; this is the
	# session's `apply_live_settings()` path. A changed gate removes or installs its owner against
	# the unchanged view, even on a shared keep.
	_fill(view, CATALOG.STANDING, CATALOG.STANDING, CATALOG.STANDING, "standing", "standing")
	facts.features = {"standing_body_sway": false}
	session.apply_live_settings()
	check(session.body_sway == null and sway.is_queued_for_deletion(),
		"the live feature refresh removes the disabled owner")
	check(not bool(session._facts.features.get("standing_body_sway", false)),
		"the live feature refresh reads the facts' flags")
	facts.features = {"standing_body_sway": true}
	session.apply_live_settings()
	sway = session.body_sway
	check(sway != null and sway.get_parent() == body,
		"the live feature refresh installs the enabled owner")

	session.leave_pose_body()
	check(session.body_sway == null and sway.is_queued_for_deletion(),
		"the act-exit leave still removes the extra modifier")
	check(session._tail == tail and tail.get_parent() == hair,
		"the pose-body leave keeps the standing tail")

	# The `anon` channel: blend carries the edge weight and switch names the authored profile; a
	# hold keeps the adapter. The adapter here is a fake so the channel contract is pinned without
	# a game scene.
	var fake_body := FakeActBody.new()
	session._act_body = fake_body
	view.anon = {"mode": "act_body", "profile": "missionary"}
	view.weight = 0.4
	var run := FakeRun.new()
	run.edge = {"channels": {"anon": {"kind": "blend"}}}
	session._run = run
	session._apply_anon_channel(view)
	check(is_equal_approx(fake_body.weight, 0.4), "the anon blend carries the edge weight")
	run.edge = {"channels": {"anon": {"kind": "switch", "profile": "authored"}}}
	session._apply_anon_channel(view)
	check(fake_body.profile == "authored" and is_equal_approx(fake_body.weight, 1.0),
		"the anon switch names the authored profile")
	run.edge = {"channels": {"anon": {"kind": "hold"}}}
	session._apply_anon_channel(view)
	check(fake_body.profile == "authored", "the anon hold keeps the retargeted adapter")
	session._run = null
	session._act_body = null

	session.release_pose()
	check(session.pose_node == null and session.body_sway == null and session._tail == null,
		"the final release clears the pose and the tail")
	check(session.tail_lay == null and session.prone_sway == null,
		"the final release keeps every extra owner cleared")
	check(not session._started and session.view().id == "",
		"the final release leaves the session idle")
	fake_body.free()
	body.free()
	hair.free()
	session.free()

	if failures == 0:
		print("MODIFIER_PROFILE_PASS")
	finish()


## Point the live view at a profile pair without rebuilding the evaluator. `pose_changed` reads
## the from/to spec rows for the profiles and the view fields for the owners' hooks.
func _fill(view: RefCounted, from_id: String, to_id: String, id: String, family: String,
		profile: String) -> void:
	view.from_id = from_id
	view.to_id = to_id
	view.id = id
	view.family = family
	view.modifiers = {"profile": profile}
	view.anon = {"mode": "player_body", "profile": "standing"}
	view.weight = 1.0


## A valid synthetic spec row in the session's registry cache.
func _synthetic_spec(session: SESSION, spec_id: String, profile: String) -> void:
	var row: Dictionary = SPECS.SPECS[CATALOG.MISSIONARY].duplicate(true)
	row["id"] = spec_id
	row["display_name"] = "Synthetic"
	row["base"] = CATALOG.MISSIONARY
	row["delta"] = ""
	row["driver"] = ""
	row["modifiers"] = {"profile": profile}
	row["public"] = false
	row["offerable"] = false
	var spec: Variant = POSE_SPEC.from_dict(spec_id, row, {})
	check(spec != null, "the synthetic spec %s builds" % spec_id)
	if spec != null:
		session._registry._specs[spec_id] = spec
