extends Node
## Service: poses
## Scope: pony
## Contract: docs/poses.md
## The act's pose session: the live pose and its space, the skeleton write, the act body, the
## teardown and the pose diagnostics.

const POSE := preload("res://mods/unfplap/poses/skeleton_pose.gd")
const POSE_SPEC := preload("res://mods/unfplap/poses/pose_spec.gd")
const DIAG := preload("res://mods/unfplap/poses/diagnostics.gd")
const MODIFIERS := preload("res://mods/unfplap/poses/modifiers.gd")
const TRANSITION_SPEC := preload("res://mods/unfplap/poses/transition_spec.gd")
const AUTHORED := preload("res://mods/unfplap/poses/authored_pose.gd")
const MISSIONARY_ANON := preload("res://mods/unfplap/poses/missionary_anon.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")
const POSE_VIEW := preload("res://mods/unfplap/shared/pose_view.gd")
const ACT_FACTS := preload("res://mods/unfplap/shared/act_facts.gd")
const POSE_STATE := preload("res://mods/unfplap/poses/pose_state.gd")
const ORAL_TURN := preload("res://mods/unfplap/poses/oral_turn.gd")
const FACE_CONTACT := preload("res://mods/unfplap/poses/face_contact.gd")
const SPECS := preload("res://mods/unfplap/shared/pose_specs.gd")
const REGISTRY := preload("res://mods/unfplap/poses/registry.gd")
const SETTINGS := preload("res://mods/unfplap/settings/api.gd")
const WORLD := preload("res://mods/unfplap/world/api.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")

## The empty sets the reconcile and the anon channel read, so a steady tick allocates nothing.
const NO_CHANNEL := {}
## The absent pose frame: a real transform whose infinite origin no reader mistakes for space.
const NO_FRAME := Transform3D(Basis.IDENTITY, Vector3.INF)


## One pose request's verdict; `ok` is true only for the accepted code.
class PoseResult extends RefCounted:
	var ok := false
	var code := ""
	var reason := ""

	static func make(code_value: String, reason_text := "") -> PoseResult:
		var out := PoseResult.new()
		out.code = code_value
		out.ok = code_value == "ok"
		out.reason = reason_text
		return out


## The start values the facts and settings cannot supply.
class PoseStart extends RefCounted:
	var pose_id := ""
	var look := Vector3.ZERO
	var camera_at := Vector3.INF


## The standing tail, as consumers move it.
class PoseTail extends RefCounted:
	var _session: Variant = null

	func _init(session: Variant) -> void:
		_session = session

	## The lift/flick weight the afterglow sets.
	func target(value: float) -> void:
		_session._set_tail_target(value)

	func flick(count: int) -> void:
		_session._flick_tail(count)

	## The thrust wave the reaction facade adds at the stroke.
	func thrust(weight: float) -> void:
		_session._thrust_tail(weight)


## One asset or rig readiness answer.
class PoseVerdict extends RefCounted:
	var ok := false
	var reason := ""
	var missing: Array[String] = []


## The asset and rig verdicts the scene gate reads.
class PoseReadiness extends RefCounted:
	var _session: Variant = null
	var _rig_checked := false
	var _rig_skeleton := 0
	var _rig_revision := -1
	var _rig_asset_path := ""
	var _rig_missing_bones: Array[String] = []

	func _init(session: Variant) -> void:
		_session = session

	## The parsed asset a candidate names, or the live rendered asset when it is empty.
	func asset(candidate := "") -> AUTHORED:
		return _session._readiness_asset(candidate)

	## The candidate's pose-asset verdict, with the gate row's reason.
	func asset_verdict(candidate := "") -> PoseVerdict:
		var verdict := PoseVerdict.new()
		var spec: Variant = _session._candidate_spec(candidate)
		if spec == null:
			verdict.reason = "pose_asset: no pose"
			return verdict
		var asset: Variant = _session._asset_for_spec(spec)
		if asset == null:
			verdict.reason = "pose_asset: no asset for %s" % str(spec.id)
			return verdict
		if not asset.available:
			var why: String = asset.error
			verdict.reason = "pose_asset: %s" % (why if not why.is_empty() else "not loaded")
			return verdict
		if not asset.usable(str(spec.frame)):
			verdict.reason = "pose_asset: %s asset in a %s pose" % [asset.frame, str(spec.frame)]
			return verdict
		verdict.ok = true
		return verdict

	## The candidate's rig verdict: the authored bones the live rig lacks, cached per skeleton and
	## asset revision.
	func rig_verdict(candidate := "") -> PoseVerdict:
		var verdict := PoseVerdict.new()
		var pony: Variant = _session._pony()
		var sk: Variant = pony.get("skeleton") if is_instance_valid(pony) else null
		if not sk is Skeleton3D:
			return verdict
		var skeleton := sk as Skeleton3D
		var instance := skeleton.get_instance_id()
		var asset_path: String = _session._asset_path_for(candidate)
		if asset_path.is_empty():
			asset_path = AUTHORED.PATH
		if _rig_checked and instance == _rig_skeleton and _rig_revision == AUTHORED.revision \
				and _rig_asset_path == asset_path:
			verdict.missing = _rig_missing_bones
		else:
			_rig_checked = true
			_rig_skeleton = instance
			_rig_revision = AUTHORED.revision
			_rig_asset_path = asset_path
			_rig_missing_bones = _session._diagnostic_asset(candidate).missing_bones(skeleton)
			verdict.missing = _rig_missing_bones
		verdict.ok = verdict.missing.is_empty()
		verdict.reason = _rig_reason(verdict.missing)
		return verdict

	## Clear the cache after a pose-scope leave or a release.
	func _reset() -> void:
		_rig_checked = false
		_rig_skeleton = 0
		_rig_revision = -1
		_rig_asset_path = ""
		_rig_missing_bones = []

	func _rig_reason(missing: Array[String]) -> String:
		if missing.is_empty():
			return ""
		var names: PackedStringArray = []
		for i in mini(3, missing.size()):
			names.append(str(missing[i]))
		var text := "pose_rig: missing %s" % ", ".join(names)
		if missing.size() > 3:
			text += " (+%d more)" % (missing.size() - 3)
		return text


## The debug rows and the settled log.
class PoseDiagnostics extends RefCounted:
	var _session: Variant = null
	var _pose_logged := false
	var _trace_frames := 0

	func _init(session: Variant) -> void:
		_session = session

	func state_rows(state: int) -> Array[String]:
		return DIAG.state_rows(_session, state)

	func log_settled(state: int, anon_diag: Callable) -> void:
		DIAG.log_settled(_session, state, anon_diag, self)

	func trace_sample(state: int) -> void:
		DIAG.trace_sample(_session, state, self)


## The act's own Anon body, as consumers see it.
class PoseActBody extends RefCounted:
	var _session: Variant = null

	func _init(session: Variant) -> void:
		_session = session

	## True while the adapter is installed and active.
	func live() -> bool:
		return _session._act_body_live()

	func mouth_point() -> Vector3:
		return _session._act_body_mouth_point()

	func eye_point() -> Vector3:
		return _session._act_body_eye_point()

	## His placed avatar's world transform.
	func transform() -> Transform3D:
		return _session._act_body_transform()

	func diag_row(face: Vector3, vulva: Vector3) -> String:
		return _session._act_body_diag_row(face, vulva)

	func refresh_palm() -> void:
		_session._act_body_refresh_palm()

	## The adapter node, or null outside a bed act body.
	func node() -> Node:
		return _session._act_body_node()


