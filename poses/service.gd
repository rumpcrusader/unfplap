extends RefCounted
## The act's pose session: the skeleton pose modifier, the authored missionary base, the bed frame,
## the extra modifiers, the bone snapshots and the pose diagnostics. The act state, the start order
## and the ledger behind the one teardown belong to the runtime. Contract: `docs/poses.md`.
## The teardown is split by lifetime: the session owns the pose-scope steps and the act-scope resets
## between them stay in the runtime's ledger.

const POSE := preload("res://mods/unfplap/poses/skeleton_pose.gd")
const POSE_SPEC := preload("res://mods/unfplap/poses/pose_spec.gd")
const BASE_INFO := preload("res://mods/unfplap/poses/pose_base_info.gd")
const TRANSITION_SPEC := preload("res://mods/unfplap/poses/transition_spec.gd")
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
const ACT_FACTS := preload("res://mods/unfplap/shared/act_facts.gd")
const ACT_STATE := preload("res://mods/unfplap/shared/act_state.gd")
const POSE_STATE := preload("res://mods/unfplap/poses/pose_state.gd")
const ORAL_TURN := preload("res://mods/unfplap/poses/oral_turn.gd")
const FACE_CONTACT := preload("res://mods/unfplap/poses/face_contact.gd")
const SPECS := preload("res://mods/unfplap/shared/pose_specs.gd")
const REGISTRY := preload("res://mods/unfplap/poses/registry.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const WORLD := preload("res://mods/unfplap/world/api.gd")
const MATTRESS := preload("res://world/life/couch/mattress.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")

## The empty sets the reconcile and the anon channel read, so a steady tick allocates nothing.
const NO_OWNERS: Array[String] = []
const NO_CHANNEL := {}
## The owner names in install order, matching `shared/pose_specs.gd`'s profile table.
const MODIFIER_ORDER := ["body_sway", "prone_sway", "ear_twitch", "tail", "tail_lay"]
## The absent pose frame: a real transform whose infinite origin no reader mistakes for space.
const NO_FRAME := Transform3D(Basis.IDENTITY, Vector3.INF)


## The act's live feature switches, held by reference so the session and the snapshot agree.
class FeatureFlags extends RefCounted:
	var flags: Dictionary = {}

	static func from_dict(block: Dictionary) -> FeatureFlags:
		var out := FeatureFlags.new()
		out.flags = block
		return out

	func enabled(name: String) -> bool:
		return bool(flags.get(name, false))


## One pose config or presentation block, wrapped at the boundary and merged in place.
class SettingsBlock extends RefCounted:
	var values: Dictionary = {}

	static func from_dict(block: Dictionary) -> SettingsBlock:
		var out := SettingsBlock.new()
		out.values = block
		return out


## One pose request's act values; an unset field falls back to the session's live facts.
class PoseRequest extends RefCounted:
	var act_state := -1
	var forms: Array[String] = []
	var views: Array[String] = []
	var features: Dictionary = {}
	var features_set := false
	var consent := ""
	var locked := false

	static func from_dict(raw: Dictionary) -> PoseRequest:
		var out := PoseRequest.new()
		out.act_state = int(raw.get("act_state", -1))
		out.forms = _names(raw.get("forms"))
		out.views = _names(raw.get("views"))
		var flags: Variant = raw.get("features")
		if flags is Dictionary:
			out.features = flags
			out.features_set = true
		out.consent = str(raw.get("consent", ""))
		out.locked = bool(raw.get("locked", false))
		return out

	static func _names(value: Variant) -> Array[String]:
		var out: Array[String] = []
		if value is Array:
			for item: Variant in value:
				out.append(str(item))
		return out

	func copy() -> PoseRequest:
		var out := PoseRequest.new()
		out.act_state = act_state
		out.forms = forms
		out.views = views
		out.features = features
		out.features_set = features_set
		out.consent = consent
		out.locked = locked
		return out


## One pose request's verdict; `ok` is true only for the accepted code.
class PoseResult extends RefCounted:
	var ok := false
	var code := ""
	var edge := ""
	var reason := ""

	static func make(code_value: String, edge_id := "", reason_text := "") -> PoseResult:
		var out := PoseResult.new()
		out.code = code_value
		out.ok = code_value == "ok"
		out.edge = edge_id
		out.reason = reason_text
		return out


## The render-time write's frame, body scale and size name.
class RenderFrame extends RefCounted:
	var bed_frame := Transform3D(Basis.IDENTITY, Vector3.INF)
	var body_scale := 1.0
	var size_name := ""

	static func of(frame: Transform3D, scale: float, size_name_value: String) -> RenderFrame:
		var out := RenderFrame.new()
		out.bed_frame = frame
		out.body_scale = scale
		out.size_name = size_name_value
		return out


## The settled line's Anon diagnostic host; an unbound host answers silence.
class AnonDiag extends RefCounted:
	var read: Callable = Callable()

	func anon_diag() -> String:
		return str(read.call()) if read.is_valid() else ""


## The values one act's pose build needs. The act's start ledger and the body swap both fill this
## typed record from the same act values; the session never reads a runtime field for it.
class ActPose extends RefCounted:
	var pose_id := ""
	var id := ""
	var features: Dictionary = {}
	var bed: Node3D = null
	var presentation: Dictionary = {}
	var pose_config: Dictionary = {}
	var look_point := Vector3.ZERO
	var look_set := false
	var camera_position := Vector3.INF
	var size_name := ""
	var size_name_set := false

	## Fill from the act's live values. The session owns them; this record is the one build input
	## the start ledger and the body-swap rebuild share.
	func fill(pose: String, id_value: String, features_block: Dictionary, bed_node: Node3D,
			presentation_block: Dictionary, config: Dictionary, look: Vector3,
			camera_at: Vector3, size_value: String) -> void:
		pose_id = pose
		id = id_value
		features = features_block
		bed = bed_node
		presentation = presentation_block
		pose_config = config
		look_point = look
		look_set = true
		camera_position = camera_at
		size_name = size_value
		size_name_set = true

	## The edge: a suite or a host that holds the act values as a plain document.
	static func from_dict(raw: Dictionary) -> ActPose:
		var out := ActPose.new()
		out.pose_id = str(raw.get("pose_id", ""))
		out.id = str(raw.get("id", ""))
		var flags_value: Variant = raw.get("features")
		if flags_value is Dictionary:
			out.features = flags_value
		var bed_value: Variant = raw.get("bed")
		if bed_value is Node3D:
			out.bed = bed_value
		var presentation_value: Variant = raw.get("presentation")
		if presentation_value is Dictionary:
			out.presentation = presentation_value
		var config_value: Variant = raw.get("pose_config")
		if config_value is Dictionary:
			out.pose_config = config_value
		var look_value: Variant = raw.get("look_point")
		if look_value is Vector3:
			out.look_point = look_value
			out.look_set = true
		var camera_value: Variant = raw.get("camera_position")
		if camera_value is Vector3:
			out.camera_position = camera_value
		if raw.has("size_name"):
			out.size_name = str(raw["size_name"])
			out.size_name_set = true
		return out


## The runtime node that parents the debug nodes and receives their `runtime` field. It is the
## host boundary; the session never reads the runtime's fields.
var host: Node = null
var pony: Node3D = null

## The act's identity and the live view's fields.
var id := ""
var features: FeatureFlags = FeatureFlags.new()
var bed_node: Node3D = null
## True between a successful `begin()` and `release_pose()`. The runtime keeps one session per pony.
var _started := false
## Live pose config. The runtime reads it through `_pose_session.pose_config`.
var pose_config: Dictionary = {}
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
var pose_node: POSE = null
var tail: TAIL = null
var tail_lay: TAIL_LAY = null
var body_sway: BODY_SWAY = null
var prone_sway: PRONE_SWAY = null
var ear_twitch: EAR_TWITCH = null
## The standing oral actor/frame turn the session owns. It preloads no scene and reads the host
## callables below; the edge weight drives it.
var _oral_turn: ORAL_TURN
## The bed face-sit contact driver. The contact switch to `face` begins it and the reverse switch
## or the one act exit restores it; it never ends the act.
var _face_driver: FACE_CONTACT
## The act's own Anon body on the `act_body` specs, or null on the player-body specs. The session
## creates, installs and frees it; the anatomy bridge only receives the opaque handle.
var act_body: MISSIONARY_ANON = null
## The authored profile table with a test seam: a synthetic profile can be added without touching
## the shipped const.
var modifier_profiles: Dictionary = SPECS.MODIFIER_PROFILES.duplicate()
## The camera position the standing tail chooses its side against, from the begin context.
var _tail_anchor := Vector3.INF

## Bed space for the authored pose. The runtime reads it through `_pose_session.bed_frame`.
var bed_frame: Variant = null
var bed_frame_source := Transform3D.IDENTITY
var bed_frame_source_saved := false
## Ground space for a ground pose, seeded from the pony root at pose start. It tracks the root's
## position and yaw every tick.
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
var rig_missing_bones: Array[String] = []
## A shared unavailable asset instance for a pose whose row supplies no asset.
var _empty_asset: AUTHORED = null

## The pony's pre-act bone snapshot.
var saved_bones: Array[Transform3D] = []
var saved_hair: Array[Transform3D] = []
var saved_skeleton: Skeleton3D
var saved_hair_skeleton: Skeleton3D

## The typed act view the pose modifiers read for the live depth, state and bed frame.
var facts: ACT_FACTS = null
## Publish or clear the opaque Anon handle on the anatomy bridge. The service owns the body.
var set_act_body := Callable()
## The eye-shot camera tick, which must run after the render write.
var eye_camera := Callable()
## The oral host boundary: the mouth and opening points, the soft kiss and the speech/viseme
## actions the edge events fire. A missing callback is a no-op.
var mouth_point := Callable()
var opening_point := Callable()
## The face contact's real anchor on the act body, read by the face driver; without a bound callback
## it does nothing.
var face_point := Callable()
var oral_kiss := Callable()
var oral_speech_stop := Callable()
var oral_viseme := Callable()
var oral_status := Callable()


func bind(host_node: Node, pony_node: Node3D) -> void:
	host = host_node
	pony = pony_node


## The act's stable id, for the pose request rows and the per-mare pose config.
func set_id(value: String) -> void:
	id = value


func _init() -> void:
	_view = POSE_VIEW.new()
	_registry = REGISTRY.new()
	_oral_turn = ORAL_TURN.new()
	_face_driver = FACE_CONTACT.new()


## The one pose read model the act view carries. `begin()` fills it and `release_pose()` clears it;
## the object is never re-created, so a consumer can keep the reference for the act.
func view() -> POSE_VIEW:
	return _view


## Stage the live pose config in place. The runtime calls this before the standing placement reads
## its gaps, and everything that holds `pose_config` sees this same object for the act.
func set_pose_config(config: SettingsBlock) -> void:
	pose_config.clear()
	if config != null:
		pose_config.merge(config.values, true)


## Build the pose for a fresh act from its typed values. A live pose or a pony with no body skeleton
## returns false with nothing installed; the started flag only follows an install.
func begin_act(values: ActPose) -> bool:
	return begin(values)


## Rebuild the live pose on a new skeleton, keeping the pose the act had; the start ramp is skipped
## because the act is continuing, not entering.
func rebuild_act(values: ActPose) -> bool:
	if not begin_act(values):
		return false
	settle()
	return true


func begin(values: ActPose) -> bool:
	if _started:
		LOG.debug("pose session: begin refused, a pose is already live")
		return false
	var skeleton: Variant = pony.get("skeleton") if is_instance_valid(pony) else null
	if not skeleton is Skeleton3D:
		LOG.debug("pose session: no body skeleton to pose")
		return false
	# A fresh act starts with no edge and no target snapshot; a failed begin never gets here.
	_abort_target()
	_oral_turn.reset()
	_bind_face()
	_face_driver.reset()
	_state = POSE_STATE.next(_state, "begin")
	var start_id := values.pose_id
	id = values.id
	features = FeatureFlags.from_dict(values.features)
	# The runtime supplies the live size name; a suite may omit it and fall back to the facts.
	var size_name := values.size_name if values.size_name_set else _size_name()
	bed_node = values.bed
	pose_logged = false
	pose_trace_frames = 0
	pose_node = POSE.new()
	pose_node.name = "UnfplapPose"
	pose_node.mare = pony
	# Fill the view first: the active settings group and family drive the start config sync, not the
	# act's start id. One live object: the sync merges the character's pose into `pose_config` in
	# place, so the modifier, the view and the runtime share it.
	var start_spec: Variant = _registry.spec(start_id)
	_fill_view(start_spec)
	_view.contact_kind = _spec_contact_kind(start_spec)
	var group := str(_view.settings_group)
	if group == CATALOG.STANDING:
		sync_standing_config(SettingsBlock.from_dict(values.presentation))
	elif group == CATALOG.MISSIONARY:
		sync_missionary_config()
	pose_node.pose_config = pose_config
	# Resolve the start asset before the evaluator pair: the same instance is the live rendered
	# asset and both sides of a pose that starts settled.
	var start_asset: AUTHORED = _asset_for_spec(start_spec)
	if start_asset != null and start_asset.available \
			and start_asset.usable(str(_view.frame)):
		pose_node.authored = start_asset
	_from_asset = pose_node.authored
	_target_asset = _from_asset
	pose_node.set_pose(_effective_driver(start_spec), _effective_driver(start_spec),
		_effective_delta(start_spec), _effective_delta(start_spec), pose_config, pose_config,
		_from_asset, _target_asset)
	pose_node.set_weight(1.0)
	pose_node.look_point = values.look_point if values.look_set else pony.global_position
	pose_node.amount = 0.0
	pose_node.target_amount = 1.0
	if str(_view.frame) == "bed":
		var bed := missionary_pose_frame()
		if has_frame(bed):
			bed_frame = bed
			bed_frame_source_saved = is_instance_valid(bed_node)
		else:
			bed_frame = null
			bed_frame_source_saved = false
		if bed_frame_source_saved:
			bed_frame_source = (bed_node as Node3D).global_transform
		pose_node.bed_frame = bed_frame
	else:
		var ground := ground_pose_frame()
		if has_frame(ground):
			ground_frame = ground
			ground_frame_source_saved = is_instance_valid(pony)
		else:
			ground_frame = null
			ground_frame_source_saved = false
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
		_tail_anchor = values.camera_position
		_install_tail()
	# A row whose base contact is already `face` starts the live mouth follow here, only to capture
	# the residual: the authored asset is already on the bed.
	if str(_view.contact_kind) == "face":
		_face_driver.begin(_view, bed_frame)
		_face_tick(0.0)
	return true


func _fill_view(spec: POSE_SPEC) -> void:
	if spec == null:
		_view.clear()
		LOG.debug("pose view: no spec for the start pose")
		return
	_view.fill(spec, pose_config)


## The spec row's base contact kind (`opening` for standing and missionary, `mouth` for the
## internal oral pose). An edge switch overrides it while it runs; completion settles it here.
func _spec_contact_kind(spec: POSE_SPEC) -> String:
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
	_face_driver.bind(pony, face_point, opening_point)


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


## The effective authored asset path for a spec id; empty when the row and its chain have none.
func asset_for(spec_id: String) -> String:
	return _effective_asset(_registry.spec(spec_id))


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


## Request one authored edge and return the typed `PoseResult` (`ok`, `code`, `edge`, `reason`). It
## leaves the act running and touches neither the live pose nor the bones.
func request_pose(target_id: String, trigger: String, request: PoseRequest = null) -> PoseResult:
	var from_id := str(_view.id)
	var target_spec: POSE_SPEC = _registry.spec(target_id)
	var edge_id := from_id + "__" + target_id
	var edge: TRANSITION_SPEC = _registry.edge(edge_id)
	var act_state := request.act_state if request != null and request.act_state >= 0 \
		else (facts.state if facts != null else 0)
	var forms := _request_forms(request)
	var views := _request_views(request)
	var features := _request_features(request)
	var checks := _request_checks(target_spec, edge, request, forms, views, features)
	var code := POSE_STATE.request_code(_state, act_state, from_id, target_id,
		edge != null, checks)
	if code != "ok":
		return PoseResult.make(code, edge_id, _reason(code, target_id))
	var run: POSE_STATE.Run = POSE_STATE.start_edge(edge.data, from_id, target_id)
	if run == null:
		return PoseResult.make("missing_asset", edge_id, "the edge did not start")
	# Cache the target by settings group, so a row with no blocks of its own (`standing_test`) still
	# gets the standing pose and presentation.
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
	var from_spec: POSE_SPEC = _registry.spec(_from_id)
	pose_node.set_pose(_effective_driver(from_spec), _effective_driver(_target_spec),
		_effective_delta(from_spec), _effective_delta(_target_spec),
		pose_config, _target_config, _from_asset, _target_asset)
	pose_node.set_weight(_run.weight)
	_bind_oral()
	_bind_face()
	if _oral_pair(from_id, target_id):
		_oral_turn.begin(target_id == CATALOG.STANDING_ORAL, _view)
	LOG.debug("pose request %s -> %s (%s): ok", [from_id, target_id, trigger])
	return PoseResult.make("ok", edge_id, "")


## The request's form list: the request's own list, or the player's live form.
func _request_forms(request: PoseRequest) -> Array[String]:
	if request != null and not request.forms.is_empty():
		return request.forms
	var forms: Array[String] = []
	forms.append("pony" if _player_pony() else "human")
	return forms


## The request's view list: the request's own list, or the live display.
func _request_views(request: PoseRequest) -> Array[String]:
	if request != null and not request.views.is_empty():
		return request.views
	var views: Array[String] = []
	views.append("vr" if _headset_view() else "desktop")
	return views


func _request_features(request: PoseRequest) -> FeatureFlags:
	if request != null and request.features_set:
		return FeatureFlags.from_dict(request.features)
	return _facts_features()


func _player_pony() -> bool:
	return facts != null and bool(facts.player_pony)


func _headset_view() -> bool:
	return facts != null and bool(facts.headset_view)


func _facts_features() -> FeatureFlags:
	if facts == null:
		return FeatureFlags.new()
	var value: Variant = facts.features
	return FeatureFlags.from_dict(value as Dictionary if value is Dictionary else {})


## The target spec and the edge requirements against the request record, in the order
## `pose_state.request_code()` reports them. A missing flag passes.
func _request_checks(target_spec: POSE_SPEC, edge: TRANSITION_SPEC, request: PoseRequest,
		forms: Array[String], views: Array[String], features: FeatureFlags) -> Dictionary:
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
			if not features.enabled(str(name_value)):
				features_ok = false
				break
	var wanted_consent := str(requires.get("consent", ""))
	var consent := request.consent if request != null else ""
	var consent_ok := wanted_consent.is_empty() or consent == wanted_consent
	return {
		"form_ok": form_ok,
		"view_ok": view_ok,
		"features_ok": features_ok,
		"consent_ok": consent_ok,
		"asset_ok": asset_ok,
		"locked": request != null and request.locked,
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
	_view.fill(_target_spec, pose_config)
	_view.from_id = _from_id
	_view.to_id = _target_id
	_view.from_config = pose_config
	_view.to_config = _target_config
	_view.edge_id = _run.id
	_view.edge_t = _run.t
	_view.weight = _run.weight
	_view.pose_state = _state


## Advance the live edge, apply its switches and events, then settle the view; a no-op outside an
## edge. The oral turn follows the same weight, so the frame write and the blend are one frame.
func tick(delta: float) -> void:
	_bind_oral()
	_bind_face()
	if facts != null:
		_oral_turn.pace = facts.auto_pace
	if _run == null:
		_oral_turn.tick(maxf(delta, 0.0), _view, 1.0)
		_face_tick(delta)
		return
	_run.tick(maxf(delta, 0.0))
	_view.edge_t = _run.t
	_view.weight = _run.weight
	if is_instance_valid(pose_node):
		pose_node.set_weight(_view.weight)
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
	if is_instance_valid(pose_node):
		pose_node.authored = completed_asset
		pose_node.from_authored = completed_asset
		pose_node.to_authored = completed_asset
		pose_node.set_pose(completed_driver, completed_driver, completed_delta,
			completed_delta, pose_config, pose_config, completed_asset, completed_asset)
		pose_node.set_weight(1.0)
		pose_node.pose_config = pose_config
	_from_asset = completed_asset
	if is_instance_valid(act_body):
		act_body.set_pose_assets(completed_asset, completed_asset, 1.0)
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
		LOG.debug("pose switch %s: %s", [name, target])


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
	if facts != null:
		level = clampf(facts.depth, 0.0, 1.0)
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
				LOG.debug("pose status %s: %s", [_target_id, str(event.get("value", ""))])
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


## Refresh the target snapshot mid-edge. The active pose's own config refresh stays on the runtime's
## standing and missionary sync paths.
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


## Adopt the target's settings into the live config in place, so the view, the pose node and the
## evaluator all see the target through the same alias object. The caller then drops the snapshot.
func _adopt_target_config() -> void:
	if _target_spec == null or is_same(_target_config, pose_config):
		return
	pose_config.clear()
	pose_config.merge(_target_config, true)
	if is_instance_valid(pose_node):
		pose_node.pose_config = pose_config


## The pose block for a settings group plus that group's presentation values. Standing folds in the
## presentation chin, neck and tail; other groups use the live settings block unchanged.
func _config_for_group(group: String, presentation: Dictionary) -> Dictionary:
	var config := SETTINGS.pose(id, group).raw()
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
func sync_standing_config(presentation: SettingsBlock) -> bool:
	if str(_view.settings_group) != CATALOG.STANDING or not is_instance_valid(pony):
		return false
	var block: Dictionary = presentation.values if presentation != null else {}
	pose_config.clear()
	pose_config.merge(_config_for_group(CATALOG.STANDING, block), true)
	if is_instance_valid(pose_node):
		pose_node.pose_config = pose_config
	if is_instance_valid(tail):
		tail.aside_angle = float(pose_config.get("tail_aside", 0.0))
		tail.lift_angle = float(pose_config.get("tail_lift", 0.0))
	return true


## Refresh the missionary block in place each frame. The session's own begin, request, completion,
## reload and release own the authored asset, so this must never reset a live pose's asset.
func sync_missionary_config() -> bool:
	if str(_view.settings_group) != CATALOG.MISSIONARY or not is_instance_valid(pony):
		return false
	pose_config.clear()
	pose_config.merge(_config_for_group(CATALOG.MISSIONARY, {}), true)
	if is_instance_valid(pose_node):
		pose_node.pose_config = pose_config
	return true


## The authored base for a candidate spec, else the live pose's, else the default missionary asset,
## parsed once per path. A row without its own asset still reads the default for diagnostics.
func authored(candidate: String = "") -> AUTHORED:
	var asset: AUTHORED = _asset_for(candidate)
	if asset != null:
		return asset
	# A row with no asset of its own reads the default missionary asset so diagnostics still have a
	# rig to describe; `authored_ready()` is the gate and stays false for such a row.
	if _empty_asset == null:
		_empty_asset = AUTHORED.shared(AUTHORED.PATH)
	return _empty_asset


## The asset the live rig is rendering: the source through an edge, the target once it settles.
func live_authored() -> AUTHORED:
	if is_instance_valid(pose_node) and pose_node.authored != null:
		return pose_node.authored
	return authored("")


## The parsed authored pose for the debug action and the pose lab. With no candidate this is the
## live rendered asset, not the target of a running edge.
func authored_asset(candidate: String = "") -> AUTHORED:
	if candidate.is_empty():
		return live_authored()
	return authored(candidate)


## Ground space for an authored ground pose, seeded from the pony root. Like the bed frame with its
## bed, it is carried by the root from then on.
func ground_pose_frame() -> Transform3D:
	if not is_instance_valid(pony):
		return NO_FRAME
	return Transform3D(pony.global_basis.orthonormalized(), pony.global_position)


## The live size name from the facts, or "" when no act context is bound.
func _size_name() -> String:
	return facts.size_name if facts != null else ""


## True when the candidate's own asset loaded and is usable for its frame. A row with no asset is
## never ready, even though `authored()` falls back for diagnostics.
func authored_ready(candidate: String = "") -> bool:
	var spec: POSE_SPEC = _candidate_spec(candidate)
	if spec == null:
		return false
	var asset: AUTHORED = _asset_for_spec(spec)
	if asset == null or not asset.available:
		return false
	return asset.usable(str(spec.frame))


## Why the candidate's pose asset is unusable, for the gate row and the start log.
func authored_reason(candidate: String = "") -> String:
	var spec: POSE_SPEC = _candidate_spec(candidate)
	if spec == null:
		return "pose_asset: no pose"
	var asset: AUTHORED = _asset_for_spec(spec)
	if asset == null:
		return "pose_asset: no asset for %s" % str(spec.id)
	if not asset.available:
		var why := asset.error
		return "pose_asset: %s" % (why if not why.is_empty() else "not loaded")
	if not asset.usable(str(spec.frame)):
		return "pose_asset: %s asset in a %s pose" % [asset.frame, str(spec.frame)]
	return ""


## Re-read the live pose's asset in place, plus the running edge's target, or the default
## missionary asset when no pose is live. A running act picks the new pose up on its next frame.
func reload_authored(candidate: String = "") -> String:
	var paths: Array[String] = []
	var seen: Dictionary = {}
	_add_reload_path(paths, seen, _asset_path_for(candidate))
	if is_instance_valid(pose_node) and pose_node.authored != null:
		_add_reload_path(paths, seen, pose_node.authored.path)
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


## Bed space for the authored pose: the middle of the real mattress top, in the bed's axes, the
## pillow end at -Z. An absent frame means no bed pose is live, so the procedural driver stays out.
func missionary_pose_frame() -> Transform3D:
	if str(_view.frame) != "bed" or not is_instance_valid(bed_node):
		return NO_FRAME
	var fallback: float = float(bed_node.get_meta("mattress_top", 0.6)) + float(bed_node.global_position.y)
	var points: Array[Vector3] = [bed_node.global_position]
	var top: float = MATTRESS.visible_top(bed_node, points, fallback)
	if not is_finite(top):
		return NO_FRAME
	var at: Vector3 = bed_node.global_position
	var basis: Basis = bed_node.global_basis.orthonormalized() * Basis(Vector3.UP, PI)
	return Transform3D(basis, Vector3(at.x, top, at.z))


## Carry the bed-space pose, act body and anatomy placement with a bed that moves under the act
## (CloudDrift); the delta is rigid, so the top height is not measured again.
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


## Turn the ground frame with the pony root each tick; the oral turn moves the root, so the frame
## turns with her exactly once.
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


## The pose-scope start state: clear the rig-check cache, release the tail lay and drop the bed and
## ground frames, keeping the pose node, the modifiers, the config and the view.
func leave_pose_start() -> void:
	rig_checked = false
	rig_skeleton = 0
	rig_revision = -1
	rig_missing_bones = []
	if _face_driver != null and _face_driver.active:
		_face_driver.restore(_view, pose_node)
	if is_instance_valid(tail_lay):
		tail_lay.restore_tail()
		_drop(tail_lay)
	tail_lay = null
	bed_frame = null
	bed_frame_source_saved = false
	bed_frame_source = Transform3D.IDENTITY
	ground_frame = null
	ground_frame_source_saved = false
	ground_frame_source = Transform3D.IDENTITY


## Drop the live-installed extra modifiers, keeping the pose node, the standing tail, the config and
## the view.
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


## The final pose clear: free the pose modifier and the standing tail and reset the act's state, so
## the next `begin()` starts clean. Safe to repeat; a pose change never calls it.
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
		tail.restore_tail()
		_drop(tail)
	tail = null
	_started = false
	id = ""
	features = FeatureFlags.new()
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


## One pose-change fan-out: reconcile the modifier profile and apply the `act_body`/`anon` channel;
## the evaluator pair is already set. Idempotent, so a steady tick installs nothing.
func pose_changed(view: POSE_VIEW) -> void:
	if not _started or view == null:
		return
	var to_spec: POSE_SPEC = _registry.spec(str(view.to_id))
	if to_spec == null:
		to_spec = _registry.spec(str(view.id))
	var from_spec: POSE_SPEC = _registry.spec(str(view.from_id))
	if from_spec == null:
		from_spec = to_spec
	_reconcile_modifiers(_profile_of(from_spec), _profile_of(to_spec), view)
	_apply_anon_channel(view)


## The spec's modifier profile name, or empty when the row has no block.
func _profile_of(spec: POSE_SPEC) -> String:
	if spec == null:
		return ""
	return str(spec.modifiers.get("profile", ""))


## The owner list of an authored profile. An unknown profile is the empty set.
func _profile_owners(profile: String) -> Array:
	var value: Variant = modifier_profiles.get(profile, NO_OWNERS)
	return value as Array if value is Array else NO_OWNERS


## Keep the shared owners, install the target-only ones and remove the source-only ones. The act
## exit's `leave_pose_body()` is still the full removal; this never calls it.
func _reconcile_modifiers(from_profile: String, to_profile: String, view: POSE_VIEW) -> void:
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
func _sync_owner(owner: String, wanted: bool, retarget: bool, view: POSE_VIEW,
		skeleton: Skeleton3D) -> void:
	var keep := wanted and _owner_feature(owner)
	match owner:
		"body_sway":
			if keep:
				if not is_instance_valid(body_sway):
					if skeleton != null:
						_install_body_sway(skeleton)
				elif retarget:
					body_sway.pose_changed(view)
			elif is_instance_valid(body_sway):
				_drop(body_sway)
				body_sway = null
		"prone_sway":
			if keep:
				if not is_instance_valid(prone_sway):
					if skeleton != null:
						_install_prone_sway(skeleton)
				elif retarget:
					prone_sway.pose_changed(view)
			elif is_instance_valid(prone_sway):
				_drop(prone_sway)
				prone_sway = null
		"ear_twitch":
			if keep:
				if not is_instance_valid(ear_twitch):
					_install_ear_twitch()
				elif retarget:
					ear_twitch.pose_changed(view)
			elif is_instance_valid(ear_twitch):
				_drop(ear_twitch)
				ear_twitch = null
		"tail":
			if keep:
				if not is_instance_valid(tail):
					_install_tail()
				elif retarget:
					tail.pose_changed(view)
			elif is_instance_valid(tail):
				tail.restore_tail()
				_drop(tail)
				tail = null
		"tail_lay":
			if keep:
				if not is_instance_valid(tail_lay):
					_install_tail_lay()
				elif retarget:
					tail_lay.pose_changed(view)
			elif is_instance_valid(tail_lay):
				tail_lay.restore_tail()
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


## Apply the `act_body` specs' Anon channel (`hold`, `blend`, `switch`) and bind the authored asset
## pair for it; the player-body specs never install the adapter.
func _apply_anon_channel(view: POSE_VIEW) -> void:
	var anon := view.anon
	if str(anon.get("mode", "")) != "act_body":
		return
	_install_act_body()
	if not is_instance_valid(act_body):
		return
	if _run == null:
		# Outside an edge the spec's profile is the hold and both assets are the live one.
		var live: AUTHORED = live_authored()
		act_body.set_pose_assets(live, live, 1.0)
		act_body.pose_changed(str(anon.get("profile", "")), 1.0)
		return
	var channel := _anon_channel()
	match str(channel.get("kind", "hold")):
		"blend":
			act_body.set_pose_assets(_from_asset, _target_asset,
				clampf(view.weight, 0.0, 1.0))
			act_body.set_weight(clampf(view.weight, 0.0, 1.0))
		"switch":
			var switched := str(channel.get("profile", ""))
			if switched.is_empty():
				switched = str(channel.get("set", ""))
			if switched.is_empty():
				switched = str(anon.get("profile", ""))
			act_body.set_pose_assets(_target_asset, _target_asset, 1.0)
			act_body.pose_changed(switched, 1.0)
		_:
			# A hold keeps the adapter's current profile, weight and asset pair.
			pass


## The act body exists only on a bed spec's `act_body` mode for desktop human Anon.
func _act_body_wanted(view: POSE_VIEW) -> bool:
	if facts == null or str(view.anon.get("mode", "")) != "act_body":
		return false
	return not facts.player_pony and not facts.headset_view


## The live act body, or null. The pose service owns it; camera, hands and kiss read it here.
func act_body_handle() -> Node:
	return act_body if is_instance_valid(act_body) else null


## The act body's authored mouth point; INF when it is missing, inactive or non-finite.
func act_body_face_point() -> Vector3:
	if not is_instance_valid(act_body) or not bool(act_body.get("active")):
		return Vector3.INF
	var value: Variant = act_body.mouth_point()
	return value if value is Vector3 and (value as Vector3).is_finite() else Vector3.INF


## The act body's debug row, or "" when no body is installed.
func act_body_diag_row(face: Vector3, vulva: Vector3) -> String:
	if not is_instance_valid(act_body):
		return ""
	return str(act_body.diag_row(face, vulva))


func refresh_act_body_palm() -> void:
	if is_instance_valid(act_body):
		act_body.refresh_palm()


## The act's own Anon body, created on the runtime host. The pose service owns it and frees it.
func _install_act_body() -> void:
	if is_instance_valid(act_body):
		return
	if host == null or not _act_body_wanted(_view):
		return
	var body := MISSIONARY_ANON.new()
	body.name = "UnfplapMissionaryAnon"
	host.add_child(body)
	if not body.install(facts):
		host.remove_child(body)
		body.queue_free()
		return
	body.set_pose_assets(live_authored(), live_authored(), 1.0)
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
	act_body.remove()
	_drop(act_body)
	act_body = null


## The live settings edit's entry: swap the feature flags and run the same `pose_changed(view)` pass
## the tick does; the view already carries the active profile.
func refresh_modifiers(feature_flags: FeatureFlags) -> void:
	features = feature_flags if feature_flags != null else FeatureFlags.new()
	pose_changed(_view)


## Detach a modifier before freeing it: `queue_free()` alone leaves it parented for the rest of the
## frame, still taking its pass, so a new act in that frame would run two.
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
	var custom := TAIL_CHAIN.custom_root(pony)
	if found.is_empty() and custom == null:
		return
	var skeleton: Skeleton3D = found.get("skeleton") as Skeleton3D
	if skeleton == null:
		skeleton = pony.get("skeleton") as Skeleton3D
	if skeleton == null:
		return
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
	tail.choose_side(side_anchor)
	tail.process_priority = 20
	skeleton.add_child(tail)


func _install_tail_lay() -> void:
	if not is_instance_valid(pony):
		return
	var found: Dictionary = TAIL_CHAIN.resolve(pony)
	var custom := TAIL_CHAIN.custom_root(pony)
	if found.is_empty() and custom == null:
		return
	var skeleton: Skeleton3D = found.get("skeleton") as Skeleton3D
	if skeleton == null:
		skeleton = pony.get("skeleton") as Skeleton3D
	if skeleton == null:
		return
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
	body_sway.mare = pony
	body_sway.facts = facts
	skeleton.add_child(body_sway)
	_reset_sway_base()


func _install_prone_sway(skeleton: Skeleton3D) -> void:
	prone_sway = PRONE_SWAY.new()
	prone_sway.name = "UnfplapProneSway"
	prone_sway.mare = pony
	prone_sway.facts = facts
	skeleton.add_child(prone_sway)


func _install_ear_twitch() -> void:
	if not _feature("thrust_ear_twitch"):
		return
	var head := head_skeleton(pony.get("boop_node"))
	if head == null:
		return
	ear_twitch = EAR_TWITCH.new()
	ear_twitch.name = "UnfplapEarTwitch"
	ear_twitch.mare = pony
	ear_twitch.facts = facts
	head.add_child(ear_twitch)


## The head skeleton the ear twitch rides, or null.
func head_skeleton(boop: Node) -> Skeleton3D:
	if boop == null:
		return null
	var head: Variant = boop.get("head_skeleton")
	return head as Skeleton3D


## The render-time pose write. The runtime calls this after the game's own writers so the
## authored missionary pose survives to the renderer.
func apply_render(skeleton: Skeleton3D) -> void:
	if is_instance_valid(pose_node):
		pose_node.apply_render(skeleton)


## Apply the live pose at its target amount for one start measurement, then put the entrance amount
## back. The caller measures the authored stance, never the game's idle pose or the ramp's blend.
func apply_target_once() -> bool:
	var skeleton: Variant = pony.get("skeleton") if is_instance_valid(pony) else null
	if not is_instance_valid(pose_node) or not skeleton is Skeleton3D:
		return false
	var amount := pose_node.amount
	pose_node.amount = 1.0
	apply_render(skeleton as Skeleton3D)
	pose_node.amount = amount
	var sk := skeleton as Skeleton3D
	sk.force_update_all_bone_transforms()
	var hips := sk.find_bone("pony_hips")
	if hips >= 0:
		sk.force_update_bone_child_transform(hips)
	return true


## The whole render-time step for one frame, in order: place the act's own Anon body, write her
## pose, replay the sway, then let the live view read his posed head.
func render_write(frame: RenderFrame) -> void:
	if frame == null or not is_instance_valid(pony):
		return
	var family := str(_view.family)
	if family == "standing":
		# Same order as the bed family: sync the ground frame, write the pose after every writer of
		# the frame, then replay the sway on top of that write.
		sync_ground_frame()
		var standing_sk: Variant = pony.get("skeleton")
		if is_instance_valid(pose_node) and standing_sk is Skeleton3D:
			apply_render(standing_sk as Skeleton3D)
			if is_instance_valid(body_sway):
				body_sway.apply_render(standing_sk as Skeleton3D)
		return
	if family != "bed":
		return
	if is_instance_valid(act_body) and has_frame(frame.bed_frame):
		act_body.apply(frame.bed_frame, frame.body_scale)
	var sk: Variant = pony.get("skeleton")
	if is_instance_valid(pose_node) and sk is Skeleton3D:
		apply_render(sk as Skeleton3D)
		if is_instance_valid(prone_sway):
			prone_sway.apply_render(sk as Skeleton3D)
	if eye_camera.is_valid():
		eye_camera.call()


func trigger_ear_twitch(impact: float) -> void:
	if is_instance_valid(ear_twitch):
		ear_twitch.try_trigger(impact)


## The pose frame the live family reads: the bed frame or the ground frame.
func sync_frame(family: String) -> void:
	if family == "bed":
		sync_bed_frame()
	else:
		sync_ground_frame()


## The typed entry for the render-time step: the session supplies its own bed frame plus the scale
## and size name it read from the act.
func write_render_frame(body_scale: float, size_name: String) -> void:
	var frame: Transform3D = bed_frame if bed_frame is Transform3D else NO_FRAME
	render_write(RenderFrame.of(frame, body_scale, size_name))


func set_tail_target(value: float) -> void:
	if is_instance_valid(tail):
		tail.target_amount = value


## The live standing glance's head throw-back; a released pose takes no write.
func set_head_back(value: float) -> void:
	if is_instance_valid(pose_node):
		pose_node.head_back = value


func flick_tail(count: int) -> void:
	if is_instance_valid(tail):
		tail.flick(count)


func pose() -> POSE:
	return pose_node


## A rebuilt pose starts settled. The body swap re-poses the surviving act inside the flame, so
## the start ramp would be a visible second entrance on the new body.
func settle() -> void:
	if is_instance_valid(pose_node):
		pose_node.amount = 1.0
		pose_node.target_amount = 1.0
	if is_instance_valid(tail):
		tail.amount = 1.0
		tail.target_amount = 1.0


func basis_amount() -> float:
	return pose_node.amount if is_instance_valid(pose_node) else 0.0


## Which missionary base is in charge and why, in one record so the log, the settled line and the
## debug action cannot drift apart.
func base_info() -> BASE_INFO:
	var info := BASE_INFO.new()
	var live_id := _live_spec_id()
	var asset: AUTHORED = authored_asset()
	info.asset = asset
	info.version = asset.version
	info.bones = asset.pony_bones.size()
	info.available = asset.available
	info.error = asset.error
	info.frame = pose_frame()
	info.frame_kind = str(_view.frame)
	info.shots = asset.has_shots
	info.asset_path = _asset_path_for(live_id)
	info.live_path = info.asset_path
	info.target_path = _asset_path_for(_target_id) if _target_spec != null else info.live_path
	info.asset_frame = asset.frame
	info.variant = asset.variant
	if live_id.is_empty():
		info.reason = "pose="
	elif info.live_path.is_empty():
		info.reason = "pose=%s" % live_id
	elif not asset.available:
		info.reason = authored_reason(live_id)
	elif not has_frame(info.frame):
		info.reason = "no %s frame" % str(_view.frame)
	elif not asset.usable(str(_view.frame)):
		info.reason = authored_reason(live_id)
	else:
		info.base = "authored"
	return info


## The live pose frame: the bed's mattress space or the pony root's ground space.
func pose_frame() -> Transform3D:
	if str(_view.frame) == "ground":
		return ground_frame if ground_frame is Transform3D else NO_FRAME
	if str(_view.frame) == "bed":
		return bed_frame if bed_frame is Transform3D else NO_FRAME
	return NO_FRAME


## True when a pose frame is real space: the absent frame carries an infinite origin.
static func has_frame(frame: Transform3D) -> bool:
	return frame.origin.is_finite()


## The authored body bones the live rig lacks: the pose writes only the bones it holds, so a missing
## one leaves the game's pose on that link. Cached per skeleton instance and asset revision.
func rig_missing(candidate: String = "") -> Array[String]:
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
	rig_missing_bones = authored(candidate).missing_bones(skeleton)
	return rig_missing_bones


## The gate row's reason, naming the first few bones and counting the rest.
func rig_reason(missing: Array[String]) -> String:
	if missing.is_empty():
		return ""
	var names: PackedStringArray = []
	for i in mini(3, missing.size()):
		names.append(str(missing[i]))
	var text := "pose_rig: missing %s" % ", ".join(names)
	if missing.size() > 3:
		text += " (+%d more)" % (missing.size() - 3)
	return text


## Render-time placement trace, printed from idle after every writer of the frame so it reads the
## pose the renderer is about to use; `diag_root` is the armature bone the placement is written to.
func idle_sample(state: int) -> void:
	if pose_trace_frames >= 2 or str(_view.frame) != "bed" or state == 0:
		return
	if not is_instance_valid(pose_node) or basis_amount() < 0.9:
		return
	var sk: Variant = pony.get("skeleton") if is_instance_valid(pony) else null
	if not sk is Skeleton3D:
		return
	var skeleton := sk as Skeleton3D
	var root := pose_node.diag_root
	var hips := skeleton.find_bone("pony_hips")
	var g := skeleton.global_transform
	var render_root := g * skeleton.get_bone_global_pose(root) if root >= 0 else Transform3D.IDENTITY
	var render_hips := g * skeleton.get_bone_global_pose(hips) if hips >= 0 else Transform3D.IDENTITY
	var wanted_root := pose_node.diag_root_wanted
	var wanted_hips := pose_node.diag_hips_wanted
	var animation: Variant = pony.get("animation")
	var clip := ""
	var playing := false
	if animation is AnimationPlayer:
		clip = (animation as AnimationPlayer).current_animation
		playing = (animation as AnimationPlayer).is_playing()
	LOG.debug("pose trace f=%d root=%d:%s asset_root=%d trace=%d mode=%d clip=%s playing=%s G=%s", [
		pose_trace_frames, root, str(pose_node.diag_root_name), pose_node.diag_asset_root,
		pose_node.diag_trace, skeleton.modifier_callback_mode_process, clip, str(playing),
		str(g)])
	LOG.debug("pose trace f=%d root start=%s after=%s render=%s wanted=%s d=%.3f/%.3f | hips start=%s render=%s wanted=%s d=%.3f", [
		pose_trace_frames, str(pose_node.diag_root_start), str(pose_node.diag_root_after),
		str(render_root), str(wanted_root),
		render_root.origin.distance_to(wanted_root.origin),
		_transform_angle(render_root, wanted_root),
		str(pose_node.diag_hips_start), str(render_hips), str(wanted_hips),
		render_hips.origin.distance_to(wanted_hips.origin)])
	pose_trace_frames += 1


## Degrees between two transforms' bases, for the trace.
func _transform_angle(a: Transform3D, b: Transform3D) -> float:
	return rad_to_deg(a.basis.orthonormalized().get_rotation_quaternion().angle_to(
		b.basis.orthonormalized().get_rotation_quaternion()))


## Rig, modifier and posture diagnostics: which skeleton the modifier drives, which skeleton every
## mesh is actually bound to, whether the pose survives between frames, and who else is near the bed.
func diagnostics(skeleton: Skeleton3D, info: BASE_INFO) -> Array[String]:
	var rows: Array[String] = []
	var modifier := pose_node
	var parent: Node = modifier.get_parent() if is_instance_valid(modifier) else null
	rows.append("modifier=%s parent=%s match=%s frames=%d weight=%.2f base=%s readback=%.2f°" % [
		"yes" if is_instance_valid(modifier) else "no",
		"%s@%s" % [str(parent.name), str(parent.get_instance_id())] if parent != null else "none",
		"yes" if parent == skeleton else "NO", modifier.diag_frames if is_instance_valid(modifier) else 0,
		modifier.diag_last_weight if is_instance_valid(modifier) else 0.0,
		modifier.diag_last_base if is_instance_valid(modifier) else "",
		modifier.diag_readback_deg if is_instance_valid(modifier) else 0.0])
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
		modifier.diag_after_write_deg if is_instance_valid(modifier) else 0.0,
		modifier.diag_readback_deg if is_instance_valid(modifier) else 0.0,
		"write lands, survives" if is_instance_valid(modifier)
			and modifier.diag_after_write_deg < 1.0
			and modifier.diag_readback_deg < 1.0
		else "write lands, lost by next frame" if is_instance_valid(modifier)
			and modifier.diag_after_write_deg < 1.0
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
	var asset: AUTHORED = info.asset
	var hips_bone := skeleton.find_bone("pony_hips")
	if hips_bone >= 0 and asset != null:
		var entry: Variant = asset.pony_bones.get("pony_hips")
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
				WORLD.pony(other).posture_requested(), str(hips_at)])
	rows.append("nearby=%d %s" % [nearest.size(), "; ".join(nearest)])
	return rows


