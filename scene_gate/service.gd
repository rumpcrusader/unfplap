extends RefCounted
## The scene half of the act gate: the rows, the small checks, the bed search, the verdicts and
## the buck. Eligibility owns the policy. Contract: `docs/scene_gate.md`

const WORLD := preload("res://mods/unfplap/world/api.gd")
const GAME := preload("res://mods/unfplap/world/game.gd")
const ACT_GATE := preload("res://mods/unfplap/act_gate/service.gd")
const POSE_SPECS := preload("res://mods/unfplap/shared/pose_specs.gd")
const POSE_SESSION := preload("res://mods/unfplap/poses/service.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const PLAYER_FORM := preload("res://world/life/player_form.gd")

const ACT_STATE := preload("res://mods/unfplap/shared/act_state.gd")
const STATE_IDLE := ACT_STATE.State.IDLE

## The act's scene handles. The runtime binds them on every gate call.
var pony: Node3D = null
## The pose session, for the missionary asset/rig rows. Its facade answers both.
var pose_session: POSE_SESSION = null
## The act gate the policy rows and the Base clearance row read; the runtime binds it.
var gate_service: ACT_GATE = null

## The act identity and state the rows read.
var state := 0
var id := ""
var features: Features = null

## Host boundary. A missing callback is a no-op.
var stool_need := Callable()
var stool_count := Callable()
var presentation_active := Callable()
## The policy verdict override and the debug context. The host may supply either; without the
## override the gate reads the act gate service itself.
var policy_verdict := Callable()
var debug_context := Callable()
## The negotiation hold's predicate, bound by the host; missing means false.
var hold_compatible := Callable()

## The transient scene-only rows: the auto-start waits on them inside the Agreement TTL.
const SCENE_ONLY_TRANSIENT := ["player", "bed_gate"]
## The default "no stool pair" for a gate call that did not read one.
const NO_STOOL_PAIR := Vector2i(-1, -1)


## The running interrupt verdict. `ok` false means the act must stop; `reason` is the typed stop
## text the runtime applies.
class RunningVerdict extends RefCounted:
	var ok := true
	var reason := ""

	func _init(ok_in: bool = true, reason_in: String = "") -> void:
		ok = ok_in
		reason = reason_in


## The act's feature switches, held as the act's own live block.
class Features extends RefCounted:
	var flags: Dictionary = {}

	static func from_dict(block: Dictionary) -> Features:
		var out := Features.new()
		out.flags = block
		return out


## The merged start/offer answer: the policy snapshot, every row and the scene's own pass.
## `show` is the start answer and `offer_ok` the proactive-offer answer.
class GateVerdict extends RefCounted:
	var policy: ACT_GATE.Verdict = null
	var rows: Array[ACT_GATE.Row] = []
	var scene_ok := false

	func show() -> bool:
		return policy != null and policy.show and scene_ok

	func offer_ok() -> bool:
		return policy != null and policy.offer and scene_ok


## The Agreement's frozen pose capability, recorded at formation and never rebuilt.
class FrozenPose:
	var pose_profile_ok := false
	var pose_source_ok := false

	func _init(profile_ok := true, source_ok := true) -> void:
		pose_profile_ok = profile_ok
		pose_source_ok = source_ok


## The scene-only start answer. `hard_ok` is every non-transient row; `transient` names the
## transient row keys still failing; `ok` is both.
class SceneVerdict:
	var ok := false
	var hard_ok := false
	var transient_ok := true
	var rows: Array[ACT_GATE.Row] = []
	var transient: PackedStringArray = []
	var reasons: PackedStringArray = []


## Bind the scene nodes and the pose session. A missing node fails the gate closed.
func bind(pony_node: Node3D, session: POSE_SESSION,
		gate: ACT_GATE = null) -> void:
	pony = pony_node
	pose_session = session
	gate_service = gate


## The runtime's live gate values. The act state, id and feature snapshot change per act.
func configure(state_value: int, id_value: String, features_block: Features) -> void:
	state = state_value
	id = id_value
	features = features_block


## The scene-only rows. They never enter the pure policy. `mode` is `start` or `offer`.
func rows(pose: String, act_source: String, bed_in: Node3D, mode: String,
		forced: bool) -> Array[ACT_GATE.Row]:
	var rows_out: Array[ACT_GATE.Row] = []
	if not is_instance_valid(pony):
		return rows_out
	_row(rows_out, "state", state == STATE_IDLE, "state=%d" % state)
	var tree: SceneTree = pony.get_tree()
	_row(rows_out, "paused", forced or tree == null or not tree.paused, "paused")
	_row(rows_out, "conversation", conversation_ok(), "conversation")
	_row(rows_out, "sleeping", not bool(pony.get("sleeping")), "sleeping")
	_row(rows_out, "sex_active", not bool(pony.get_meta("sex_active", false)), "sex_active")
	_row(rows_out, "aftercare", not pony.has_meta("sex_aftercare"), "aftercare")
	_row(rows_out, "cuddle",
		not cuddle_active() or cuddle_start_override(pose, act_source), "cuddle")
	_row(rows_out, "affection", free_of_affection(), "affection")
	var scene := _scene(pose)
	var known := POSE_SPECS.is_public(pose) and not str(scene.get("frame", "")).is_empty()
	_row(rows_out, "pose_profile", known, "pose")
	var form := _player_form_id()
	var display := _view_id()
	_row(rows_out, "pose_form", _supports(pose, "forms", form), "pose_form")
	_row(rows_out, "pose_view", _supports(pose, "views", display), "pose_view")
	_row(rows_out, "pose_source", _source_allowed(pose, act_source), "pose_source")
	if mode == "start":
		_row(rows_out, "player", player_ready_for(pose, act_source, bed_in), "player")
	var nav: Node = GAME.navigator_of(pony)
	if mode == "start":
		_row(rows_out, "navigator", nav != null, "no_navigator")
		if nav != null:
			_row(rows_out, "navigator_reserved",
				GAME.navigator_reserved(nav) == "", "navigator_reserved")
			_row(rows_out, "nav_owner", nav_owner_allows(pose, act_source), "nav_owner")
		_row(rows_out, "nav_pose", nav_pose_gate(pose, act_source), "nav_pose")
	else:
		_row(rows_out, "nav_owner",
			nav != null and nav_owner_allows(pose, act_source), "nav_owner")
	if bool(scene.get("stool", false)):
		var need := needed_stool()
		_row(rows_out, "stool", need <= 0 or owned_stools() >= need, "needs_stool")
	if _is_bed_pose(pose) or str(_scene(pose).get("frame", "")) == "ground":
		var pose_ready := authored_ready(pose)
		_row(rows_out, "pose_asset", pose_ready, authored_reason(pose))
		if pose_ready:
			var missing := rig_missing(pose)
			_row(rows_out, "pose_rig", missing.is_empty(), rig_reason(missing))
	if _is_bed_pose(pose):
		var found: Node3D = resolve_bed(pose, act_source, bed_in)
		_row(rows_out, "bed", found != null, "no_bed")
		if found != null:
			_row(rows_out, "bed_occupied", not WORLD.bed_occupied(found, pony), "bed_occupied")
			if mode == "start":
				_row(rows_out, "bed_gate", bed_gate(pose, act_source, found), "bed_gate")
	elif mode == "offer":
		if bool(scene.get("standing_free", false)):
			_row(rows_out, "standing_free",
				not GAME.is_held(pony) and not pony.has_meta("seated"), "standing_free")
		elif not POSE_SPECS.is_offerable(pose):
			_row(rows_out, "pose", false, "pose")
	return rows_out


## The structural rows and the policy/scene merge. The runtime supplies the policy verdict and
## the debug context; the gate owns the merge and the debug string.
func start_verdict(pose: String, act_source: String, bed_in: Node3D = null,
		verdict_in: ACT_GATE.Verdict = null) -> GateVerdict:
	return _gate_data(pose, act_source, bed_in, "start", false, verdict_in)


## The full proactive-offer gate. It uses the offer-safe scene subset.
func offer_verdict(pose: String, act_source: String, bed_in: Node3D = null,
		forced: bool = false, verdict_in: ACT_GATE.Verdict = null) -> GateVerdict:
	return _gate_data(pose, act_source, bed_in, "offer", forced, verdict_in)


## The scene-only start of an accepted Agreement: no policy rebuild, no formation row.
## `player` and `bed_gate` stay transient; every other row is hard.
func scene_only_verdict(pose: String, act_source: String, bed: Node3D = null,
		frozen: FrozenPose = null, stool_need: int = -1, stool_have: int = -1) -> SceneVerdict:
	var rows_out: Array[ACT_GATE.Row] = []
	_gate_row(rows_out, "invalid_pony", is_instance_valid(pony), "invalid_pony")
	_gate_row(rows_out, "no_world", is_instance_valid(WORLD.game), "no_world")
	_gate_row(rows_out, "no_player", is_instance_valid(WORLD.player),
		"no_player")
	_gate_row(rows_out, "no_game", is_instance_valid(WORLD.game),
		"no_game")
	if not is_instance_valid(pony) or not is_instance_valid(WORLD.game):
		return _scene_only_result(rows_out)
	var tree: SceneTree = pony.get_tree()
	_gate_row(rows_out, "state", state == STATE_IDLE, "state=%d" % state)
	_gate_row(rows_out, "paused", tree == null or not tree.paused, "paused")
	_gate_row(rows_out, "conversation", conversation_ok(), "conversation")
	_gate_row(rows_out, "sleeping", not pony.sleeping, "sleeping")
	_gate_row(rows_out, "sex_active", not bool(pony.get_meta("sex_active", false)), "sex_active")
	_gate_row(rows_out, "cuddle",
		not cuddle_active() or cuddle_start_override(pose, act_source), "cuddle")
	var hold_exempt := _hold_exempt(pose, act_source)
	_gate_row(rows_out, "affection", hold_exempt or free_of_affection(), "affection")
	_gate_row(rows_out, "pose_profile", frozen != null and frozen.pose_profile_ok, "pose")
	_gate_row(rows_out, "pose_source", frozen != null and frozen.pose_source_ok, "pose_source")
	_gate_row(rows_out, "player", player_ready_for(pose, act_source, bed), "player")
	var nav: Node = pony.get_node_or_null("Navigator")
	_gate_row(rows_out, "navigator", nav != null, "no_navigator")
	if nav != null:
		_gate_row(rows_out, "navigator_reserved", str(nav.get("reserved_by")) == "",
			"navigator_reserved")
		_gate_row(rows_out, "nav_owner", hold_exempt or nav_owner_allows(pose, act_source),
			"nav_owner")
	_gate_row(rows_out, "nav_pose", nav_pose_gate(pose, act_source, hold_exempt), "nav_pose")
	var scene := _scene(pose)
	if bool(scene.get("stool", false)):
		var need := stool_need
		var have := stool_have
		if need < 0:
			need = needed_stool()
			have = owned_stools()
		_gate_row(rows_out, "stool", need <= 0 or have >= need, "needs_stool")
	if _is_bed_pose(pose) or str(scene.get("frame", "")) == "ground":
		var pose_ready := authored_ready(pose)
		_gate_row(rows_out, "pose_asset", pose_ready, authored_reason(pose))
		if pose_ready:
			var missing := rig_missing(pose)
			_gate_row(rows_out, "pose_rig", missing.is_empty(), rig_reason(missing))
	if _is_bed_pose(pose):
		var found: Node3D = resolve_bed(pose, act_source, bed)
		_gate_row(rows_out, "bed", found != null, "no_bed")
		if found != null:
			_gate_row(rows_out, "bed_occupied", not WORLD.bed_occupied(found, pony), "bed_occupied")
			_gate_row(rows_out, "bed_gate", bed_gate(pose, act_source, found), "bed_gate")
	elif bool(scene.get("standing_free", false)):
		_gate_row(rows_out, "standing_free",
			not pony.is_held() and not pony.has_meta("seated"), "standing_free")
	return _scene_only_result(rows_out)


func _scene_only_result(rows_in: Array[ACT_GATE.Row]) -> SceneVerdict:
	var out := SceneVerdict.new()
	out.rows = rows_in
	out.hard_ok = true
	for row: ACT_GATE.Row in rows_in:
		if row.ok:
			continue
		out.reasons.append(row.reason)
		if row.key in SCENE_ONLY_TRANSIENT:
			if not out.transient.has(row.key):
				out.transient.append(row.key)
		else:
			out.hard_ok = false
	out.transient_ok = out.transient.is_empty()
	out.ok = out.hard_ok and out.transient_ok
	return out


## One answer for both the hint and the press: helper checks and clearance, no rows.
## A matrix suite keeps it in step with the row-based verdict.
func hotkey_ready(pose: String, act_source: String, bed_in: Node3D = null,
		stool_pair: Vector2i = NO_STOOL_PAIR) -> bool:
	if not available():
		return false
	if not pose_supported(pose, act_source):
		return false
	if not player_ready(pose, act_source, bed_in):
		return false
	if not navigator_allows(pose, act_source):
		return false
	if not posture_allows(pose):
		return false
	if not _stool_allows(pose, stool_pair):
		return false
	var service: ACT_GATE = gate_service
	if service == null or not is_instance_valid(service):
		return false
	return service.ready(pony)


## The runtime state and the standing scene rows that do not depend on a pose.
func available() -> bool:
	if not is_instance_valid(pony) or not is_instance_valid(WORLD.game):
		return false
	if not is_instance_valid(WORLD.player):
		return false
	var tree: SceneTree = pony.get_tree()
	if state != STATE_IDLE or (tree != null and tree.paused):
		return false
	if not conversation_ok() or bool(pony.get("sleeping")):
		return false
	if bool(pony.get_meta("sex_active", false)):
		return false
	if not free_of_affection():
		return false
	return not cuddle_active() or cuddle_start_override("", "")


## The pose's public profile, its authored source, and the asset and rig it needs.
func pose_supported(pose: String, act_source: String) -> bool:
	if not POSE_SPECS.is_public(pose) or str(_scene(pose).get("frame", "")).is_empty():
		return false
	if not _source_allowed(pose, act_source):
		return false
	return _pose_assets_ok(pose)


## The navigator's existence, its reservation and the owner lease.
func navigator_allows(pose: String, act_source: String) -> bool:
	if not is_instance_valid(pony):
		return false
	var nav: Node = pony.get_node_or_null("Navigator")
	if nav == null or str(nav.get("reserved_by")) != "":
		return false
	return _hold_exempt(pose, act_source) or nav_owner_allows(pose, act_source)


## Her standing posture: grounded, settled, still and unheld. A lying or cradle pose passes.
func posture_allows(pose: String) -> bool:
	if not is_instance_valid(pony):
		return false
	if not _is_standing_pose(pose):
		return true
	return nav_pose_gate(pose, "", _hold_exempt(pose, ""))


## Anon's side: his readiness, and the free bed a bed pose needs.
func player_ready(pose: String, act_source: String, bed_in: Node3D = null) -> bool:
	if not player_ready_for(pose, act_source, bed_in):
		return false
	if not _is_bed_pose(pose):
		return true
	var found: Node3D = resolve_bed(pose, act_source, bed_in)
	if found == null or WORLD.bed_occupied(found, pony):
		return false
	return bed_gate(pose, act_source, found)


## The accepted Agreement's scene-only start without a row list. `frozen` is its pose capability.
func agreement_ready(pose: String, act_source: String, bed_in: Node3D = null,
		frozen: FrozenPose = null) -> bool:
	if frozen == null or not frozen.pose_profile_ok or not frozen.pose_source_ok:
		return false
	if not available():
		return false
	if not player_ready(pose, act_source, bed_in):
		return false
	if not navigator_allows(pose, act_source):
		return false
	if not posture_allows(pose):
		return false
	if not _pose_assets_ok(pose):
		return false
	return _stool_allows(pose, NO_STOOL_PAIR)


## The posed asset and rig rows: a bed or ground pose needs its authored asset.
func _pose_assets_ok(pose: String) -> bool:
	if not _is_bed_pose(pose) and str(_scene(pose).get("frame", "")) != "ground":
		return true
	return authored_ready(pose) and rig_missing(pose).is_empty()


## The footstool row: a supplied pair is this call's read; `-1` reads the live callbacks.
func _stool_allows(pose: String, stool_pair: Vector2i) -> bool:
	if not bool(_scene(pose).get("stool", false)):
		return true
	var need := stool_pair.x
	var have := stool_pair.y
	if need < 0:
		need = needed_stool()
		have = owned_stools()
	return need <= 0 or have >= need


func _hold_exempt(pose: String, act_source: String) -> bool:
	if not hold_compatible.is_valid():
		return false
	return bool(hold_compatible.call(pose, act_source))


func _gate_data(pose: String, act_source: String, bed_in: Node3D, mode: String,
		forced := false, verdict_in: ACT_GATE.Verdict = null) -> GateVerdict:
	var out := GateVerdict.new()
	var structural: Array[ACT_GATE.Row] = []
	_gate_row(structural, "invalid_pony", is_instance_valid(pony), "invalid_pony")
	if not is_instance_valid(pony):
		out.rows = structural
		return out
	_gate_row(structural, "no_world", is_instance_valid(WORLD.game), "no_world")
	if not is_instance_valid(WORLD.game):
		out.rows = structural
		return out
	_gate_row(structural, "no_player", is_instance_valid(WORLD.player), "no_player")
	if not is_instance_valid(WORLD.player):
		out.rows = structural
		return out
	_gate_row(structural, "no_game", is_instance_valid(WORLD.game), "no_game")
	if not is_instance_valid(WORLD.game):
		out.rows = structural
		return out
	var policy_mode: ACT_GATE.Mode = ACT_GATE.Mode.OFFER if mode == "offer" \
		else ACT_GATE.Mode.START
	out.policy = policy_verdict_for(policy_mode, verdict_in)
	var scene_rows := rows(pose, act_source, bed_in, mode, forced)
	var rows_all: Array[ACT_GATE.Row] = []
	rows_all.append_array(structural)
	if out.policy != null:
		rows_all.append_array(out.policy.rows)
	rows_all.append_array(scene_rows)
	out.rows = rows_all
	out.scene_ok = _report_ok(scene_rows)
	return out


## The policy verdict. The host may override it for a suite; otherwise the gate reads the
## act gate service's verdict for the bound pony.
func policy_verdict_for(mode: ACT_GATE.Mode,
		verdict_in: ACT_GATE.Verdict = null) -> ACT_GATE.Verdict:
	if verdict_in != null:
		return verdict_in
	if policy_verdict.is_valid():
		return policy_verdict.call(mode, verdict_in)
	if not is_instance_valid(WORLD.game):
		return null
	var service: ACT_GATE = gate_service
	if service == null:
		return null
	return service.get_verdict(pony, mode)


func _gate_row(rows_out: Array[ACT_GATE.Row], key: String, ok: bool, reason := "") -> void:
	var row := ACT_GATE.Row.new()
	row.key = key
	row.ok = ok
	row.reason = reason if not reason.is_empty() else key
	rows_out.append(row)


func _report_ok(rows_in: Array[ACT_GATE.Row]) -> bool:
	for row in rows_in:
		if not row.ok:
			return false
	return true


## The failed reasons of a row list. The gate's debug line and the offer's status reads use it.
func report_reasons(rows_in: Array[ACT_GATE.Row]) -> PackedStringArray:
	var reasons: PackedStringArray = []
	for row in rows_in:
		if not row.ok:
			reasons.append(row.reason)
	return reasons


func _policy_row_ok(policy: ACT_GATE.Verdict, key: String) -> bool:
	if policy == null:
		return true
	for row in policy.rows:
		if row.key == key:
			return row.ok
	return true


## The debug status line. The gate owns the row and verdict assembly; the runtime supplies the
## live act values through the context callback.
func debug_line(pose: String, act_source: String, bed_in: Node3D = null,
		distance: float = -1.0, dot: float = -1.0) -> String:
	var context: Dictionary = debug_context.call() if debug_context.is_valid() else {}
	var gate := start_verdict(pose, act_source, bed_in)
	var policy: ACT_GATE.Verdict = gate.policy
	var relations: ACT_GATE.Relations = policy.relations if policy != null \
		else ACT_GATE.Relations.new()
	var reasons: PackedStringArray = report_reasons(gate.rows)
	var reason_text := "none" if reasons.is_empty() else ",".join(reasons)
	var bed_pose := _is_bed_pose(pose)
	var found_bed: Node3D = resolve_bed(pose, act_source, bed_in) if bed_pose else null
	var bed_text := "n/a"
	if bed_pose:
		bed_text = str(found_bed != null and bed_gate(pose, act_source, found_bed))
	var text := "pony=%s id=%s dist=%.2f dot=%.2f stage=%s love=%s(level%d) welcomes=%s mood=%s | show=%s offer=%s | state=%d presenting=%s sleep=%s held=%s grounded=%s seated=%s cuddle=%s motion=%s speed=%.2f posture=%s interrupt=%s | nav owner=%s target=%s reserved=%s | player locked=%s flying=%s seat=%s mouse=%s paused=%s | gates rel=%s form=%s romance=%s promiscuity=%s cycle=%s historyrow=%s conv=%s aff=%s player=%s navowner=%s navpose=%s bed=%s | can_start=%s reasons=%s" % [
		str(context.get("display", "?")), str(context.get("id", "")),
		float(distance), float(dot), str(context.get("stage", "")),
		str(context.get("love_name", "?")), int(context.get("love_level", 0)),
		str(context.get("welcomes", false)),
		str(context.get("mood", "?")),
		str(gate.show()), str(policy != null and policy.offer),
		int(context.get("state", 0)), str(context.get("presenting", false)),
		str(context.get("sleeping", false)), str(context.get("held", false)),
		str(context.get("grounded", false)), str(context.get("seated", false)),
		str(context.get("cuddle", false)), str(context.get("motion", false)),
		float(context.get("speed", 0.0)), str(context.get("posture", "")),
		str(context.get("interrupt", "")),
		str(context.get("owner", "")), str(context.get("target", false)),
		str(context.get("reserved", "")),
		str(context.get("body_controls_locked", "?")),
		str(context.get("body_flying", "?")), str(context.get("body_seat", "?")),
		str(context.get("mouse", "")), str(context.get("paused", false)),
		str(_policy_row_ok(policy, "relation")), str(_policy_row_ok(policy, "form")),
		str(_policy_row_ok(policy, "romance")), str(_policy_row_ok(policy, "promiscuity")),
		str(_policy_row_ok(policy, "cycle")),
		str(_policy_row_ok(policy, "history")), str(conversation_ok()), str(free_of_affection()),
		str(player_ready_for(pose, act_source, bed_in)), str(nav_owner_allows(pose, act_source)),
		str(nav_pose_gate(pose, act_source)), bed_text, str(gate.show()),
		reason_text]
	if int(context.get("state", 0)) != STATE_IDLE:
		var limit_text := "∞" if int(context.get("max_pony_climaxes", 0)) <= 0 \
			else str(int(context.get("max_pony_climaxes", 0)))
		text += " | readiness=%.0f mood=%s climaxes=%d/%s intensity=%s pattern=%s cue=%s up=%s penetration=%.1f/%.1fcm | %s" % [
			float(context.get("satisfaction", 0.0)), str(context.get("mood", "")),
			int(context.get("pony_climaxes", 0)), limit_text,
			str(context.get("last_intensity", "")), str(context.get("last_pattern", "")),
			str(context.get("cue", "")), str(context.get("thrust_up", false)),
			float(context.get("penetration_m", 0.0)) * 100.0,
			float(context.get("penetration_reach", 0.0)) * 100.0,
			str(context.get("preferences", "")).replace("\n", "; ")]
	text += " | " + str(context.get("voice_status_line", ""))
	return text


## Footstool rows through the host's callbacks.
func needed_stool() -> int:
	return int(stool_need.call()) if stool_need.is_valid() else 0


func owned_stools() -> int:
	return int(stool_count.call()) if stool_count.is_valid() else 0


func authored_ready(pose := "") -> bool:
	return pose_session != null and pose_session.authored_ready(pose)


func authored_reason(pose := "") -> String:
	return pose_session.authored_reason(pose) if pose_session != null else "pose_asset"


func rig_missing(pose := "") -> Array[String]:
	return pose_session.rig_missing(pose) if pose_session != null else []


func rig_reason(missing: Array[String]) -> String:
	return pose_session.rig_reason(missing) if pose_session != null else ""


func buck_or_push() -> bool:
	if not is_instance_valid(pony) or not is_instance_valid(WORLD.game):
		return false
	var affection: Node = pony.get_node_or_null("Affection")
	if affection != null:
		if GAME.affection_buck(affection, WORLD.player_body()):
			return true
	var body: Node3D = WORLD.player
	if not is_instance_valid(body):
		return false
	var knockdown: Object = GAME.knockdown_of(body)
	if knockdown == null:
		return false
	var direction: Vector3 = pony.global_position - body.global_position
	direction.y = 0.25
	if direction.length_squared() < 0.0001:
		direction = -body.global_basis.z
	return GAME.start_knockdown(knockdown, body, direction.normalized() * 3.0)


func conversation_ok() -> bool:
	if not is_instance_valid(pony) or not is_instance_valid(WORLD.game):
		return false
	var target: Variant = pony.get("conversation_target")
	if target == null or not is_instance_valid(target):
		return true
	var body: Node3D = WORLD.player_body()
	if target == WORLD.player or target == body:
		return true
	# The player's body/avatar is under the rig; another pony's is not.
	if is_instance_valid(WORLD.player) and WORLD.player is Node \
			and (WORLD.player as Node).is_ancestor_of(target as Node):
		return true
	return false


## The stock bed marks a lying companion with couch_cuddle; cuddle/player_input then automatically
## begins a CuddleSession. That interrupts missionary, so keep it off while an act is active.
func suppress_auto_cuddle() -> void:
	if state == STATE_IDLE or not is_instance_valid(pony):
		return
	if pony.has_meta("couch_cuddle"):
		pony.remove_meta("couch_cuddle")
	var session: Node = pony.get_node_or_null("CuddleSession")
	if session != null and (bool(session.get("enabled")) or float(session.get("blend")) > 0.0):
		GAME.cuddle_end(session)
	if pony.has_meta("cuddle_active"):
		pony.remove_meta("cuddle_active")


## Starting an act always ends an active cuddle; the normal bed-side paths remain.
func cuddle_start_override(_pose: String, _act_source: String) -> bool:
	return true


func cuddle_active() -> bool:
	if not is_instance_valid(pony):
		return false
	if pony.has_meta("cuddle_active"):
		return true
	# cuddle_session is a persistent reference to the cuddle input's session; the session stays on
	# the pony after end(). Only an enabled/blending session is an active cuddle.
	if not pony.has_meta("cuddle_session"):
		return false
	var session: Variant = pony.get_meta("cuddle_session")
	if session == null or not is_instance_valid(session):
		return false
	if bool(session.get("enabled")):
		return true
	var blend: Variant = session.get("blend")
	return blend != null and float(blend) > 0.01


func free_of_affection() -> bool:
	if not is_instance_valid(pony):
		return false
	var affection: Node = pony.get_node_or_null("Affection")
	if affection != null:
		var kind: Variant = affection.get("kind")
		if kind != null and not str(kind).is_empty():
			return false
	var hoof: Variant = pony.get("hoof_hold")
	if hoof != null and GAME.hoof_active(hoof):
		return false
	return true


## The running interrupt verdict; the runtime passes the live values it holds.
## Conversation is not an interruption: the act clears the listener.
func running_verdict(nav: Node, bed: Node3D, player_pony: bool, our_kiss: bool) -> RunningVerdict:
	if not is_instance_valid(pony):
		return RunningVerdict.new(false, "picked up")
	if pony.is_held():
		return RunningVerdict.new(false, "picked up")
	var affection: Node = pony.get_node_or_null("Affection")
	if affection != null:
		var kind := str(affection.get("kind"))
		# The base-game kiss runs through Affection; it is part of the act, not an interruption.
		if not kind.is_empty() and not (our_kiss and kind == "kiss"):
			return RunningVerdict.new(false, "interrupted")
	if cuddle_active():
		return RunningVerdict.new(false, "interrupted")
	if nav != null and is_instance_valid(nav) and str(nav.get("reserved_by")) != "":
		return RunningVerdict.new(false, "interrupted")
	var view: Variant = pose_session.view() if pose_session != null else null
	if view != null and str(view.family) == "bed" and bed != null \
			and WORLD.bed_occupied(bed, pony):
		return RunningVerdict.new(false, "interrupted")
	if pony.is_inside_tree() \
			and player_pony != PLAYER_FORM.is_pony(PLAYER_FORM.active(pony.get_tree())):
		return RunningVerdict.new(false, "form change")
	return RunningVerdict.new(true, "")


func nav_owner_allows(pose: String, act_source: String, hold_exempt := false) -> bool:
	if not is_instance_valid(pony):
		return false
	var nav: Node = pony.get_node_or_null("Navigator")
	if nav == null:
		return false
	if hold_exempt:
		return true
	var owner := str(nav.get("command_owner"))
	if owner.is_empty():
		return true
	# The request controller holds her while she walks over, presents and waits for the act key.
	if owner.begins_with("unfplap:request:"):
		return state == STATE_IDLE
	# NightRest's new [go_to_bed] owns her with a sleep: lease. While she is lying awake in a bed,
	# a bed-side act is still valid; walking to bed or sleeping is not.
	if owner.begins_with("sleep:"):
		return sleep_owner_allows_bed(pose, act_source)
	if owner.begins_with("unfplap:"):
		return false
	if owner.begins_with("weather:") or owner.begins_with("show:"):
		return false
	if owner.begins_with("cuddle:"):
		return _is_bed_pose(pose) and _source_allowed(pose, act_source)
	# A managed bed/couch rest is valid for a bed pose; every other leisure seat is not.
	if owner.begins_with("leisure:"):
		return _is_bed_pose(pose) and _source_allowed(pose, act_source)
	# Player conversation is free; another pony's conversation is not.
	if owner.begins_with("social:"):
		return owner.begins_with("social:talk") and conversation_ok()
	# Normal routine owners: idle routines are free, an active route is not.
	if owner.begins_with("life:") or owner.begins_with("day:"):
		return not bool(nav.get("_has_target"))
	# A player-owned date/outing, following the player, or an idle rest.
	if owner.begins_with("bond:") or owner.begins_with("player:") or owner == "rest_after_command":
		return true
	return false


## NightRest's sleep: lease is also used for an awake [go_to_bed] rest. Only a pony already lying
## in a bed, with Anon there too, may accept a bed-side act through it.
func sleep_owner_allows_bed(pose: String, act_source: String) -> bool:
	if not _is_bed_pose(pose) or not _source_allowed(pose, act_source):
		return false
	if not is_instance_valid(pony) or bool(pony.get("sleeping")):
		return false
	if not pony.has_method("posture_status"):
		return false
	var status: Dictionary = pony.posture_status()
	return str(status.get("requested", "")) == "lie_down"


func nav_pose_gate(pose: String, act_source: String, hold_exempt := false) -> bool:
	if not is_instance_valid(pony):
		return false
	if _is_standing_pose(pose):
		if pony.is_held() or not pony.grounded():
			return false
		if bool(pony.motion_paused):
			return false
		if pony.has_meta("seated"):
			return false
		var interruption := str(pony.action_interruption_reason())
		if not interruption.is_empty():
			# The act presentation's own affection hold or the negotiation hold is not a gate
			# against its own invite.
			var presented := presentation_active.is_valid() and bool(presentation_active.call())
			if not (hold_exempt or (presented and state == STATE_IDLE \
					and interruption.contains("Affection"))):
				return false
		var status: Dictionary = pony.posture_status()
		if str(status.get("requested", "")) != "stand" or not bool(status.get("settled", false)):
			return false
		if float(pony.actual_speed) > 0.06:
			return false
		return true
	if act_source == "cradle":
		return true
	# already_lying: seated is allowed; held/grounded/interruption are not used.
	return true


func bed_gate(pose: String, act_source: String, found: Node3D) -> bool:
	if not _is_bed_pose(pose):
		return true
	if not is_instance_valid(pony) or not is_instance_valid(WORLD.game):
		return false
	var rest: Node = pony.get_node_or_null("CradleRest")
	if rest != null:
		if bool(rest.get("asleep")):
			return false
		if act_source == "cradle" and float(rest.get("drowse")) >= 0.5:
			return false
	var tree: SceneTree = pony.get_tree()
	if act_source == "cradle":
		var reach: Node = WORLD.interactor()
		if not is_instance_valid(reach):
			return false
		if reach.get("held") != pony or reach.get("cradled") != true:
			return false
		# The cradle path exists only for human Anon.
		if PLAYER_FORM.is_pony(PLAYER_FORM.active(tree)):
			return false
		return true
	if act_source == "bed_side":
		var status: Dictionary = pony.posture_status()
		if str(status.get("requested", "")) != "lie_down" or not bool(status.get("settled", false)):
			return false
		return WORLD.player_beside_bed(found)
	if not PLAYER_FORM.is_pony(PLAYER_FORM.active(tree)):
		return false
	var status2: Dictionary = pony.posture_status()
	if str(status2.get("requested", "")) != "lie_down" or not bool(status2.get("settled", false)):
		return false
	return WORLD.player_beside_bed(found)


func resolve_bed(pose: String, act_source: String, bed_in: Node3D) -> Node3D:
	if not _is_bed_pose(pose) or not is_instance_valid(WORLD.game):
		return null
	if bed_in is Node3D and is_instance_valid(bed_in):
		var real := WORLD.real_bed(bed_in)
		if real is Node3D and is_instance_valid(real):
			return real
	if act_source == "cradle":
		return WORLD.bed_for_cradle(pony)
	return find_bed_under()


func find_bed_under() -> Node3D:
	if not is_instance_valid(pony) or not is_instance_valid(WORLD.game):
		return null
	var exclude: RID = pony.get_rid() if pony is CollisionObject3D else RID()
	return WORLD.bed_under(pony.global_position, exclude)


func player_ready_for(pose: String, act_source: String, bed_in: Node3D) -> bool:
	if not is_instance_valid(WORLD.game):
		return false
	var body: Variant = WORLD.player
	if not is_instance_valid(body):
		return false
	# A headset rig is a plain Node3D: it has neither desktop `controls_locked` nor `flying`, and
	# `bool(null)` is an error in GDScript, so compare against true instead.
	if body.get("controls_locked") == true:
		return false
	if body.get("flying") == true:
		return false
	var wing: Variant = body.get("wing_flight")
	if wing != null and bool(wing.get("active")):
		return false
	if bool(body.get_meta("knocked_down", false)):
		return false
	var swimming: Variant = body.get("swimming")
	if swimming != null and bool(swimming.get("active")):
		return false
	if DisplayServer.get_name() != "headless" and not headset_view() \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return false
	var inventory: Variant = WORLD.game.get("inventory") \
		if is_instance_valid(WORLD.game) else null
	if inventory != null:
		var held: Variant = inventory.get("held")
		if held is Dictionary and not (held as Dictionary).is_empty():
			return false
		if str(inventory.get("holding_case")) != "":
			return false
	if not POSE_SPECS.is_public(pose) or not _source_allowed(pose, act_source):
		return false
	var seat: Variant = body.get("seat")
	if _is_standing_pose(pose):
		if seat != null:
			return false
	elif act_source == "cradle":
		if seat != null:
			return false
	elif act_source == "already_lying":
		var found: Node3D = resolve_bed(pose, act_source, bed_in)
		if not WORLD.player_beside_bed(found):
			return false
	elif act_source == "bed_side":
		if seat == null:
			return false
		var rest: Variant = body.get("_couch_rest")
		if rest != null and is_instance_valid(rest) and float(rest.get("amount")) < 0.99:
			return false
		var found_bed: Node3D = resolve_bed(pose, act_source, bed_in)
		if not WORLD.player_beside_bed(found_bed):
			return false
	return true


## The pose's scene block. An unknown row reads the fail-closed default.
func _scene(pose: String) -> Dictionary:
	return POSE_SPECS.scene(pose)


func _is_bed_pose(pose: String) -> bool:
	return bool(_scene(pose).get("requires_bed", false))


func _is_standing_pose(pose: String) -> bool:
	return bool(_scene(pose).get("standing_free", false))


## The authored act sources, or an empty list for a pose with no source constraint.
func _sources(pose: String) -> Array:
	var value: Variant = _scene(pose).get("sources", [])
	return value as Array if value is Array else []


func _source_allowed(pose: String, act_source: String) -> bool:
	var sources := _sources(pose)
	return sources.is_empty() or act_source in sources


## One support list from the spec row. `supports()` checks both; the row reasons name which failed.
func _supports(pose: String, key: String, value: String) -> bool:
	var row: Dictionary = POSE_SPECS.spec(pose)
	var list: Variant = row.get(key)
	return list is Array and value in (list as Array)


func _player_form_id() -> String:
	var tree: SceneTree = pony.get_tree() if is_instance_valid(pony) else null
	return "pony" if PLAYER_FORM.is_pony(PLAYER_FORM.active(tree)) else "human"


func _view_id() -> String:
	return "vr" if headset_view() else "desktop"


func headset_view() -> bool:
	return is_instance_valid(WORLD.game) \
		and WORLD.game.get("headset_view") == true


func _row(rows_out: Array[ACT_GATE.Row], key: String, ok: bool, reason := "") -> void:
	var row := ACT_GATE.Row.new()
	row.key = key
	row.ok = ok
	row.reason = reason if not reason.is_empty() else key
	rows_out.append(row)