## The act's live view fields.
var _bed_node: Node3D = null
## True between a successful `begin()` and `release_pose()`. The runtime keeps one session per pony.
var _started := false
## The live pose config, one object shared by the view and the evaluator.
var _pose_config: Dictionary = {}
## The standing tail handle consumers move; it no-ops while no tail is installed.
var _tail_handle: PoseTail = null
## The act-body handle consumers read; it reports nothing while no body is installed.
var _act_body_handle: PoseActBody = null
## The verdict and diagnostic handles; each owns the cache it fills.
var _readiness: PoseReadiness = null
var _diagnostics: PoseDiagnostics = null
## The one pose read model for the act, and the registry that validates the static spec table.
var _view: POSE_VIEW
var _registry: REGISTRY

## The live state-machine value; the view mirrors it. `begin()` enters `ENTERING`, settles `STEADY`,
## a request enters `TRANSITIONING` and `release_pose()` exits through `EXITING` to `IDLE`.
var _state := POSE_VIEW.IDLE
## The running edge, or null. A release aborts it without an act exit.
var _run: POSE_STATE.Run = null
var _from_id := ""
var _target_id := ""
var _target_spec: POSE_SPEC = null
## The target's settings snapshot, by reference from the view's `to_config`.
var _target_config: Dictionary = {}
var _target_presentation: Dictionary = {}
## The authored asset on each side of the live edge, or the live pose's asset outside one; the
## target side is cached at request and adopted on completion.
var _from_asset: AUTHORED = null
var _target_asset: AUTHORED = null

## The pose modifier and the extra scene modifiers the act installs.
var _pose_node: POSE = null
## The tail, its lay, the sways and the ear twitch, with their profile table.
var _mods: MODIFIERS = null
## The standing oral actor/frame turn the session owns. It preloads no scene and reads the host
## callables below; the edge weight drives it.
var _oral_turn: ORAL_TURN
## The bed face-sit contact driver. The contact switch to `face` begins it and the reverse switch
## or the one act exit restores it; it never ends the act.
var _face_driver: FACE_CONTACT
## The act's own Anon body on the `act_body` specs, or null on the player-body specs. The session
## creates, installs and frees it; the anatomy bridge only receives the opaque handle.
var _act_body: MISSIONARY_ANON = null
## The camera position the standing tail chooses its side against, from the begin context.
var _tail_anchor := Vector3.INF

## Bed space for the authored pose. The runtime reads it through `_pose_session.bed_frame`.
var _bed_frame: Variant = null
var _bed_frame_source := Transform3D.IDENTITY
var _bed_frame_source_saved := false
## Ground space for a ground pose, seeded from the pony root at pose start. It tracks the root's
## position and yaw every tick.
var _ground_frame: Variant = null
var _ground_frame_source := Transform3D.IDENTITY
var _ground_frame_source_saved := false


## A shared unavailable asset instance for a pose whose row supplies no asset.
var _empty_asset: AUTHORED = null

## The pony's pre-act bone snapshot.
var _saved_bones: Array[Transform3D] = []
var _saved_hair: Array[Transform3D] = []
var _saved_skeleton: Skeleton3D
var _saved_hair_skeleton: Skeleton3D

## The act context the session reads for the pony, its id, the bed, the features and the live
## presentation. The runtime builds it before the session.
var _facts: ACT_FACTS = null


func _init(facts: ACT_FACTS = null) -> void:
	_facts = facts
	_view = POSE_VIEW.new()
	_registry = REGISTRY.new()
	_oral_turn = ORAL_TURN.new()
	_face_driver = FACE_CONTACT.new()
	_tail_handle = PoseTail.new(self)
	_act_body_handle = PoseActBody.new(self)
	_readiness = PoseReadiness.new(self)
	_diagnostics = PoseDiagnostics.new(self)
	_mods = MODIFIERS.new(self)
	_mods.set_profiles(SPECS.MODIFIER_PROFILES)
	_bind_oral()
	_bind_face()


## The presented body, or null outside a scene.
func _pony() -> Node3D:
	if _facts == null:
		return null
	var value: Variant = _facts.pony
	return value as Node3D if is_instance_valid(value) else null


## The act's stable id, or "" outside an act.
func _pony_id() -> String:
	return _facts.pony_id if _facts != null else ""


## The standing tail consumers move; a released pose's handle is a no-op.
func tail() -> PoseTail:
	return _tail_handle


## The act's own Anon body; a released pose's handle reports not live.
func act_body() -> PoseActBody:
	return _act_body_handle


## The asset and rig verdicts the scene gate reads.
func readiness() -> PoseReadiness:
	return _readiness


## The debug rows and the settled log.
func diagnostics() -> PoseDiagnostics:
	return _diagnostics


## The one pose read model the act view carries. `begin()` fills it and `release_pose()` clears it;
## the object is never re-created, so a consumer can keep the reference for the act.
func view() -> POSE_VIEW:
	return _view


## Build the pose for a fresh act from its start values. A live pose or a pony with no body skeleton
## returns false with nothing installed; the started flag only follows an install.
func begin_act(start: PoseStart) -> bool:
	return _begin(start)


## Rebuild the live pose on a new skeleton, keeping the pose the act had; the start ramp is skipped
## because the act is continuing, not entering.
func rebuild_act(start: PoseStart) -> bool:
	if not begin_act(start):
		return false
	settle()
	return true