## Why the face-sit debug action cannot toggle right now, or "" when it is ready: an active act, a
## live missionary or face-sit view, a steady pose, no running kiss and the anatomy's act body.
func face_sit_error(act_state: int) -> String:
	if act_state == ACT_STATE.State.IDLE or act_state == ACT_STATE.State.RESTORE:
		return "no active act"
	if _view == null:
		return "no active act"
	if str(_view.id) != CATALOG.MISSIONARY and str(_view.id) != CATALOG.BED_FACESIT:
		return "only in a missionary act"
	if act_state != ACT_STATE.State.ACTIVE:
		return "the act is not active"
	if int(_view.pose_state) != POSE_VIEW.STEADY:
		return "the pose is changing"
	if facts != null and bool(facts.kiss_active):
		return "a kiss is running"
	var anatomy_body: Variant = facts.missionary_body() if facts != null else null
	if not SETTINGS.anatomy_on() or not is_instance_valid(act_body) \
			or not is_instance_valid(anatomy_body):
		return "the anatomy is not available"
	return ""


## Multi-row pose diagnostic for the debug action: base source, asset state, bed frame and where
## the live pose actually put her (world and bed space).
func state_rows(state: int) -> Array[String]:
	var info := base_info()
	var frame: Transform3D = info.frame
	var rows: Array[String] = []
	rows.append("pony=%s pose=%s state=%d weight=%.2f" % [
		str(pony.name) if is_instance_valid(pony) else "?", str(_view.id), state, basis_amount()])
	rows.append("base=%s reason=%s asset=v%d %s path=%s frame=%s variant=%s bones=%d missing=%s shots=%s error=%s" % [
		info.base, info.reason,
		info.version, "ok" if info.available else "error",
		info.asset_path, info.asset_frame, info.variant, info.bones,
		str(rig_missing()), "yes" if info.shots else "no", info.error])
	var target_path := info.target_path
	if not target_path.is_empty() and target_path != info.asset_path:
		rows.append("target=%s" % target_path)
	rows.append("frame=%s kind=%s scale=%.2f" % [
		str(frame) if has_frame(frame) else "null", info.frame_kind, body_scale()])
	var sk: Variant = pony.get("skeleton") if is_instance_valid(pony) else null
	if not sk is Skeleton3D:
		return rows
	var skeleton := sk as Skeleton3D
	rows.append_array(diagnostics(skeleton, info))
	var space := Transform3D.IDENTITY
	if has_frame(frame):
		space = frame.affine_inverse()
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
	var frame: Transform3D = info.frame
	var missing := rig_missing()
	LOG.debug("pose base=%s reason=%s asset=v%d %s path=%s frame=%s variant=%s bones=%d missing=%d shots=%s frame_pose=%s scale=%.2f", [
		info.base, info.reason, info.version,
		"ok" if info.available else "error", info.asset_path,
		info.asset_frame, info.variant, info.bones,
		missing.size(), "yes" if info.shots else "no",
		str(frame) if has_frame(frame) else "null", body_scale()])
	if not missing.is_empty():
		LOG.debug("pose rig %s", [rig_reason(missing)])


