extends RefCounted
## The act's pose session: the skeleton pose modifier, the authored missionary base, the bed
## frame, the extra modifiers (tail, tail lay, body sway, prone sway, ear twitch), the bone
## snapshots and the pose diagnostics. The runtime owns the act state, the start order and the one
## teardown ledger; it binds this session and calls the render-time write.
##
## The teardown is split by lifetime: the session owns the pose-scope steps
## (`leave_pose_start()`, `leave_pose_body()` and the final `release_pose()`), while the act-scope
## resets between them stay in the runtime's one pose ledger. Contract: docs/poses.md.

const POSE := preload("res://mods/unfplap/poses/skeleton_pose.gd")
const AUTHORED := preload("res://mods/unfplap/poses/authored_pose.gd")
const MISSIONARY_ANON := preload("res://mods/unfplap/poses/missionary_anon.gd")
const TAIL := preload("res://mods/unfplap/poses/tail_pose.gd")
const TAIL_LAY := preload("res://mods/unfplap/poses/tail_lay.gd")
const TAIL_CHAIN := preload("res://mods/unfplap/poses/tail_chain.gd")
const BODY_SWAY := preload("res://mods/unfplap/poses/body_sway.gd")
const PRONE_SWAY := preload("res://mods/unfplap/poses/prone_sway.gd")
const EAR_TWITCH := preload("res://mods/unfplap/poses/ear_twitch.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")
const POSE_VIEW := preload("res://mods/unfplap/shared/pose_view.gd")
const POSE_STATE := preload("res://mods/unfplap/poses/pose_state.gd")
const ORAL_TURN := preload("res://mods/unfplap/poses/oral_turn.gd")
const FACE_CONTACT := preload("res://mods/unfplap/poses/face_contact.gd")
const SPECS := preload("res://mods/unfplap/shared/pose_specs.gd")
const REGISTRY := preload("res://mods/unfplap/poses/registry.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const MATTRESS := preload("res://world/life/couch/mattress.gd")

## The empty sets the reconcile and the anon channel read, so a steady tick allocates nothing.
const NO_OWNERS := []
const NO_CHANNEL := {}
## The owner names in install order, matching `shared/pose_specs.gd`'s profile table.
const MODIFIER_ORDER := ["body_sway", "prone_sway", "ear_twitch", "tail", "tail_lay"]

## The runtime node that parents the debug nodes and receives their `runtime` field. It is the
## host boundary; the session never reads the runtime's fields.
var host: Variant = null
var pony: Variant = null

## The act's identity and the live view's fields.
var id := ""
var features: Dictionary = {}
var bed_node: Variant = null
## True between a successful `begin()` and `release_pose()`. The runtime keeps one session per pony.
var _started := false
## Live pose config. The runtime reads it through `_pose_session.pose_config`.
var pose_config: Dictionary = {}
## The one pose read model for the act, and the registry that validates the static spec table.
var _view: RefCounted
var _registry: RefCounted

## The live state-machine value; the view mirrors it. `begin()` enters `ENTERING`, settles `STEADY`,
## a request enters `TRANSITIONING` and `release_pose()` exits through `EXITING` to `IDLE`.
var _state := POSE_VIEW.IDLE
## The running edge, or null. A release aborts it without an act exit.
var _run: Variant = null
var _from_id := ""
var _target_id := ""
var _target_spec: Variant = null
## The target's settings snapshot, by reference from the view's `to_config`.
var _target_config: Dictionary = {}
var _target_presentation: Dictionary = {}
## The authored asset of each side of the live edge, or the live pose's asset outside an edge.
## `_target_asset` is cached at request and adopted on completion.
var _from_asset: Variant = null
var _target_asset: Variant = null

## The pose modifier and the extra scene modifiers the act installs.
var pose_node: Node
var tail: Variant = null
var tail_lay: Node
var body_sway: SkeletonModifier3D
var prone_sway: SkeletonModifier3D
var ear_twitch: SkeletonModifier3D
## The standing oral actor/frame turn the session owns. It preloads no scene and reads the host
## callables below; the edge weight drives it.
var _oral_turn: RefCounted = null
## The bed face-sit contact driver. The contact switch to `face` begins it and the reverse switch
## or the one act exit restores it; it never ends the act.
var _face_driver: RefCounted = null
## The act's own Anon body on the `act_body` specs, or null on the player-body specs. The session
## creates, installs and frees it; the anatomy bridge only receives the opaque handle.
var act_body: Variant = null
## The authored profile table with a test seam: a synthetic profile can be added without touching
## the shipped const.
var modifier_profiles: Dictionary = SPECS.MODIFIER_PROFILES.duplicate()
## The camera position the standing tail chooses its side against, from the begin context.
var _tail_anchor := Vector3.INF

## Bed space for the authored pose. The runtime reads it through `_pose_session.bed_frame`.
var bed_frame: Variant = null
var bed_frame_source := Transform3D.IDENTITY
var bed_frame_source_saved := false
## Ground space for a ground pose: the pony root's basis and position at pose start. It follows the
## root's position and yaw each tick; the runtime reads it through `_pose_session.ground_frame`.
var ground_frame: Variant = null
var ground_frame_source := Transform3D.IDENTITY
var ground_frame_source_saved := false

## Per-act log and rig-check caches.
var pose_logged := false
var pose_trace_frames := 0
var rig_checked := false
var rig_skeleton := 0
## The authored asset revision the rig verdict was computed against.
var rig_revision := -1
## The asset path the rig verdict was computed against.
var rig_asset_path := ""
var rig_missing_bones: Array = []
## A shared unavailable asset instance for a pose whose row supplies no asset.
var _empty_asset: Variant = null

## The pony's pre-act bone snapshot.
var saved_bones: Array[Transform3D] = []
var saved_hair: Array[Transform3D] = []
var saved_skeleton: Skeleton3D
var saved_hair_skeleton: Skeleton3D

## Host boundary. A missing callback is a no-op.
var log := Callable()
var perf := Callable()
## The typed act view the pose modifiers read for the live depth, state and bed frame.
var facts: Variant = null
## Park the game presentation for the bed family, for `render_write()`.
var hide_avatar := Callable()
## Publish or clear the opaque Anon handle on the anatomy bridge. The service owns the body.
var set_act_body := Callable()
## The eye-shot camera tick, which must run after the render write.
var eye_camera := Callable()
## The oral host boundary: the mouth and opening points, the soft kiss and the speech/viseme
## actions the edge events fire. A missing callback is a no-op.
var mouth_point := Callable()
var opening_point := Callable()
## The face contact's real anchor on the act body. The face driver (D5) reads it; a missing
## callback is a no-op.
var face_point := Callable()
var oral_kiss := Callable()
var oral_speech_stop := Callable()
var oral_viseme := Callable()
var oral_status := Callable()


func bind(host_node: Variant, pony_node: Variant) -> void:
	host = host_node
	pony = pony_node


func _init() -> void:
	_view = POSE_VIEW.new()
	_registry = REGISTRY.new()
	_oral_turn = ORAL_TURN.new()
	_face_driver = FACE_CONTACT.new()


## The one pose read model the act view carries. `begin()` fills it and `release_pose()` clears it;
## the object is never re-created, so a consumer can keep the reference for the act.
func view() -> RefCounted:
	return _view


## Stage the live pose config in place. The runtime calls this before the standing placement reads
## its gaps, and everything that holds `pose_config` sees this same object for the act.
func set_pose_config(config: Dictionary) -> void:
	pose_config.clear()
	pose_config.merge(config, true)


## Build the pose for a fresh act. `context` carries the start spec id, `id`, `features`, `bed`,
## `presentation`, `look_point` and `camera_position` from the runtime's start sequence. Returns
## false, before installing anything, when a pose is already live or the pony has no body skeleton;
## `_started` only follows a complete install.
func begin(context: Dictionary) -> bool:
	if _started:
		_write_log("pose session: begin refused, a pose is already live")
		return false
	var skeleton: Variant = pony.get("skeleton") if is_instance_valid(pony) else null
	if not skeleton is Skeleton3D:
		_write_log("pose session: no body skeleton to pose")
		return false
	# A fresh act starts with no edge and no target snapshot; a failed begin never gets here.
	_abort_target()
	_oral_turn.reset()
	_bind_face()
	_face_driver.reset()
	_state = POSE_STATE.next(_state, "begin")
	var start_id := str(context.get("pose_id", ""))
	id = str(context.get("id", ""))
	features = context.get("features", {})
	# The runtime supplies the live size name; a suite may omit it and fall back to the facts.
	var size_name := str(context.get("size_name", _size_name()))
	bed_node = context.get("bed")
	pose_logged = false
	pose_trace_frames = 0
	pose_node = POSE.new()
	pose_node.name = "UnfplapPose"
	pose_node.mare = pony
	pose_node.log = log
	pose_node.perf = perf
	# Fill the view first: the active settings group and family drive the start config sync, not the
	# act's start id. One live object: the sync merges the character's pose into `pose_config` in
	# place, so the modifier, the view and the runtime share it.
	var start_spec: Variant = _registry.spec(start_id)
	_fill_view(start_spec)
	_view.contact_kind = _spec_contact_kind(start_spec)
	var group := str(_view.settings_group)
	if group == CATALOG.STANDING:
		sync_standing_config(context.get("presentation", {}))
	elif group == CATALOG.MISSIONARY:
		sync_missionary_config()
	pose_node.pose_config = pose_config
	# Resolve the start asset before the evaluator pair: the same instance is the live rendered
	# asset and both sides of a pose that starts settled.
	var start_asset: Variant = _asset_for_spec(start_spec)
	if start_asset != null and bool(start_asset.get("available")) \
			and bool(start_asset.call("usable", str(_view.frame))):
		pose_node.authored = start_asset
	_from_asset = pose_node.authored
	_target_asset = _from_asset
	pose_node.call("set_pose", _effective_driver(start_spec), _effective_driver(start_spec),
		_effective_delta(start_spec), _effective_delta(start_spec), pose_config, pose_config,
		_from_asset, _target_asset)
	pose_node.call("set_weight", 1.0)
	var look: Variant = context.get("look_point")
	pose_node.look_point = look if look is Vector3 else pony.global_position
	pose_node.amount = 0.0
	pose_node.target_amount = 1.0
	if str(_view.frame) == "bed":
		bed_frame = missionary_pose_frame()
		bed_frame_source_saved = bed_frame is Transform3D and is_instance_valid(bed_node)
		if bed_frame_source_saved:
			bed_frame_source = (bed_node as Node3D).global_transform
		pose_node.bed_frame = bed_frame
	else:
		ground_frame = ground_pose_frame()
		ground_frame_source_saved = ground_frame is Transform3D and is_instance_valid(pony)
		if ground_frame_source_saved:
			ground_frame_source = (pony as Node3D).global_transform
		pose_node.ground_frame = ground_frame
		pose_node.size_name = size_name
	log_base()
	(skeleton as Skeleton3D).add_child(pose_node)
	var family := str(_view.family)
	if family == "bed":
		if _feature("missionary_body_motion"):
			_install_prone_sway(skeleton)
	elif family == "standing":
		if _feature("standing_body_sway"):
			_install_body_sway(skeleton)
		if _feature("thrust_ear_twitch"):
			_install_ear_twitch()
	_started = true
	if family == "bed":
		_install_tail_lay()
	_state = POSE_STATE.next(_state, "entered")
	_view.pose_state = _state
	if family == "standing":
		var anchor: Variant = context.get("camera_position")
		_tail_anchor = anchor if anchor is Vector3 else Vector3.INF
		_install_tail()
	# A pose row whose base contact is already `face` begins the live mouth follow here; the
	# authored asset is already placed, so this only captures the residual.
	if str(_view.contact_kind) == "face":
		_face_driver.begin(_view, bed_frame)
		_face_tick(0.0)
	return true


func _fill_view(spec: Variant) -> void:
	if spec == null:
		_view.clear()
		_write_log("pose view: no spec for the start pose")
		return
	_view.fill(spec, pose_config)


## The spec row's base contact kind (`opening` for standing and missionary, `mouth` for the
## internal oral pose). An edge switch overrides it while it runs; completion settles it here.
func _spec_contact_kind(spec: Variant) -> String:
	if spec == null:
		return "none"
	var value: Variant = spec.contact
	return str((value as Dictionary).get("kind", "none")) if value is Dictionary else "none"


## Point the turn at this pony and the host callbacks. Cheap field writes; the runtime re-binds
## the session on every access, so a suite can set the callbacks after construction.
func _bind_oral() -> void:
	if _oral_turn == null:
		_oral_turn = ORAL_TURN.new()
	_oral_turn.bind(pony, mouth_point, opening_point, oral_kiss)


## Bind the face driver's host reads. The driver is the session's own; the anatomy bridge stays
## behind `face_point` and is never preloaded here.
func _bind_face() -> void:
	if _face_driver == null:
		_face_driver = FACE_CONTACT.new()
	_face_driver.bind(pony, face_point, opening_point, log)


## True for the authored oral pair in either direction.
func _oral_pair(from_id: String, to_id: String) -> bool:
	return (from_id == CATALOG.STANDING and to_id == CATALOG.STANDING_ORAL) \
		or (from_id == CATALOG.STANDING_ORAL and to_id == CATALOG.STANDING)


## The spec's own driver, or its base chain's driver; `standing_test` resolves to `standing`. A
## missing row, an empty chain or a repeat is empty.
func _effective_driver(spec: Variant) -> String:
	var cursor: Variant = spec
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
func _effective_delta(spec: Variant) -> String:
	return str(spec.delta) if spec != null else ""


## The authored pose document of a spec row, or the nearest base that supplies one. An internal row
## with no asset of its own inherits it from its base chain.
func _effective_asset(spec: Variant) -> String:
	var cursor: Variant = spec
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


## The effective authored asset path for a spec id; empty when the row and its chain have none.
func asset_for(spec_id: String) -> String:
	return _effective_asset(_registry.spec(spec_id))


## The spec a candidate names: the id's row, or the live view's row when the candidate is empty.
func _candidate_spec(candidate := "") -> Variant:
	var spec_id := str(candidate)
	if spec_id.is_empty() and _view != null:
		spec_id = str(_view.id)
	if spec_id.is_empty():
		return null
	return _registry.spec(spec_id)


## The parsed asset for a candidate spec, or null when the row and its chain supply none.
func _asset_for(candidate := "") -> Variant:
	var spec: Variant = _candidate_spec(candidate)
	if spec == null:
		return null
	var path := _effective_asset(spec)
	if path.is_empty():
		return null
	return AUTHORED.shared(path)


## The parsed asset for an already resolved spec.
func _asset_for_spec(spec: Variant) -> Variant:
	var path := _effective_asset(spec)
	return AUTHORED.shared(path) if not path.is_empty() else null


## The path the rig gate and diagnostics name for a candidate.
func _asset_path_for(candidate := "") -> String:
	var spec: Variant = _candidate_spec(candidate)
	return _effective_asset(spec) if spec != null else ""


## The pose id of the live rendered side: the source while an edge runs, the view's pose otherwise.
func _live_spec_id() -> String:
	if _run != null and not _from_id.is_empty():
		return _from_id
	return str(_view.id)


## Request one authored edge. Returns the A3.1 `PoseResult`: `{ok, code, edge, reason}`. It never
## ends the act, releases the pose or restores bones.
func request_pose(target_id: String, trigger: String, context: Dictionary = {}) -> Dictionary:
	var from_id := str(_view.id)
	var target_spec: Variant = _registry.spec(target_id)
	var edge_id := from_id + "__" + target_id
	var edge: Variant = _registry.edge(edge_id)
	var act_state := int(context.get("act_state", facts.state if facts != null else 0))
	var forms := _request_forms(context)
	var views := _request_views(context)
	var features := _request_features(context)
	var checks := _request_checks(target_spec, edge, context, forms, views, features)
	var code := POSE_STATE.request_code(_state, act_state, from_id, target_id,
		edge != null, checks)
	if code != "ok":
		return POSE_STATE.result(code, edge_id, _reason(code, target_id))
	var run: Variant = POSE_STATE.start_edge(edge.data, from_id, target_id)
	if run == null:
		return POSE_STATE.result("missing_asset", edge_id, "the edge did not start")
	# Cache the target by settings group: `standing_test` uses the standing pose and presentation
	# blocks and has no block of its own.
	_from_id = from_id
	_target_id = target_id
	_target_spec = target_spec
	var group := str(target_spec.settings_group)
	_target_presentation = SETTINGS.act_snapshot(group).presentation
	_target_config = _config_for_group(group, _target_presentation)
	_target_asset = _asset_for_spec(target_spec)
	_from_asset = live_authored()
	if _from_asset == null:
		_from_asset = _asset_for_spec(_registry.spec(from_id))
	_run = run
	_state = POSE_STATE.next(_state, "request")
	_fill_transition_view()
	var from_spec: Variant = _registry.spec(_from_id)
	pose_node.call("set_pose", _effective_driver(from_spec), _effective_driver(_target_spec),
		_effective_delta(from_spec), _effective_delta(_target_spec),
		pose_config, _target_config, _from_asset, _target_asset)
	pose_node.call("set_weight", _run.weight)
	_bind_oral()
	_bind_face()
	if _oral_pair(from_id, target_id):
		_oral_turn.begin(target_id == CATALOG.STANDING_ORAL, _view)
	_write_log("pose request %s -> %s (%s): ok" % [from_id, target_id, trigger])
	return POSE_STATE.result("ok", edge_id, "")


## The request's form list: the context's own list, or the player's live form.
func _request_forms(context: Dictionary) -> Array:
	var value: Variant = context.get("forms")
	if value is Array and not (value as Array).is_empty():
		return value as Array
	return ["pony"] if _player_pony() else ["human"]


## The request's view list: the context's own list, or the live display.
func _request_views(context: Dictionary) -> Array:
	var value: Variant = context.get("views")
	if value is Array and not (value as Array).is_empty():
		return value as Array
	return ["vr"] if _headset_view() else ["desktop"]


func _request_features(context: Dictionary) -> Dictionary:
	var value: Variant = context.get("features")
	if value is Dictionary:
		return value as Dictionary
	return _facts_features()


func _player_pony() -> bool:
	return facts != null and bool(facts.player_pony)


func _headset_view() -> bool:
	return facts != null and bool(facts.headset_view)


func _facts_features() -> Dictionary:
	if facts == null:
		return {}
	var value: Variant = facts.features
	return value as Dictionary if value is Dictionary else {}


## The target spec and the edge requirements against the live request values, in the order
## `pose_state.request_code()` reports them. A missing flag passes.
func _request_checks(target_spec: Variant, edge: Variant, context: Dictionary, forms: Array,
		views: Array, features: Dictionary) -> Dictionary:
	var requires: Dictionary = {}
	if edge != null:
		var requires_value: Variant = edge.requires
		if requires_value is Dictionary:
			requires = requires_value
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
	var consent := str(context.get("consent", ""))
	var consent_ok := wanted_consent.is_empty() or consent == wanted_consent
	return {
		"form_ok": form_ok,
		"view_ok": view_ok,
		"features_ok": features_ok,
		"consent_ok": consent_ok,
		"asset_ok": asset_ok,
		"locked": bool(context.get("locked", false)),
	}


func _intersects(declared: Array, live: Array) -> bool:
	for value: Variant in declared:
		if value in live:
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


## The transition view: the target identity and profiles from `fill()`, the from/to sides and the
## live edge clock filled explicitly. The live `pose_config` is the from side; the target snapshot
## is the to side.
func _fill_transition_view() -> void:
	_view.fill(_target_spec, pose_config)
	_view.from_id = _from_id
	_view.to_id = _target_id
	_view.from_config = pose_config
	_view.to_config = _target_config
	_view.edge_id = _run.id
	_view.edge_t = _run.t
	_view.weight = _run.weight
	_view.pose_state = _state


## Advance the live edge, apply its switches/events and settle the view. No-op outside an edge.
## The oral turn follows the edge weight from the same tick, so the frame write and the pose blend
## are one frame; a steady oral pose keeps the turn and the live mouth anchor.
func tick(delta: float) -> void:
	_bind_oral()
	_bind_face()
	if facts != null:
		var pace_value: Variant = facts.get("auto_pace")
		_oral_turn.pace = float(pace_value) if pace_value != null else 1.0
	if _run == null:
		_oral_turn.tick(maxf(delta, 0.0), _view, 1.0)
		_face_tick(delta)
		return
	_run.tick(maxf(delta, 0.0))
	_view.edge_t = _run.t
	_view.weight = _run.weight
	if is_instance_valid(pose_node):
		pose_node.call("set_weight", _view.weight)
	_oral_turn.tick(maxf(delta, 0.0), _view, _view.weight)
	_absorb_switches()
	_face_tick(delta)
	_absorb_events()
	if not _run.complete():
		return
	# Capture the target pair before `_abort_target()` drops the target snapshot, adopt its config
	# into the live object, then settle the evaluator on that one pose and its authored asset.
	var completed_target := _target_id
	var completed_driver := _effective_driver(_target_spec)
	var completed_delta := _effective_delta(_target_spec)
	var completed_asset: Variant = _target_asset
	_adopt_target_config()
	if is_instance_valid(pose_node):
		pose_node.authored = completed_asset
		pose_node.from_authored = completed_asset
		pose_node.to_authored = completed_asset
		pose_node.call("set_pose", completed_driver, completed_driver, completed_delta,
			completed_delta, pose_config, pose_config, completed_asset, completed_asset)
		pose_node.call("set_weight", 1.0)
		pose_node.pose_config = pose_config
	_from_asset = completed_asset
	if is_instance_valid(act_body):
		act_body.call("set_pose_assets", completed_asset, completed_asset, 1.0)
	_state = POSE_STATE.next(_state, "complete")
	_view.pose_state = _state
	_view.contact_kind = _spec_contact_kind(_target_spec)
	_view.from_id = _view.id
	_view.to_id = _view.id
	_view.from_config = pose_config
	_view.to_config = pose_config
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
		_write_log("pose switch %s: %s" % [name, target])


## Point the view's contact at the authored kind. Leaving the mouth releases the viseme through
## the host, so a reverse edge cannot leave the open mouth behind while the body eases back.
func _apply_contact_switch(kind: String) -> void:
	if kind.is_empty():
		return
	var previous := str(_view.contact_kind)
	_view.contact_kind = kind
	if kind == "face":
		_bind_face()
		_face_driver.begin(_view, bed_frame)
	elif previous == "face":
		_bind_face()
		_face_driver.restore(_view, pose_node)
	if kind != "mouth" and oral_viseme.is_valid():
		oral_viseme.call("")


## Release the mouth contact without ending the turn. The afterglow calls this to keep the turned
## frame and the neck pose while the part returns to the opening and no close window opens.
func release_mouth_contact() -> void:
	if str(_view.contact_kind) != "mouth":
		return
	_apply_contact_switch(str(_spec_contact_kind(_registry.spec(CATALOG.STANDING))))
	_oral_turn.release_contact(_view)


## Advance the face driver from the live depth. It writes the pose node's frame-space offset and
## the view's contact target; outside a face contact it is a no-op. No allocation in the steady
## tick.
func _face_tick(delta: float) -> void:
	if _face_driver == null or str(_view.contact_kind) != "face":
		return
	var level := 0.0
	if facts != null:
		var value: Variant = facts.get("depth")
		if value is float or value is int:
			level = clampf(float(value), 0.0, 1.0)
	_face_driver.tick(maxf(delta, 0.0), _view, level, bed_frame, pose_node)


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
				_write_log("pose status %s: %s" % [_target_id, str(event.get("value", ""))])
			"speech_stop":
				if oral_speech_stop.is_valid():
					oral_speech_stop.call()
			"viseme":
				if oral_viseme.is_valid():
					oral_viseme.call(str(event.get("value", "")))


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


## Refresh the target snapshot mid-edge. The active pose's config refresh stays in the runtime's
## existing `_sync_standing_pose_config()`/`_sync_missionary_pose_config()` path.
func apply_live_settings() -> void:
	if _target_spec == null:
		return
	var group := str(_target_spec.settings_group)
	var presentation: Dictionary = SETTINGS.act_snapshot(group).presentation
	_target_presentation = presentation
	var fresh := _config_for_group(group, presentation)
	_target_config.clear()
	_target_config.merge(fresh, true)
	_oral_turn.write_config(_view)


## Drop the target snapshot and the running edge without touching the live pose or the view.
func _abort_target() -> void:
	_run = null
	_from_id = ""
	_target_id = ""
	_target_spec = null
	_target_config.clear()
	_target_presentation.clear()
	_target_asset = null


## Adopt the target's settings into the live config in place. The alias object and every consumer
## that holds it (the view, the pose node, the evaluator) see the target; the caller then
## drops the target snapshot.
func _adopt_target_config() -> void:
	if _target_spec == null or is_same(_target_config, pose_config):
		return
	pose_config.clear()
	pose_config.merge(_target_config, true)
	if is_instance_valid(pose_node):
		pose_node.pose_config = pose_config


## The pose block for a settings group plus that group's presentation values. Standing applies the
## presentation chin/neck/tail the same way `sync_standing_config()` does; missionary and an unknown
## group use the live settings block unchanged.
func _config_for_group(group: String, presentation: Dictionary) -> Dictionary:
	var config := SETTINGS.pose(id, group)
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


## The standing recipe reads these from pose_config every frame. Re-reading the character's pose
## first keeps the other pose overrides, then the presentation neck/head controls win.
func sync_standing_config(presentation: Dictionary) -> bool:
	if str(_view.settings_group) != CATALOG.STANDING or not is_instance_valid(pony):
		return false
	pose_config.clear()
	pose_config.merge(_config_for_group(CATALOG.STANDING, presentation), true)
	if is_instance_valid(pose_node):
		pose_node.pose_config = pose_config
	if is_instance_valid(tail):
		tail.aside_angle = float(pose_config.get("tail_aside", 0.0))
		tail.lift_angle = float(pose_config.get("tail_lift", 0.0))
	return true


## The missionary recipe reads these from pose_config every frame. Re-reading the character's
## pose keeps its nuzzle overrides live. The authored asset is owned by the session's begin,
## request, completion, reload and release, so a missionary-group sync cannot reset a live pose
## whose asset differs from the missionary file.
func sync_missionary_config() -> bool:
	if str(_view.settings_group) != CATALOG.MISSIONARY or not is_instance_valid(pony):
		return false
	pose_config.clear()
	pose_config.merge(_config_for_group(CATALOG.MISSIONARY, {}), true)
	if is_instance_valid(pose_node):
		pose_node.pose_config = pose_config
	return true


## The authored base pose for a candidate spec, the live view's pose, or the default missionary
## asset. Parsed once per path; the debug action rewrites the same instance in place, so a live act
## picks the new pose up on its next frame. A row with no asset of its own reads the default so the
## diagnostics still have a rig to describe; `authored_ready()` is the gate.
func authored(candidate := "") -> Variant:
	var asset: Variant = _asset_for(candidate)
	if asset != null:
		return asset
	# A row with no asset of its own reads the default missionary asset so diagnostics still have a
	# rig to describe; `authored_ready()` is the gate and stays false for such a row.
	if _empty_asset == null:
		_empty_asset = AUTHORED.shared(AUTHORED.PATH)
	return _empty_asset


## The asset the live rig is rendering: the source through an edge, the target once it settles.
func live_authored() -> RefCounted:
	if is_instance_valid(pose_node) and pose_node.authored is RefCounted:
		return pose_node.authored as RefCounted
	return authored("") as RefCounted


## The parsed authored pose for the shot camera and the debug action. With no candidate this is
## the live rendered asset, not the target of a running edge.
func authored_asset(candidate := "") -> Variant:
	if str(candidate).is_empty():
		return live_authored()
	return authored(candidate)


## Ground space for an authored ground pose: the pony root's orthonormal basis and position at
## pose start. The frame follows the root each tick, like the bed frame follows its bed.
func ground_pose_frame() -> Variant:
	if not is_instance_valid(pony):
		return null
	return Transform3D(pony.global_basis.orthonormalized(), pony.global_position)


## The live size name from the facts, or "" when no act context is bound.
func _size_name() -> String:
	var value: Variant = facts.get("size_name") if facts != null else null
	return str(value) if value != null else ""


## True when the candidate's own asset loaded and is usable for its frame. A row with no asset is
## never ready, even though `authored()` falls back for diagnostics.
func authored_ready(candidate := "") -> bool:
	var spec: Variant = _candidate_spec(candidate)
	if spec == null:
		return false
	var asset: Variant = _asset_for_spec(spec)
	if asset == null or not bool(asset.get("available")):
		return false
	return bool(asset.call("usable", str(spec.frame)))


## Why the candidate's pose asset is unusable, for the gate row and the start log.
func authored_reason(candidate := "") -> String:
	var spec: Variant = _candidate_spec(candidate)
	if spec == null:
		return "pose_asset: no pose"
	var asset: Variant = _asset_for_spec(spec)
	if asset == null:
		return "pose_asset: no asset for %s" % str(spec.id)
	if not bool(asset.get("available")):
		var why := str(asset.get("error"))
		return "pose_asset: %s" % (why if not why.is_empty() else "not loaded")
	if not bool(asset.call("usable", str(spec.frame))):
		return "pose_asset: %s asset in a %s pose" % [str(asset.get("frame")), str(spec.frame)]
	return ""


## Re-read the live pose's asset in place, plus the running edge's target, or the default
## missionary asset when no pose is live. A running act picks the new pose up on its next frame.
func reload_authored(candidate := "") -> String:
	var paths: Array[String] = []
	var seen: Dictionary = {}
	_add_reload_path(paths, seen, _asset_path_for(candidate))
	if is_instance_valid(pose_node) and pose_node.authored != null:
		_add_reload_path(paths, seen, str(pose_node.authored.get("path")))
	if paths.is_empty():
		_add_reload_path(paths, seen, AUTHORED.PATH)
	for path: String in paths:
		var load_error := AUTHORED.reload_file(path)
		if not load_error.is_empty():
			return load_error
	if is_instance_valid(pose_node):
		# The wrappers were reloaded in place; the pair keeps the same instances.
		pose_node.authored = live_authored()
		if _target_spec != null:
			_target_asset = _asset_for_spec(_target_spec)
			pose_node.to_authored = _target_asset
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


## The middle of the missionary bed's mattress top: the authored pose's origin in world space.
func missionary_origin() -> Vector3:
	if bed_frame is Transform3D:
		return (bed_frame as Transform3D).origin
	return pony.global_position if is_instance_valid(pony) else Vector3.ZERO


## Bed space for the authored pose: the middle of the real bed's mattress top, in the bed's axes,
## with the pillow end at -Z so the authored `+Z` (her head) points at the head of the bed. The
## pose is stored relative to this frame, so any bed size or yaw works; `null` leaves the
## correction stack in charge.
func missionary_pose_frame() -> Variant:
	if str(_view.frame) != "bed" or not is_instance_valid(bed_node):
		return null
	var fallback: float = float(bed_node.get_meta("mattress_top", 0.6)) + float(bed_node.global_position.y)
	var points: Array[Vector3] = [bed_node.global_position]
	var top: float = MATTRESS.visible_top(bed_node, points, fallback)
	if not is_finite(top):
		return null
	var at: Vector3 = bed_node.global_position
	var basis: Basis = bed_node.global_basis.orthonormalized() * Basis(Vector3.UP, PI)
	return Transform3D(basis, Vector3(at.x, top, at.z))


## A bed can move under the act: the Cloudominium's CloudDrift moves it every 0.1 s from
## TimeOfDay.active_seconds. The authored pose, the act body, the camera shot and the anatomy
## placement are all bed-space, so carry them with the bed instead of leaving them at the world
## transform where the act started. The delta is rigid; the mattress top is not re-measured.
func sync_bed_frame() -> void:
	if str(_view.frame) != "bed" or not is_instance_valid(bed_node) \
			or not bed_frame_source_saved or not bed_frame is Transform3D:
		return
	var now: Transform3D = bed_node.global_transform
	if now.is_equal_approx(bed_frame_source):
		return
	var delta: Transform3D = now * bed_frame_source.affine_inverse()
	bed_frame = delta * (bed_frame as Transform3D)
	bed_frame_source = now
	if is_instance_valid(pose_node):
		pose_node.bed_frame = bed_frame


## The ground frame follows the pony root's position and rotation each tick, the way the bed frame
## follows its bed. The oral turn moves the root, so the frame turns with her exactly once.
func sync_ground_frame() -> void:
	if str(_view.frame) != "ground" or not is_instance_valid(pony) \
			or not ground_frame_source_saved or not ground_frame is Transform3D:
		return
	var now: Transform3D = (pony as Node3D).global_transform
	if now.is_equal_approx(ground_frame_source):
		return
	var delta: Transform3D = now * ground_frame_source.affine_inverse()
	ground_frame = delta * (ground_frame as Transform3D)
	ground_frame_source = now
	if is_instance_valid(pose_node):
		pose_node.ground_frame = ground_frame


## Snapshot before the act changes her posture or the pose writes bones.
func snapshot_bones() -> void:
	saved_bones.clear()
	saved_hair.clear()
	saved_skeleton = null
	saved_hair_skeleton = null
	if not is_instance_valid(pony):
		return
	var sk: Variant = pony.get("skeleton")
	if sk is Skeleton3D:
		saved_skeleton = sk as Skeleton3D
		for i in (saved_skeleton as Skeleton3D).get_bone_count():
			saved_bones.append((saved_skeleton as Skeleton3D).get_bone_pose(i))
	var hair: Variant = pony.get("hair_skeleton")
	if hair is Skeleton3D:
		saved_hair_skeleton = hair as Skeleton3D
		for i in (saved_hair_skeleton as Skeleton3D).get_bone_count():
			saved_hair.append((saved_hair_skeleton as Skeleton3D).get_bone_pose(i))


## Put every pony bone back before the game's animation re-poses her. The act's pose modifier is
## already freed when this runs, so nothing rewrites the act pose on top.
func restore_bones() -> void:
	if is_instance_valid(saved_skeleton) \
			and saved_bones.size() == saved_skeleton.get_bone_count():
		for i in saved_bones.size():
			saved_skeleton.set_bone_pose(i, saved_bones[i])
	if is_instance_valid(saved_hair_skeleton) \
			and saved_hair.size() == saved_hair_skeleton.get_bone_count():
		for i in saved_hair.size():
			saved_hair_skeleton.set_bone_pose(i, saved_hair[i])
	saved_bones.clear()
	saved_hair.clear()
	saved_skeleton = null
	saved_hair_skeleton = null


## The pose-scope start state: clear the rig-check cache and release the tail lay and the bed frame.
## A pose change that keeps the act alive calls this first and keeps the pose node, the modifiers,
## `pose_config` and the view.
func leave_pose_start() -> void:
	rig_checked = false
	rig_skeleton = 0
	rig_revision = -1
	rig_missing_bones = []
	if _face_driver != null and bool(_face_driver.get("active")):
		_face_driver.restore(_view, pose_node)
	if is_instance_valid(tail_lay):
		tail_lay.call("restore_tail")
		_drop(tail_lay)
	tail_lay = null
	bed_frame = null
	bed_frame_source_saved = false
	bed_frame_source = Transform3D.IDENTITY
	ground_frame = null
	ground_frame_source_saved = false
	ground_frame_source = Transform3D.IDENTITY


## The pose-scope body state: drop the live-installed extra modifiers. It keeps the pose node, the
## standing tail, `pose_config` and the view.
func leave_pose_body() -> void:
	if is_instance_valid(body_sway):
		_drop(body_sway)
	body_sway = null
	if is_instance_valid(prone_sway):
		_drop(prone_sway)
	prone_sway = null
	if is_instance_valid(ear_twitch):
		_drop(ear_twitch)
	ear_twitch = null


## The final pose clear: free the pose modifier and the standing tail, and clear the act's state so
## `base_info()` and `state_rows()` stop describing an act that ended and the next `begin()` starts
## clean. The runtime calls this last in the one pose teardown, then re-stamps its identity mirror
## on the next access. A pose change never calls it. Safe to repeat.
func release_pose() -> void:
	# A release aborts a live edge and returns the oral frame before the view is cleared; it never
	# runs a second act exit.
	_bind_oral()
	_oral_turn.restore(_view)
	_bind_face()
	_face_driver.restore(_view, pose_node)
	_face_driver.reset()
	_abort_target()
	_state = POSE_STATE.next(_state, "exit")
	_release_act_body()
	if is_instance_valid(pose_node):
		_drop(pose_node)
	pose_node = null
	_from_asset = null
	_target_asset = null
	if is_instance_valid(tail):
		tail.call("restore_tail")
		_drop(tail)
	tail = null
	_started = false
	id = ""
	features = {}
	pose_config.clear()
	rig_checked = false
	rig_skeleton = 0
	rig_revision = -1
	rig_missing_bones = []
	bed_frame = null
	bed_frame_source_saved = false
	bed_frame_source = Transform3D.IDENTITY
	ground_frame = null
	ground_frame_source_saved = false
	ground_frame_source = Transform3D.IDENTITY
	_tail_anchor = Vector3.INF
	_view.clear()
	_oral_turn.reset()
	_state = POSE_STATE.next(_state, "released")


## One pose-change fan-out. Reconciles the modifier profile and applies the `act_body`/`anon`
## channel; the pose evaluator pair was already set by `begin`/`request_pose`/`tick`. Cheap and
## idempotent: every owner compares against its own cache, so a steady tick installs nothing.
func pose_changed(view: Variant) -> void:
	if not _started or view == null:
		return
	var to_spec: Variant = _registry.spec(str(view.to_id))
	if to_spec == null:
		to_spec = _registry.spec(str(view.id))
	var from_spec: Variant = _registry.spec(str(view.from_id))
	if from_spec == null:
		from_spec = to_spec
	_reconcile_modifiers(_profile_of(from_spec), _profile_of(to_spec), view)
	_apply_anon_channel(view)


## The spec's modifier profile name, or empty when the row has no block.
func _profile_of(spec: Variant) -> String:
	if spec == null:
		return ""
	var value: Variant = spec.modifiers
	return str((value as Dictionary).get("profile", "")) if value is Dictionary else ""


## The owner list of an authored profile. An unknown profile is the empty set.
func _profile_owners(profile: String) -> Array:
	var value: Variant = modifier_profiles.get(profile, NO_OWNERS)
	return value as Array if value is Array else NO_OWNERS


## Keep the shared owners, install the target-only ones and remove the source-only ones. The act
## exit's `leave_pose_body()` is still the full removal; this never calls it.
func _reconcile_modifiers(from_profile: String, to_profile: String, view: Variant) -> void:
	var from_owners := _profile_owners(from_profile)
	var to_owners := _profile_owners(to_profile)
	var skeleton_value: Variant = pony.get("skeleton") if is_instance_valid(pony) else null
	var skeleton := skeleton_value as Skeleton3D
	for owner: String in MODIFIER_ORDER:
		var wanted: bool = owner in to_owners
		var shared: bool = wanted and owner in from_owners
		_sync_owner(owner, wanted, shared, view, skeleton)


## Install, keep and retarget, or remove one owner. A shared keep calls the owner's own idempotent
## `pose_changed(view)`; a feature edit that turns the owner off removes it even on a shared keep.
func _sync_owner(owner: String, wanted: bool, retarget: bool, view: Variant,
		skeleton: Skeleton3D) -> void:
	var keep := wanted and _owner_feature(owner)
	match owner:
		"body_sway":
			if keep:
				if not is_instance_valid(body_sway):
					if skeleton != null:
						_install_body_sway(skeleton)
				elif retarget:
					body_sway.call("pose_changed", view)
			elif is_instance_valid(body_sway):
				_drop(body_sway)
				body_sway = null
		"prone_sway":
			if keep:
				if not is_instance_valid(prone_sway):
					if skeleton != null:
						_install_prone_sway(skeleton)
				elif retarget:
					prone_sway.call("pose_changed", view)
			elif is_instance_valid(prone_sway):
				_drop(prone_sway)
				prone_sway = null
		"ear_twitch":
			if keep:
				if not is_instance_valid(ear_twitch):
					_install_ear_twitch()
				elif retarget:
					ear_twitch.call("pose_changed", view)
			elif is_instance_valid(ear_twitch):
				_drop(ear_twitch)
				ear_twitch = null
		"tail":
			if keep:
				if not is_instance_valid(tail):
					_install_tail()
				elif retarget:
					tail.call("pose_changed", view)
			elif is_instance_valid(tail):
				tail.call("restore_tail")
				_drop(tail)
				tail = null
		"tail_lay":
			if keep:
				if not is_instance_valid(tail_lay):
					_install_tail_lay()
				elif retarget:
					tail_lay.call("pose_changed", view)
			elif is_instance_valid(tail_lay):
				tail_lay.call("restore_tail")
				_drop(tail_lay)
				tail_lay = null


## The feature gate an owner installs behind. The tails have none.
func _owner_feature(owner: String) -> bool:
	match owner:
		"body_sway":
			return _feature("standing_body_sway")
		"prone_sway":
			return _feature("missionary_body_motion")
		"ear_twitch":
			return _feature("thrust_ear_twitch")
	return true


## The live edge's `anon` channel, or the empty hold. Outside an edge the spec's profile holds.
func _anon_channel() -> Dictionary:
	if _run == null:
		return NO_CHANNEL
	var channels_value: Variant = _run.edge.get("channels", {})
	if not channels_value is Dictionary:
		return NO_CHANNEL
	var value: Variant = (channels_value as Dictionary).get("anon")
	return value as Dictionary if value is Dictionary else NO_CHANNEL


## Apply the `act_body` specs' Anon channel: `hold` keeps the adapter, `blend` carries the edge
## weight and `switch` names the authored profile. The service also binds the authored asset pair:
## both sides of the live asset outside an edge, the source and target on a blend, and the target
## twice on a switch. The player-body specs never install the adapter.
func _apply_anon_channel(view: Variant) -> void:
	var anon_value: Variant = view.anon
	if not anon_value is Dictionary:
		return
	var anon := anon_value as Dictionary
	if str(anon.get("mode", "")) != "act_body":
		return
	_install_act_body()
	if not is_instance_valid(act_body):
		return
	if _run == null:
		# Outside an edge the spec's profile is the hold and both assets are the live one.
		var live: Variant = live_authored()
		act_body.call("set_pose_assets", live, live, 1.0)
		act_body.call("pose_changed", str(anon.get("profile", "")), 1.0)
		return
	var channel := _anon_channel()
	match str(channel.get("kind", "hold")):
		"blend":
			act_body.call("set_pose_assets", _from_asset, _target_asset,
				clampf(float(view.weight), 0.0, 1.0))
			act_body.call("set_weight", clampf(float(view.weight), 0.0, 1.0))
		"switch":
			var switched := str(channel.get("profile", ""))
			if switched.is_empty():
				switched = str(channel.get("set", ""))
			if switched.is_empty():
				switched = str(anon.get("profile", ""))
			act_body.call("set_pose_assets", _target_asset, _target_asset, 1.0)
			act_body.call("pose_changed", switched, 1.0)
		_:
			# A hold keeps the adapter's current profile, weight and asset pair.
			pass


## The act body exists only on a bed spec's `act_body` mode for desktop human Anon.
func _act_body_wanted(view: Variant) -> bool:
	if facts == null:
		return false
	var anon_value: Variant = view.anon
	if not anon_value is Dictionary:
		return false
	if str((anon_value as Dictionary).get("mode", "")) != "act_body":
		return false
	return not bool(facts.player_pony) and not bool(facts.headset_view)


## The act's own Anon body, created on the runtime host and handed to the anatomy bridge as an
## opaque handle. The bridge never creates or frees it.
func _install_act_body() -> void:
	if is_instance_valid(act_body):
		return
	var parent := host as Node
	if parent == null or not _act_body_wanted(_view):
		return
	var body: Node = MISSIONARY_ANON.new()
	body.name = "UnfplapMissionaryAnon"
	parent.add_child(body)
	if not bool(body.call("install", facts)):
		parent.remove_child(body)
		body.queue_free()
		return
	body.call("set_pose_assets", live_authored(), live_authored(), 1.0)
	act_body = body
	if set_act_body.is_valid():
		set_act_body.call(body)


## Clear the bridge handle first, then restore and free the act body once. A transition never
## reaches this.
func _release_act_body() -> void:
	if set_act_body.is_valid():
		set_act_body.call(null)
	if not is_instance_valid(act_body):
		act_body = null
		return
	var body := act_body as Node
	if body != null:
		if body.has_method("remove"):
			body.call("remove")
		_drop(body)
	act_body = null


## The live settings edit's entry: swap the session's feature flags and run the same
## `pose_changed(view)` pass the tick does. The view carries the active profile, so no pose id is
## needed.
func refresh_modifiers(feature_flags: Dictionary) -> void:
	features = feature_flags
	pose_changed(_view)


## Detach a released modifier before freeing it. `queue_free()` alone leaves it parented for the
## rest of the frame, where it still gets a modification pass, and a new act built in the same
## frame would run two. Callers restore their own bones before the detach.
func _drop(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	var parent := node.get_parent()
	if parent != null:
		parent.remove_child(node)
	node.queue_free()


func _install_tail() -> void:
	if is_instance_valid(tail) or not is_instance_valid(pony):
		return
	var found: Dictionary = TAIL_CHAIN.resolve(pony)
	if found.is_empty():
		return
	var skeleton: Skeleton3D = found["skeleton"]
	tail = TAIL.new()
	tail.name = "UnfplapTail"
	tail.mare = pony
	tail.facts = facts
	tail.aside_angle = float(pose_config.get("tail_aside", 0.0))
	tail.lift_angle = float(pose_config.get("tail_lift", 0.0))
	tail.amount = 0.0
	tail.target_amount = 1.0
	var side_anchor: Variant = _tail_anchor
	if not side_anchor is Vector3:
		side_anchor = Vector3.INF
	tail.call("choose_side", side_anchor)
	tail.process_priority = 20
	skeleton.add_child(tail)


func _install_tail_lay() -> void:
	if not is_instance_valid(pony):
		return
	var found: Dictionary = TAIL_CHAIN.resolve(pony)
	if found.is_empty():
		return
	var skeleton: Skeleton3D = found["skeleton"]
	tail_lay = TAIL_LAY.new()
	tail_lay.name = "UnfplapTailLay"
	tail_lay.mare = pony
	tail_lay.facts = facts
	tail_lay.process_priority = 20
	skeleton.add_child(tail_lay)


func _install_body_sway(skeleton: Skeleton3D) -> void:
	if not _feature("standing_body_sway"):
		return
	body_sway = BODY_SWAY.new()
	body_sway.name = "UnfplapBodySway"
	body_sway.set("mare", pony)
	body_sway.set("facts", facts)
	skeleton.add_child(body_sway)
	_reset_sway_base()


func _install_prone_sway(skeleton: Skeleton3D) -> void:
	prone_sway = PRONE_SWAY.new()
	prone_sway.name = "UnfplapProneSway"
	prone_sway.set("mare", pony)
	prone_sway.set("facts", facts)
	prone_sway.set("perf", perf)
	skeleton.add_child(prone_sway)


func _install_ear_twitch() -> void:
	if not _feature("thrust_ear_twitch"):
		return
	var boop: Variant = pony.get("boop_node")
	var head: Variant = head_skeleton(boop)
	if not head is Skeleton3D:
		return
	ear_twitch = EAR_TWITCH.new()
	ear_twitch.name = "UnfplapEarTwitch"
	ear_twitch.set("mare", pony)
	ear_twitch.set("facts", facts)
	(head as Skeleton3D).add_child(ear_twitch)


## The head skeleton the ear twitch rides, or null.
func head_skeleton(boop: Variant) -> Variant:
	if boop == null:
		return null
	return boop.get("head_skeleton")


## The render-time pose write. The runtime calls this after the game's own writers so the
## authored missionary pose survives to the renderer.
func apply_render(skeleton: Skeleton3D) -> void:
	if is_instance_valid(pose_node):
		pose_node.call("apply_render", skeleton)


## The whole render-time step for one frame, in order: park the game presentation and place the
## act's own Anon body over it, write her pose last, then let the eye-shot camera read his posed
## head. The runtime owns the call site in `_process_tick`; this facade owns the sequence.
## Context: `bed_frame`, `body_scale`, `eye_camera_active`. The view family is the active pose's.
func render_write(context: Dictionary) -> void:
	if not is_instance_valid(pony):
		return
	var family := str(_view.family)
	if family == "standing":
		# Same order as the bed family: the ground frame, then the pose write after every physics
		# and process writer of the frame.
		sync_ground_frame()
		var standing_sk: Variant = pony.get("skeleton")
		if is_instance_valid(pose_node) and standing_sk is Skeleton3D:
			apply_render(standing_sk as Skeleton3D)
		return
	if family != "bed":
		return
	if hide_avatar.is_valid():
		hide_avatar.call()
	var frame: Variant = context.get("bed_frame")
	if is_instance_valid(act_body) and frame is Transform3D:
		act_body.call("apply", frame as Transform3D, float(context.get("body_scale", 1.0)))
	var sk: Variant = pony.get("skeleton")
	if is_instance_valid(pose_node) and sk is Skeleton3D:
		apply_render(sk as Skeleton3D)
	if bool(context.get("eye_camera_active", false)) and eye_camera.is_valid():
		eye_camera.call()


func trigger_ear_twitch(impact: float) -> void:
	if is_instance_valid(ear_twitch):
		ear_twitch.call("try_trigger", impact)


func set_tail_target(value: float) -> void:
	if is_instance_valid(tail):
		tail.target_amount = value


func flick_tail(count: int) -> void:
	if is_instance_valid(tail):
		tail.call("flick", count)


func pose() -> Variant:
	return pose_node


func basis_amount() -> float:
	return float(pose_node.get("amount")) if is_instance_valid(pose_node) else 0.0


## Which missionary base is in charge and why. One dictionary so the log, the settled line and the
## debug action cannot drift apart. The live side is the rendered asset while an edge runs; the
## target path names where the edge is going.
func base_info() -> Dictionary:
	var live_id := _live_spec_id()
	var asset: Variant = authored_asset()
	var bones: Variant = asset.get("pony_bones")
	var live: Variant = pose_frame()
	var live_path := _asset_path_for(live_id)
	var target_path := _asset_path_for(_target_id) if _target_spec != null else live_path
	var info := {
		"base": "none",
		"reason": "",
		"version": int(asset.get("version")),
		"bones": (bones as Dictionary).size() if bones is Dictionary else 0,
		"available": bool(asset.get("available")),
		"error": str(asset.get("error")),
		"frame": live,
		"frame_kind": str(_view.frame),
		"shots": bool(asset.get("has_shots")),
		"asset": asset,
		"asset_path": live_path,
		"live_path": live_path,
		"target_path": target_path,
		"asset_frame": str(asset.get("frame")),
		"variant": str(asset.get("variant")),
	}
	if live_id.is_empty():
		info["reason"] = "pose="
	elif live_path.is_empty():
		info["reason"] = "pose=%s" % live_id
	elif not bool(asset.get("available")):
		info["reason"] = authored_reason(live_id)
	elif not live is Transform3D:
		info["reason"] = "no %s frame" % str(_view.frame)
	elif not bool(asset.call("usable", str(_view.frame))):
		info["reason"] = authored_reason(live_id)
	else:
		info["base"] = "authored"
	return info


## The live pose frame: the bed's mattress space or the pony root's ground space.
func pose_frame() -> Variant:
	if str(_view.frame) == "ground":
		return ground_frame
	if str(_view.frame) == "bed":
		return bed_frame
	return null


## The authored body bones the live rig lacks. The pose writes only the bones it holds, so a missing
## one leaves the game's pose on that link and the chain above it reads broken; the act refuses to
## start. Cached per skeleton instance and asset revision, because the gate polls every frame and a
## posed-base reload must re-check the new asset.
func rig_missing(candidate := "") -> Array:
	var sk: Variant = pony.get("skeleton") if is_instance_valid(pony) else null
	if not sk is Skeleton3D:
		return []
	var skeleton := sk as Skeleton3D
	var instance := skeleton.get_instance_id()
	var asset_path := _asset_path_for(candidate)
	if asset_path.is_empty():
		asset_path = AUTHORED.PATH
	if rig_checked and instance == rig_skeleton and rig_revision == AUTHORED.revision \
			and rig_asset_path == asset_path:
		return rig_missing_bones
	rig_checked = true
	rig_skeleton = instance
	rig_revision = AUTHORED.revision
	rig_asset_path = asset_path
	var missing: Variant = authored(candidate).call("missing_bones", skeleton)
	rig_missing_bones = missing if missing is Array else []
	return rig_missing_bones


## The gate row's reason, naming the first few bones and counting the rest.
func rig_reason(missing: Array) -> String:
	if missing.is_empty():
		return ""
	var names: PackedStringArray = []
	for i in mini(3, missing.size()):
		names.append(str(missing[i]))
	var text := "pose_rig: missing %s" % ", ".join(names)
	if missing.size() > 3:
		text += " (+%d more)" % (missing.size() - 3)
	return text


## Render-time placement trace, two lines per act: printed from idle, after every physics and process
## writer, so it reads the pose the renderer is about to use. `root` is the armature bone the authored
## placement is written to; `wanted` is that pose carried into the live bed frame.
func idle_sample(state: int) -> void:
	if pose_trace_frames >= 2 or str(_view.frame) != "bed" or state == 0:
		return
	if not is_instance_valid(pose_node) or basis_amount() < 0.9:
		return
	var sk: Variant = pony.get("skeleton") if is_instance_valid(pony) else null
	if not sk is Skeleton3D:
		return
	var skeleton := sk as Skeleton3D
	var root := int(pose_node.get("diag_root"))
	var hips := skeleton.find_bone("pony_hips")
	var g := skeleton.global_transform
	var render_root := g * skeleton.get_bone_global_pose(root) if root >= 0 else Transform3D.IDENTITY
	var render_hips := g * skeleton.get_bone_global_pose(hips) if hips >= 0 else Transform3D.IDENTITY
	var wanted_root: Transform3D = pose_node.get("diag_root_wanted")
	var wanted_hips: Transform3D = pose_node.get("diag_hips_wanted")
	var animation: Variant = pony.get("animation")
	var clip := ""
	var playing := false
	if animation is AnimationPlayer:
		clip = (animation as AnimationPlayer).current_animation
		playing = (animation as AnimationPlayer).is_playing()
	_write_log("pose trace f=%d root=%d:%s asset_root=%d trace=%d mode=%d clip=%s playing=%s G=%s" % [
		pose_trace_frames, root, str(pose_node.get("diag_root_name")), int(pose_node.get("diag_asset_root")),
		int(pose_node.get("diag_trace")), skeleton.modifier_callback_mode_process, clip, str(playing),
		str(g)])
	_write_log("pose trace f=%d root start=%s after=%s render=%s wanted=%s d=%.3f/%.3f | hips start=%s render=%s wanted=%s d=%.3f" % [
		pose_trace_frames, str(pose_node.get("diag_root_start")), str(pose_node.get("diag_root_after")),
		str(render_root), str(wanted_root),
		render_root.origin.distance_to(wanted_root.origin),
		_transform_angle(render_root, wanted_root),
		str(pose_node.get("diag_hips_start")), str(render_hips), str(wanted_hips),
		render_hips.origin.distance_to(wanted_hips.origin)])
	pose_trace_frames += 1


## Degrees between two transforms' bases, for the trace.
func _transform_angle(a: Transform3D, b: Transform3D) -> float:
	return rad_to_deg(a.basis.orthonormalized().get_rotation_quaternion().angle_to(
		b.basis.orthonormalized().get_rotation_quaternion()))


## Rig, modifier and posture diagnostics: which skeleton the modifier drives, which skeleton every
## mesh is actually bound to, whether the pose survives between frames, and who else is near the bed.
func diagnostics(skeleton: Skeleton3D, info: Dictionary) -> Array:
	var rows: Array = []
	var modifier: Variant = pose_node
	var parent: Node = modifier.get_parent() if is_instance_valid(modifier) else null
	rows.append("modifier=%s parent=%s match=%s frames=%d weight=%.2f base=%s readback=%.2f°" % [
		"yes" if is_instance_valid(modifier) else "no",
		"%s@%s" % [str(parent.name), str(parent.get_instance_id())] if parent != null else "none",
		"yes" if parent == skeleton else "NO", int(_num(modifier.get("diag_frames"))) if is_instance_valid(modifier) else 0,
		_num(modifier.get("diag_last_weight")) if is_instance_valid(modifier) else 0.0,
		str(modifier.get("diag_last_base")) if is_instance_valid(modifier) else "",
		_num(modifier.get("diag_readback_deg")) if is_instance_valid(modifier) else 0.0])
	var modifiers: Array[String] = []
	for child: Node in skeleton.get_children():
		if child is SkeletonModifier3D:
			var active: Variant = child.get("active")
			var influence: Variant = child.get("influence")
			modifiers.append("%s%s%s" % [
				str(child.name),
				(" active=%s" % str(active)) if active != null else "",
				(" inf=%.2f" % float(influence)) if influence is float else ""])
	rows.append("skeleton modifiers=%d [%s]" % [modifiers.size(), ", ".join(modifiers)])
	rows.append("hips write check: after_write=%.2f° readback=%.2f° (%s)" % [
		_num(modifier.get("diag_after_write_deg")) if is_instance_valid(modifier) else 0.0,
		_num(modifier.get("diag_readback_deg")) if is_instance_valid(modifier) else 0.0,
		"write lands, survives" if is_instance_valid(modifier)
			and _num(modifier.get("diag_after_write_deg")) < 1.0
			and _num(modifier.get("diag_readback_deg")) < 1.0
		else "write lands, lost by next frame" if is_instance_valid(modifier)
			and _num(modifier.get("diag_after_write_deg")) < 1.0
		else "write does not land"])
	rows.append("pony_skeleton=%s@%s actor=%s paused=%s visible=%s" % [
		str(skeleton.name), str(skeleton.get_instance_id()), str(pony.global_position),
		str(pony.get("motion_paused")), str(pony.visible)])
	var posture: Variant = pony.get("posture")
	if posture != null:
		rows.append("posture kind=%s requested=%s phase=%s progress=%.2f ready=%s clip=%s refusal=%s" % [
			str(posture.get("kind")), str(posture.get("requested")), str(posture.get("phase")),
			_num(posture.get("progress")), str(posture.get("ready")), str(posture.get("clip")),
			str(posture.get("refusal"))])
	# Every mesh's own skeleton: a mesh bound elsewhere would follow the game's animation instead of
	# the pose modifier.
	var groups: Dictionary = {}
	for node: Node in pony.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var target: Node = mesh.get_node_or_null(mesh.skeleton) if not mesh.skeleton.is_empty() else null
		var instance := target.get_instance_id() if target != null else 0
		if not groups.has(instance):
			groups[instance] = {"count": 0, "sample": str(mesh.name), "visible": false, "target": target}
		var entry: Dictionary = groups[instance]
		entry["count"] = int(entry["count"]) + 1
		entry["visible"] = bool(entry["visible"]) or mesh.is_visible_in_tree()
	for instance: Variant in groups:
		var entry: Dictionary = groups[instance]
		var target: Variant = entry["target"]
		var hips := Vector3.INF
		if target is Skeleton3D:
			var bone := (target as Skeleton3D).find_bone("pony_hips")
			if bone >= 0:
				hips = (target as Skeleton3D).global_transform * (target as Skeleton3D).get_bone_global_pose(bone).origin
		rows.append("mesh_skeleton=%s meshes=%d sample=%s visible=%s hips=%s" % [
			("%s@%s" % [str((target as Node).name), str(instance)]) if target is Node else "none",
			int(entry["count"]), str(entry["sample"]), str(entry["visible"]), str(hips)])
	# Live hips pose vs the authored quaternion: proves whether the modifier's write is what lives.
	var asset: Variant = info.get("asset")
	var hips_bone := skeleton.find_bone("pony_hips")
	if hips_bone >= 0 and asset != null:
		var entry: Variant = (asset.get("pony_bones") as Dictionary).get("pony_hips")
		if entry is Dictionary:
			var wanted: Quaternion = (entry as Dictionary)["rotation"]
			var live := skeleton.get_bone_pose_rotation(hips_bone)
			rows.append("hips_pose live=%s authored=%s delta=%.1f°" % [
				str(live), str(wanted), rad_to_deg(live.angle_to(wanted))])
	# Nearby ponies, so a body on the bed can be identified as someone else.
	var nearest: Array = []
	var tree: SceneTree = pony.get_tree() if is_instance_valid(pony) else null
	if tree != null:
		for node: Node in tree.get_nodes_in_group("ai_characters"):
			var other := node as Node3D
			if other == null or other == pony:
				continue
			var distance := other.global_position.distance_to(pony.global_position)
			if distance > 4.0:
				continue
			var other_sk: Variant = other.get("skeleton")
			var hips_at := Vector3.INF
			if other_sk is Skeleton3D:
				var b := (other_sk as Skeleton3D).find_bone("pony_hips")
				if b >= 0:
					hips_at = (other_sk as Skeleton3D).global_transform * (other_sk as Skeleton3D).get_bone_global_pose(b).origin
			nearest.append("%s d=%.1f posture=%s hips=%s" % [
				str(other.name), distance,
				str(other.call("posture_status").get("requested", "?")), str(hips_at)])
	rows.append("nearby=%d %s" % [nearest.size(), "; ".join(nearest)])
	return rows


## Multi-row pose diagnostic for the debug action: base source, asset state, bed frame and where
## the live pose actually put her (world and bed space).
func state_rows(state: int) -> Array:
	var info := base_info()
	var frame: Variant = info["frame"]
	var rows: Array = []
	rows.append("pony=%s pose=%s state=%d weight=%.2f" % [
		str(pony.name) if is_instance_valid(pony) else "?", str(_view.id), state, basis_amount()])
	rows.append("base=%s reason=%s asset=v%d %s path=%s frame=%s variant=%s bones=%d missing=%s shots=%s error=%s" % [
		str(info["base"]), str(info["reason"]),
		int(info["version"]), "ok" if bool(info["available"]) else "error",
		str(info["asset_path"]), str(info["asset_frame"]), str(info["variant"]), int(info["bones"]),
		str(rig_missing()), "yes" if bool(info["shots"]) else "no", str(info["error"])])
	var target_path := str(info.get("target_path", ""))
	if not target_path.is_empty() and target_path != str(info["asset_path"]):
		rows.append("target=%s" % target_path)
	rows.append("frame=%s kind=%s scale=%.2f" % [
		str(frame) if frame is Transform3D else "null", str(info["frame_kind"]), body_scale()])
	var sk: Variant = pony.get("skeleton") if is_instance_valid(pony) else null
	if not sk is Skeleton3D:
		return rows
	var skeleton := sk as Skeleton3D
	rows.append_array(diagnostics(skeleton, info))
	var space := Transform3D.IDENTITY
	if frame is Transform3D:
		space = (frame as Transform3D).affine_inverse()
	for pair: Array in [["hips", "pony_hips"], ["neck", "pony_neck1"], ["neck_mid", "pony_neck2"],
			["head", "pony_head"], ["hoof_l", "pony_hoof_L"], ["hoof_r", "pony_hoof_R"]]:
		var bone := skeleton.find_bone(str(pair[1]))
		if bone < 0:
			continue
		var world := skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
		var bed := space * world
		rows.append("%s world=(%.3f,%.3f,%.3f) bed=(%.3f,%.3f,%.3f)" % [
			str(pair[0]), world.x, world.y, world.z, bed.x, bed.y, bed.z])
	return rows


## The base line written once when the act builds its pose.
func log_base() -> void:
	var info := base_info()
	var frame: Variant = info["frame"]
	var missing := rig_missing()
	_write_log("pose base=%s reason=%s asset=v%d %s path=%s frame=%s variant=%s bones=%d missing=%d shots=%s frame_pose=%s scale=%.2f" % [
		str(info["base"]), str(info["reason"]), int(info["version"]),
		"ok" if bool(info["available"]) else "error", str(info["asset_path"]),
		str(info["asset_frame"]), str(info["variant"]), int(info["bones"]),
		missing.size(), "yes" if bool(info["shots"]) else "no",
		str(frame) if frame is Transform3D else "null", body_scale()])
	if not missing.is_empty():
		_write_log("pose rig %s" % rig_reason(missing))


## One line with where the pose actually put her, in world and bed space, once the weight settles.
func log_settled(state: int, anon_diag: Callable) -> void:
	if pose_logged or str(_view.frame) != "bed" or state == 0:
		return
	if basis_amount() < 0.9:
		return
	pose_logged = true
	if not is_instance_valid(pony):
		return
	var sk: Variant = pony.get("skeleton")
	if not sk is Skeleton3D:
		return
	var skeleton := sk as Skeleton3D
	var space := Transform3D.IDENTITY
	if bed_frame is Transform3D:
		space = (bed_frame as Transform3D).affine_inverse()
	var parts: Array[String] = []
	for pair: Array in [["hips", "pony_hips"], ["neck", "pony_neck1"], ["head", "pony_head"],
			["hoof_l", "pony_hoof_L"], ["hoof_r", "pony_hoof_R"]]:
		var bone := skeleton.find_bone(str(pair[1]))
		if bone < 0:
			continue
		var world := skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
		var bed := space * world
		parts.append("%s=w%s/b(%.3f,%.3f,%.3f)" % [
			str(pair[0]), str(world), bed.x, bed.y, bed.z])
	_write_log("missionary settled base=%s weight=%.2f %s" % [
		str(base_info()["base"]), basis_amount(), " ".join(parts)])
	for row: Variant in diagnostics(skeleton, base_info()):
		_write_log("missionary diag %s" % str(row))
	if anon_diag.is_valid():
		var text := str(anon_diag.call())
		if not text.is_empty():
			_write_log("anon diag %s" % text)


## Absolute body scale from the rig's own pivot, 1.0 when the pony is gone.
func body_scale() -> float:
	var value: Variant = pony.get("body_scale") if is_instance_valid(pony) else null
	return float(value) if value != null else 1.0


func _reset_sway_base() -> void:
	if is_instance_valid(body_sway):
		body_sway.call("reset_base")


func _feature(name: String) -> bool:
	return bool(features.get(name, false))


## Numeric read of a Variant property without tripping over a missing one.
func _num(value: Variant, fallback := 0.0) -> float:
	return float(value) if value is float or value is int else fallback


func _write_log(text: String) -> void:
	if log.is_valid():
		log.call(text)