func _begin(start: PoseStart) -> bool:
	if _started:
		LOG.debug("pose session: begin refused, a pose is already live")
		return false
	if start == null:
		return false
	var pony := _pony()
	var skeleton: Variant = pony.get("skeleton") if is_instance_valid(pony) else null
	if not skeleton is Skeleton3D:
		LOG.debug("pose session: no body skeleton to pose")
		return false
	# A fresh act starts with no edge and no target snapshot; a failed begin never gets here.
	_abort_target()
	_oral_turn.reset()
	_face_driver.reset()
	_state = POSE_STATE.next(_state, "begin")
	var start_id := start.pose_id
	var bed: Variant = _facts.bed if _facts != null else null
	_bed_node = bed if bed is Node3D else null
	_diagnostics._pose_logged = false
	_diagnostics._trace_frames = 0
	_pose_node = POSE.new()
	_pose_node.name = "UnfplapPose"
	_pose_node.mare = pony
	# Fill the view first: the active settings group, not the act's start id, drives the live config.
	# The sync merges in place, so the modifier, the view and the runtime share one object.
	var start_spec: Variant = _registry.spec(start_id)
	_fill_view(start_spec)
	_view.contact_kind = _spec_contact_kind(start_spec)
	_sync_live_config()
	_pose_node.pose_config = _pose_config
	# Resolve the start asset before the evaluator pair: the same instance is the live rendered
	# asset and both sides of a pose that starts settled.
	var start_asset: AUTHORED = _asset_for_spec(start_spec)
	if start_asset != null and start_asset.available \
			and start_asset.usable(str(_view.frame)):
		_pose_node.authored = start_asset
	_from_asset = _pose_node.authored
	_target_asset = _from_asset
	_sync_view_asset()
	_pose_node.set_pose(_effective_driver(start_spec), _effective_driver(start_spec),
		_effective_delta(start_spec), _effective_delta(start_spec), _pose_config, _pose_config,
		_from_asset, _target_asset)
	_pose_node.set_weight(1.0)
	_pose_node.look_point = start.look
	_pose_node.amount = 0.0
	_pose_node.target_amount = 1.0
	if str(_view.frame) == "bed":
		var bed_space := _missionary_pose_frame()
		if _has_frame(bed_space):
			_bed_frame = bed_space
			_bed_frame_source_saved = is_instance_valid(_bed_node)
		else:
			_bed_frame = null
			_bed_frame_source_saved = false
		if _bed_frame_source_saved:
			_bed_frame_source = (_bed_node as Node3D).global_transform
		_pose_node.bed_frame = _bed_frame
		_view.bed_frame = _bed_frame
	else:
		var ground := _ground_pose_frame()
		if _has_frame(ground):
			_ground_frame = ground
			_ground_frame_source_saved = is_instance_valid(pony)
		else:
			_ground_frame = null
			_ground_frame_source_saved = false
		if _ground_frame_source_saved:
			_ground_frame_source = (pony as Node3D).global_transform
		_pose_node.ground_frame = _ground_frame
		_pose_node.size_name = SETTINGS.pony_size_name()
	DIAG.log_base(self)
	(skeleton as Skeleton3D).add_child(_pose_node)
	var family := str(_view.family)
	if family == "bed":
		if _feature("missionary_body_motion"):
			_mods.install_prone_sway(skeleton)
	elif family == "standing":
		if _feature("standing_body_sway"):
			_mods.install_body_sway(skeleton)
		if _feature("thrust_ear_twitch"):
			_mods.install_ear_twitch()
	_started = true
	if family == "bed":
		_mods.install_tail_lay()
	_state = POSE_STATE.next(_state, "entered")
	_view.pose_state = _state
	if family == "standing":
		_tail_anchor = start.camera_at
		_mods.install_tail()
	# A row whose base contact is already `face` starts the live mouth follow here, only to capture
	# the residual: the authored asset is already on the bed.
	if str(_view.contact_kind) == "face":
		_face_driver.begin(_view, _bed_frame)
		_face_tick(0.0)
	return true


func _fill_view(spec: POSE_SPEC) -> void:
	if spec == null:
		_view.clear()
		LOG.debug("pose view: no spec for the start pose")
		return
	_view.fill(spec, _pose_config)


## The spec row's base contact kind (`opening` for standing and missionary, `mouth` for the
## internal oral pose). An edge switch overrides it while it runs; completion settles it here.
func _spec_contact_kind(spec: POSE_SPEC) -> String:
	if spec == null:
		return "none"
	var value: Variant = spec.contact
	return str((value as Dictionary).get("kind", "none")) if value is Dictionary else "none"


## Point the turn at the act facts; the driver reads the live mouth, opening and kiss from them.
func _bind_oral() -> void:
	if _oral_turn == null:
		_oral_turn = ORAL_TURN.new()
	_oral_turn.bind(_facts)


## Bind the face driver to the act facts; the anatomy bridge stays behind the facts handle.
func _bind_face() -> void:
	if _face_driver == null:
		_face_driver = FACE_CONTACT.new()
	_face_driver.bind(_facts)


## True for the authored oral pair in either direction.
func _oral_pair(from_id: String, to_id: String) -> bool:
	return (from_id == CATALOG.STANDING and to_id == CATALOG.STANDING_ORAL) \
		or (from_id == CATALOG.STANDING_ORAL and to_id == CATALOG.STANDING)


## The spec's driver, or the driver of a base further up; the first row that names one wins and a
## repeated base ends the search.
func _effective_driver(spec: POSE_SPEC) -> String:
	var cursor: POSE_SPEC = spec
	var seen: Dictionary = {}
	while cursor != null:
		var path := str(cursor.driver)
		if not path.is_empty():
			return path
		var base := str(cursor.base)
		if base.is_empty() or seen.has(base):
			return ""
		seen[base] = true
		cursor = _registry.spec(base)
	return ""


## The procedural delta path; empty for a pose whose row carries no delta. `standing_oral` is the
## first shipped row with one.
func _effective_delta(spec: POSE_SPEC) -> String:
	return str(spec.delta) if spec != null else ""


## The authored pose document of a spec row, or the nearest base that supplies one. An internal row
## with no asset of its own inherits it from its base chain.
func _effective_asset(spec: POSE_SPEC) -> String:
	var cursor: POSE_SPEC = spec
	var seen: Dictionary = {}
	while cursor != null:
		var path := str(cursor.asset)
		if not path.is_empty():
			return path
		var base := str(cursor.base)
		if base.is_empty() or seen.has(base):
			return ""
		seen[base] = true
		cursor = _registry.spec(base)
	return ""


## Warm the shared asset cache with one authored file before its first reader, so no idle scan or act
## start pays for the parse. A row with no asset is a quiet no-op.
static func warm_asset(path: String) -> void:
	if not path.is_empty():
		AUTHORED.shared(path)


## Re-read the authored missionary base from disk for the debug Reload posed base action; returns an
## empty string on success, otherwise the reader's complaint.
static func reload_authored_base() -> String:
	return AUTHORED.reload_file()


## The spec a candidate names: the id's row, or the live view's row when the candidate is empty.
func _candidate_spec(candidate: String = "") -> POSE_SPEC:
	var spec_id := candidate
	if spec_id.is_empty() and _view != null:
		spec_id = str(_view.id)
	if spec_id.is_empty():
		return null
	return _registry.spec(spec_id)


## The parsed asset for a candidate spec, or null when the row and its chain supply none.
func _asset_for(candidate: String = "") -> AUTHORED:
	var spec: POSE_SPEC = _candidate_spec(candidate)
	if spec == null:
		return null
	var path := _effective_asset(spec)
	if path.is_empty():
		return null
	return AUTHORED.shared(path)


## The parsed asset for an already resolved spec.
func _asset_for_spec(spec: POSE_SPEC) -> AUTHORED:
	var path := _effective_asset(spec)
	return AUTHORED.shared(path) if not path.is_empty() else null


## The path the rig gate and diagnostics name for a candidate.
func _asset_path_for(candidate: String = "") -> String:
	var spec: POSE_SPEC = _candidate_spec(candidate)
	return _effective_asset(spec) if spec != null else ""


## The pose id of the live rendered side: the source while an edge runs, the view's pose otherwise.
func _live_spec_id() -> String:
	if _run != null and not _from_id.is_empty():
		return _from_id
	return str(_view.id)