## One line with where the pose actually put her, in world and bed space, once the weight settles.
func log_settled(state: int, anon_diag: AnonDiag) -> void:
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
	LOG.debug("missionary settled base=%s weight=%.2f %s", [
		base_info().base, basis_amount(), " ".join(parts)])
	for row: String in diagnostics(skeleton, base_info()):
		LOG.debug("missionary diag %s", [str(row)])
	if anon_diag != null:
		var text := anon_diag.anon_diag()
		if not text.is_empty():
			LOG.debug("anon diag %s", [text])


## Absolute body scale from the rig's own pivot, 1.0 when the pony is gone.
func body_scale() -> float:
	var value: Variant = pony.get("body_scale") if is_instance_valid(pony) else null
	return float(value) if value != null else 1.0


func _reset_sway_base() -> void:
	if is_instance_valid(body_sway):
		body_sway.reset_base()


func _feature(name: String) -> bool:
	return features.enabled(name)


## Numeric read of a Variant property without tripping over a missing one.
func _num(value: Variant, fallback := 0.0) -> float:
	return float(value) if value is float or value is int else fallback


## The start pose's settings-group sync after the pose build. This is a group dispatch, not a pose
## branch: a new group adds its own sync with its pose row.
func sync_start_config(group: String) -> void:
	if group == "missionary":
		sync_missionary_config()


## The moments the host-callback bindings need: the bed frame the anatomy bridge mirrors, and the
## pose handle the bridge calls.
func _bed_frame_value() -> Variant:
	return bed_frame


func self_handle() -> RefCounted:
	return self