## One authored edge request, answered with `PoseResult`; a refusal changes nothing at all.
func request_pose(target_id: String, trigger: String, consent := "") -> PoseResult:
	var from_id := str(_view.id)
	var target_spec: POSE_SPEC = _registry.spec(target_id)
	var edge_id := from_id + "__" + target_id
	var edge: TRANSITION_SPEC = _registry.edge(edge_id)
	var act_state := _facts.state if _facts != null else 0
	var forms := _request_forms()
	var views := _request_views()
	var features := _facts_features()
	var checks := _request_checks(target_spec, edge, consent, forms, views, features)
	var code := POSE_STATE.request_code(_state, act_state, from_id, target_id,
		edge != null, checks)
	if code != "ok":
		return PoseResult.make(code, _reason(code, target_id))
	# The bed face-sit is a live arrangement: its provider must exist before the edge starts.
	if _spec_contact_kind(target_spec) == "face":
		var face_reason := _face_ready()
		if not face_reason.is_empty():
			return PoseResult.make("refused", face_reason)
	var run: POSE_STATE.Run = POSE_STATE.start_edge(edge.data, from_id, target_id)
	if run == null:
		return PoseResult.make("missing_asset", "the edge did not start")
	# Cache the target by settings group, so a row with no blocks of its own (`standing_test`) still
	# gets the standing pose and presentation.
	_from_id = from_id
	_target_id = target_id
	_target_spec = target_spec
	var group := str(target_spec.settings_group)
	_target_presentation = SETTINGS.act_snapshot(group).presentation
	_target_config = _config_for_group(group, _target_presentation)
	_target_asset = _asset_for_spec(target_spec)
	_from_asset = _live_asset()
	if _from_asset == null:
		_from_asset = _asset_for_spec(_registry.spec(from_id))
	_run = run
	_state = POSE_STATE.next(_state, "request")
	_fill_transition_view()
	var from_spec: POSE_SPEC = _registry.spec(_from_id)
	_pose_node.set_pose(_effective_driver(from_spec), _effective_driver(_target_spec),
		_effective_delta(from_spec), _effective_delta(_target_spec),
		_pose_config, _target_config, _from_asset, _target_asset)
	_pose_node.set_weight(_run.weight)
	if _oral_pair(from_id, target_id):
		_oral_turn.begin(target_id == CATALOG.STANDING_ORAL, _view)
	LOG.debug("pose request %s -> %s (%s): ok", [from_id, target_id, trigger])
	return PoseResult.make("ok")


## The player's live form.
func _request_forms() -> Array[String]:
	var forms: Array[String] = []
	forms.append("pony" if _player_pony() else "human")
	return forms


## The live display.
func _request_views() -> Array[String]:
	var views: Array[String] = []
	views.append("vr" if _headset_view() else "desktop")
	return views


## Why the bed face-sit cannot start right now, or "" when it can: the anatomy master, the live act
## body and the anatomy bridge, and no running kiss.
func _face_ready() -> String:
	if not SETTINGS.anatomy_on() or not is_instance_valid(_act_body):
		return "the anatomy is not available"
	var anatomy_body: Variant = _facts.missionary_body() if _facts != null else null
	if anatomy_body == null or not bool(anatomy_body.live()):
		return "the anatomy is not available"
	if _facts != null and bool(_facts.kiss_active):
		return "a kiss is running"
	return ""


func _player_pony() -> bool:
	return _facts != null and bool(_facts.player_pony)


func _headset_view() -> bool:
	return _facts != null and bool(_facts.headset_view)


func _facts_features() -> Dictionary:
	if _facts == null:
		return {}
	var value: Variant = _facts.features
	return value as Dictionary if value is Dictionary else {}


## The target spec and the edge requirements against the request record, in the order
## `pose_state.request_code()` reports them. A missing flag passes.
func _request_checks(target_spec: POSE_SPEC, edge: TRANSITION_SPEC, consent: String,
		forms: Array[String], views: Array[String], features: Dictionary) -> Dictionary:
	var requires: Dictionary = {}
	if edge != null:
		requires = edge.requires
	var form_ok := false
	var view_ok := false
	var asset_ok := false
	if target_spec != null:
		form_ok = _intersects(target_spec.forms, forms)
		view_ok = _intersects(target_spec.views, views)
		asset_ok = not str(target_spec.base).is_empty() \
				or not str(target_spec.delta).is_empty() \
				or not str(target_spec.driver).is_empty()
	var wanted_forms: Variant = requires.get("forms", [])
	if form_ok and wanted_forms is Array and not (wanted_forms as Array).is_empty():
		form_ok = _intersects(wanted_forms as Array, forms)
	var wanted_views: Variant = requires.get("views", [])
	if view_ok and wanted_views is Array and not (wanted_views as Array).is_empty():
		view_ok = _intersects(wanted_views as Array, views)
	var features_ok := true
	var wanted_features: Variant = requires.get("features", [])
	if wanted_features is Array:
		for name_value: Variant in wanted_features as Array:
			if not bool(features.get(str(name_value), false)):
				features_ok = false
				break
	var wanted_consent := str(requires.get("consent", ""))
	var consent_ok := wanted_consent.is_empty() or consent == wanted_consent
	return {
		"form_ok": form_ok,
		"view_ok": view_ok,
		"features_ok": features_ok,
		"consent_ok": consent_ok,
		"asset_ok": asset_ok,
		"locked": false,
	}


func _intersects(declared: Array, live: Array[String]) -> bool:
	for value: Variant in declared:
		if str(value) in live:
			return true
	return false


func _reason(code: String, target_id: String) -> String:
	match code:
		"same":
			return "already %s" % target_id
		"bad_phase":
			return "the act is not active"
		"busy":
			return "a transition is running"
		"not_steady":
			return "the pose is not steady"
		"no_edge":
			return "no edge to %s" % target_id
		"unsupported_form":
			return "the form is not supported"
		"unsupported_view":
			return "the view is not supported"
		"refused":
			return "a requirement is not met"
		"missing_asset":
			return "the target has no pose asset"
		"locked":
			return "the pose is locked"
	return ""


## The transition view: target identity and profiles from `fill()`, the from/to sides and the live
## edge clock. The live config is the from side and the target snapshot the to side.
func _fill_transition_view() -> void:
	_view.fill(_target_spec, _pose_config)
	_view.from_id = _from_id
	_view.to_id = _target_id
	_view.from_config = _pose_config
	_view.to_config = _target_config
	_view.edge_id = _run.id
	_view.edge_t = _run.t
	_view.weight = _run.weight
	_view.pose_state = _state


## Advance the live edge, apply its switches and events, then settle the view; a no-op outside an
## edge. The oral turn follows the same weight, so the frame write and the blend are one frame.
func tick(delta: float) -> void:
	if _facts != null:
		_oral_turn.pace = _facts.auto_pace
	if _run == null:
		_oral_turn.tick(maxf(delta, 0.0), _view, 1.0)
		_face_tick(delta)
		return
	_run.tick(maxf(delta, 0.0))
	_view.edge_t = _run.t
	_view.weight = _run.weight
	if is_instance_valid(_pose_node):
		_pose_node.set_weight(_view.weight)
	_oral_turn.tick(maxf(delta, 0.0), _view, _view.weight)
	_absorb_switches()
	_face_tick(delta)
	_absorb_events()
	if not _run.complete():
		return
	# Capture the target pair before the target snapshot is dropped, adopt its config into the live
	# object, then settle the evaluator on that pose and its authored asset.
	var completed_target := _target_id
	var completed_driver := _effective_driver(_target_spec)
	var completed_delta := _effective_delta(_target_spec)
	var completed_asset: AUTHORED = _target_asset
	_adopt_target_config()
	if is_instance_valid(_pose_node):
		_pose_node.authored = completed_asset
		_pose_node.from_authored = completed_asset
		_pose_node.to_authored = completed_asset
		_pose_node.set_pose(completed_driver, completed_driver, completed_delta,
			completed_delta, _pose_config, _pose_config, completed_asset, completed_asset)
		_pose_node.set_weight(1.0)
		_pose_node.pose_config = _pose_config
	_from_asset = completed_asset
	_sync_view_asset()
	if is_instance_valid(_act_body):
		_act_body.set_pose_assets(completed_asset, completed_asset, 1.0)
	_state = POSE_STATE.next(_state, "complete")
	_view.pose_state = _state
	_view.contact_kind = _spec_contact_kind(_target_spec)
	_view.from_id = _view.id
	_view.to_id = _view.id
	_view.from_config = _pose_config
	_view.to_config = _pose_config
	_view.edge_id = ""
	_view.edge_t = 0.0
	_view.weight = 1.0
	# The forward edge keeps the turn; the reverse edge returns the captured root and facing and
	# erases the oral keys once. Both run before the target snapshot is dropped.
	if completed_target == CATALOG.STANDING:
		_oral_turn.restore(_view)
	_abort_target()


## Drain the switches that fired since the last tick. The contact switch moves the view's contact
## and the audio switch is the authored speech profile; the log names the payload for the lab.
func _absorb_switches() -> void:
	for name_value: Variant in _run.switches():
		var name := str(name_value)
		var target := _switch_target(name)
		if name == "contact":
			_apply_contact_switch(target)
		LOG.debug("pose switch %s: %s", [name, target])


## Point the view's contact at the authored kind. Leaving the mouth releases the viseme through
## the host, so a reverse edge cannot leave the open mouth behind while the body eases back.
func _apply_contact_switch(kind: String) -> void:
	if kind.is_empty():
		return
	var previous := str(_view.contact_kind)
	_view.contact_kind = kind
	if kind == "face":
		_face_driver.begin(_view, _bed_frame)
	elif previous == "face":
		_face_driver.restore(_view, _pose_node)
	if kind != "mouth" and _facts != null and _facts.set_mouth_viseme.is_valid():
		_facts.set_mouth_viseme.call("")


## Release the mouth contact while the turn continues: the afterglow holds the turned frame and neck
## pose as the part returns to the opening, and no close window opens.
func release_mouth_contact() -> void:
	if str(_view.contact_kind) != "mouth":
		return
	_apply_contact_switch(str(_spec_contact_kind(_registry.spec(CATALOG.STANDING))))
	_oral_turn.release_contact(_view)


## Advance the face driver from the live depth: it writes the pose node's frame-space offset and the
## view's contact target, is a no-op outside a face contact, and allocates nothing.
func _face_tick(delta: float) -> void:
	if _face_driver == null or str(_view.contact_kind) != "face":
		return
	var level := 0.0
	if _facts != null:
		level = clampf(_facts.depth, 0.0, 1.0)
	_face_driver.tick(maxf(delta, 0.0), _view, level, _bed_frame, _pose_node)


func _switch_target(channel: String) -> String:
	var channels_value: Variant = _run.edge.get("channels", {})
	if not channels_value is Dictionary:
		return ""
	var channel_value: Variant = (channels_value as Dictionary).get(channel)
	if not channel_value is Dictionary:
		return ""
	var channel_data := channel_value as Dictionary
	for key: String in ["set", "profile", "to"]:
		var value := str(channel_data.get(key, ""))
		if not value.is_empty():
			return value
	return ""


## Drain the edge events that fired since the last tick. `speech_stop` and `viseme` are the oral
## host actions; `status` is logged. The arrays are the run's own and are not copied.
func _absorb_events() -> void:
	for event_value: Variant in _run.events():
		if not event_value is Dictionary:
			continue
		var event := event_value as Dictionary
		var kind := str(event.get("kind", ""))
		match kind:
			"status":
				LOG.debug("pose status %s: %s", [_target_id, str(event.get("value", ""))])
			"speech_stop":
				if _facts != null and _facts.speech_stop.is_valid():
					_facts.speech_stop.call()
			"viseme":
				if _facts != null and _facts.set_mouth_viseme.is_valid():
					_facts.set_mouth_viseme.call(str(event.get("value", "")))


## Whether the active control set and the live edge lock allow this command. `end` is reserved and
## always allowed. It reports; it does not execute the command.
func request_command(command_id: String) -> bool:
	if command_id.is_empty():
		return false
	if command_id == "end":
		return true
	var set_id := str(_view.controls.get("set", ""))
	var allowed_value: Variant = SPECS.CONTROL_SETS.get(set_id, [])
	if not allowed_value is Array or not (command_id in (allowed_value as Array)):
		return false
	if _run != null and _lock_denies(command_id):
		return false
	return true


## A live edge whose `controls` channel is a `lock` denies its `block` list and anything outside a
## non-empty `allow` list.
func _lock_denies(command_id: String) -> bool:
	var channels_value: Variant = _run.edge.get("channels", {})
	if not channels_value is Dictionary:
		return false
	var controls_value: Variant = (channels_value as Dictionary).get("controls")
	if not controls_value is Dictionary:
		return false
	var controls := controls_value as Dictionary
	if str(controls.get("kind", "")) != "lock":
		return false
	var block: Variant = controls.get("block", [])
	if block is Array and command_id in (block as Array):
		return true
	var allow: Variant = controls.get("allow", [])
	if allow is Array and not (allow as Array).is_empty():
		return not (command_id in (allow as Array))
	return false


## One live settings edit: re-read the live block and presentation, refresh a running edge's
## target snapshot, reconcile the modifiers and the act body palm. `begin()` syncs internally.
func apply_live_settings() -> void:
	if not _started:
		return
	_sync_live_config()
	if _target_spec != null:
		var group := str(_target_spec.settings_group)
		var presentation: Dictionary = SETTINGS.act_snapshot(group).presentation
		_target_presentation = presentation
		var fresh := _config_for_group(group, presentation)
		_target_config.clear()
		_target_config.merge(fresh, true)
		_oral_turn.write_config(_view)
	pose_changed()
	if is_instance_valid(_act_body):
		_act_body.refresh_palm()


## Drop the target snapshot and the running edge without touching the live pose or the view.
func _abort_target() -> void:
	_run = null
	_from_id = ""
	_target_id = ""
	_target_spec = null
	_target_config.clear()
	_target_presentation.clear()
	_target_asset = null


## Adopt the target's settings into the live config in place, so the view, the pose node and the
## evaluator all see the target through the same alias object. The caller then drops the snapshot.
func _adopt_target_config() -> void:
	if _target_spec == null or is_same(_target_config, _pose_config):
		return
	_pose_config.clear()
	_pose_config.merge(_target_config, true)
	if is_instance_valid(_pose_node):
		_pose_node.pose_config = _pose_config


## The pose block for a settings group plus that group's presentation values. Standing folds in the
## presentation chin, neck and tail; other groups use the live settings block unchanged.
func _config_for_group(group: String, presentation: Dictionary) -> Dictionary:
	var config := SETTINGS.pose(_pony_id(), group).raw()
	if group != CATALOG.STANDING:
		return config
	config["chin_up_deg"] = float(presentation.get("chin_up_deg",
		SETTINGS.chin_up_deg.default))
	config["neck_down_deg"] = float(presentation.get("neck_down_deg",
		SETTINGS.neck_down_deg.default))
	var tail_cfg: Variant = presentation.get("tail", {})
	if not tail_cfg is Dictionary:
		tail_cfg = {}
	config["tail_aside"] = deg_to_rad(float((tail_cfg as Dictionary).get("yaw_deg",
		SETTINGS.yaw_deg.default)))
	config["tail_lift"] = deg_to_rad(float((tail_cfg as Dictionary).get("pitch_deg",
		SETTINGS.tail_pitch_deg.default)))
	return config


## Refresh the live config in place from the live view's settings group and presentation; it never
## resets the authored asset the begin, request, completion, reload and release own.
func _sync_live_config() -> bool:
	var pony := _pony()
	var group := str(_view.settings_group)
	if group.is_empty() or not is_instance_valid(pony):
		return false
	var presentation: Dictionary = {}
	if group == CATALOG.STANDING:
		presentation = SETTINGS.act_snapshot(group).presentation
	_pose_config.clear()
	_pose_config.merge(_config_for_group(group, presentation), true)
	if is_instance_valid(_pose_node):
		_pose_node.pose_config = _pose_config
	if group == CATALOG.STANDING:
		_mods.apply_config()
	return true


## The authored base for a candidate spec, else the live pose's, else the default missionary asset,
## parsed once per path. A row without its own asset still reads the default for diagnostics.
func _diagnostic_asset(candidate: String = "") -> AUTHORED:
	var asset: AUTHORED = _asset_for(candidate)
	if asset != null:
		return asset
	# A row with no asset of its own reads the default missionary asset so diagnostics still have a
	# rig to describe; the readiness verdict stays false for such a row.
	if _empty_asset == null:
		_empty_asset = AUTHORED.shared(AUTHORED.PATH)
	return _empty_asset


## The asset the live rig is rendering: the source through an edge, the target once it settles.
func _live_asset() -> AUTHORED:
	if is_instance_valid(_pose_node) and _pose_node.authored != null:
		return _pose_node.authored
	return _diagnostic_asset("")


## Mirror the live rendered asset into the view, the one source presentation modules read.
func _sync_view_asset() -> void:
	_view.authored = _live_asset()


## The parsed authored pose for the debug action and the pose lab. With no candidate this is the
## live rendered asset, not the target of a running edge.
func _readiness_asset(candidate: String = "") -> AUTHORED:
	if candidate.is_empty():
		return _live_asset()
	return _diagnostic_asset(candidate)


## Ground space for an authored ground pose, seeded from the pony root. Like the bed frame with its
## bed, it is carried by the root from then on.
func _ground_pose_frame() -> Transform3D:
	var pony := _pony()
	if not is_instance_valid(pony):
		return NO_FRAME
	return Transform3D(pony.global_basis.orthonormalized(), pony.global_position)


## Re-read the live pose's asset in place, plus the running edge's target, or the default
## missionary asset when no pose is live. A running act picks the new pose up on its next frame.
func reload_authored(candidate: String = "") -> String:
	var paths: Array[String] = []
	var seen: Dictionary = {}
	_add_reload_path(paths, seen, _asset_path_for(candidate))
	if is_instance_valid(_pose_node) and _pose_node.authored != null:
		_add_reload_path(paths, seen, _pose_node.authored.path)
	if paths.is_empty():
		_add_reload_path(paths, seen, AUTHORED.PATH)
	for path: String in paths:
		var load_error := AUTHORED.reload_file(path)
		if not load_error.is_empty():
			return load_error
	if is_instance_valid(_pose_node):
		# The wrappers were reloaded in place; the pair keeps the same instances.
		_pose_node.authored = _live_asset()
		if _target_spec != null:
			_target_asset = _asset_for_spec(_target_spec)
			_pose_node.to_authored = _target_asset
		_sync_view_asset()
	return ""


## Add one unique non-empty asset path to the reload list. The resolved path is the key, so a
## relative row path and the wrapper's `res://` path are the same file.
func _add_reload_path(paths: Array[String], seen: Dictionary, path: String) -> void:
	if path.is_empty():
		return
	var resolved := AUTHORED.resolve(path)
	if seen.has(resolved):
		return
	seen[resolved] = true
	paths.append(resolved)


## Bed space for the authored pose: the middle of the real mattress top, in the bed's axes, the
## pillow end at -Z. An absent frame means no bed pose is live, so the procedural driver stays out.
func _missionary_pose_frame() -> Transform3D:
	if str(_view.frame) != "bed" or not is_instance_valid(_bed_node):
		return NO_FRAME
	var fallback: float = float(_bed_node.get_meta("mattress_top", 0.6)) + float(_bed_node.global_position.y)
	var points: Array[Vector3] = [_bed_node.global_position]
	var top: float = WORLD.bed(_bed_node).surface_top(points, fallback)
	if not is_finite(top):
		return NO_FRAME
	var at: Vector3 = _bed_node.global_position
	var basis: Basis = _bed_node.global_basis.orthonormalized() * Basis(Vector3.UP, PI)
	return Transform3D(basis, Vector3(at.x, top, at.z))


## Carry the bed-space pose, act body and anatomy placement with a bed that moves under the act
## (CloudDrift); the delta is rigid, so the top height is not measured again.
func _sync_bed_frame() -> void:
	if str(_view.frame) != "bed" or not is_instance_valid(_bed_node) \
			or not _bed_frame_source_saved or not _bed_frame is Transform3D:
		return
	var now: Transform3D = _bed_node.global_transform
	if now.is_equal_approx(_bed_frame_source):
		return
	var delta: Transform3D = now * _bed_frame_source.affine_inverse()
	_bed_frame = delta * (_bed_frame as Transform3D)
	_bed_frame_source = now
	if is_instance_valid(_pose_node):
		_pose_node.bed_frame = _bed_frame
	_view.bed_frame = _bed_frame


## Turn the ground frame with the pony root each tick; the oral turn moves the root, so the frame
## turns with her exactly once.
func _sync_ground_frame() -> void:
	var pony := _pony()
	if str(_view.frame) != "ground" or not is_instance_valid(pony) \
			or not _ground_frame_source_saved or not _ground_frame is Transform3D:
		return
	var now: Transform3D = (pony as Node3D).global_transform
	if now.is_equal_approx(_ground_frame_source):
		return
	var delta: Transform3D = now * _ground_frame_source.affine_inverse()
	_ground_frame = delta * (_ground_frame as Transform3D)
	_ground_frame_source = now
	if is_instance_valid(_pose_node):
		_pose_node.ground_frame = _ground_frame


## Snapshot before the act changes her posture or the pose writes bones.
func snapshot_bones() -> void:
	var pony := _pony()
	_saved_bones.clear()
	_saved_hair.clear()
	_saved_skeleton = null
	_saved_hair_skeleton = null
	if not is_instance_valid(pony):
		return
	var sk: Variant = pony.get("skeleton")
	if sk is Skeleton3D:
		_saved_skeleton = sk as Skeleton3D
		for i in (_saved_skeleton as Skeleton3D).get_bone_count():
			_saved_bones.append((_saved_skeleton as Skeleton3D).get_bone_pose(i))
	var hair: Variant = pony.get("hair_skeleton")
	if hair is Skeleton3D:
		_saved_hair_skeleton = hair as Skeleton3D
		for i in (_saved_hair_skeleton as Skeleton3D).get_bone_count():
			_saved_hair.append((_saved_hair_skeleton as Skeleton3D).get_bone_pose(i))


## Put every pony bone back before the game's animation re-poses her. The act's pose modifier is
## already freed when this runs, so nothing rewrites the act pose on top.
func restore_bones() -> void:
	if is_instance_valid(_saved_skeleton) \
			and _saved_bones.size() == _saved_skeleton.get_bone_count():
		for i in _saved_bones.size():
			_saved_skeleton.set_bone_pose(i, _saved_bones[i])
	if is_instance_valid(_saved_hair_skeleton) \
			and _saved_hair.size() == _saved_hair_skeleton.get_bone_count():
		for i in _saved_hair.size():
			_saved_hair_skeleton.set_bone_pose(i, _saved_hair[i])
	_saved_bones.clear()
	_saved_hair.clear()
	_saved_skeleton = null
	_saved_hair_skeleton = null


## The pose-scope start state: clear the rig-check cache, release the tail lay and drop the bed and
## ground frames, keeping the pose node, the modifiers, the config and the view.
func leave_pose_start() -> void:
	_readiness._reset()
	if _face_driver != null and _face_driver.active:
		_face_driver.restore(_view, _pose_node)
	_mods.release_tail_lay()
	_bed_frame = null
	_bed_frame_source_saved = false
	_bed_frame_source = Transform3D.IDENTITY
	_view.bed_frame = null
	_ground_frame = null
	_ground_frame_source_saved = false
	_ground_frame_source = Transform3D.IDENTITY


## Drop the live-installed extra modifiers, keeping the pose node, the standing tail, the config and
## the view.
func leave_pose_body() -> void:
	_mods.remove_extras()


## The final pose clear: free the pose modifier and the standing tail and reset the act's state, so
## the next `begin()` starts clean. Safe to repeat; a pose change never calls it.
func release_pose() -> void:
	# A release aborts a live edge and returns the oral frame before the view is cleared; it never
	# runs a second act exit.
	_oral_turn.restore(_view)
	_face_driver.restore(_view, _pose_node)
	_face_driver.reset()
	_abort_target()
	_state = POSE_STATE.next(_state, "exit")
	_release_act_body()
	if is_instance_valid(_pose_node):
		_drop(_pose_node)
	_pose_node = null
	_from_asset = null
	_target_asset = null
	_mods.release()
	_started = false
	_pose_config.clear()
	_readiness._reset()
	_bed_frame = null
	_bed_frame_source_saved = false
	_bed_frame_source = Transform3D.IDENTITY
	_ground_frame = null
	_ground_frame_source_saved = false
	_ground_frame_source = Transform3D.IDENTITY
	_tail_anchor = Vector3.INF
	_view.clear()
	_oral_turn.reset()
	_state = POSE_STATE.next(_state, "released")


## One pose-change fan-out: reconcile the modifier profile and apply the `act_body`/`anon` channel;
## the evaluator pair is already set. Idempotent, so a steady tick installs nothing.
func pose_changed() -> void:
	if not _started:
		return
	var to_spec: POSE_SPEC = _registry.spec(str(_view.to_id))
	if to_spec == null:
		to_spec = _registry.spec(str(_view.id))
	var from_spec: POSE_SPEC = _registry.spec(str(_view.from_id))
	if from_spec == null:
		from_spec = to_spec
	_mods.reconcile(_mods.profile_of(from_spec), _mods.profile_of(to_spec))
	_apply_anon_channel(_view)


## The test seam: replace the authored profile table with a synthetic one.
func _set_modifier_profiles(table: Dictionary) -> void:
	_mods.set_profiles(table)


## The live edge's `anon` channel, or the empty hold. Outside an edge the spec's profile holds.
func _anon_channel() -> Dictionary:
	if _run == null:
		return NO_CHANNEL
	var channels_value: Variant = _run.edge.get("channels", {})
	if not channels_value is Dictionary:
		return NO_CHANNEL
	var value: Variant = (channels_value as Dictionary).get("anon")
	return value as Dictionary if value is Dictionary else NO_CHANNEL


## Apply the `act_body` specs' Anon channel (`hold`, `blend`, `switch`) and bind the authored asset
## pair for it; the player-body specs never install the adapter.
func _apply_anon_channel(view: POSE_VIEW) -> void:
	var anon := view.anon
	if str(anon.get("mode", "")) != "act_body":
		return
	_install_act_body()
	if not is_instance_valid(_act_body):
		return
	if _run == null:
		# Outside an edge the spec's profile is the hold and both assets are the live one.
		var live: AUTHORED = _live_asset()
		_act_body.set_pose_assets(live, live, 1.0)
		_act_body.pose_changed(str(anon.get("profile", "")), 1.0)
		return
	var channel := _anon_channel()
	match str(channel.get("kind", "hold")):
		"blend":
			_act_body.set_pose_assets(_from_asset, _target_asset,
				clampf(view.weight, 0.0, 1.0))
			_act_body.set_weight(clampf(view.weight, 0.0, 1.0))
		"switch":
			var switched := str(channel.get("profile", ""))
			if switched.is_empty():
				switched = str(channel.get("set", ""))
			if switched.is_empty():
				switched = str(anon.get("profile", ""))
			_act_body.set_pose_assets(_target_asset, _target_asset, 1.0)
			_act_body.pose_changed(switched, 1.0)
		_:
			# A hold keeps the adapter's current profile, weight and asset pair.
			pass


## The act body exists only on a bed spec's `act_body` mode for desktop human Anon.
func _act_body_wanted(view: POSE_VIEW) -> bool:
	if _facts == null or str(view.anon.get("mode", "")) != "act_body":
		return false
	return not _facts.player_pony and not _facts.headset_view


## True while the act body is installed and its adapter is active.
func _act_body_live() -> bool:
	return is_instance_valid(_act_body) and bool(_act_body.get("active"))


## The act body's authored mouth point; INF when it is missing, inactive or non-finite.
func _act_body_mouth_point() -> Vector3:
	if not _act_body_live():
		return Vector3.INF
	var value: Variant = _act_body.mouth_point()
	return value if value is Vector3 and (value as Vector3).is_finite() else Vector3.INF


## The act body's authored eye point; INF when it is missing, inactive or non-finite.
func _act_body_eye_point() -> Vector3:
	if not _act_body_live():
		return Vector3.INF
	var value: Variant = _act_body.eye_point()
	return value if value is Vector3 and (value as Vector3).is_finite() else Vector3.INF


## The act body's placed avatar transform, or the identity when no body is installed.
func _act_body_transform() -> Transform3D:
	if not is_instance_valid(_act_body):
		return Transform3D.IDENTITY
	var avatar: Variant = _act_body.get("avatar")
	return (avatar as Node3D).global_transform if avatar is Node3D else Transform3D.IDENTITY


## The act body's debug row, or "" when no body is installed.
func _act_body_diag_row(face: Vector3, vulva: Vector3) -> String:
	if not is_instance_valid(_act_body):
		return ""
	return str(_act_body.diag_row(face, vulva))


func _act_body_refresh_palm() -> void:
	if is_instance_valid(_act_body):
		_act_body.refresh_palm()


## The act body's node, or null when none is installed.
func _act_body_node() -> Node:
	return _act_body if is_instance_valid(_act_body) else null


## The act's own Anon body, created on the runtime host. The pose service owns it and frees it.
func _install_act_body() -> void:
	if is_instance_valid(_act_body):
		return
	var host := get_parent()
	if host == null or not _act_body_wanted(_view):
		return
	var body := MISSIONARY_ANON.new()
	body.name = "UnfplapMissionaryAnon"
	host.add_child(body)
	if not body.install(_facts):
		host.remove_child(body)
		body.queue_free()
		return
	body.set_pose_assets(_live_asset(), _live_asset(), 1.0)
	_act_body = body


## Clear the bridge handle first, then restore and free the act body once. A transition never
## reaches this.
func _release_act_body() -> void:
	if not is_instance_valid(_act_body):
		_act_body = null
		return
	_act_body.remove()
	_drop(_act_body)
	_act_body = null


## Detach a modifier before freeing it: `queue_free()` alone leaves it parented for the rest of the
## frame, still taking its pass, so a new act in that frame would run two.
func _drop(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	var parent := node.get_parent()
	if parent != null:
		parent.remove_child(node)
	node.queue_free()


## The render-time pose write. The runtime calls this after the game's own writers so the
## authored missionary pose survives to the renderer.
func _apply_render(skeleton: Skeleton3D) -> void:
	if is_instance_valid(_pose_node):
		_pose_node.apply_render(skeleton)


## The authored stance's neck midpoint in world space, for the start's one aim measurement. It
## writes the live pose at its target amount for the read and puts the entrance amount back.
func stance_neck_point() -> Vector3:
	var pony := _pony()
	var skeleton: Variant = pony.get("skeleton") if is_instance_valid(pony) else null
	if not is_instance_valid(_pose_node) or not skeleton is Skeleton3D:
		return Vector3.INF
	var amount := _pose_node.amount
	_pose_node.amount = 1.0
	_apply_render(skeleton as Skeleton3D)
	_pose_node.amount = amount
	var sk := skeleton as Skeleton3D
	sk.force_update_all_bone_transforms()
	var hips := sk.find_bone("pony_hips")
	if hips >= 0:
		sk.force_update_bone_child_transform(hips)
	var first := sk.find_bone("pony_neck1")
	var second := sk.find_bone("pony_neck2")
	if first >= 0 and second >= 0:
		var a := sk.global_transform * sk.get_bone_global_pose(first).origin
		var b := sk.global_transform * sk.get_bone_global_pose(second).origin
		return (a + b) * 0.5
	if second >= 0:
		return sk.global_transform * sk.get_bone_global_pose(second).origin
	return Vector3.INF


## The render-time step for one frame, in order: sync the live space, place the act's own Anon
## body, write her pose and replay the sway; the live view reads his posed head after it.
func write_render_frame(body_scale: float) -> void:
	var pony := _pony()
	if not is_instance_valid(pony):
		return
	var family := str(_view.family)
	if family == "standing":
		# Same order as the bed family: sync the ground frame, write the pose after every writer of
		# the frame, then replay the sway on top of that write.
		_sync_ground_frame()
		var standing_sk: Variant = pony.get("skeleton")
		if is_instance_valid(_pose_node) and standing_sk is Skeleton3D:
			_apply_render(standing_sk as Skeleton3D)
			_mods.apply_render(standing_sk as Skeleton3D, "standing")
		return
	if family != "bed":
		return
	var frame: Transform3D = _bed_frame if _bed_frame is Transform3D else NO_FRAME
	if is_instance_valid(_act_body) and _has_frame(frame):
		_act_body.apply(frame, body_scale)
	var sk: Variant = pony.get("skeleton")
	if is_instance_valid(_pose_node) and sk is Skeleton3D:
		_apply_render(sk as Skeleton3D)
		_mods.apply_render(sk as Skeleton3D, "bed")


## One thrust's ear flick; a released pose or a disabled feature ignores it.
func trigger_ear_twitch(impact: float) -> void:
	_mods.ear_twitch(impact)


## The pose frame the live family reads: the bed frame or the ground frame.
func follow_space(family: String) -> void:
	if family == "bed":
		_sync_bed_frame()
	else:
		_sync_ground_frame()


## The tail handle's one write: the lift/flick weight the afterglow sets.
func _set_tail_target(value: float) -> void:
	_mods.tail_target(value)


## The live standing glance's head throw-back; a released pose takes no write.
func set_head_back(value: float) -> void:
	if is_instance_valid(_pose_node):
		_pose_node.head_back = value


func _flick_tail(count: int) -> void:
	_mods.flick(count)


## The tail handle's thrust wave, scaled by the caller.
func _thrust_tail(weight: float) -> void:
	_mods.thrust(weight)


## A rebuilt pose starts settled. The body swap re-poses the surviving act inside the flame, so
## the start ramp would be a visible second entrance on the new body.
func settle() -> void:
	if is_instance_valid(_pose_node):
		_pose_node.amount = 1.0
		_pose_node.target_amount = 1.0
	_mods.settle()


func _basis_amount() -> float:
	return _pose_node.amount if is_instance_valid(_pose_node) else 0.0


## The restore's fade: release the live pose weight and the standing tail toward zero.
func fade_out() -> void:
	if is_instance_valid(_pose_node):
		_pose_node.target_amount = 0.0
	_mods.tail_target(0.0)


## Aim the live pose's look point for this rendered frame; the head solve reads it after the pose
## write, and the camera owns the point, the kiss blend and the climax weight.
func aim_look(point: Vector3, kiss: float, climaxing: bool) -> void:
	if not is_instance_valid(_pose_node):
		return
	_pose_node.look_point = point
	_pose_node.kiss = kiss
	_pose_node.climaxing = climaxing


## The live pose frame: the bed's mattress space or the pony root's ground space.
func _pose_frame() -> Transform3D:
	if str(_view.frame) == "ground":
		return _ground_frame if _ground_frame is Transform3D else NO_FRAME
	if str(_view.frame) == "bed":
		return _bed_frame if _bed_frame is Transform3D else NO_FRAME
	return NO_FRAME


## True when a pose frame is real space: the absent frame carries an infinite origin.
static func _has_frame(frame: Transform3D) -> bool:
	return frame.origin.is_finite()


func _reset_sway_base() -> void:
	_mods.reset_sway()


func _feature(name: String) -> bool:
	return bool(_facts.features.get(name, false)) if _facts != null else false
